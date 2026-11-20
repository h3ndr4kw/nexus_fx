import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/windows_conpty.dart';

void main() {
  group('WindowsConPty.buildCommandLine', () {
    test('quotes paths and arguments with spaces', () {
      expect(
        WindowsConPty.buildCommandLine(
          r'C:\Program Files\PowerShell\7\pwsh.exe',
          ['-NoLogo', 'Write-Host "hi there"'],
        ),
        r'"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo "Write-Host \"hi there\""',
      );
    });

    test('doubles trailing backslashes inside quotes', () {
      expect(WindowsConPty.buildCommandLine('a', [r'C:\dir with space\']),
          r'a "C:\dir with space\\"');
    });

    test('quotes empty arguments', () {
      expect(WindowsConPty.buildCommandLine('a', ['']), 'a ""');
    });
  });

  test(
    'runs the shell on a real console with UTF-8 output',
    () async {
      final pty = await WindowsConPty.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-Command',
          r'"tty:$([Console]::IsInputRedirected)/$([Console]::IsOutputRedirected)"; '
              r'"glyph:$([char]0x276F)$([char]::ConvertFromUtf32(0x1F4E6))"',
        ],
        columns: 120,
        rows: 30,
      );
      final out = StringBuffer();
      final done = pty.output.cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach(out.write);
      final code = await pty.exitCode.timeout(const Duration(seconds: 30));
      await done.timeout(const Duration(seconds: 10));

      final text = out.toString();
      expect(code, 0, reason: text);
      expect(text, contains('tty:False/False'));
      expect(text, contains('glyph:\u276F\u{1F4E6}'));
    },
    skip: !Platform.isWindows,
  );
}
