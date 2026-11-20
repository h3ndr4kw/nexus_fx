import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';

import 'windows_conpty.dart';

/// A local shell running on a pseudo-terminal, so programs see a real TTY:
/// ConPTY on Windows, `forkpty` on Linux and macOS.
abstract class LocalPty {
  /// Terminal output: UTF-8 text with VT escape sequences.
  Stream<Uint8List> get output;

  /// Completes with the exit code once the process has terminated.
  Future<int> get exitCode;

  void write(List<int> data);

  void resize(int columns, int rows);

  void kill();

  static Future<LocalPty> start(
    String executable,
    List<String> arguments, {
    required int columns,
    required int rows,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (Platform.isWindows) {
      return _WindowsLocalPty(await WindowsConPty.start(
        executable,
        arguments,
        columns: columns,
        rows: rows,
        workingDirectory: workingDirectory,
        environment: environment,
      ));
    }
    return _UnixLocalPty(Pty.start(
      executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      columns: columns,
      rows: rows,
    ));
  }

  /// Shells to try for the local tab, best first, with their arguments.
  static List<(String, List<String>)> defaultShells() {
    if (Platform.isWindows) {
      const pwsh7 = r'C:\Program Files\PowerShell\7\pwsh.exe';
      return [
        if (File(pwsh7).existsSync()) (pwsh7, const ['-NoLogo']),
        ('powershell.exe', const ['-NoLogo']),
      ];
    }
    final candidates = <String>[
      if (Platform.environment['SHELL']?.isNotEmpty ?? false) Platform.environment['SHELL']!,
      if (Platform.isMacOS) '/bin/zsh',
      '/bin/bash',
      '/bin/sh',
    ];
    final seen = <String>{};
    return [
      for (final shell in candidates)
        if (seen.add(shell) && File(shell).existsSync()) (shell, const ['-l']),
    ];
  }

  /// Environment for a Unix shell: the app's own environment with a terminal
  /// type that matches the xterm emulator. A GUI launch often has no TERM or
  /// TERM=dumb, which turns off colours and line editing.
  static Map<String, String> unixEnvironment() => {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
        if (!(Platform.environment['LANG']?.isNotEmpty ?? false)) 'LANG': 'en_US.UTF-8',
      };
}

class _WindowsLocalPty implements LocalPty {
  _WindowsLocalPty(this._pty);
  final WindowsConPty _pty;

  @override
  Stream<Uint8List> get output => _pty.output;
  @override
  Future<int> get exitCode => _pty.exitCode;
  @override
  void write(List<int> data) => _pty.write(data);
  @override
  void resize(int columns, int rows) => _pty.resize(columns, rows);
  @override
  void kill() => _pty.kill();
}

class _UnixLocalPty implements LocalPty {
  _UnixLocalPty(this._pty);
  final Pty _pty;

  @override
  Stream<Uint8List> get output => _pty.output;
  @override
  Future<int> get exitCode => _pty.exitCode;
  @override
  void write(List<int> data) =>
      _pty.write(data is Uint8List ? data : Uint8List.fromList(data));
  // flutter_pty takes rows first.
  @override
  void resize(int columns, int rows) => _pty.resize(rows, columns);
  @override
  void kill() => _pty.kill();
}
