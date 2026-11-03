import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/session_models.dart';

class CircularJumpHostException implements Exception {
  final String message;
  const CircularJumpHostException(this.message);

  @override
  String toString() => 'CircularJumpHostException: $message';
}

class ResolvedSshRoute {
  final SessionProfile targetSession;
  final String? jumpHost;
  final int jumpPort;
  final String? jumpFallbackHost;
  final String? jumpUsername;
  final String? jumpPassword;

  const ResolvedSshRoute({
    required this.targetSession,
    this.jumpHost,
    this.jumpPort = 22,
    this.jumpFallbackHost,
    this.jumpUsername,
    this.jumpPassword,
  });

  bool get hasJumpHost => jumpHost != null && jumpHost!.isNotEmpty;
}

class _ClipboardItem {
  final bool isCut;
  final String? sessionId;
  final String? folderId;

  const _ClipboardItem({
    required this.isCut,
    this.sessionId,
    this.folderId,
  });
}

class SessionManagerService extends ChangeNotifier {
  static SessionManagerService? _instance;
  static SessionManagerService get instance => _instance ??= SessionManagerService._();

  @visibleForTesting
  factory SessionManagerService.forTesting() => SessionManagerService._();

  SessionManagerService._();

  final List<SessionFolder> _folders = [];
  final List<SessionProfile> _sessions = [];
  String? _filePath;
  _ClipboardItem? _clipboard;

  List<SessionFolder> get folders => List.unmodifiable(_folders);
  List<SessionProfile> get sessions => List.unmodifiable(_sessions);
  bool get hasClipboardItem => _clipboard != null;
  bool get isClipboardCut => _clipboard?.isCut ?? false;

