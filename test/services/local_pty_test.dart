import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/local_pty.dart';

void main() {
  test('default shells exist on this platform', () {
    final shells = LocalPty.defaultShells();
    expect(shells, isNotEmpty);
  });

  test('unix environment forces a capable TERM', () {
    final env = LocalPty.unixEnvironment();
    expect(env['TERM'], 'xterm-256color');
    expect(env['LANG'], isNotEmpty);
  });

  test('child process sees a terminal on stdin and stdout', () async {
    final (executable, args) = Platform.isWindows
        ? (
            'powershell.exe',
            [
              '-NoProfile',
              '-Command',
              r'"tty:$(-not [Console]::IsInputRedirected)/$(-not [Console]::IsOutputRedirected)"',
            ]
          )
        : ('/bin/sh', ['-c', r'printf "tty:%s/%s\n" "$( [ -t 0 ] && echo True )" "$( [ -t 1 ] && echo True )"']);

    final pty = await LocalPty.start(
      executable,
      args,
      columns: 100,
      rows: 30,
      environment: Platform.isWindows ? null : LocalPty.unixEnvironment(),
    );
    final out = StringBuffer();
    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(out.write);
    final code = await pty.exitCode.timeout(const Duration(seconds: 30));
    // Output can trail the exit notification by a moment.
    for (var i = 0; i < 50 && !out.toString().contains('tty:'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(code, 0, reason: out.toString());
    expect(out.toString(), contains('tty:True/True'));
  });
}
