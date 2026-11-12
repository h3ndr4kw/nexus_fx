// End-to-end tests for the native (Rust) SFTP engine against a local
// paramiko SFTP server (test/fixtures/sftp_test_server.py).
//
// Skipped automatically when sftp_engine.dll is not built
// (scripts/build_native.ps1) or Python with paramiko is not installed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';
import 'package:nexus_fx/services/rust_sftp_bridge.dart';

const _user = 'tester';
const _password = 'secret';

String? _skipReason() {
  if (!RustSftpBridge.isAvailable) {
    return 'sftp_engine.dll (API v${RustSftpBridge.expectedApiVersion}) not built';
  }
  try {
    final r = Process.runSync('python', ['-I', '-c', 'import paramiko']);
    if (r.exitCode != 0) return 'python with paramiko not available';
  } catch (_) {
    return 'python not available';
  }
  return null;
}

class _TestServer {
  _TestServer._(this.process, this.port, this.root);

  final Process process;
  final int port;
  final Directory root;

  static Future<_TestServer> start({String auth = 'password', int throttle = 0}) async {
    final root = await Directory.systemTemp.createTemp('sftp_e2e_root_');
    final script = '${Directory.current.path}${Platform.pathSeparator}test'
        '${Platform.pathSeparator}fixtures${Platform.pathSeparator}sftp_test_server.py';
    final process = await Process.start('python', [
      '-I', script, '--root', root.path, '--auth', auth, '--throttle', '$throttle',
    ]);
    final portLine = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((l) => l.startsWith('PORT '))
        .timeout(const Duration(seconds: 20));
    process.stderr
        .transform(utf8.decoder)
        .listen((l) => stderr.write('[sftp_test_server] $l'));
    return _TestServer._(process, int.parse(portLine.substring(5).trim()), root);
  }

  RustSftpConnectParams params({String password = _password}) => RustSftpConnectParams(
        host: '127.0.0.1',
        port: port,
        username: _user,
        password: password,
      );

  String remote(String name) => '/$name';
  File file(String name) => File('${root.path}${Platform.pathSeparator}$name');

  Future<void> stop() async {
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  }
}

Uint8List _randomBytes(int n, [int seed = 7]) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