  List<SessionFolder> getChildFolders(String? parentId) {
    return _folders.where((f) => f.parentId == parentId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<SessionProfile> getChildSessions(String? parentId) {
    return _sessions.where((s) => s.parentId == parentId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<SessionFolder> getBreadcrumbPath(String? folderId) {
    final path = <SessionFolder>[];
    String? currentId = folderId;
    final visited = <String>{};

    while (currentId != null && !visited.contains(currentId)) {
      visited.add(currentId);
      final folder = _folders.where((f) => f.id == currentId).firstOrNull;
      if (folder == null) break;
      path.insert(0, folder);
      currentId = folder.parentId;
    }
    return path;
  }

  String getFullPathLabel(SessionProfile session) {
    final crumbs = getBreadcrumbPath(session.parentId);
    if (crumbs.isEmpty) return session.name;
    return '${crumbs.map((c) => c.name).join(' / ')} / ${session.name}';
  }

  Future<void> loadSessions({String? customFilePath}) async {
    _filePath = customFilePath ?? _getDefaultFilePath();
    final file = File(_filePath!);

    if (!await file.exists()) {
      _folders.clear();
      _sessions.clear();
      // Seed default LOCAL session
      _sessions.add(SessionProfile(
        id: 'sess_local_default',
        parentId: null,
        name: 'LOCAL',
        protocol: SessionProtocol.local,
        description: 'Local system shell',
        modifiedAt: DateTime.now(),
      ));
      await saveSessions();
      notifyListeners();
      return;
    }

    try {
      final content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);

      _folders.clear();
      if (data['folders'] is List) {
        for (final item in data['folders']) {
          _folders.add(SessionFolder.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      _sessions.clear();
      if (data['sessions'] is List) {
        for (final item in data['sessions']) {
          _sessions.add(SessionProfile.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      // Ensure LOCAL session always exists if sessions list is empty
      if (_sessions.isEmpty) {
        _sessions.add(SessionProfile(
          id: 'sess_local_default',
          parentId: null,
          name: 'LOCAL',
          protocol: SessionProtocol.local,
          description: 'Local system shell',
          modifiedAt: DateTime.now(),
        ));
        await saveSessions();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading sessions from $_filePath: $e');
    }
  }

  Future<void> saveSessions() async {
    if (_filePath == null) return;
    try {
      final file = File(_filePath!);
      await file.parent.create(recursive: true);

      final data = {
        'version': 1,
        'folders': _folders.map((f) => f.toJson()).toList(),
        'sessions': _sessions.map((s) => s.toJson()).toList(),
      };

      final tempFile = File('${_filePath!}.tmp');
      await tempFile.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(_filePath!);
    } catch (e) {
      debugPrint('Error saving sessions: $e');
    }
  }

  String _getDefaultFilePath() {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    return '$home/.nexus_fx/sessions.json';
  }

  Future<SessionFolder> createFolder({
    required String name,
    String? parentId,
    String description = '',
  }) async {
    final folder = SessionFolder(
      id: 'folder_${DateTime.now().microsecondsSinceEpoch}',
      parentId: parentId,
      name: name,
      description: description,
      modifiedAt: DateTime.now(),
    );
    _folders.add(folder);
    await saveSessions();
    notifyListeners();
    return folder;
  }

  Future<SessionProfile> createSession(SessionProfile profile) async {
    _sessions.add(profile);
    await saveSessions();
    notifyListeners();
    return profile;
  }

  Future<void> updateSession(SessionProfile profile) async {
    final index = _sessions.indexWhere((s) => s.id == profile.id);
    if (index != -1) {
      _sessions[index] = profile.copyWith(modifiedAt: DateTime.now());
      await saveSessions();
      notifyListeners();
    }
  }

  Future<void> updateFolder(SessionFolder folder) async {
    final index = _folders.indexWhere((f) => f.id == folder.id);
    if (index != -1) {
      _folders[index] = folder.copyWith(modifiedAt: DateTime.now());
      await saveSessions();
      notifyListeners();
    }
  }

  List<SessionProfile> getDependentSessions(String jumpSessionId) {
    return _sessions
        .where((s) => s.jumpHostMode == JumpHostMode.existingSession && s.jumpSessionId == jumpSessionId)
        .toList();
  }

  Future<void> deleteSession(String sessionId) async {
    // Reset dependent sessions referencing this jump host to direct
    for (int i = 0; i < _sessions.length; i++) {
      if (_sessions[i].jumpHostMode == JumpHostMode.existingSession &&
          _sessions[i].jumpSessionId == sessionId) {
        _sessions[i] = _sessions[i].copyWith(
          jumpHostMode: JumpHostMode.direct,
          clearJumpSessionId: true,
          modifiedAt: DateTime.now(),
        );
      }
    }

    _sessions.removeWhere((s) => s.id == sessionId);
    await saveSessions();
    notifyListeners();
  }

  Future<void> deleteFolder(String folderId) async {
    final folderIdsToDelete = <String>{folderId};
    void collectDescendants(String id) {
      final children = _folders.where((f) => f.parentId == id).map((f) => f.id);
      for (final cid in children) {
        folderIdsToDelete.add(cid);
        collectDescendants(cid);
      }
    }
    collectDescendants(folderId);

    // Collect sessions inside these folders to delete
    final sessionsToDelete = _sessions.where((s) => folderIdsToDelete.contains(s.parentId)).map((s) => s.id).toList();
    for (final sid in sessionsToDelete) {
      await deleteSession(sid);
    }

    _folders.removeWhere((f) => folderIdsToDelete.contains(f.id));
    await saveSessions();
    notifyListeners();
  }

  void copyItem({String? sessionId, String? folderId}) {
    if (sessionId == null && folderId == null) return;
    _clipboard = _ClipboardItem(isCut: false, sessionId: sessionId, folderId: folderId);
  }

  void cutItem({String? sessionId, String? folderId}) {
    if (sessionId == null && folderId == null) return;
    _clipboard = _ClipboardItem(isCut: true, sessionId: sessionId, folderId: folderId);
  }

  bool isFolderDescendantOf(String potentialChildId, String parentFolderId) {
    if (potentialChildId == parentFolderId) return true;
    String? current = potentialChildId;
    final visited = <String>{};
    while (current != null && !visited.contains(current)) {
      visited.add(current);
      if (current == parentFolderId) return true;
      final f = _folders.where((folder) => folder.id == current).firstOrNull;
      if (f == null) break;
      current = f.parentId;
    }
    return false;
  }

  Future<void> moveSession(String sessionId, String? targetFolderId) async {
    final sess = _sessions.where((s) => s.id == sessionId).firstOrNull;
    if (sess == null) return;
    if (sess.parentId == targetFolderId) return;
    await updateSession(sess.copyWith(
      parentId: targetFolderId,
      clearParentId: targetFolderId == null,
    ));
  }

  Future<void> moveFolder(String folderId, String? targetFolderId) async {
    if (folderId == targetFolderId) return;
    if (targetFolderId != null && isFolderDescendantOf(targetFolderId, folderId)) {
      throw ArgumentError('Cannot move folder into its own descendant');
    }
    final folder = _folders.where((f) => f.id == folderId).firstOrNull;
    if (folder == null) return;
    if (folder.parentId == targetFolderId) return;
    await updateFolder(folder.copyWith(
      parentId: targetFolderId,
      clearParentId: targetFolderId == null,
    ));
  }

  Future<void> pasteInto(String? targetFolderId) async {
    if (_clipboard == null) return;
    final clip = _clipboard!;

    if (clip.isCut) {
      if (clip.sessionId != null) {
        final sess = _sessions.where((s) => s.id == clip.sessionId).firstOrNull;
        if (sess != null) {
          await updateSession(sess.copyWith(
            parentId: targetFolderId,
            clearParentId: targetFolderId == null,
          ));
        }
      } else if (clip.folderId != null) {
        if (targetFolderId != null && isFolderDescendantOf(targetFolderId, clip.folderId!)) {
          throw ArgumentError('Cannot move folder into its own descendant');
        }
        final folder = _folders.where((f) => f.id == clip.folderId).firstOrNull;
        if (folder != null) {
          await updateFolder(folder.copyWith(
            parentId: targetFolderId,
            clearParentId: targetFolderId == null,
          ));
        }
      }
      _clipboard = null;
    } else {
      // Copy item
      if (clip.sessionId != null) {
        final orig = _sessions.where((s) => s.id == clip.sessionId).firstOrNull;
        if (orig != null) {
          final newName = _generateUniqueSessionName(orig.name, targetFolderId);
          final cloned = orig.copyWith(
            id: 'sess_${DateTime.now().microsecondsSinceEpoch}',
            parentId: targetFolderId,
            name: newName,
            modifiedAt: DateTime.now(),
          );
          await createSession(cloned);
        }
      } else if (clip.folderId != null) {
        final origFolder = _folders.where((f) => f.id == clip.folderId).firstOrNull;
        if (origFolder != null) {
          final newName = _generateUniqueFolderName(origFolder.name, targetFolderId);
          await _deepCloneFolder(origFolder.id, targetFolderId, newName);
        }
      }
    }
  }

  Future<SessionFolder> _deepCloneFolder(String sourceFolderId, String? targetParentId, String newName) async {
    final orig = _folders.firstWhere((f) => f.id == sourceFolderId);
    final newFolder = await createFolder(
      name: newName,
      parentId: targetParentId,
      description: orig.description,
    );

    // Clone sessions in source folder
    final childSessions = _sessions.where((s) => s.parentId == sourceFolderId).toList();
    for (final s in childSessions) {
      await createSession(s.copyWith(
        id: 'sess_${DateTime.now().microsecondsSinceEpoch}',
        parentId: newFolder.id,
        modifiedAt: DateTime.now(),
      ));
    }

    // Clone subfolders recursively
    final childFolders = _folders.where((f) => f.parentId == sourceFolderId).toList();
    for (final cf in childFolders) {
      await _deepCloneFolder(cf.id, newFolder.id, cf.name);
    }

    return newFolder;
  }

  String _generateUniqueSessionName(String baseName, String? parentId) {
    final siblingNames = getChildSessions(parentId).map((s) => s.name).toSet();
    String name = baseName.contains(' - Copy') ? baseName : '$baseName - Copy';
    if (!siblingNames.contains(name)) return name;

    int counter = 2;
    final prefix = baseName.contains(' - Copy')
        ? baseName.replaceAll(RegExp(r' - Copy( \(\d+\))?$'), ' - Copy')
        : '$baseName - Copy';

    while (siblingNames.contains('$prefix ($counter)')) {
      counter++;
    }
    return '$prefix ($counter)';
  }

  String _generateUniqueFolderName(String baseName, String? parentId) {
    final siblingNames = getChildFolders(parentId).map((f) => f.name).toSet();
    String name = baseName.contains(' - Copy') ? baseName : '$baseName - Copy';
    if (!siblingNames.contains(name)) return name;

    int counter = 2;
    final prefix = baseName.contains(' - Copy')
        ? baseName.replaceAll(RegExp(r' - Copy( \(\d+\))?$'), ' - Copy')
        : '$baseName - Copy';

    while (siblingNames.contains('$prefix ($counter)')) {
      counter++;
    }
    return '$prefix ($counter)';
  }

  Future<SessionProfile> duplicateSession(String sessionId) async {
    final orig = _sessions.firstWhere((s) => s.id == sessionId);
    final newName = _generateUniqueSessionName(orig.name, orig.parentId);
    final cloned = orig.copyWith(
      id: 'sess_${DateTime.now().microsecondsSinceEpoch}',
      name: newName,
      modifiedAt: DateTime.now(),
    );
    await createSession(cloned);
    return cloned;
  }

  ResolvedSshRoute resolveSshRoute(SessionProfile session) {
    if (session.jumpHostMode == JumpHostMode.direct || session.protocol == SessionProtocol.local) {
      return ResolvedSshRoute(targetSession: session);
    }

    if (session.jumpHostMode == JumpHostMode.customJumpHost) {
      return ResolvedSshRoute(
        targetSession: session,
        jumpHost: session.customJumpHost,
        jumpPort: session.customJumpPort,
        jumpFallbackHost: session.customJumpFallbackHost,
        jumpUsername: session.customJumpUsername,
        jumpPassword: session.customJumpPassword,
      );
    }

    // JumpHostMode.existingSession
    final visitedIds = <String>{session.id};
    String? currentJumpId = session.jumpSessionId;
    SessionProfile? jumpSession;

    while (currentJumpId != null) {
      if (visitedIds.contains(currentJumpId)) {
        throw CircularJumpHostException('Circular jump host dependency detected on session $currentJumpId');
      }
      visitedIds.add(currentJumpId);

      jumpSession = _sessions.where((s) => s.id == currentJumpId).firstOrNull;
      if (jumpSession == null) break;

      if (jumpSession.jumpHostMode == JumpHostMode.existingSession) {
        currentJumpId = jumpSession.jumpSessionId;
      } else {
        break;
      }
    }

    if (jumpSession == null) {
      return ResolvedSshRoute(targetSession: session);
    }

    return ResolvedSshRoute(
      targetSession: session,
      jumpHost: jumpSession.host,
      jumpPort: jumpSession.port,
      jumpFallbackHost: jumpSession.fallbackHost,
      jumpUsername: jumpSession.username,
      jumpPassword: jumpSession.password,
    );
  }

  Future<void> exportToFile(File file) async {
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'folders': _folders.map((f) => f.toJson()).toList(),
      'sessions': _sessions.map((s) => s.toJson()).toList(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<void> importFromFile(File file, {bool merge = true}) async {
    final content = await file.readAsString();
    final Map<String, dynamic> data = jsonDecode(content);

    if (!merge) {
      _folders.clear();
      _sessions.clear();
    }

    final existingFolderIds = _folders.map((f) => f.id).toSet();
    final existingSessionIds = _sessions.map((s) => s.id).toSet();

    if (data['folders'] is List) {
      for (final item in data['folders']) {
        final f = SessionFolder.fromJson(Map<String, dynamic>.from(item));
        if (!existingFolderIds.contains(f.id)) {
          _folders.add(f);
        }
      }
    }

    if (data['sessions'] is List) {
      for (final item in data['sessions']) {
        final s = SessionProfile.fromJson(Map<String, dynamic>.from(item));
        if (!existingSessionIds.contains(s.id)) {
          _sessions.add(s);
        }
      }
    }

    await saveSessions();
    notifyListeners();
  }
}
