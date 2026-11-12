import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'file_explorer_service.dart' show TransferCancelToken, TransferCancelledException;

// ---------------------------------------------------------------------------
// C ABI (native/sftp_engine/src/ffi.rs, API version 3)
// ---------------------------------------------------------------------------

final class _ConnectConfigC extends Struct {
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
  external Pointer<Utf8> hostKeys;
  external Pointer<Utf8> jumpHostKeys;
}

typedef _NativeProgressCallback = Void Function(Int64 transferred, Int64 total);

typedef _IntFnC = Int32 Function();
typedef _IntFnDart = int Function();

typedef _ConnectC = Pointer<Void> Function(
  Pointer<_ConnectConfigC> config,
  Pointer<Utf8> errBuf,
  IntPtr errLen,
  Pointer<Int32> outCode,
);
typedef _ConnectDart = Pointer<Void> Function(
  Pointer<_ConnectConfigC> config,
  Pointer<Utf8> errBuf,
  int errLen,
  Pointer<Int32> outCode,
);

typedef _TransferC = Int32 Function(
  Pointer<Void> engine,
  Pointer<Utf8> from,
  Pointer<Utf8> to,
  Pointer<NativeFunction<_NativeProgressCallback>> callback,
  Pointer<Uint8> control,
  Pointer<Utf8> errBuf,
  IntPtr errLen,
);
typedef _TransferDart = int Function(
  Pointer<Void> engine,
  Pointer<Utf8> from,
  Pointer<Utf8> to,
  Pointer<NativeFunction<_NativeProgressCallback>> callback,
  Pointer<Uint8> control,
  Pointer<Utf8> errBuf,
  int errLen,
);

typedef _DisconnectC = Void Function(Pointer<Void> engine);
typedef _DisconnectDart = void Function(Pointer<Void> engine);

const int _errBufLen = 1024;

/// Error from the native engine. [code] matches `EngineError::code` in Rust.
class RustSftpException implements Exception {
  const RustSftpException(this.code, this.message);

  static const int invalidArgs = -1;
  static const int io = -2;
  static const int auth = -3;
  static const int connect = -4;
  static const int sftpUnavailable = -5;
  static const int cancelled = -6;
  static const int hostKey = -7;
  static const int workerDied = -98;
  static const int panic = -99;

  final int code;
  final String message;

  bool get isCancelled => code == cancelled;

  /// The engine cannot talk to this target at all (as opposed to one file
  /// failing), so falling back to the Dart client for the rest makes sense.
  bool get isConnectionLevel =>
      code == auth ||
      code == connect ||
      code == sftpUnavailable ||
      code == hostKey ||
      code == workerDied ||
      code == panic;

  @override
  String toString() => message;
}

/// Where and as whom to connect. Plain data so it can cross isolates.
@immutable
class RustSftpConnectParams {
  const RustSftpConnectParams({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.jumpHost,
    this.jumpPort = 22,
    this.jumpUsername,
    this.jumpPassword,
    this.hostKeys = const [],
    this.jumpHostKeys = const [],
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String? jumpHost;
  final int jumpPort;
  final String? jumpUsername;
  final String? jumpPassword;

  /// `SHA256:...` fingerprints the target may present. The engine refuses
  /// any other key, and refuses everything when this is empty.
  final List<String> hostKeys;

  /// Same for the jump host.
  final List<String> jumpHostKeys;
}

/// One SFTP connection the file explorer can push file transfers through.
/// Implemented by [RustSftpConnection]; tests substitute fakes.
abstract class NativeSftpLink {
  bool get isClosed;

  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int transferred, int total)? onProgress,
    TransferCancelToken? cancelToken,
  });

  Future<void> upload(
    String localPath,
    String remotePath, {
    void Function(int transferred, int total)? onProgress,
    TransferCancelToken? cancelToken,
  });

  Future<void> close();
}

class RustSftpBridge {
  static const int expectedApiVersion = 3;

  static bool? _cachedIsAvailable;
  static String? _resolvedDllPath;

