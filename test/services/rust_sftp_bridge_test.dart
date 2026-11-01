import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/rust_sftp_bridge.dart';

void main() {
  group('RustSftpBridge Tests', () {
    test('Library loader resolves and detects availability', () {
      final isAvailable = RustSftpBridge.isAvailable;
      expect(isAvailable, isTrue, reason: 'sftp_engine.dll should be detected in release target');
    });

    test('Threshold constant is exactly 500 MB', () {
      expect(RustSftpBridge.kRustTransferThreshold, equals(500 * 1024 * 1024));
    });

    test('Threshold check helper functions', () {
      expect(RustSftpBridge.shouldUseRust(499 * 1024 * 1024), isFalse);
      expect(RustSftpBridge.shouldUseRust(500 * 1024 * 1024), isTrue);
      expect(RustSftpBridge.shouldUseRust(1024 * 1024 * 1024), isTrue);
    });
  });
}
