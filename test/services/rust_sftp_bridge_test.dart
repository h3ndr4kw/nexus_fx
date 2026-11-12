import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';
import 'package:nexus_fx/services/rust_sftp_bridge.dart';

void main() {
  group('RustSftpBridge', () {
    test('loads the DLL when it is built with the current API version', () {
      final dll = RustSftpBridge.resolveDllPath();
      if (dll == null) {
        markTestSkipped('sftp_engine.dll not built (scripts/build_native.ps1)');
        return;
      }
      expect(File(dll).existsSync(), isTrue);
      expect(RustSftpBridge.isAvailable, isTrue,
          reason: '$dll must export nexus_sftp_api_version == '
              '${RustSftpBridge.expectedApiVersion}');
    });

    test('exception classification', () {
      expect(const RustSftpException(RustSftpException.cancelled, '').isCancelled, isTrue);
      for (final code in [
        RustSftpException.auth,
        RustSftpException.connect,
        RustSftpException.sftpUnavailable,
        RustSftpException.workerDied,
      ]) {
        expect(RustSftpException(code, '').isConnectionLevel, isTrue, reason: '$code');
      }
      expect(const RustSftpException(RustSftpException.io, '').isConnectionLevel, isFalse);
    });
  });

  group('TransferCancelToken native hooks', () {
    test('pause listeners fire on pause/resume and can be removed', () {
      final token = TransferCancelToken();
      final seen = <bool>[];
      final remove = token.addPauseListener(() => seen.add(token.isPaused));
      token.pause();
      token.resume();
      remove();
      token.pause();
      expect(seen, [true, false]);
    });

    test('enterHalt marks the token halted until left, once', () {
      final token = TransferCancelToken();
      var notified = 0;
      token.onPauseStateChanged = () => notified++;
      final leave = token.enterHalt();
      expect(token.isHalted, isTrue);
      leave();
      leave();
      expect(token.isHalted, isFalse);
      expect(notified, 2);
    });
  });
}