Future<void> _until(bool Function() cond, {Duration timeout = const Duration(seconds: 20)}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Runs [body] in a zone that ignores [SocketException]s. dartssh2 reports
/// the server's TCP reset after `close()` as an async socket error in the
/// zone that opened the socket, which would otherwise fail the test.
Future<T> _quietly<T>(Future<T> Function() body) {
  final done = Completer<T>();
  runZonedGuarded(() async {
    try {
      done.complete(await body());
    } catch (e, s) {
      if (!done.isCompleted) done.completeError(e, s);
    }
  }, (e, s) {
    if (e is SocketException) return;
    if (!done.isCompleted) {
      done.completeError(e, s);
    } else {
      Zone.root.handleUncaughtError(e, s);
    }
  });
  return done.future;
}

void main() {
  final skip = _skipReason();

  group('RustSftpConnection (native engine) e2e', () {
    late Directory local;

    setUp(() async {
      local = await Directory.systemTemp.createTemp('sftp_e2e_local_');
    });

    tearDown(() async {
      try {
        await local.delete(recursive: true);
      } catch (_) {}
    });

    String localPath(String name) => '${local.path}${Platform.pathSeparator}$name';

    test('downloads and uploads over one reused connection', () async {
      final server = await _TestServer.start();
      addTearDown(server.stop);
      final data = _randomBytes(3 * 1024 * 1024);
      server.file('big.bin').writeAsBytesSync(data);

      final conn = await RustSftpConnection.connect(server.params());
      addTearDown(conn.close);

      final progress = <int>[];
      await conn.download(server.remote('big.bin'), localPath('big.bin'),
          onProgress: (t, total) {
        progress.add(t);
        expect(total, data.length);
      });
      expect(File(localPath('big.bin')).readAsBytesSync(), data);
      expect(progress.last, data.length);

      final up = _randomBytes(1024 * 1024, 11);
      File(localPath('up.bin')).writeAsBytesSync(up);
      await conn.upload(localPath('up.bin'), server.remote('up.bin'));
      expect(server.file('up.bin').readAsBytesSync(), up);

      // A second download on the same connection.
      await conn.download(server.remote('up.bin'), localPath('up_again.bin'));
      expect(File(localPath('up_again.bin')).readAsBytesSync(), up);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('cancel stops a download mid-file and removes the partial file', () async {
      final server = await _TestServer.start(throttle: 512 * 1024);
      addTearDown(server.stop);
      server.file('slow.bin').writeAsBytesSync(_randomBytes(8 * 1024 * 1024));

      final conn = await RustSftpConnection.connect(server.params());
      addTearDown(conn.close);

      final token = TransferCancelToken();
      var transferred = 0;
      final future = conn.download(server.remote('slow.bin'), localPath('slow.bin'),
          onProgress: (t, _) => transferred = t, cancelToken: token);

      await _until(() => transferred > 300 * 1024);
      final sw = Stopwatch()..start();
      token.cancel();
      await expectLater(future, throwsA(isA<TransferCancelledException>()));
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      expect(transferred, lessThan(8 * 1024 * 1024));
      expect(File(localPath('slow.bin')).existsSync(), isFalse);

      // The connection stays usable after a cancel.
      server.file('small.txt').writeAsStringSync('still works');
      await conn.download(server.remote('small.txt'), localPath('small.txt'));
      expect(File(localPath('small.txt')).readAsStringSync(), 'still works');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('pause halts mid-file, resume completes with identical bytes', () async {
      final server = await _TestServer.start(throttle: 1024 * 1024);
      addTearDown(server.stop);
      final data = _randomBytes(4 * 1024 * 1024, 3);
      server.file('pause.bin').writeAsBytesSync(data);

      final conn = await RustSftpConnection.connect(server.params());
      addTearDown(conn.close);

      final token = TransferCancelToken();
      var transferred = 0;
      final future = conn.download(server.remote('pause.bin'), localPath('pause.bin'),
          onProgress: (t, _) => transferred = t, cancelToken: token);

      await _until(() => transferred > 256 * 1024);
      token.pause();
      await _until(() => token.isHalted);
      // Let an in-flight chunk land, then the count must stand still.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final atPause = transferred;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(transferred, atPause, reason: 'no bytes may arrive while paused');
      expect(atPause, lessThan(data.length));

      token.resume();
      expect(token.isHalted, isFalse);
      await future;
      expect(File(localPath('pause.bin')).readAsBytesSync(), data);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('keyboard-interactive-only server is accepted', () async {
      final server = await _TestServer.start(auth: 'kbd');
      addTearDown(server.stop);
      server.file('k.txt').writeAsStringSync('kbd ok');

      final conn = await RustSftpConnection.connect(server.params());
      addTearDown(conn.close);
      await conn.download(server.remote('k.txt'), localPath('k.txt'));
      expect(File(localPath('k.txt')).readAsStringSync(), 'kbd ok');
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('wrong password fails with an auth error', () async {
      final server = await _TestServer.start();
      addTearDown(server.stop);
      await expectLater(
        RustSftpConnection.connect(server.params(password: 'nope')),
        throwsA(isA<RustSftpException>()
            .having((e) => e.code, 'code', RustSftpException.auth)),
      );
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('FileExplorerService routes SFTP downloads through the native engine', () async {
      final server = await _TestServer.start();
      addTearDown(server.stop);
      final data = _randomBytes(2 * 1024 * 1024, 5);
      server.file('svc.bin').writeAsBytesSync(data);

      final svc = FileExplorerService();
      addTearDown(svc.closeAllSessions);
      var nativeConnects = 0;
      svc.customNativeConnector = (t) {
        nativeConnects++;
        return RustSftpConnection.connect(RustSftpConnectParams(
            host: t.host, port: t.port, username: t.username, password: t.password));
      };

      final target = ExplorerNodeTarget(
        type: ExplorerTargetType.customSsh,
        label: 'e2e',
        port: server.port,
        username: _user,
        password: _password,
      );
      final session = await _quietly(() => svc.getOrConnectRemote(target));
      var last = 0;
      await svc.downloadRemoteToLocal(session, '/svc.bin', false, local.path,
          onProgress: (s, _) => last = s, cancelToken: TransferCancelToken());

      expect(nativeConnects, 1);
      expect(File(localPath('svc.bin')).readAsBytesSync(), data);
      expect(last, data.length);

      // Upload reuses the same native connection.
      File(localPath('svc_up.bin')).writeAsBytesSync(data);
      await svc.uploadLocalToRemote(localPath('svc_up.bin'), session, '/',
          cancelToken: TransferCancelToken());
      expect(nativeConnects, 1);
      expect(server.file('svc_up.bin').readAsBytesSync(), data);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('FileExplorerService falls back to the Dart client when the engine cannot connect',
        () async {
      final server = await _TestServer.start();
      addTearDown(server.stop);
      server.file('fb.txt').writeAsStringSync('fallback');

      final svc = FileExplorerService();
      addTearDown(svc.closeAllSessions);
      var attempts = 0;
      svc.customNativeConnector = (t) async {
        attempts++;
        throw const RustSftpException(RustSftpException.auth, 'simulated');
      };
      final target = ExplorerNodeTarget(
        type: ExplorerTargetType.customSsh,
        label: 'e2e',
        port: server.port,
        username: _user,
        password: _password,
      );
      final session = await _quietly(() => svc.getOrConnectRemote(target));
      await svc.downloadRemoteToLocal(session, '/fb.txt', false, local.path);
      await svc.downloadRemoteToLocal(session, '/fb.txt', false, local.path,
          destName: 'fb2.txt');

      expect(File(localPath('fb.txt')).readAsStringSync(), 'fallback');
      expect(File(localPath('fb2.txt')).readAsStringSync(), 'fallback');
      expect(attempts, 1, reason: 'an unsupported target is not retried every file');
    }, timeout: const Timeout(Duration(minutes: 1)));
  }, skip: skip);
}