  /// Locates the compiled sftp_engine.dll across build, execution, and development directories
  static String? resolveDllPath() {
    if (_resolvedDllPath != null && File(_resolvedDllPath!).existsSync()) {
      return _resolvedDllPath;
    }
    final sep = Platform.pathSeparator;
    final cwd = Directory.current.path;
    final candidatePaths = <String>[
      // Beside the executable (installed bundle / flutter build output)
      '${File(Platform.resolvedExecutable).parent.path}${sep}sftp_engine.dll',
      // Cargo output when running from the nexus_fx project root
      '$cwd${sep}native${sep}sftp_engine${sep}target${sep}release${sep}sftp_engine.dll',
      '$cwd${sep}native${sep}sftp_engine${sep}target${sep}debug${sep}sftp_engine.dll',
      '$cwd${sep}build${sep}windows${sep}x64${sep}runner${sep}Release${sep}sftp_engine.dll',
      '$cwd${sep}build${sep}windows${sep}x64${sep}runner${sep}Debug${sep}sftp_engine.dll',
    ];
    for (final path in candidatePaths) {
      if (File(path).existsSync()) {
        _resolvedDllPath = path;
        return path;
      }
    }
    return null;
  }

  /// True when a DLL with the expected C ABI can be loaded.
  static bool get isAvailable {
    final cached = _cachedIsAvailable;
    if (cached != null) return cached;
    try {
      final dllPath = resolveDllPath();
      if (dllPath == null) return _cachedIsAvailable = false;
      final lib = DynamicLibrary.open(dllPath);
      if (!lib.providesSymbol('nexus_sftp_api_version')) {
        debugPrint('[RustSftpBridge] $dllPath is an old build (no API version); ignoring it');
        return _cachedIsAvailable = false;
      }
      final version = lib.lookupFunction<_IntFnC, _IntFnDart>('nexus_sftp_api_version')();
      if (version != expectedApiVersion) {
        debugPrint('[RustSftpBridge] $dllPath has API v$version, need v$expectedApiVersion');
        return _cachedIsAvailable = false;
      }
      return _cachedIsAvailable = true;
    } catch (e) {
      debugPrint('[RustSftpBridge] Failed to load native library: $e');
      return _cachedIsAvailable = false;
    }
  }

  @visibleForTesting
  static void resetCache() {
    _cachedIsAvailable = null;
    _resolvedDllPath = null;
  }
}

/// A connection held by a dedicated worker isolate. All SSH crypto and file
/// I/O happens in native code on that isolate's thread, never on the UI
/// isolate. Transfers run one at a time, in call order.
///
/// Cancel and pause go through two bytes of native memory that the engine
/// polls (every chunk, and every 100 ms while waiting), so both take effect
/// mid-file. While paused the engine stops reading, which stops the SSH
/// window and therefore the sender.
class RustSftpConnection implements NativeSftpLink {
  RustSftpConnection._(
    this._isolate,
    this._commands,
    this._replies,
    this._repliesPort,
    this._exits,
    this._exitPort,
  );

  final Isolate _isolate;
  final SendPort _commands;
  final Stream<dynamic> _replies;
  final ReceivePort _repliesPort;
  final Stream<dynamic> _exits;
  final ReceivePort _exitPort;
  final Map<int, _PendingOp> _pending = {};
  int _nextId = 1;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  Completer<void>? _closing;

  @override
  bool get isClosed => _closed;

