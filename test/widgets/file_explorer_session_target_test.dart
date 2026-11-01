import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/services/session_manager_service.dart';

void main() {
  group('ExplorerNodeTarget & SessionProfile', () {
    test('creates ExplorerNodeTarget for LOCAL shell profile as local target', () {
      final localProfile = SessionProfile(
        id: 'sess_loc',
        name: 'LOCAL',
        protocol: SessionProtocol.local,
        modifiedAt: DateTime.now(),
      );

      final target = ExplorerNodeTarget.fromSessionProfile(
        localProfile,
        ResolvedSshRoute(targetSession: localProfile),
      );

      expect(target.isLocal, isTrue);
      expect(target.label, 'Local Filesystem');
    });

    test('creates ExplorerNodeTarget for SSH session carrying resolved jump host credentials', () {
      final sshProfile = SessionProfile(
        id: 'sess_prod',
        name: 'PROD_DB',
        protocol: SessionProtocol.ssh,
        host: '10.0.1.50',
        port: 22,
        username: 'dbadmin',
        password: 'dbpassword',
        modifiedAt: DateTime.now(),
      );

      final route = ResolvedSshRoute(
        targetSession: sshProfile,
        jumpHost: 'bastion.prod.internal',
        jumpPort: 2222,
        jumpFallbackHost: 'bastion-backup.prod.internal',
        jumpUsername: 'bastionuser',
        jumpPassword: 'bastionpassword',
      );

      final target = ExplorerNodeTarget.fromSessionProfile(
        sshProfile,
        route,
      );

      expect(target.isLocal, isFalse);
      expect(target.label, 'PROD_DB');
      expect(target.host, '10.0.1.50');
      expect(target.port, 22);
      expect(target.username, 'dbadmin');
      expect(target.password, 'dbpassword');
      expect(target.jumpHost, 'bastion.prod.internal');
      expect(target.jumpPort, 2222);
      expect(target.jumpUsername, 'bastionuser');
      expect(target.jumpPassword, 'bastionpassword');
    });
  });
}
