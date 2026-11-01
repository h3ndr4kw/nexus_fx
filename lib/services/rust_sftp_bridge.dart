import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

final class _SftpTransferConfigC extends Struct {
  external Pointer<Utf8> host;
  @Uint16()
  external int port;
  external Pointer<Utf8> username;
  external Pointer<Utf8> password;
  external Pointer<Utf8> jumpHost;
  @Uint16()
  external int jumpPort;
  external Pointer<Utf8> jumpUsername;
  external Pointer<Utf8> jumpPassword;
  external Pointer<Utf8> localPath;
  external Pointer<Utf8> remotePath;
}

typedef _NativeProgressCallback = Void Function(Int64 transferred, Int64 total);

typedef _NexusIsAvailableC = Int32 Function();
typedef _NexusIsAvailableDart = int Function();

typedef _NexusTransferC = Int32 Function(
  Pointer<_SftpTransferConfigC> config,
  Pointer<NativeFunction<_NativeProgressCallback>> callback,
  Pointer<Uint8> cancelFlag,
);
typedef _NexusTransferDart = int Function(
  Pointer<_SftpTransferConfigC> config,
  Pointer<NativeFunction<_NativeProgressCallback>> callback,
  Pointer<Uint8> cancelFlag,
);

class RustSftpBridge {
  /// Threshold in bytes: exactly 500 MB
  static const int kRustTransferThreshold = 500 * 1024 * 1024;

  static bool? _cachedIsAvailable;
  static String? _resolvedDllPath;

  /// Check whether the file size qualifies for the high-speed Rust engine
  static bool shouldUseRust(int byteSize) {
    return byteSize >= kRustTransferThreshold;
  }

  /// Locates the compiled sftp_engine.dll across build, execution, and development directories
  static String? resolveDllPath() {
    if (_resolvedDllPath != null && File(_resolvedDllPath!).existsSync()) {
      return _resolvedDllPath;
    }

    final candidatePaths = <String>[
      // Release build output in project root
      '${Directory.current.path}${Platform.pathSeparator}native${Platform.pathSeparator}sftp_engine${Platform.pathSeparator}target${Platform.pathSeparator}release${Platform.pathSeparator}sftp_engine.dll',
      // Debug build output in project root
      '${Directory.current.path}${Platform.pathSeparator}native${Platform.pathSeparator}sftp_engine${Platform.pathSeparator}target${Platform.pathSeparator}debug${Platform.pathSeparator}sftp_engine.dll',
      // Runner directory beside executable (Windows production bundle)
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}sftp_engine.dll',
      // Runner release build directory
      '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}windows${Platform.pathSeparator}x64${Platform.pathSeparator}runner${Platform.pathSeparator}Release${Platform.pathSeparator}sftp_engine.dll',
      '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}windows${Platform.pathSeparator}x64${Platform.pathSeparator}runner${Platform.pathSeparator}Debug${Platform.pathSeparator}sftp_engine.dll',
    ];

    for (final path in candidatePaths) {
      if (File(path).existsSync()) {
        _resolvedDllPath = path;
        return path;
      }
    }
    return null;
  }

  /// Check whether the Rust native engine is available on the current system
  static bool get isAvailable {
    if (_cachedIsAvailable != null) {
      return _cachedIsAvailable!;
    }

    try {
      final dllPath = resolveDllPath();
      if (dllPath == null) {
        _cachedIsAvailable = false;
        return false;
      }

      final lib = DynamicLibrary.open(dllPath);
      final isAvailableFn = lib
          .lookup<NativeFunction<_NexusIsAvailableC>>('nexus_sftp_is_available')
          .asFunction<_NexusIsAvailableDart>();
      
      final res = isAvailableFn();
      _cachedIsAvailable = res == 1;
      return _cachedIsAvailable!;
    } catch (e) {
      debugPrint('[RustSftpBridge] Failed to load native library: $e');
      _cachedIsAvailable = false;
      return false;
    }
  }

  /// Transfers a large file using the Rust engine on a background worker thread.
  static Future<bool> transferFile({
    required String host,
    required int port,
    required String username,
    required String password,
    String? jumpHost,
    int jumpPort = 22,
    String? jumpUsername,
    String? jumpPassword,
    required String localPath,
    required String remotePath,
    required bool isUpload,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final dllPath = resolveDllPath();
    if (dllPath == null || !isAvailable) {
      throw UnsupportedError('Rust SFTP engine dynamic library is not available');
    }

    final receivePort = ReceivePort();
    final workerParams = _WorkerTransferParams(
      dllPath: dllPath,
      host: host,
      port: port,
      username: username,
      password: password,
      jumpHost: jumpHost,
      jumpPort: jumpPort,
      jumpUsername: jumpUsername,
      jumpPassword: jumpPassword,
      localPath: localPath,
      remotePath: remotePath,
      isUpload: isUpload,
      replyPort: receivePort.sendPort,
    );

    final completer = Completer<bool>();

    late StreamSubscription sub;
    sub = receivePort.listen((message) {
      if (message is _ProgressMessage) {
        onProgress?.call(message.transferred, message.total);
      } else if (message is _ResultMessage) {
        sub.cancel();
        receivePort.close();
        if (message.exitCode == 0) {
          completer.complete(true);
        } else {
          completer.completeError(
            Exception('Rust SFTP transfer failed with code: ${message.exitCode}'),
          );
        }
      }
    });

    await Isolate.spawn(_runNativeTransferWorker, workerParams);
    return completer.future;
  }
}