  static Future<RustSftpConnection> connect(
    RustSftpConnectParams params, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final dllPath = RustSftpBridge.resolveDllPath();
    if (dllPath == null || !RustSftpBridge.isAvailable) {
      throw UnsupportedError('Rust SFTP engine dynamic library is not available');
    }

    final replies = ReceivePort('sftp_engine.replies');
    final exitPort = ReceivePort('sftp_engine.exit');
    // Ports are single-subscription; the connection listens again later.
    final replyStream = replies.asBroadcastStream();
    final exitStream = exitPort.asBroadcastStream();
    final errorPort = ReceivePort('sftp_engine.error');
    final ready = Completer<SendPort>();
    late final StreamSubscription<dynamic> errSub;
    errSub = errorPort.listen((e) {
      if (!ready.isCompleted) {
        ready.completeError(RustSftpException(RustSftpException.workerDied, 'Native worker failed: $e'));
      }
    });
    final exitSub = exitStream.listen((_) {
      if (!ready.isCompleted) {
        ready.completeError(const RustSftpException(RustSftpException.workerDied, 'Native worker exited while connecting'));
      }
    });
    late final StreamSubscription<dynamic> replySub;
    replySub = replyStream.listen((msg) {
      if (msg is _Connected) {
        ready.complete(msg.commands);
      } else if (msg is _ConnectFailed) {
        ready.completeError(RustSftpException(msg.code, msg.message));
      }
    });

    final isolate = await Isolate.spawn(
      _workerMain,
      _WorkerStart(dllPath, params, replies.sendPort),
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
      errorsAreFatal: true,
      debugName: 'sftp_engine ${params.host}',
    );

    final SendPort commands;
    try {
      commands = await ready.future.timeout(timeout, onTimeout: () {
        isolate.kill(priority: Isolate.immediate);
        throw RustSftpException(RustSftpException.connect,
            'Native engine: no connection to ${params.host} after ${timeout.inSeconds}s');
      });
    } catch (_) {
      await replySub.cancel();
      await exitSub.cancel();
      await errSub.cancel();
      replies.close();
      exitPort.close();
      errorPort.close();
      rethrow;
    } finally {
      await errSub.cancel();
      errorPort.close();
    }
    await replySub.cancel();
    await exitSub.cancel();

    final conn = RustSftpConnection._(
        isolate, commands, replyStream, replies, exitStream, exitPort);
    conn._listen();
    return conn;
  }

  void _listen() {
    _replies.listen((msg) {
      if (msg is _Progress) {
        _pending[msg.id]?.onProgress?.call(msg.transferred, msg.total);
      } else if (msg is _Done) {
        final op = _pending.remove(msg.id);
        if (op == null) return;
        if (msg.code == 0) {
          op.done.complete();
        } else {
          op.done.completeError(RustSftpException(msg.code, msg.message));
        }
      } else if (msg is _Closed) {
        _closing?.complete();
      }
    });
    _exits.listen((_) => _onWorkerGone());
  }

  void _onWorkerGone() {
    _closed = true;
    for (final op in _pending.values) {
      if (!op.done.isCompleted) {
        op.done.completeError(const RustSftpException(
            RustSftpException.workerDied, 'Native SFTP worker stopped unexpectedly'));
      }
    }
    _pending.clear();
    if (!(_closing?.isCompleted ?? true)) _closing!.complete();
    _repliesPort.close();
    _exitPort.close();
  }

  @override
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int transferred, int total)? onProgress,
    TransferCancelToken? cancelToken,
  }) =>
      _enqueue(false, remotePath, localPath, onProgress, cancelToken);

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    void Function(int transferred, int total)? onProgress,
    TransferCancelToken? cancelToken,
  }) =>
      _enqueue(true, localPath, remotePath, onProgress, cancelToken);

  Future<void> _enqueue(
    bool upload,
    String from,
    String to,
    void Function(int, int)? onProgress,
    TransferCancelToken? token,
  ) {
    final run = _tail.then((_) => _run(upload, from, to, onProgress, token));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _run(
    bool upload,
    String from,
    String to,
    void Function(int, int)? onProgress,
    TransferCancelToken? token,
  ) async {
    token?.throwIfCancelled();
    if (_closed) {
      throw const RustSftpException(RustSftpException.workerDied, 'Native SFTP connection is closed');
    }

    final control = calloc<Uint8>(2); // [cancel, pause]
    void Function()? leaveHalt;
    void syncPause() {
      final paused = token?.isPaused ?? false;
      control[1] = paused ? 1 : 0;
      if (paused && leaveHalt == null) {
        leaveHalt = token!.enterHalt();
      } else if (!paused && leaveHalt != null) {
        leaveHalt!();
        leaveHalt = null;
      }
    }

    final removePauseListener = token?.addPauseListener(syncPause);
    final unregisterCancel = token?.onCancel(() => control[0] = 1);
    syncPause();

    final id = _nextId++;
    final op = _PendingOp(onProgress);
    _pending[id] = op;
    try {
      _commands.send(_Transfer(id, upload, from, to, control.address));
      await op.done.future;
    } on RustSftpException catch (e) {
      if (e.isCancelled || (token?.isCancelled ?? false)) {
        throw const TransferCancelledException();
      }
      rethrow;
    } finally {
      removePauseListener?.call();
      unregisterCancel?.call();
      leaveHalt?.call();
      // The engine has returned (or its isolate is gone): nothing reads the
      // control block any more.
      calloc.free(control);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final closing = _closing = Completer<void>();
    // Let queued transfers finish first; the worker handles messages in order.
    _commands.send(const _Close());
    await closing.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _isolate.kill(priority: Isolate.immediate);
    });
  }
}

