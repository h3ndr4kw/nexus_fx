import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/services/session_manager_service.dart';

void main() {
  late Directory tempDir;
  late File sessionFile;
  late SessionManagerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nexus_fx_test_');
    sessionFile = File('${tempDir.path}/sessions.json');
    service = SessionManagerService.forTesting();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SessionManagerService', () {
    test('seeds default LOCAL session when file does not exist', () async {
      await service.loadSessions(customFilePath: sessionFile.path);

      expect(service.sessions, hasLength(1));
      final local = service.sessions.first;
      expect(local.name, 'LOCAL');
      expect(local.protocol, SessionProtocol.local);
      expect(local.parentId, isNull);
    });

    test('creates folders, sessions, and resolves breadcrumb path', () async {
      await service.loadSessions(customFilePath: sessionFile.path);

      final folder1 = await service.createFolder(name: 'TSEL_PS');
      final folderSub = await service.createFolder(name: 'CLUSTER_A', parentId: folder1.id);

      final sessInSub = await service.createSession(SessionProfile(
        id: 'sess_sub',
        parentId: folderSub.id,
        name: 'NODE_1',
        protocol: SessionProtocol.ssh,
        host: '10.0.0.1',
        modifiedAt: DateTime.now(),
      ));

      expect(service.getChildFolders(null).map((f) => f.name), contains('TSEL_PS'));
      expect(service.getChildFolders(folder1.id).map((f) => f.name), contains('CLUSTER_A'));
      expect(service.getChildSessions(folderSub.id).map((s) => s.name), contains('NODE_1'));

      final breadcrumb = service.getBreadcrumbPath(folderSub.id);
      expect(breadcrumb.map((b) => b.name).toList(), ['TSEL_PS', 'CLUSTER_A']);

      final pathLabel = service.getFullPathLabel(sessInSub);
      expect(pathLabel, 'TSEL_PS / CLUSTER_A / NODE_1');
    });

    test('duplicates session in same folder with incremented name', () async {
      await service.loadSessions(customFilePath: sessionFile.path);

      final s1 = await service.createSession(SessionProfile(
        id: 'sess_orig',
        name: 'DOCKER_SERVER',
        protocol: SessionProtocol.ssh,
        host: '192.168.1.10',
        modifiedAt: DateTime.now(),
      ));

      final dup1 = await service.duplicateSession(s1.id);
      expect(dup1.name, 'DOCKER_SERVER - Copy');
      expect(dup1.id, isNot(equals(s1.id)));

      final dup2 = await service.duplicateSession(s1.id);
      expect(dup2.name, 'DOCKER_SERVER - Copy (2)');
    });

    test('deep-clones folder and all child sessions and subfolders on copy/paste', () async {
      await service.loadSessions(customFilePath: sessionFile.path);

      final parentFolder = await service.createFolder(name: 'REGION_1');
      final subFolder = await service.createFolder(name: 'SITE_A', parentId: parentFolder.id);
      await service.createSession(SessionProfile(
        id: 'sess_site_a',
        parentId: subFolder.id,
        name: 'SERVER_A',
        protocol: SessionProtocol.ssh,
        host: '192.168.1.20',
        modifiedAt: DateTime.now(),
      ));

      service.copyItem(folderId: parentFolder.id);
      await service.pasteInto(null);

      final rootFolders = service.getChildFolders(null);
      expect(rootFolders.any((f) => f.name == 'REGION_1 - Copy'), isTrue);

      final copiedFolder = rootFolders.firstWhere((f) => f.name == 'REGION_1 - Copy');
      final copiedSubFolders = service.getChildFolders(copiedFolder.id);
      expect(copiedSubFolders, hasLength(1));
      expect(copiedSubFolders.first.name, 'SITE_A');

      final copiedSessions = service.getChildSessions(copiedSubFolders.first.id);
      expect(copiedSessions, hasLength(1));
      expect(copiedSessions.first.name, 'SERVER_A');
      expect(copiedSessions.first.id, isNot(equals('sess_site_a')));
    });

    test('cuts and moves session or folder and prevents circular folder move', () async {
      await service.loadSessions(customFilePath: sessionFile.path);

      final f1 = await service.createFolder(name: 'F1');
      final f2 = await service.createFolder(name: 'F2');

      // Move F2 into F1
      service.cutItem(folderId: f2.id);
      await service.pasteInto(f1.id);

      expect(service.getChildFolders(null).map((f) => f.name), ['F1']);
      expect(service.getChildFolders(f1.id).map((f) => f.name), ['F2']);

      // Attempt to move F1 into F2 (its child) should throw/reject
      service.cutItem(folderId: f1.id);
      expect(() => service.pasteInto(f2.id), throwsArgumentError);
    });

    test('resolves SSH route and detects circular jump host chain', () async {
      await service.loadSessions(customFilePath: sessionFile.path);

      final jump = await service.createSession(SessionProfile(
        id: 'sess_jump',
        name: 'BASTION_HOST',
        protocol: SessionProtocol.ssh,
        host: '203.0.113.5',
        port: 2222,
        username: 'bastion-user',
        password: 'bastion-pass',
        modifiedAt: DateTime.now(),
      ));

      final target = await service.createSession(SessionProfile(
        id: 'sess_target',
        name: 'INTERNAL_NODE',
        protocol: SessionProtocol.ssh,
        host: '10.10.1.5',
        port: 22,
        username: 'root',
        password: 'target-pass',
        jumpHostMode: JumpHostMode.existingSession,
        jumpSessionId: jump.id,
        modifiedAt: DateTime.now(),
      ));

      final route = service.resolveSshRoute(target);
      expect(route.targetSession.id, target.id);
      expect(route.jumpHost, '203.0.113.5');
      expect(route.jumpPort, 2222);
      expect(route.jumpUsername, 'bastion-user');
      expect(route.jumpPassword, 'bastion-pass');

      // Create cycle: jump -> target -> jump
      await service.updateSession(jump.copyWith(
        jumpHostMode: JumpHostMode.existingSession,
        jumpSessionId: target.id,
      ));

      expect(() => service.resolveSshRoute(target), throwsA(isA<CircularJumpHostException>()));
    });

    test('deleting a session referenced as jumpSessionId resets dependent sessions to direct', () async {
      await service.loadSessions(customFilePath: sessionFile.path);

      final jump = await service.createSession(SessionProfile(
        id: 'jump_node',
        name: 'JUMP',
        protocol: SessionProtocol.ssh,
        host: '192.168.1.1',
        modifiedAt: DateTime.now(),
      ));

      final dep = await service.createSession(SessionProfile(
        id: 'dep_node',
        name: 'DEP',
        protocol: SessionProtocol.ssh,
        host: '10.0.0.5',
        jumpHostMode: JumpHostMode.existingSession,
        jumpSessionId: jump.id,
        modifiedAt: DateTime.now(),
      ));

      expect(service.getDependentSessions(jump.id), hasLength(1));

      await service.deleteSession(jump.id);

      final updatedDep = service.sessions.firstWhere((s) => s.id == dep.id);
      expect(updatedDep.jumpHostMode, JumpHostMode.direct);
      expect(updatedDep.jumpSessionId, isNull);
    });
  });
}
