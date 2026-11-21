import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/file_explorer_models.dart';
import 'ssh_service.dart';
import 'rust_sftp_bridge.dart';
import 'known_hosts_service.dart';
import 'ssh_key_loader.dart';
import 'archive_commands.dart';
import 'app_log.dart';
import 'external_tools.dart';
import 'local_file_operations.dart';
import 'remote_session.dart';
import 'transfer_control.dart';

export 'external_tools.dart';
export 'local_file_operations.dart';
export 'remote_session.dart';
export 'transfer_control.dart';

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

  /// Operations on this machine's disk.
  LocalFileOperations local = LocalFileOperations();

  /// Wireshark and external editor discovery and launch.
  ExternalTools externalTools = ExternalTools();

  FileExplorerService();

  static FileExplorerService get instance {
    _instance ??= FileExplorerService();
    return _instance!;
  }

  static set instance(FileExplorerService inst) {
    _instance = inst;
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
      } catch (e, st) {
        AppLog.warning('FileExplorer: SFTP remove failed, falling back to rm', e, st);
      }
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
      } catch (e, st) {
        AppLog.warning('FileExplorer: SFTP rename failed, falling back to mv', e, st);
      }
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
      } catch (e, st) {
        AppLog.warning('FileExplorer: SFTP move failed, falling back to mv', e, st);
      }
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
    if (session.sftp != null) {
      try {
        final file = await session.sftp!.open(path, mode: SftpFileOpenMode.read);
        final bytes = await file.readBytes();
        await file.close();
        return utf8.decode(bytes, allowMalformed: true);
      } catch (e, st) {
        AppLog.warning('FileExplorer: SFTP read failed, falling back to cat', e, st);
      }
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
      } catch (e, st) {
        AppLog.warning('FileExplorer: SFTP write failed, falling back to base64 over shell', e, st);
      }
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
        : TransferProgressAggregator(await local.localSize(localPath), onProgress);
    await _uploadLocalToRemote(localPath, session, remoteDestDir, agg, cancelToken,
        destName: destName);
  }

  Future<void> _uploadLocalToRemote(
    String localPath,
    RemoteSession session,
    String remoteDestDir,
    TransferProgressAggregator? agg,
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
        } catch (_) {
          // Fails when the folder already exists, which is the usual case on
          // a re-upload. A folder that really cannot be created fails the
          // uploads into it below, and those errors are reported.
        }
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
    TransferProgressAggregator? agg;
    if (onProgress != null) {
      var total = -1;
      if (!isDir && session.sftp != null) {
        try {
          total = (await session.sftp!.stat(remotePath)).size ?? -1;
        } catch (e, st) {
          AppLog.warning('FileExplorer: SFTP stat failed, sizing with shell', e, st);
        }
      }
      if (total <= 0) total = await session.sizeOf(remotePath);
      agg = TransferProgressAggregator(total, onProgress);
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
    TransferProgressAggregator? agg,
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
        } catch (e, st) {
          AppLog.warning('FileExplorer: SFTP stat failed, download size unknown', e, st);
        }
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
        } catch (e, st) {
          AppLog.warning('FileExplorer: download abort callback', e, st);
        }
      }
      try {
        await sink.flush();
      } catch (e, st) {
        AppLog.warning('FileExplorer: flushing download file', e, st);
      }
      try {
        await sink.close();
      } catch (e, st) {
        AppLog.warning('FileExplorer: closing download file', e, st);
      }
      if (!ok) {
        try {
          if (await localFile.exists()) await localFile.delete();
        } catch (e, st) {
          AppLog.warning('FileExplorer: deleting partial download', e, st);
        }
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
      } catch (e, st) {
        AppLog.warning('FileExplorer: SFTP download failed, falling back to cat', e, st);
      }
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

