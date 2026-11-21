import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/file_explorer_models.dart';
import 'ssh_service.dart';
import 'ssh_tunnel_manager.dart';
import 'rust_sftp_bridge.dart';
import 'known_hosts_service.dart';
import 'ssh_key_loader.dart';
import 'app_paths.dart';
import 'archive_commands.dart';

class RemoteSession {
  final SSHClient client;
  SftpClient? sftp;
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
    if (await detectTmshShell()) {
      return await _runViaTmshBash(cmd);
    }
    return await client.run(cmd);
  }

  /// Starts [cmd] on an exec channel and returns the live session, so callers
  /// can stream stdin/stdout (for byte-level progress). Applies the same
  /// FE-hop and tmsh wrapping as [run].
  Future<SSHSession> execute(String cmd) async {
    if (feHostname != null && feHostname!.isNotEmpty) {
      final escaped = cmd.replaceAll("'", "'\\''");
      return await client.execute(
        "ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $feHostname '$escaped'",
      );
    }
    if (await detectTmshShell()) {
      await ensureShellAccess();
      final encoded = base64.encode(utf8.encode(cmd));
      return await client.execute(
        'run util bash -c "echo $encoded | base64 -d | bash"',
      );
    }
    return await client.execute(cmd);
  }

  /// Total size in bytes of [path] (file or directory), or -1 if unknown.
  Future<int> sizeOf(String path) async {
    try {
      final out = utf8.decode(
        await run('du -sb "$path" 2>/dev/null | cut -f1'),
        allowMalformed: true,
      );
      return int.tryParse(out.trim().split('\n').last.trim()) ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// Whether the remote login shell is F5 tmsh (null = not probed yet).
  bool? isTmshShell;

  static const _shellProbeMarker = '__NEXUS_SHELL_OK__';
  static final _tmshErrorPattern = RegExp(r'^\s*Syntax Error:', multiLine: true);

  /// Probes the login shell once. F5 BIG-IP users whose shell is tmsh cannot
  /// run POSIX commands (or SFTP) directly; commands must go through
  /// `run util bash -c`.
  Future<bool> detectTmshShell() async {
    final known = isTmshShell;
    if (known != null) return known;
    var tmsh = false;
    try {
      final out = utf8.decode(
        await client.run('echo $_shellProbeMarker'),
        allowMalformed: true,
      );
      tmsh = !out.contains(_shellProbeMarker) && _tmshErrorPattern.hasMatch(out);
    } catch (_) {}
    isTmshShell = tmsh;
    if (tmsh) {
      // The SFTP subsystem is unusable under tmsh (the channel carries tmsh
      // text instead of SFTP packets), so stop trying it for this session.
      sftp?.close();
      sftp = null;
    }
    return tmsh;
  }

  bool _shellAccessVerified = false;

  /// Under tmsh, verifies that this user may run `run util bash` (F5 roles
  /// without advanced-shell access may not). Throws a clear error instead of
  /// letting callers treat tmsh's refusal text as command output.
  Future<void> ensureShellAccess() async {
    if (_shellAccessVerified || !await detectTmshShell()) return;
    final out = utf8.decode(
      await client
          .run('run util bash -c "echo $_shellProbeMarker"')
          .timeout(const Duration(seconds: 20)),
      allowMalformed: true,
    );
    if (!out.contains(_shellProbeMarker)) {
      final firstLine = out.trim().isEmpty
          ? 'no output'
          : out.trim().split('\n').first.trim();
      throw ShellAccessDeniedException(
        'Bash access denied on this node: the tmsh user is not allowed to '
        'run "run util bash" ($firstLine). File transfer needs bash or SFTP '
        'access.',
      );
    }
    _shellAccessVerified = true;
  }

  Future<Uint8List> _runViaTmshBash(String cmd) async {
    await ensureShellAccess();
    // Base64 keeps the command free of quoting issues in tmsh's parser.
    final encoded = base64.encode(utf8.encode(cmd));
    final out = await client.run(
      'run util bash -c "echo $encoded | base64 -d | bash"',
    );
    final text = utf8.decode(out, allowMalformed: true);
    if (_tmshErrorPattern.hasMatch(text)) {
      final firstLine = text.trim().split('\n').first;
      throw Exception(
        'tmsh shell rejected "run util bash" (bash access required): $firstLine',
      );
    }
    return out;
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

  // Native (Rust) SFTP engine: one connection per remote target, reused for
  // every file and closed after [nativeIdleTimeout] without a transfer.
  final Map<String, _NativeLinkEntry> _nativeLinks = {};
  final Map<String, Future<NativeSftpLink?>> _nativeConnecting = {};

  /// Targets the native engine could not connect to (auth method, ciphers,
  /// no SFTP...). They use the Dart client until [closeAllSessions].
  final Set<String> _nativeUnsupported = {};

  Duration nativeIdleTimeout = const Duration(seconds: 60);

  @visibleForTesting
  Future<NativeSftpLink> Function(ExplorerNodeTarget target)? customNativeConnector;

  /// Forces native engine availability on/off in tests.
  @visibleForTesting
  bool? nativeEngineAvailableOverride;

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

  // Local filesystem operations

  Future<List<FileExplorerItem>> listLocal(String dirPath, {String filter = ''}) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return listLocal(AppPaths.defaultLocalDir, filter: filter);
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

  /// Copies [srcPath] into [destDirPath], named [destName] if given (else
  /// the source name).
  Future<void> copyLocal(
    String srcPath,
    String destDirPath, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    String? destName,
  }) async {
    final name = destName ?? srcPath.split(Platform.pathSeparator).last;
    final destPath = '$destDirPath${Platform.pathSeparator}$name';
    final isDir = await Directory(srcPath).exists();
    final agg = onProgress == null
        ? null
        : _ProgressAggregator(await _localSize(srcPath), onProgress);

    if (isDir) {
      await _copyDirLocal(Directory(srcPath), Directory(destPath), agg, cancelToken);
    } else {
      await File(destPath).parent.create(recursive: true);
      await _copyFileLocal(File(srcPath), File(destPath), agg?.forFile(), cancelToken);
    }
  }

  Future<void> _copyFileLocal(
    File src,
    File dest,
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
  ) async {
    final totalBytes = await src.length();
    final sink = dest.openWrite();
    var sent = 0;
    var ok = false;
    try {
      await for (final chunk in src.openRead()) {
        cancelToken?.throwIfCancelled();
        if (cancelToken?.isPaused ?? false) await cancelToken!.waitIfPaused();
        sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent, totalBytes);
      }
      await sink.flush();
      ok = true;
    } finally {
      await sink.close();
      if (!ok) {
        try {
          await dest.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _copyDirLocal(
    Directory src,
    Directory dest,
    _ProgressAggregator? agg,
    TransferCancelToken? cancelToken,
  ) async {
    if (!await dest.exists()) {
      await dest.create(recursive: true);
    }
    await for (final entity in src.list(recursive: false)) {
      final entityName = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments[entity.uri.pathSegments.length - (entity.uri.pathSegments.last.isEmpty ? 2 : 1)]
          : entity.path;
      final newDest = '${dest.path}${Platform.pathSeparator}$entityName';
      if (entity is Directory) {
        await _copyDirLocal(entity, Directory(newDest), agg, cancelToken);
      } else if (entity is File) {
        await _copyFileLocal(entity, File(newDest), agg?.forFile(), cancelToken);
      }
    }
  }

  /// Total size in bytes of a local file or directory tree.
  Future<int> _localSize(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.file) return await File(path).length();
    if (type != FileSystemEntityType.directory) return 0;
    var total = 0;
    await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<void> moveLocal(
    String srcPath,
    String destDirPath, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    String? destName,
  }) async {
    final name = destName ?? srcPath.split(Platform.pathSeparator).last;
    final destPath = '$destDirPath${Platform.pathSeparator}$name';
    try {
      // Same-volume rename: atomic and instant.
      if (await Directory(srcPath).exists()) {
        await Directory(srcPath).rename(destPath);
      } else {
        await File(srcPath).rename(destPath);
      }
      onProgress?.call(1, 1);
    } catch (_) {
      // Cross-volume: copy (with progress) then delete.
      await copyLocal(
        srcPath,
        destDirPath,
        onProgress: onProgress,
        cancelToken: cancelToken,
        destName: destName,
      );
      await deleteLocal(srcPath);
    }
  }

  Future<String> readLocalText(String filePath) async {
    final file = File(filePath);
    return await file.readAsString();
  }

  Future<Uint8List> readLocalBytes(String filePath) => File(filePath).readAsBytes();

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

  // Remote node connection & SFTP operations

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
    String password, {
    required String host,
    required int port,
    SshPrivateKeyRef? privateKey,
  }) async {
    final identities = privateKey == null ? null : await loadSshIdentities(privateKey);
    final keyOnly = identities != null && password.isEmpty;
    final client = SSHClient(
      socket,
      username: username,
      onVerifyHostKey: KnownHostsService.instance.handlerFor(host, port),
      identities: identities,
      algorithms: SshAlgorithmHelper.buildAlgorithms(),
      onPasswordRequest: keyOnly ? null : () => password,
      onUserInfoRequest: keyOnly ? null : (r) => r.prompts.map((_) => password).toList(),
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
      // Bad key files fail here, before connecting anywhere.
      final identities =
          target.privateKey == null ? null : await loadSshIdentities(target.privateKey!);
      final jumpIdentities = target.hasJumpHost && target.jumpPrivateKey != null
          ? await loadSshIdentities(target.jumpPrivateKey!)
          : null;
      final keyOnly = identities != null && target.password.isEmpty;
      final jumpKeyOnly = jumpIdentities != null && (target.jumpPassword ?? '').isEmpty;
      if (target.hasJumpHost) {
        final jumpSocket = await SSHSocket.connect(
          target.jumpHost!,
          target.jumpPort,
          timeout: const Duration(seconds: 15),
        );
        jumpClient = SSHClient(
          jumpSocket,
          username: target.jumpUsername ?? '',
          onVerifyHostKey: KnownHostsService.instance
              .handlerFor(target.jumpHost!, target.jumpPort),
          identities: jumpIdentities,
          algorithms: SshAlgorithmHelper.buildAlgorithms(),
          onPasswordRequest: jumpKeyOnly ? null : () => target.jumpPassword ?? '',
          onUserInfoRequest: jumpKeyOnly
              ? null
              : (r) => r.prompts.map((_) => target.jumpPassword ?? '').toList(),
        );
        await jumpClient.authenticated;
        final channel = await jumpClient.forwardLocal(target.host, target.port);
        client = SSHClient(
          channel,
          username: target.username,
          onVerifyHostKey: KnownHostsService.instance
              .handlerFor(target.host, target.port, via: target.jumpHost),
          algorithms: SshAlgorithmHelper.buildAlgorithms(
            sshMacs: target.sshMacs,
            customSshOptions: target.customSshOptions,
          ),
          identities: identities,
          onPasswordRequest: keyOnly ? null : () => target.password,
          onUserInfoRequest: keyOnly
              ? null
              : (r) => r.prompts.map((_) => target.password).toList(),
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
          onVerifyHostKey: KnownHostsService.instance.handlerFor(target.host, target.port),
          algorithms: SshAlgorithmHelper.buildAlgorithms(
            sshMacs: target.sshMacs,
            customSshOptions: target.customSshOptions,
          ),
          identities: identities,
          onPasswordRequest: keyOnly ? null : () => target.password,
          onUserInfoRequest: keyOnly
              ? null
              : (r) => r.prompts.map((_) => target.password).toList(),
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
            host: target.host,
            port: target.port,
            privateKey: target.privateKey,
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

  Future<void> moveRemote(
    RemoteSession session,
    String srcPath,
    String destDirPath, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    String? destName,
  }) async {
    final cleanDest = destDirPath.endsWith('/') && destDirPath.length > 1
        ? destDirPath.substring(0, destDirPath.length - 1)
        : destDirPath;
    final name = destName ?? srcPath.split('/').last;
    final targetPath = cleanDest == '/' ? '/$name' : '$cleanDest/$name';

    if (session.sftp != null) {
      try {
        // Same-filesystem rename: atomic and instant.
        await session.sftp!.rename(srcPath, targetPath);
        onProgress?.call(1, 1);
        return;
      } catch (_) {}
    }
    // `mv` across filesystems copies the data, so track the target growing.
    await _runWithRemoteProgress(
      session,
      'mv "$srcPath" "$targetPath"',
      srcPath: srcPath,
      targetPath: targetPath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<void> copyRemote(
    RemoteSession session,
    String srcPath,
    String destDirPath, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    String? destName,
  }) async {
    final cleanDest = destDirPath.endsWith('/') && destDirPath.length > 1
        ? destDirPath.substring(0, destDirPath.length - 1)
        : destDirPath;
    final name = destName ?? srcPath.split('/').last;
    final targetPath = cleanDest == '/' ? '/$name' : '$cleanDest/$name';

    await _runWithRemoteProgress(
      session,
      'cp -r "$srcPath" "$targetPath"',
      srcPath: srcPath,
      targetPath: targetPath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// Runs a server-side copy/move [cmd] and reports progress by polling the
  /// size of [targetPath] against the size of [srcPath] (measured up front),
  /// since `cp`/`mv` themselves give no progress output.
  Future<void> _runWithRemoteProgress(
    RemoteSession session,
    String cmd, {
    required String srcPath,
    required String targetPath,
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    final total = onProgress == null ? -1 : await session.sizeOf(srcPath);
    if (onProgress == null || total <= 0) {
      await session.run(cmd);
      onProgress?.call(1, 1);
      return;
    }

    onProgress(0, total);
    var finished = false;
    final op = session.run(cmd).whenComplete(() => finished = true);
    while (!finished) {
      await Future.any<void>([
        op.then((_) {}),
        Future<void>.delayed(const Duration(milliseconds: 800)),
      ]);
      if (finished) break;
      if (cancelToken?.isCancelled ?? false) {
        // Stop waiting; the server-side cp/mv cannot be interrupted safely.
        op.ignore();
        throw const TransferCancelledException(
          'Cancelled (the copy may still finish on the node).',
        );
      }
      final current = await session.sizeOf(targetPath);
      if (!finished && current >= 0) {
        // Hold back the last 1% until the command actually exits.
        onProgress(current.clamp(0, (total * 0.99).floor()), total);
      }
    }
    await op;
    onProgress(total, total);
  }

  /// Archives [names] in [dir] on the node into [archiveName] (also in [dir]).
  Future<void> compressRemote(
    RemoteSession session,
    String dir,
    List<String> names,
    String archiveName,
    FileExplorerArchiveFormat format,
  ) async {
    await _runArchiveCommand(
      session,
      remoteCompressCommand(
        dir: dir,
        names: names,
        archiveName: archiveName,
        format: format,
      ),
      remoteToolFor(format: format),
    );
  }

  /// Unpacks [archivePath] on the node into the new folder [destDir].
  Future<void> extractRemote(
    RemoteSession session,
    String archivePath,
    String destDir,
    ArchiveKind kind,
  ) async {
    await _runArchiveCommand(
      session,
      remoteExtractCommand(archivePath: archivePath, destDir: destDir, kind: kind),
      remoteToolFor(kind: kind),
    );
  }

  Future<void> _runArchiveCommand(
    RemoteSession session,
    String cmd,
    String tool,
  ) async {
    final output = utf8.decode(
      await session.run(wrapWithExitCode(cmd)),
      allowMalformed: true,
    );
    final result = parseExitCode(output);
    if (!result.ok) {
      throw ArchiveOperationException(describeRemoteFailure(result, tool));
    }
  }

  Future<String> readRemoteText(RemoteSession session, String path) async {
    final bytes = await readRemoteBytes(session, path);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List> readRemoteBytes(RemoteSession session, String path) async {
    if (session.sftp != null) {
      try {
        final file = await session.sftp!.open(path, mode: SftpFileOpenMode.read);
        final bytes = await file.readBytes();
        await file.close();
        return bytes;
      } catch (_) {}
    }
    return session.run('cat "$path"');
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

  // Cross-transfer operations (upload / download / copy)

  /// Abort a streaming transfer when no bytes arrive for this long.
  static const Duration transferIdleTimeout = Duration(seconds: 30);

  /// Yield to the event loop after this many bytes, so a fast transfer
  /// (SSH crypto runs on the UI isolate) cannot starve frames/input and
  /// make the window "Not Responding".
  static const int _yieldEveryBytes = 512 * 1024;

  Future<void> uploadLocalToRemote(
    String localPath,
    RemoteSession session,
    String remoteDestDir, {
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    String? destName,
  }) async {
    final agg = onProgress == null
        ? null
        : _ProgressAggregator(await _localSize(localPath), onProgress);
    await _uploadLocalToRemote(localPath, session, remoteDestDir, agg, cancelToken,
        destName: destName);
  }

  Future<void> _uploadLocalToRemote(
    String localPath,
    RemoteSession session,
    String remoteDestDir,
    _ProgressAggregator? agg,
    TransferCancelToken? cancelToken, {
    String? destName,
  }) async {
    cancelToken?.throwIfCancelled();
    final entity = FileSystemEntity.isFileSync(localPath)
        ? File(localPath)
        : Directory(localPath);
    final name = destName ?? localPath.split(Platform.pathSeparator).last;
    final cleanDest = remoteDestDir.endsWith('/') && remoteDestDir.length > 1
        ? remoteDestDir.substring(0, remoteDestDir.length - 1)
        : remoteDestDir;
    final targetRemotePath = cleanDest == '/' ? '/$name' : '$cleanDest/$name';

    if (entity is File) {
      final onProgress = agg?.forFile();

      if (await _tryNative(
        session,
        (link) => link.upload(localPath, targetRemotePath,
            onProgress: onProgress, cancelToken: cancelToken),
        what: 'upload of $localPath',
      )) {
        return;
      }

      final totalBytes = await entity.length();

      if (session.sftp != null) {
        final rFile = await session.sftp!.open(
          targetRemotePath,
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );
        try {
          var sentBytes = 0;
          final stream = entity.openRead().asyncMap((chunk) async {
            cancelToken?.throwIfCancelled();
            if (cancelToken?.isPaused ?? false) await cancelToken!.waitIfPaused();
            sentBytes += chunk.length;
            onProgress?.call(sentBytes, totalBytes);
            return Uint8List.fromList(chunk);
          });
          await rFile.write(stream).done;
        } finally {
          await rFile.close();
        }
      } else {
        await _shellUpload(
          session,
          entity,
          targetRemotePath,
          totalBytes,
          onProgress,
          cancelToken,
        );
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
        await _uploadLocalToRemote(
          child.path,
          session,
          targetRemotePath,
          agg,
          cancelToken,
        );
      }
    }
  }

  /// Uploads [file] over a shell exec channel when SFTP is unavailable,
  /// reporting progress per chunk instead of all-at-once.
  Future<void> _shellUpload(
    RemoteSession session,
    File file,
    String targetRemotePath,
    int totalBytes,
    void Function(int sentBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
  ) async {
    // Fails fast with a clear message if tmsh refuses `run util bash`.
    await session.ensureShellAccess();

    if (await session.detectTmshShell()) {
      // tmsh: each command goes through `run util bash -c`, so send the file
      // as base64 chunks appended one command at a time (kept well below the
      // shell's per-argument length limit). One command per 48 KB is slow,
      // so cap the size; larger uploads need SFTP or a bash login shell.
      if (totalBytes > 50 * 1024 * 1024) {
        throw UnsupportedError(
          'File size (${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB) exceeds the tmsh shell upload limit (50 MB). SFTP or a bash login shell is required.',
        );
      }
      const chunkSize = 48 * 1024;
      final raf = await file.open();
      try {
        var sent = 0;
        var first = true;
        while (true) {
          cancelToken?.throwIfCancelled();
          if (cancelToken?.isPaused ?? false) await cancelToken!.waitIfPaused();
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty && !first) break;
          final redirect = first ? '>' : '>>';
          await session
              .run('echo "${base64Encode(chunk)}" | base64 -d $redirect "$targetRemotePath"')
              .timeout(
                transferIdleTimeout,
                onTimeout: () => throw TimeoutException(
                  'Upload stalled: no response from the node for '
                  '${transferIdleTimeout.inSeconds}s (connection dropped or '
                  'access revoked).',
                ),
              );
          first = false;
          sent += chunk.length;
          onProgress?.call(sent, totalBytes);
          if (chunk.length < chunkSize) break;
        }
      } finally {
        await raf.close();
      }
    } else {
      // Regular shell: stream raw bytes into `cat` over stdin.
      final ssh = await session.execute('cat > "$targetRemotePath"');
      final unregister = cancelToken?.onCancel(ssh.close);
      final drainOut = ssh.stdout.drain<void>().catchError((_) {});
      final drainErr = ssh.stderr.drain<void>().catchError((_) {});
      var ok = false;
      try {
        var sent = 0;
        await ssh.stdin.addStream(file.openRead().asyncMap((chunk) async {
          cancelToken?.throwIfCancelled();
          if (cancelToken?.isPaused ?? false) await cancelToken!.waitIfPaused();
          sent += chunk.length;
          onProgress?.call(sent, totalBytes);
          return Uint8List.fromList(chunk);
        }));
        await ssh.stdin.close();
        await ssh.done.timeout(transferIdleTimeout);
        cancelToken?.throwIfCancelled();
        final code = ssh.exitCode;
        if (code != null && code != 0) {
          throw Exception('Upload to $targetRemotePath failed (exit code $code)');
        }
        ok = true;
      } finally {
        unregister?.call();
        if (!ok) ssh.close();
        await drainOut.timeout(const Duration(seconds: 2), onTimeout: () {});
        await drainErr.timeout(const Duration(seconds: 2), onTimeout: () {});
      }
    }

    // Verify the node actually received every byte.
    final remoteSize = await session.sizeOf(targetRemotePath);
    if (remoteSize >= 0 && remoteSize != totalBytes) {
      throw Exception(
        'Upload incomplete: $targetRemotePath has $remoteSize of $totalBytes '
        'bytes (connection dropped or access revoked).',
      );
    }
  }

  Future<void> downloadRemoteToLocal(
    RemoteSession session,
    String remotePath,
    bool isDir,
    String localDestDir, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    String? destName,
  }) async {
    _ProgressAggregator? agg;
    if (onProgress != null) {
      var total = -1;
      if (!isDir && session.sftp != null) {
        try {
          total = (await session.sftp!.stat(remotePath)).size ?? -1;
        } catch (_) {}
      }
      if (total <= 0) total = await session.sizeOf(remotePath);
      agg = _ProgressAggregator(total, onProgress);
    }
    await _downloadRemoteToLocal(
      session,
      remotePath,
      isDir,
      localDestDir,
      agg,
      cancelToken,
      destName: destName,
    );
  }

  Future<void> _downloadRemoteToLocal(
    RemoteSession session,
    String remotePath,
    bool isDir,
    String localDestDir,
    _ProgressAggregator? agg,
    TransferCancelToken? cancelToken, {
    String? destName,
  }) async {
    cancelToken?.throwIfCancelled();
    final name = destName ?? remotePath.split('/').last;
    final targetLocalPath = '$localDestDir${Platform.pathSeparator}$name';

    if (!isDir) {
      final onProgress = agg?.forFile();
      final localFile = File(targetLocalPath);
      await localFile.parent.create(recursive: true);

      if (await _tryNative(
        session,
        (link) => link.download(remotePath, targetLocalPath,
            onProgress: onProgress, cancelToken: cancelToken),
        what: 'download of $remotePath',
      )) {
        return;
      }

      int totalBytes = -1;
      if (session.sftp != null) {
        try {
          final attrs = await session.sftp!.stat(remotePath);
          totalBytes = attrs.size ?? -1;
        } catch (_) {}
      }

      if (session.sftp != null) {
        final remoteFile = await session.sftp!.open(remotePath, mode: SftpFileOpenMode.read);
        await _streamToLocalFile(
          remoteFile.read(),
          localFile,
          totalBytes: totalBytes,
          onProgress: onProgress,
          cancelToken: cancelToken,
          onAbort: () => remoteFile.close(),
          sourceLabel: remotePath,
        );
        await remoteFile.close();
      } else {
        // Fails fast with a clear message if tmsh refuses `run util bash`.
        await session.ensureShellAccess();
        if (totalBytes <= 0) totalBytes = await session.sizeOf(remotePath);
        // Stream `cat` output straight to disk (no size limit, constant
        // memory) so progress advances per chunk.
        final ssh = await session.execute('cat "$remotePath"');
        final drainErr = ssh.stderr.drain<void>().catchError((_) {});
        await _streamToLocalFile(
          ssh.stdout,
          localFile,
          totalBytes: totalBytes,
          onProgress: onProgress,
          cancelToken: cancelToken,
          onAbort: ssh.close,
          sourceLabel: remotePath,
          afterStream: () async {
            await ssh.done.timeout(transferIdleTimeout, onTimeout: () {});
            await drainErr.timeout(const Duration(seconds: 2), onTimeout: () {});
            return ssh.exitCode;
          },
        );
      }
    } else {
      final localDir = Directory(targetLocalPath);
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }
      final items = await listRemote(session, remotePath);
      for (final item in items) {
        if (item.name == '..') continue;
        await _downloadRemoteToLocal(
          session,
          item.path,
          item.isDir,
          targetLocalPath,
          agg,
          cancelToken,
        );
      }
    }
  }

  /// Writes [source] to [localFile] with byte progress, an idle timeout,
  /// cancellation, periodic yielding to keep the UI responsive, and
  /// validation. On any failure the partial local file is deleted and a
  /// descriptive error is thrown.
  Future<void> _streamToLocalFile(
    Stream<Uint8List> source,
    File localFile, {
    required int totalBytes,
    required String sourceLabel,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    TransferCancelToken? cancelToken,
    void Function()? onAbort,
    Future<int?> Function()? afterStream,
  }) async {
    final unregister = onAbort == null ? null : cancelToken?.onCancel(onAbort);
    final sink = localFile.openWrite();
    final head = BytesBuilder(copy: true);
    var received = 0;
    var sinceYield = 0;
    var ok = false;
    try {
      final guarded = source.timeout(
        transferIdleTimeout,
        onTimeout: (s) {
          s.addError(TimeoutException(
            'Download stalled: no data from the node for '
            '${transferIdleTimeout.inSeconds}s (connection dropped or access '
            'revoked).',
          ));
          s.close();
        },
      );
      await for (final chunk in guarded) {
        cancelToken?.throwIfCancelled();
        // Halting here pauses the subscription: the idle timeout stops and
        // SSH back-pressure holds the sender.
        if (cancelToken?.isPaused ?? false) await cancelToken!.waitIfPaused();
        if (head.length < 4096) head.add(chunk);
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, totalBytes > 0 ? totalBytes : received);
        sinceYield += chunk.length;
        if (sinceYield >= _yieldEveryBytes) {
          sinceYield = 0;
          // Pausing here also applies SSH back-pressure (no window adjust
          // while the stream is paused).
          await Future<void>.delayed(Duration.zero);
        }
      }
      cancelToken?.throwIfCancelled();
      final exitCode = afterStream == null ? null : await afterStream();
      cancelToken?.throwIfCancelled();

      final headText = utf8.decode(head.toBytes(), allowMalformed: true);
      final looksLikeShellError = received < 4096 &&
          RegExp(
            r'Syntax Error|not allowed|denied|not authorized|permission|No such file',
            caseSensitive: false,
          ).hasMatch(headText);

      if (totalBytes > 0 && received != totalBytes) {
        final detail = looksLikeShellError ? ': ${headText.trim().split('\n').first}' : '';
        throw Exception(
          'Download incomplete: received $received of $totalBytes bytes for '
          '$sourceLabel (connection dropped or access revoked)$detail',
        );
      }
      if (totalBytes <= 0 &&
          ((exitCode != null && exitCode != 0) || looksLikeShellError)) {
        throw Exception(
          'Download of $sourceLabel failed'
          '${exitCode != null && exitCode != 0 ? ' (exit code $exitCode)' : ''}'
          ': ${headText.trim().isEmpty ? 'no data' : headText.trim().split('\n').first}',
        );
      }
      ok = true;
    } finally {
      unregister?.call();
      if (!ok) {
        try {
          onAbort?.call();
        } catch (_) {}
      }
      try {
        await sink.flush();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
      if (!ok) {
        try {
          if (await localFile.exists()) await localFile.delete();
        } catch (_) {}
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
    // dispose() unregisters itself from the map, so iterate a copy.
    for (final entry in List.of(_nativeLinks.values)) {
      entry.dispose();
    }
    _nativeLinks.clear();
    _nativeUnsupported.clear();
  }

  // Native (Rust) transfer engine

  /// Whether [session]'s target can go through the native engine: it needs a
  /// direct (or jump-host tunnelled) SSH login with an SFTP subsystem. FE
  /// nodes reached by hopping through a cluster shell, and tmsh-only hosts,
  /// stay on the Dart client.
  bool _nativeEligible(RemoteSession session) {
    final t = session.target;
    if (t == null || t.isLocal || t.type == ExplorerTargetType.fe) return false;
    if (session.sftp == null) return false;
    if ((session.feHostname ?? '').isNotEmpty) return false;
    if (_nativeUnsupported.contains(_sessionKey(t))) return false;
    if (customNativeConnector != null) return true;
    return nativeEngineAvailableOverride ?? RustSftpBridge.isAvailable;
  }

  Future<NativeSftpLink> _connectNative(ExplorerNodeTarget t) {
    final custom = customNativeConnector;
    if (custom != null) return custom(t);
    return RustSftpConnection.connect(RustSftpConnectParams(
      host: t.host,
      port: t.port,
      username: t.username,
      password: t.password,
      jumpHost: t.hasJumpHost ? t.jumpHost : null,
      jumpPort: t.jumpPort,
      jumpUsername: t.jumpUsername,
      jumpPassword: t.jumpPassword,
      // The Dart session to this target was verified (and the user asked)
      // already; the engine only accepts those same keys.
      hostKeys: KnownHostsService.instance.fingerprintsFor(t.host, t.port),
      jumpHostKeys: t.hasJumpHost
          ? KnownHostsService.instance.fingerprintsFor(t.jumpHost!, t.jumpPort)
          : const [],
      keyPath: t.privateKey == null ? null : expandKeyPath(t.privateKey!.path),
      keyPassphrase: t.privateKey?.passphrase,
      jumpKeyPath: t.hasJumpHost && t.jumpPrivateKey != null
          ? expandKeyPath(t.jumpPrivateKey!.path)
          : null,
      jumpKeyPassphrase: t.hasJumpHost ? t.jumpPrivateKey?.passphrase : null,
    ));
  }

  /// The cached native connection for [session], connecting on first use.
  /// Returns null (and remembers the target as unsupported) if the engine
  /// cannot connect.
  Future<NativeSftpLink?> _nativeLinkFor(RemoteSession session) async {
    final t = session.target!;
    final key = _sessionKey(t);
    final entry = _nativeLinks[key];
    if (entry != null && !entry.link.isClosed) return entry.link;
    if (entry != null) {
      entry.dispose();
      _nativeLinks.remove(key);
    }
    final pending = _nativeConnecting[key];
    if (pending != null) return pending;

    final future = () async {
      try {
        final link = await _connectNative(t);
        _nativeLinks[key] = _NativeLinkEntry(link, nativeIdleTimeout, () {
          if (identical(_nativeLinks[key]?.link, link)) _nativeLinks.remove(key);
        });
        return link;
      } catch (e) {
        debugPrint('[FileExplorerService] Native engine cannot connect to ${t.host}; '
            'using the Dart client for this target: $e');
        _nativeUnsupported.add(key);
        return null;
      } finally {
        _nativeConnecting.remove(key);
      }
    }();
    _nativeConnecting[key] = future;
    return future;
  }

  /// Runs [op] through the native engine when possible. Returns true when the
  /// file was transferred natively, false when the caller should use the
  /// Dart client instead. Cancellation propagates as
  /// [TransferCancelledException].
  Future<bool> _tryNative(
    RemoteSession session,
    Future<void> Function(NativeSftpLink link) op, {
    required String what,
  }) async {
    if (!_nativeEligible(session)) return false;
    final link = await _nativeLinkFor(session);
    if (link == null) return false;
    final entry = _nativeLinks[_sessionKey(session.target!)];
    entry?.begin();
    try {
      await op(link);
      return true;
    } on TransferCancelledException {
      rethrow;
    } on RustSftpException catch (e) {
      if (e.isConnectionLevel) {
        final key = _sessionKey(session.target!);
        _nativeLinks.remove(key)?.dispose();
        _nativeUnsupported.add(key);
      }
      debugPrint('[FileExplorerService] Native $what failed, retrying with the Dart client: $e');
      return false;
    } catch (e) {
      debugPrint('[FileExplorerService] Native $what failed, retrying with the Dart client: $e');
      return false;
    } finally {
      entry?.end();
    }
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

/// A cached native connection that closes itself after [idle] with no
/// transfer running.
class _NativeLinkEntry {
  _NativeLinkEntry(this.link, this.idle, this._onClosed) {
    _scheduleIdleClose();
  }

  final NativeSftpLink link;
  final Duration idle;
  final void Function() _onClosed;
  int _active = 0;
  Timer? _idleTimer;

  void begin() {
    _active++;
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void end() {
    if (_active > 0) _active--;
    if (_active == 0) _scheduleIdleClose();
  }

  void _scheduleIdleClose() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idle, dispose);
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _onClosed();
    unawaited(link.close().catchError((_) {}));
  }
}

/// Turns per-file progress callbacks into one cumulative progress stream
/// across a whole directory tree, so the bar does not reset for every file.
class _ProgressAggregator {
  _ProgressAggregator(this.total, this._sink);

  final int total;
  final void Function(int sentBytes, int totalBytes) _sink;
  int _done = 0;

  void Function(int sentBytes, int totalBytes) forFile() {
    var last = 0;
    return (sent, _) {
      if (sent > last) {
        _done += sent - last;
        last = sent;
      }
      final effectiveTotal = total > 0 ? total : _done;
      _sink(_done.clamp(0, effectiveTotal), effectiveTotal);
    };
  }
}

/// Thrown when the user cancels a transfer.
class TransferCancelledException implements Exception {
  const TransferCancelledException([this.message = 'Transfer cancelled']);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when a tmsh user may not run `run util bash`.
class ShellAccessDeniedException implements Exception {
  const ShellAccessDeniedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cooperative control for file transfers.
///
/// Cancel: loops poll [throwIfCancelled], and blocking operations (an SSH
/// channel waiting on a stalled peer) register an [onCancel] hook that
/// aborts them.
///
/// Pause: byte loops call [waitIfPaused] between chunks, which halts them
/// (applying back-pressure to the source stream) until [resume]. The native
/// engine follows [addPauseListener] and reports its own halt through
/// [enterHalt]. Operations with no chunk loop (server-side `cp`/`mv`) cannot
/// stop mid-file; they halt at the next pause point instead.
class TransferCancelToken {
  bool _cancelled = false;
  final List<void Function()> _hooks = [];
  final List<void Function()> _pauseListeners = [];

  bool _paused = false;
  Completer<void>? _resumed;
  int _haltedLoops = 0;

  /// Called whenever [isPaused] or [isHalted] changes.
  void Function()? onPauseStateChanged;

  bool get isCancelled => _cancelled;

  /// Pause was requested and not yet resumed.
  bool get isPaused => _paused;

  /// A transfer loop is actually stopped at a pause point right now (as
  /// opposed to a pause that is still waiting for the current file).
  bool get isHalted => _haltedLoops > 0;

  void pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    _resumed = Completer<void>();
    _pauseRequestChanged();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _resumed?.complete();
    _resumed = null;
    _pauseRequestChanged();
  }

  void _pauseRequestChanged() {
    onPauseStateChanged?.call();
    for (final listener in List.of(_pauseListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  /// Calls [listener] whenever [isPaused] flips; returns an unregister
  /// function. For transfers that do not run a Dart byte loop.
  void Function() addPauseListener(void Function() listener) {
    _pauseListeners.add(listener);
    return () => _pauseListeners.remove(listener);
  }

  /// Marks the transfer as actually stopped (see [isHalted]) until the
  /// returned function is called. Calling it more than once is harmless.
  void Function() enterHalt() {
    _haltedLoops++;
    onPauseStateChanged?.call();
    var left = false;
    return () {
      if (left) return;
      left = true;
      _haltedLoops--;
      onPauseStateChanged?.call();
    };
  }

  /// Returns at once unless paused; otherwise waits for [resume] or
  /// [cancel] (then throws [TransferCancelledException]).
  Future<void> waitIfPaused() async {
    throwIfCancelled();
    if (!_paused) return;
    _haltedLoops++;
    onPauseStateChanged?.call();
    try {
      while (_paused && !_cancelled) {
        await _resumed!.future;
      }
    } finally {
      _haltedLoops--;
      onPauseStateChanged?.call();
    }
    throwIfCancelled();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    // Release loops halted on a pause so they can observe the cancel.
    if (_paused) {
      _paused = false;
      _resumed?.complete();
      _resumed = null;
    }
    for (final hook in List.of(_hooks)) {
      try {
        hook();
      } catch (_) {}
    }
    _hooks.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const TransferCancelledException();
  }

  /// Registers [hook] to run on cancel; returns a function that unregisters.
  void Function() onCancel(void Function() hook) {
    if (_cancelled) {
      hook();
      return () {};
    }
    _hooks.add(hook);
    return () => _hooks.remove(hook);
  }
}
