import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/ssh_service.dart';

void main() {
  test(
    'local shell takes the terminal size set while it was starting',
    () async {
      final conn = SshConnection(
        id: 'local_size_test',
        host: 'localhost',
        port: 0,
        label: 'LOCAL',
        isLocalShell: true,
        enableLogging: false,
      );
      final out = StringBuffer();
      final sub = conn.outputStream.listen(out.write);
      try {
        // The tab lays the terminal out while the shell is still starting,
        // so the first real size arrives before the PTY exists.
        final connecting = conn.connect();
        // Let connect() read the (default) size and begin spawning first.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(conn.isConnected, isFalse, reason: 'resize must land mid-start');
        conn.terminal.resize(150, 50);
        expect(await connecting, isTrue);

        conn.write(r'Write-Output "SIZE=$([Console]::WindowWidth)x$([Console]::WindowHeight)"' '\r');
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!RegExp(r'SIZE=\d+x\d+').hasMatch(out.toString()) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(RegExp(r'SIZE=\d+x\d+').firstMatch(out.toString())?.group(0), 'SIZE=150x50');
      } finally {
        await sub.cancel();
        conn.dispose();
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