class _PendingOp {
  _PendingOp(this.onProgress);
  final void Function(int, int)? onProgress;
  final Completer<void> done = Completer<void>();
}

// ---------------------------------------------------------------------------
// Worker isolate
// ---------------------------------------------------------------------------

class _WorkerStart {
  const _WorkerStart(this.dllPath, this.params, this.replies);
  final String dllPath;
  final RustSftpConnectParams params;
  final SendPort replies;
}

class _Connected {
  const _Connected(this.commands);
  final SendPort commands;
}

class _ConnectFailed {
  const _ConnectFailed(this.code, this.message);
  final int code;
  final String message;
}

class _Transfer {
  const _Transfer(this.id, this.upload, this.from, this.to, this.controlAddress);
  final int id;
  final bool upload;
  final String from;
  final String to;
  final int controlAddress;
}

class _Progress {
  const _Progress(this.id, this.transferred, this.total);
  final int id;
  final int transferred;
  final int total;
}

class _Done {
  const _Done(this.id, this.code, this.message);
  final int id;
  final int code;
  final String message;
}

class _Close {
  const _Close();
}

class _Closed {
  const _Closed();
}

Pointer<Utf8> _str(String? s, Arena arena) =>
    (s == null || s.isEmpty) ? nullptr : s.toNativeUtf8(allocator: arena);

void _workerMain(_WorkerStart start) {
  final lib = DynamicLibrary.open(start.dllPath);
  final connect = lib.lookupFunction<_ConnectC, _ConnectDart>('nexus_sftp_connect');
  final download = lib.lookupFunction<_TransferC, _TransferDart>('nexus_sftp_engine_download');
  final upload = lib.lookupFunction<_TransferC, _TransferDart>('nexus_sftp_engine_upload');
  final disconnect = lib.lookupFunction<_DisconnectC, _DisconnectDart>('nexus_sftp_disconnect');

  final p = start.params;
  final engine = using((arena) {
    final cfg = arena<_ConnectConfigC>();
    cfg.ref
      ..host = _str(p.host, arena)
      ..port = p.port
      ..username = p.username.toNativeUtf8(allocator: arena)
      ..password = p.password.toNativeUtf8(allocator: arena)
      ..jumpHost = _str(p.jumpHost, arena)
      ..jumpPort = p.jumpPort
      ..jumpUsername = _str(p.jumpUsername, arena)
      ..jumpPassword = _str(p.jumpPassword, arena)
      ..hostKeys = _str(p.hostKeys.join('\n'), arena)
      ..jumpHostKeys = _str(p.jumpHostKeys.join('\n'), arena);
    final err = arena<Uint8>(_errBufLen).cast<Utf8>();
    final code = arena<Int32>();
    final handle = connect(cfg, err, _errBufLen, code);
    if (handle == nullptr) {
      start.replies.send(_ConnectFailed(code.value, err.toDartString()));
    }
    return handle;
  });
  if (engine == nullptr) return; // isolate ends; main side already told

  final commands = ReceivePort('sftp_engine.commands');
  start.replies.send(_Connected(commands.sendPort));

  commands.listen((msg) {
    if (msg is _Transfer) {
      final id = msg.id;
      final callback = NativeCallable<_NativeProgressCallback>.isolateLocal(
        (int transferred, int total) => start.replies.send(_Progress(id, transferred, total)),
      );
      try {
        using((arena) {
          final err = arena<Uint8>(_errBufLen).cast<Utf8>();
          err.cast<Uint8>().value = 0;
          final fn = msg.upload ? upload : download;
          final code = fn(
            engine,
            msg.from.toNativeUtf8(allocator: arena),
            msg.to.toNativeUtf8(allocator: arena),
            callback.nativeFunction,
            Pointer<Uint8>.fromAddress(msg.controlAddress),
            err,
            _errBufLen,
          );
          start.replies.send(_Done(id, code, code == 0 ? '' : err.toDartString()));
        });
      } finally {
        callback.close();
      }
    } else if (msg is _Close) {
      disconnect(engine);
      start.replies.send(const _Closed());
      commands.close();
    }
  });
}
