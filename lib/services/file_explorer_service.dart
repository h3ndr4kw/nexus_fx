import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/file_explorer_models.dart';
import 'ssh_service.dart';
import 'ssh_tunnel_manager.dart';
import 'rust_sftp_bridge.dart';

class RemoteSession {
  final SSHClient client;
  final SftpClient? sftp;
  final SSHClient? jumpClient;
  final String? leaseId;
  final bool isSharedClient;
  final bool isSharedJumpClient;
  final String? feHostname;
  final ExplorerNodeTarget? target;

  RemoteSession({
    required this.client,
    this.sftp,
    this.jumpClient,
    this.leaseId,
    this.isSharedClient = false,
    this.isSharedJumpClient = true,
    this.feHostname,
    this.target,
  });

  Future<Uint8List> run(String cmd) async {
    if (feHostname != null && feHostname!.isNotEmpty) {
      final escaped = cmd.replaceAll("'", "'\\''");
      final feCmd =
          "ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $feHostname '$escaped'";
      return await client.run(feCmd, stderr: false);
    }
    return await client.run(cmd);
  }

  void close() {
    if (!isSharedClient) {
      try {
        client.close();
      } catch (_) {}
    }
    if (!isSharedJumpClient) {
      try {
        jumpClient?.close();
      } catch (_) {}
    }
    if (leaseId != null) {
      SshTunnelManager.instance.releaseLease(leaseId!);
    }
  }
}

enum ExternalEditor {
  notepadPlusPlus('Notepad++'),
  nvim('Neovim (nvim)'),
  vscode('VS Code'),
  zed('Zed'),
  internalViewer('Built-in Viewer');

  final String label;
  const ExternalEditor(this.label);
}

class FileExplorerService {
  static FileExplorerService? _instance;
  final Map<String, RemoteSession> _cachedSessions = {};

  String? Function(ExternalEditor editor)? customEditorPathResolver;

  @visibleForTesting
  Future<bool> Function(ExternalEditor editor, String filePath)? customEditorLauncher;

  FileExplorerService();

  static FileExplorerService get instance {
    _instance ??= FileExplorerService();
    return _instance!;
  }

  static set instance(FileExplorerService inst) {
    _instance = inst;
  }

  // ==========================================
  // Local Filesystem Operations
  // ==========================================