class _ProgressMessage {
  final int transferred;
  final int total;
  _ProgressMessage(this.transferred, this.total);
}

class _ResultMessage {
  final int exitCode;
  _ResultMessage(this.exitCode);
}

class _WorkerTransferParams {
  final String dllPath;
  final String host;
  final int port;
  final String username;
  final String password;
  final String? jumpHost;
  final int jumpPort;
  final String? jumpUsername;
  final String? jumpPassword;
  final String localPath;
  final String remotePath;
  final bool isUpload;
  final SendPort replyPort;

  _WorkerTransferParams({
    required this.dllPath,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.jumpHost,
    this.jumpPort = 22,
    this.jumpUsername,
    this.jumpPassword,
    required this.localPath,
    required this.remotePath,
    required this.isUpload,
    required this.replyPort,
  });
}

void _runNativeTransferWorker(_WorkerTransferParams params) {
  final lib = DynamicLibrary.open(params.dllPath);
  final fnName = params.isUpload ? 'nexus_sftp_upload' : 'nexus_sftp_download';
  final transferFn = lib
      .lookup<NativeFunction<_NexusTransferC>>(fnName)
      .asFunction<_NexusTransferDart>();

  final config = calloc<_SftpTransferConfigC>();
  config.ref.host = params.host.toNativeUtf8();
  config.ref.port = params.port;
  config.ref.username = params.username.toNativeUtf8();
  config.ref.password = params.password.toNativeUtf8();

  if (params.jumpHost != null && params.jumpHost!.isNotEmpty) {
    config.ref.jumpHost = params.jumpHost!.toNativeUtf8();
    config.ref.jumpPort = params.jumpPort;
    config.ref.jumpUsername = (params.jumpUsername ?? '').toNativeUtf8();
    config.ref.jumpPassword = (params.jumpPassword ?? '').toNativeUtf8();
  } else {
    config.ref.jumpHost = nullptr;
    config.ref.jumpPort = 22;
    config.ref.jumpUsername = nullptr;
    config.ref.jumpPassword = nullptr;
  }

  config.ref.localPath = params.localPath.toNativeUtf8();
  config.ref.remotePath = params.remotePath.toNativeUtf8();

  // Progress callback bridging to SendPort
  final callback = NativeCallable<_NativeProgressCallback>.isolateLocal((int transferred, int total) {
    params.replyPort.send(_ProgressMessage(transferred, total));
  });

  int result = -99;
  try {
    result = transferFn(config, callback.nativeFunction, nullptr);
  } catch (e) {
    debugPrint('[RustSftpBridge Worker] Exception during native call: $e');
  } finally {
    callback.close();
    calloc.free(config.ref.host);
    calloc.free(config.ref.username);
    calloc.free(config.ref.password);
    if (config.ref.jumpHost != nullptr) {
      calloc.free(config.ref.jumpHost);
      calloc.free(config.ref.jumpUsername);
      calloc.free(config.ref.jumpPassword);
    }
    calloc.free(config.ref.localPath);
    calloc.free(config.ref.remotePath);
    calloc.free(config);
  }

  params.replyPort.send(_ResultMessage(result));
}