  Future<List<FileExplorerItem>> listLocal(String dirPath, {String filter = ''}) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      final cur = Directory.current;
      return listLocal(cur.path, filter: filter);
    }

    final items = <FileExplorerItem>[];
    final filterLower = filter.trim().toLowerCase();

    try {
      final entries = await dir.list().toList();
      for (final entity in entries) {
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments[entity.uri.pathSegments.length - (entity.uri.pathSegments.last.isEmpty ? 2 : 1)]
            : entity.path;

        if (filterLower.isNotEmpty && !name.toLowerCase().contains(filterLower)) {
          continue;
        }

        final isDir = entity is Directory;
        int size = 0;
        DateTime? modTime;

        try {
          final stat = await entity.stat();
          size = stat.size;
          modTime = stat.modified;
        } catch (_) {}

        final modStr = modTime != null
            ? FileExplorerItem.formatDateTime(modTime)
            : 'Unknown';

        items.add(FileExplorerItem(
          name: name,
          path: entity.path,
          isDir: isDir,
          size: size,
          modified: isDir ? '- -' : modStr,
          modifiedDateTime: modTime,
        ));
      }

      // Sort: dirs first, then alphabetically
      items.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Add parent directory ".." if parent exists and no active filter
      final parent = dir.parent;
      if (filterLower.isEmpty && parent.path != dir.path) {
        items.insert(0, FileExplorerItem.parentDir(parent.path));
      }
    } catch (e) {
      debugPrint('Error listing local files in $dirPath: $e');
      rethrow;
    }

    return items;
  }

  Future<void> createLocalFile(String dirPath, String fileName) async {
    final file = File('$dirPath${Platform.pathSeparator}$fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
  }

  Future<void> createLocalDir(String dirPath, String dirName) async {
    final dir = Directory('$dirPath${Platform.pathSeparator}$dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<void> deleteLocal(String targetPath) async {
    final type = await FileSystemEntity.type(targetPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(targetPath).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(targetPath).delete();
    }
  }

  Future<void> renameLocal(String oldPath, String newName) async {
    final file = File(oldPath);
    final isDir = await Directory(oldPath).exists();
    final parent = File(oldPath).parent.path;
    final newPath = '$parent${Platform.pathSeparator}$newName';

    if (isDir) {
      await Directory(oldPath).rename(newPath);
    } else {
      await file.rename(newPath);
    }
  }

  Future<void> copyLocal(
    String srcPath,
    String destDirPath, {
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final isDir = await Directory(srcPath).exists();
    final name = srcPath.split(Platform.pathSeparator).last;
    final destPath = '$destDirPath${Platform.pathSeparator}$name';

    if (isDir) {
      await _copyDirLocal(Directory(srcPath), Directory(destPath), onProgress: onProgress);
    } else {
      final file = File(srcPath);
      final totalBytes = await file.length();
      final destFile = File(destPath);
      await destFile.parent.create(recursive: true);
      final sink = destFile.openWrite();
      var sent = 0;
      try {
        await for (final chunk in file.openRead()) {
          sink.add(chunk);
          sent += chunk.length;
          onProgress?.call(sent, totalBytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    }
  }

  Future<void> _copyDirLocal(
    Directory src,
    Directory dest, {
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (!await dest.exists()) {
      await dest.create(recursive: true);
    }
    await for (final entity in src.list(recursive: false)) {
      final entityName = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments[entity.uri.pathSegments.length - (entity.uri.pathSegments.last.isEmpty ? 2 : 1)]
          : entity.path;
      final newDest = '${dest.path}${Platform.pathSeparator}$entityName';
      if (entity is Directory) {
        await _copyDirLocal(entity, Directory(newDest), onProgress: onProgress);
      } else if (entity is File) {
        final totalBytes = await entity.length();
        final destFile = File(newDest);
        final sink = destFile.openWrite();
        var sent = 0;
        try {
          await for (final chunk in entity.openRead()) {
            sink.add(chunk);
            sent += chunk.length;
            onProgress?.call(sent, totalBytes);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
    }
  }

  Future<void> moveLocal(String srcPath, String destDirPath) async {
    final name = srcPath.split(Platform.pathSeparator).last;
    final destPath = '$destDirPath${Platform.pathSeparator}$name';
    try {
      if (await Directory(srcPath).exists()) {
        await Directory(srcPath).rename(destPath);
      } else {
        await File(srcPath).rename(destPath);
      }
    } catch (_) {
      // Fallback: copy and delete
      await copyLocal(srcPath, destDirPath);
      await deleteLocal(srcPath);
    }
  }

  Future<String> readLocalText(String filePath) async {
    final file = File(filePath);
    return await file.readAsString();
  }

  Future<void> writeLocalText(String filePath, String content) async {
    final file = File(filePath);
    await file.writeAsString(content);
  }

  Future<void> mergeLocal(List<String> srcPaths, String destDirPath, String newFileName) async {
    final outFile = File('$destDirPath${Platform.pathSeparator}$newFileName');
    final sink = outFile.openWrite();
    try {
      for (int i = 0; i < srcPaths.length; i++) {
        final f = File(srcPaths[i]);
        if (await f.exists()) {
          final stream = f.openRead();
          await sink.addStream(stream);
          if (i < srcPaths.length - 1) {
            sink.writeln();
          }
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  // ==========================================
  // Remote Node Connection & SFTP Operations
  // ==========================================

  @visibleForTesting
  Future<SSHClient> Function(
    SSHSocket socket, {
    required String username,
    required String password,
  })? customTargetClientFactory;

  @visibleForTesting
  Future<SSHSocket> Function(
    String host,
    int port, {
    Duration? timeout,
  })? customSocketConnector;

  @visibleForTesting
  void resetTestHooks() {
    customTargetClientFactory = null;
    customSocketConnector = null;
  }

  Future<SSHClient> _defaultTargetClientFactory(
    SSHSocket socket,
    String username,
    String password,
  ) async {
    final client = SSHClient(
      socket,
      username: username,
      algorithms: SshAlgorithmHelper.buildAlgorithms(),
      onPasswordRequest: () => password,
      onUserInfoRequest: (r) => r.prompts.map((_) => password).toList(),
      keepAliveInterval: const Duration(seconds: 15),
    );
    await client.authenticated;
    return client;
  }

  String _sessionKey(ExplorerNodeTarget target) {
    if (target.type == ExplorerTargetType.fe) {
      return 'fe_${target.clusterName}_${target.host}_${target.feHostname}';
    }
    return '${target.type}_${target.host}_${target.port}_${target.username}';
  }

  Future<RemoteSession> getOrConnectRemote(ExplorerNodeTarget target) async {
    final key = _sessionKey(target);
    final existing = _cachedSessions[key];
    if (existing != null &&
        !existing.client.isClosed &&
        (existing.jumpClient == null || !existing.jumpClient!.isClosed)) {
      return existing;
    }
    if (existing != null) {
      existing.close();
      _cachedSessions.remove(key);
    }

    // Connect new session
    final session = await _connectRemote(target);
    _cachedSessions[key] = session;
    return session;
  }

  Future<RemoteSession> _connectRemote(ExplorerNodeTarget target) async {
    if (target.type == ExplorerTargetType.sessionSsh || target.type == ExplorerTargetType.customSsh) {
      SSHClient? jumpClient;
      final SSHClient client;
      if (target.hasJumpHost) {
        final jumpSocket = await SSHSocket.connect(
          target.jumpHost!,
          target.jumpPort,
          timeout: const Duration(seconds: 15),
        );
        jumpClient = SSHClient(
          jumpSocket,
          username: target.jumpUsername ?? '',
          algorithms: SshAlgorithmHelper.buildAlgorithms(),
          onPasswordRequest: () => target.jumpPassword ?? '',
        );
        await jumpClient.authenticated;
        final channel = await jumpClient.forwardLocal(target.host, target.port);
        client = SSHClient(
          channel,
          username: target.username,
          algorithms: SshAlgorithmHelper.buildAlgorithms(
            sshMacs: target.sshMacs,
            customSshOptions: target.customSshOptions,
          ),
          onPasswordRequest: () => target.password,
        );
        await client.authenticated;
      } else {
        final socket = await SSHSocket.connect(
          target.host,
          target.port,
          timeout: const Duration(seconds: 15),
        );
        client = SSHClient(
          socket,
          username: target.username,
          algorithms: SshAlgorithmHelper.buildAlgorithms(
            sshMacs: target.sshMacs,
            customSshOptions: target.customSshOptions,
          ),
          onPasswordRequest: () => target.password,
        );
        await client.authenticated;
      }

      SftpClient? sftp;
      try {
        sftp = await client.sftp();
      } catch (e) {
        debugPrint('SFTP subsystem failed: $e');
      }
      return RemoteSession(
        client: client,
        sftp: sftp,
        jumpClient: jumpClient,
        target: target,
      );
    }

    // Direct SSH connection to node or custom SSH
    var directUsername = target.username;
    var directPassword = target.password;

    final socket = await (customSocketConnector != null
        ? customSocketConnector!(target.host, target.port, timeout: const Duration(seconds: 12))
        : SSHSocket.connect(
            target.host,
            target.port,
            timeout: const Duration(seconds: 12),
          ));
    final client = await (customTargetClientFactory != null
        ? customTargetClientFactory!(
            socket,
            username: directUsername,
            password: directPassword,
          )
        : _defaultTargetClientFactory(
            socket,
            directUsername,
            directPassword,
          ));
    SftpClient? sftp;
    try {
      sftp = await client.sftp();
    } catch (e) {
      debugPrint('SFTP not available: $e');
    }
    return RemoteSession(
      client: client,
      sftp: sftp,
      target: target,
    );
  }

  Future<List<FileExplorerItem>> listRemote(
    RemoteSession session,
    String remoteDir, {
    String filter = '',
  }) async {
    final items = <FileExplorerItem>[];
    final filterLower = filter.trim().toLowerCase();

    // Normalized remote dir
    var cleanDir = remoteDir.trim();
    if (!cleanDir.startsWith('/')) {
      cleanDir = '/$cleanDir';
    }
    if (cleanDir.length > 1 && cleanDir.endsWith('/')) {
      cleanDir = cleanDir.substring(0, cleanDir.length - 1);
    }

    if (session.sftp != null) {
      try {
        final entries = await session.sftp!.listdir(cleanDir);
        for (final entry in entries) {
          final name = entry.filename;
          if (name == '.' || name == '..') continue;
          if (filterLower.isNotEmpty && !name.toLowerCase().contains(filterLower)) {
            continue;
          }

          final isDir = entry.attr.isDirectory;
          final size = entry.attr.size ?? 0;
          final modSec = entry.attr.modifyTime;
          final modDate = modSec != null
              ? DateTime.fromMillisecondsSinceEpoch(modSec * 1000)
              : null;
          final modStr = modDate != null
              ? FileExplorerItem.formatDateTime(modDate)
              : '-';

          final fullPath = cleanDir == '/' ? '/$name' : '$cleanDir/$name';

          items.add(FileExplorerItem(
            name: name,
            path: fullPath,
            isDir: isDir,
            size: size,
            modified: isDir ? '- -' : modStr,
            modifiedDateTime: modDate,
          ));
        }

        // Sort: dirs first, then alphabetically
        items.sort((a, b) {
          if (a.isDir && !b.isDir) return -1;
          if (!a.isDir && b.isDir) return 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        // Add parent directory ".." if not root and no active filter
        if (filterLower.isEmpty && cleanDir != '/') {
          final lastSlash = cleanDir.lastIndexOf('/');
          final parentDir = lastSlash <= 0 ? '/' : cleanDir.substring(0, lastSlash);
          items.insert(0, FileExplorerItem.parentDir(parentDir));
        }

        return items;
      } catch (e) {
        debugPrint('SFTP listdir failed, falling back to SSH ls: $e');
      }
    }

    // Shell fallback: ls -la
    final cmd = 'ls -la "$cleanDir"';
    final outputBytes = await session.run(cmd);
    final output = utf8.decode(outputBytes, allowMalformed: true);
    final lines = output.split('\n');

    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 9) continue;
      final permissions = parts[0];
      final isDir = permissions.startsWith('d');
      final size = int.tryParse(parts[4]) ?? 0;
      final name = parts.sublist(8).join(' ');

      if (name == '.' || name == '..') continue;
      if (filterLower.isNotEmpty && !name.toLowerCase().contains(filterLower)) {
        continue;
      }

      final dateStr = '${parts[5]} ${parts[6]} ${parts[7]}';
      final fullPath = cleanDir == '/' ? '/$name' : '$cleanDir/$name';

      items.add(FileExplorerItem(
        name: name,
        path: fullPath,
        isDir: isDir,
        size: size,
        modified: isDir ? '- -' : dateStr,
      ));
    }

    items.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    if (filterLower.isEmpty && cleanDir != '/') {
      final lastSlash = cleanDir.lastIndexOf('/');
      final parentDir = lastSlash <= 0 ? '/' : cleanDir.substring(0, lastSlash);
      items.insert(0, FileExplorerItem.parentDir(parentDir));
    }

    return items;
  }

  Future<void> createRemoteFile(RemoteSession session, String dirPath, String fileName) async {
    final cleanDir = dirPath.endsWith('/') && dirPath.length > 1
        ? dirPath.substring(0, dirPath.length - 1)
        : dirPath;
    final path = cleanDir == '/' ? '/$fileName' : '$cleanDir/$fileName';

    if (session.sftp != null) {
      final file = await session.sftp!.open(
        path,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
      );
      await file.close();
    } else {
      await session.run('touch "$path"');
    }
  }

  Future<void> createRemoteDir(RemoteSession session, String dirPath, String dirName) async {
    final cleanDir = dirPath.endsWith('/') && dirPath.length > 1
        ? dirPath.substring(0, dirPath.length - 1)
        : dirPath;
    final path = cleanDir == '/' ? '/$dirName' : '$cleanDir/$dirName';

    if (session.sftp != null) {
      await session.sftp!.mkdir(path);
    } else {
      await session.run('mkdir -p "$path"');
    }
  }

  Future<void> deleteRemote(RemoteSession session, String targetPath, bool isDir) async {
    if (session.sftp != null && !isDir) {
      try {
        await session.sftp!.remove(targetPath);
        return;
      } catch (_) {}
    }
    // Command rm -rf works reliably for both dirs and files
    await session.run('rm -rf "$targetPath"');
  }

  Future<void> renameRemote(RemoteSession session, String oldPath, String newName) async {
    final lastSlash = oldPath.lastIndexOf('/');
    final parentDir = lastSlash <= 0 ? '/' : oldPath.substring(0, lastSlash);
    final newPath = parentDir == '/' ? '/$newName' : '$parentDir/$newName';

    if (session.sftp != null) {
      try {
        await session.sftp!.rename(oldPath, newPath);
        return;
      } catch (_) {}
    }
    await session.run('mv "$oldPath" "$newPath"');
  }

  Future<void> moveRemote(RemoteSession session, String srcPath, String destDirPath) async {
    final cleanDest = destDirPath.endsWith('/') && destDirPath.length > 1
        ? destDirPath.substring(0, destDirPath.length - 1)
        : destDirPath;
    final name = srcPath.split('/').last;
    final targetPath = cleanDest == '/' ? '/$name' : '$cleanDest/$name';

    if (session.sftp != null) {
      try {
        await session.sftp!.rename(srcPath, targetPath);
        return;
      } catch (_) {}
    }
    await session.run('mv "$srcPath" "$targetPath"');
  }

  Future<void> copyRemote(RemoteSession session, String srcPath, String destDirPath) async {
    final cleanDest = destDirPath.endsWith('/') && destDirPath.length > 1
        ? destDirPath.substring(0, destDirPath.length - 1)
        : destDirPath;
    final name = srcPath.split('/').last;
    final targetPath = cleanDest == '/' ? '/$name' : '$cleanDest/$name';

    await session.run('cp -r "$srcPath" "$targetPath"');
  }

  Future<String> readRemoteText(RemoteSession session, String path) async {
    if (session.sftp != null) {
      try {
        final file = await session.sftp!.open(path, mode: SftpFileOpenMode.read);
        final bytes = await file.readBytes();
        await file.close();
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {}
    }
    final bytes = await session.run('cat "$path"');
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeRemoteText(RemoteSession session, String path, String content) async {
    final bytes = utf8.encode(content);
    if (session.sftp != null) {
      try {
        final file = await session.sftp!.open(
          path,
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );
        await file.writeBytes(Uint8List.fromList(bytes));
        await file.close();
        return;
      } catch (_) {}
    }
    final encoded = base64Encode(bytes);
    await session.run('echo "$encoded" | base64 -d > "$path"');
  }

  // ==========================================
  // Cross-Transfer (Upload / Download / Copy)
  // ==========================================

  Future<void> uploadLocalToRemote(
    String localPath,
    RemoteSession session,
    String remoteDestDir, {
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final entity = FileSystemEntity.isFileSync(localPath)
        ? File(localPath)
        : Directory(localPath);
    final name = localPath.split(Platform.pathSeparator).last;
    final cleanDest = remoteDestDir.endsWith('/') && remoteDestDir.length > 1
        ? remoteDestDir.substring(0, remoteDestDir.length - 1)
        : remoteDestDir;
    final targetRemotePath = cleanDest == '/' ? '/$name' : '$cleanDest/$name';

    if (entity is File) {
      final totalBytes = await entity.length();

      // Check if threshold qualifies for Rust native engine (>= 500 MB)
      if (RustSftpBridge.shouldUseRust(totalBytes) &&
          RustSftpBridge.isAvailable &&
          session.target != null &&
          session.target!.type != ExplorerTargetType.local) {
        try {
          final success = await RustSftpBridge.transferFile(
            host: session.target!.host,
            port: session.target!.port,
            username: session.target!.username,
            password: session.target!.password,
            jumpHost: session.target!.jumpHost,
            jumpPort: session.target!.jumpPort,
            jumpUsername: session.target!.jumpUsername,
            jumpPassword: session.target!.jumpPassword,
            localPath: localPath,
            remotePath: targetRemotePath,
            isUpload: true,
            onProgress: onProgress,
          );
          if (success) return;
        } catch (e) {
          debugPrint('[FileExplorerService] Rust native upload failed, falling back to Dart: $e');
        }
      }

      if (session.sftp != null) {
        final rFile = await session.sftp!.open(
          targetRemotePath,
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );
        try {
          var sentBytes = 0;
          final stream = entity.openRead().map((chunk) {
            sentBytes += chunk.length;
            onProgress?.call(sentBytes, totalBytes);
            return Uint8List.fromList(chunk);
          });
          await rFile.write(stream).done;
        } finally {
          await rFile.close();
        }
      } else {
        if (totalBytes > 50 * 1024 * 1024) {
          throw UnsupportedError(
            'File size (${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB) exceeds shell fallback limit (50 MB). SFTP subsystem required.',
          );
        }
        final bytes = await entity.readAsBytes();
        onProgress?.call(bytes.length, totalBytes);
        final encoded = base64Encode(bytes);
        await session.run('echo "$encoded" | base64 -d > "$targetRemotePath"');
      }
    } else if (entity is Directory) {
      if (session.sftp != null) {
        try {
          await session.sftp!.mkdir(targetRemotePath);
        } catch (_) {}
      } else {
        await session.run('mkdir -p "$targetRemotePath"');
      }

      await for (final child in entity.list(recursive: false)) {
        await uploadLocalToRemote(
          child.path,
          session,
          targetRemotePath,
          onProgress: onProgress,
        );
      }
    }
  }

  Future<void> downloadRemoteToLocal(
    RemoteSession session,
    String remotePath,
    bool isDir,
    String localDestDir, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final name = remotePath.split('/').last;
    final targetLocalPath = '$localDestDir${Platform.pathSeparator}$name';

    if (!isDir) {
      final localFile = File(targetLocalPath);
      await localFile.parent.create(recursive: true);

      int totalBytes = -1;
      if (session.sftp != null) {
        try {
          final attrs = await session.sftp!.stat(remotePath);
          totalBytes = attrs.size ?? -1;
        } catch (_) {}
      }

      // Check if threshold qualifies for Rust native engine (>= 500 MB)
      if (totalBytes > 0 &&
          RustSftpBridge.shouldUseRust(totalBytes) &&
          RustSftpBridge.isAvailable &&
          session.target != null &&
          session.target!.type != ExplorerTargetType.local) {
        try {
          final success = await RustSftpBridge.transferFile(
            host: session.target!.host,
            port: session.target!.port,
            username: session.target!.username,
            password: session.target!.password,
            jumpHost: session.target!.jumpHost,
            jumpPort: session.target!.jumpPort,
            jumpUsername: session.target!.jumpUsername,
            jumpPassword: session.target!.jumpPassword,
            localPath: targetLocalPath,
            remotePath: remotePath,
            isUpload: false,
            onProgress: onProgress,
          );
          if (success) return;
        } catch (e) {
          debugPrint('[FileExplorerService] Rust native download failed, falling back to Dart: $e');
        }
      }

      if (session.sftp != null) {
        final remoteFile = await session.sftp!.open(remotePath, mode: SftpFileOpenMode.read);
        final sink = localFile.openWrite();
        var received = 0;
        try {
          await for (final chunk in remoteFile.read()) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, totalBytes > 0 ? totalBytes : received);
          }
          await sink.flush();
        } finally {
          await sink.close();
          await remoteFile.close();
        }
      } else {
        if (totalBytes > 50 * 1024 * 1024) {
          throw UnsupportedError(
            'File size exceeds shell fallback limit (50 MB). SFTP subsystem required.',
          );
        }
        final bytes = await session.run('cat "$remotePath"');
        await localFile.writeAsBytes(bytes);
        onProgress?.call(bytes.length, bytes.length);
      }
    } else {
      final localDir = Directory(targetLocalPath);
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }
      final items = await listRemote(session, remotePath);
      for (final item in items) {
        if (item.name == '..') continue;
        await downloadRemoteToLocal(
          session,
          item.path,
          item.isDir,
          targetLocalPath,
          onProgress: onProgress,
        );
      }
    }
  }

  Future<void> mergeRemote(
    RemoteSession session,
    List<String> remotePaths,
    String destDir,
    String newFileName,
  ) async {
    final cleanDest = destDir.endsWith('/') && destDir.length > 1
        ? destDir.substring(0, destDir.length - 1)
        : destDir;
    final targetPath = cleanDest == '/' ? '/$newFileName' : '$cleanDest/$newFileName';

    final escapedPaths = remotePaths.map((p) => '"$p"').join(' ');
    await session.run('cat $escapedPaths > "$targetPath"');
  }

  void closeAllSessions() {
    for (final s in _cachedSessions.values) {
      s.close();
    }
    _cachedSessions.clear();
  }

  @visibleForTesting
  String? Function()? customWiresharkPathResolver;

  @visibleForTesting
  Future<bool> Function(String filePath)? customWiresharkLauncher;

  /// Detects installed Wireshark GUI executable on the host system.
  String? getWiresharkPath() {
    if (customWiresharkPathResolver != null) {
      return customWiresharkPathResolver!();
    }

    if (Platform.isWindows) {
      final candidates = <String>[
        r'C:\Program Files\Wireshark\Wireshark.exe',
        r'C:\Program Files (x86)\Wireshark\Wireshark.exe',
      ];
      final progFiles = Platform.environment['ProgramFiles'];
      if (progFiles != null && progFiles.isNotEmpty) {
        candidates.add('$progFiles\\Wireshark\\Wireshark.exe');
      }
      final progFilesX86 = Platform.environment['ProgramFiles(x86)'];
      if (progFilesX86 != null && progFilesX86.isNotEmpty) {
        candidates.add('$progFilesX86\\Wireshark\\Wireshark.exe');
      }
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        candidates.add('$localAppData\\Programs\\Wireshark\\Wireshark.exe');
      }
      for (final p in candidates) {
        if (File(p).existsSync()) {
          return p;
        }
      }
      try {
        final result = Process.runSync('where.exe', ['wireshark']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty && File(trimmed).existsSync()) {
              return trimmed;
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isMacOS) {
      const candidates = [
        '/Applications/Wireshark.app/Contents/MacOS/Wireshark',
        '/opt/homebrew/bin/wireshark',
        '/usr/local/bin/wireshark',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      try {
        final result = Process.runSync('which', ['wireshark']);
        if (result.exitCode == 0) {
          final trimmed = (result.stdout as String).trim();
          if (trimmed.isNotEmpty && File(trimmed).existsSync()) return trimmed;
        }
      } catch (_) {}
    } else {
      // Linux
      const candidates = [
        '/usr/bin/wireshark',
        '/usr/local/bin/wireshark',
        '/snap/bin/wireshark',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      try {
        final result = Process.runSync('which', ['wireshark']);
        if (result.exitCode == 0) {
          final trimmed = (result.stdout as String).trim();
          if (trimmed.isNotEmpty && File(trimmed).existsSync()) return trimmed;
        }
      } catch (_) {}
    }
    return null;
  }

  bool isWiresharkInstalled() => getWiresharkPath() != null;

  /// Launches Wireshark GUI in detached mode opening [filePath].
  Future<bool> launchWireshark(String filePath) async {
    if (customWiresharkLauncher != null) {
      return await customWiresharkLauncher!(filePath);
    }
    final exePath = getWiresharkPath();
    if (exePath == null) return false;
    try {
      await Process.start(exePath, [filePath], mode: ProcessStartMode.detached);
      return true;
    } catch (e) {
      debugPrint('Failed to launch Wireshark: $e');
      return false;
    }
  }

  /// Detects installed executable path for an external editor.
  String? getEditorPath(ExternalEditor editor) {
    if (editor == ExternalEditor.internalViewer) return null;
    if (customEditorPathResolver != null) {
      return customEditorPathResolver!(editor);
    }

    if (Platform.isWindows) {
      final progFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final progFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';

      final candidates = <String>[];
      final whereCommands = <String>[];

      switch (editor) {
        case ExternalEditor.notepadPlusPlus:
          candidates.addAll([
            r'C:\Program Files\Notepad++\notepad++.exe',
            r'C:\Program Files (x86)\Notepad++\notepad++.exe',
            '$progFiles\\Notepad++\\notepad++.exe',
            '$progFilesX86\\Notepad++\\notepad++.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Notepad++\\notepad++.exe',
          ]);
          whereCommands.addAll(['notepad++.exe', 'notepad++']);
          break;

        case ExternalEditor.nvim:
          candidates.addAll([
            r'C:\Program Files\Neovim\bin\nvim.exe',
            r'C:\Program Files (x86)\Neovim\bin\nvim.exe',
            '$progFiles\\Neovim\\bin\\nvim.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Neovim\\bin\\nvim.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Neovim\\bin\\nvim.exe',
            r'C:\tools\neovim\bin\nvim.exe',
            r'C:\ProgramData\chocolatey\bin\nvim.exe',
          ]);
          whereCommands.addAll(['nvim.exe', 'nvim']);
          break;

        case ExternalEditor.vscode:
          candidates.addAll([
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Microsoft VS Code\\Code.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Microsoft VS Code\\bin\\code.cmd',
            r'C:\Program Files\Microsoft VS Code\Code.exe',
            r'C:\Program Files\Microsoft VS Code\bin\code.cmd',
            '$progFiles\\Microsoft VS Code\\Code.exe',
            '$progFiles\\Microsoft VS Code\\bin\\code.cmd',
          ]);
          whereCommands.addAll(['code.cmd', 'code.exe', 'code']);
          break;

        case ExternalEditor.zed:
          candidates.addAll([
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Zed\\bin\\Zed.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Zed\\bin\\zed.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Zed\\Zed.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Zed\\zed.exe',
            r'C:\Program Files\Zed\zed.exe',
            '$progFiles\\Zed\\zed.exe',
          ]);
          whereCommands.addAll(['zed.exe', 'zed']);
          break;

        case ExternalEditor.internalViewer:
          return null;
      }

      for (final p in candidates) {
        if (File(p).existsSync()) {
          return p;
        }
      }

      for (final cmd in whereCommands) {
        try {
          final result = Process.runSync('where.exe', [cmd]);
          if (result.exitCode == 0) {
            final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isNotEmpty && File(trimmed).existsSync()) {
                return trimmed;
              }
            }
          }
        } catch (_) {}
      }
    } else if (Platform.isMacOS) {
      final candidates = <String>[];
      final whichCmds = <String>[];

      switch (editor) {
        case ExternalEditor.notepadPlusPlus:
          return null;
        case ExternalEditor.nvim:
          candidates.addAll([
            '/opt/homebrew/bin/nvim',
            '/usr/local/bin/nvim',
            '/usr/bin/nvim',
          ]);
          whichCmds.add('nvim');
          break;
        case ExternalEditor.vscode:
          candidates.addAll([
            '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code',
            '/usr/local/bin/code',
          ]);
          whichCmds.add('code');
          break;
        case ExternalEditor.zed:
          candidates.addAll([
            '/Applications/Zed.app/Contents/MacOS/Zed',
            '/usr/local/bin/zed',
          ]);
          whichCmds.add('zed');
          break;
        case ExternalEditor.internalViewer:
          return null;
      }

      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      for (final cmd in whichCmds) {
        try {
          final result = Process.runSync('which', [cmd]);
          if (result.exitCode == 0) {
            final trimmed = (result.stdout as String).trim();
            if (trimmed.isNotEmpty && File(trimmed).existsSync()) return trimmed;
          }
        } catch (_) {}
      }
    } else {
      // Linux
      final candidates = <String>[];
      final whichCmds = <String>[];

      switch (editor) {
        case ExternalEditor.notepadPlusPlus:
          return null;
        case ExternalEditor.nvim:
          candidates.addAll([
            '/usr/bin/nvim',
            '/usr/local/bin/nvim',
            '/snap/bin/nvim',
          ]);
          whichCmds.add('nvim');
          break;
        case ExternalEditor.vscode:
          candidates.addAll([
            '/usr/bin/code',
            '/snap/bin/code',
            '/usr/local/bin/code',
          ]);
          whichCmds.add('code');
          break;
        case ExternalEditor.zed:
          candidates.addAll([
            '/usr/bin/zed',
            '/usr/local/bin/zed',
          ]);
          whichCmds.add('zed');
          break;
        case ExternalEditor.internalViewer:
          return null;
      }

      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      for (final cmd in whichCmds) {
        try {
          final result = Process.runSync('which', [cmd]);
          if (result.exitCode == 0) {
            final trimmed = (result.stdout as String).trim();
            if (trimmed.isNotEmpty && File(trimmed).existsSync()) return trimmed;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  bool isEditorInstalled(ExternalEditor editor) {
    if (editor == ExternalEditor.internalViewer) return true;
    return getEditorPath(editor) != null;
  }

  /// Launches an external editor opening [filePath].
  Future<bool> launchExternalEditor(ExternalEditor editor, String filePath) async {
    if (editor == ExternalEditor.internalViewer) return true;
    if (customEditorLauncher != null) {
      return await customEditorLauncher!(editor, filePath);
    }

    final exePath = getEditorPath(editor);
    if (exePath == null) return false;

    try {
      if (Platform.isWindows) {
        if (editor == ExternalEditor.nvim) {
          final userName = Platform.environment['USERNAME'] ?? '';
          final localApp = Platform.environment['LOCALAPPDATA'];
          final wtCandidates = [
            if (userName.isNotEmpty)
              'C:\\Users\\$userName\\AppData\\Local\\Microsoft\\WindowsApps\\wt.exe',
            if (localApp != null && localApp.isNotEmpty)
              '$localApp\\Microsoft\\WindowsApps\\wt.exe',
          ];
          String? wtPath;
          for (final w in wtCandidates) {
            if (File(w).existsSync()) {
              wtPath = w;
              break;
            }
          }
          if (wtPath != null) {
            await Process.start(wtPath, [exePath, filePath], mode: ProcessStartMode.detached);
          } else {
            await Process.start('cmd.exe', ['/c', 'start', '""', exePath, filePath], runInShell: true);
          }
          return true;
        } else if (exePath.toLowerCase().endsWith('.cmd') || exePath.toLowerCase().endsWith('.bat')) {
          await Process.start('cmd.exe', ['/c', exePath, filePath], mode: ProcessStartMode.detached);
          return true;
        } else {
          await Process.start(exePath, [filePath], mode: ProcessStartMode.detached);
          return true;
        }
      } else {
        await Process.start(exePath, [filePath], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (e) {
      debugPrint('Failed to launch editor $editor: $e');
      return false;
    }
  }

  /// Downloads a remote file to a local temporary path.
  Future<String> downloadRemoteToTemp(RemoteSession session, String remotePath, String fileName) async {
    final tempDir = await Directory.systemTemp.createTemp('smart_e_he_preview_');
    final localPath = '${tempDir.path}${Platform.pathSeparator}$fileName';
    if (session.sftp != null) {
      try {
        final file = await session.sftp!.open(remotePath, mode: SftpFileOpenMode.read);
        final bytes = await file.readBytes();
        await file.close();
        await File(localPath).writeAsBytes(bytes);
        return localPath;
      } catch (_) {}
    }
    final bytes = await session.run('cat "$remotePath"');
    await File(localPath).writeAsBytes(bytes);
    return localPath;
  }
}
