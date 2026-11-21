import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_log.dart';

enum ExternalEditor {
  notepadPlusPlus('Notepad++'),
  nvim('Neovim (nvim)'),
  vscode('VS Code'),
  zed('Zed'),
  internalViewer('Built-in Viewer');

  final String label;
  const ExternalEditor(this.label);
}

/// Finds and starts the desktop programs files are handed to: Wireshark
/// for captures and the user's text editor.
class ExternalTools {
  String? Function(ExternalEditor editor)? customEditorPathResolver;

  @visibleForTesting
  Future<bool> Function(ExternalEditor editor, String filePath)? customEditorLauncher;

  @visibleForTesting
  String? Function()? customWiresharkPathResolver;

  @visibleForTesting
  Future<bool> Function(String filePath)? customWiresharkLauncher;

  /// Detects installed Wireshark GUI executable on the host system.
  String? getWiresharkPath() {
    if (customWiresharkPathResolver != null) {
      return customWiresharkPathResolver!();
    }

    if (Platform.isWindows) {
      final candidates = <String>[
        r'C:\Program Files\Wireshark\Wireshark.exe',
        r'C:\Program Files (x86)\Wireshark\Wireshark.exe',
      ];
      final progFiles = Platform.environment['ProgramFiles'];
      if (progFiles != null && progFiles.isNotEmpty) {
        candidates.add('$progFiles\\Wireshark\\Wireshark.exe');
      }
      final progFilesX86 = Platform.environment['ProgramFiles(x86)'];
      if (progFilesX86 != null && progFilesX86.isNotEmpty) {
        candidates.add('$progFilesX86\\Wireshark\\Wireshark.exe');
      }
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        candidates.add('$localAppData\\Programs\\Wireshark\\Wireshark.exe');
      }
      for (final p in candidates) {
        if (File(p).existsSync()) {
          return p;
        }
      }
      try {
        final result = Process.runSync('where.exe', ['wireshark']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty && File(trimmed).existsSync()) {
              return trimmed;
            }
          }
        }
      } catch (e, st) {
        AppLog.warning('FileExplorer: locating Wireshark', e, st);
      }
    } else if (Platform.isMacOS) {
      const candidates = [
        '/Applications/Wireshark.app/Contents/MacOS/Wireshark',
        '/opt/homebrew/bin/wireshark',
        '/usr/local/bin/wireshark',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      try {
        final result = Process.runSync('which', ['wireshark']);
        if (result.exitCode == 0) {
          final trimmed = (result.stdout as String).trim();
          if (trimmed.isNotEmpty && File(trimmed).existsSync()) return trimmed;
        }
      } catch (e, st) {
        AppLog.warning('FileExplorer: locating Wireshark', e, st);
      }
    } else {
      // Linux
      const candidates = [
        '/usr/bin/wireshark',
        '/usr/local/bin/wireshark',
        '/snap/bin/wireshark',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      try {
        final result = Process.runSync('which', ['wireshark']);
        if (result.exitCode == 0) {
          final trimmed = (result.stdout as String).trim();
          if (trimmed.isNotEmpty && File(trimmed).existsSync()) return trimmed;
        }
      } catch (e, st) {
        AppLog.warning('FileExplorer: locating Wireshark', e, st);
      }
    }
    return null;
  }

  bool isWiresharkInstalled() => getWiresharkPath() != null;

  /// Launches Wireshark GUI in detached mode opening [filePath].
  Future<bool> launchWireshark(String filePath) async {
    if (customWiresharkLauncher != null) {
      return await customWiresharkLauncher!(filePath);
    }
    final exePath = getWiresharkPath();
    if (exePath == null) return false;
    try {
      await Process.start(exePath, [filePath], mode: ProcessStartMode.detached);
      return true;
    } catch (e) {
      debugPrint('Failed to launch Wireshark: $e');
      return false;
    }
  }

  /// Detects installed executable path for an external editor.
  String? getEditorPath(ExternalEditor editor) {
    if (editor == ExternalEditor.internalViewer) return null;
    if (customEditorPathResolver != null) {
      return customEditorPathResolver!(editor);
    }

    if (Platform.isWindows) {
      final progFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final progFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';

      final candidates = <String>[];
      final whereCommands = <String>[];

      switch (editor) {
        case ExternalEditor.notepadPlusPlus:
          candidates.addAll([
            r'C:\Program Files\Notepad++\notepad++.exe',
            r'C:\Program Files (x86)\Notepad++\notepad++.exe',
            '$progFiles\\Notepad++\\notepad++.exe',
            '$progFilesX86\\Notepad++\\notepad++.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Notepad++\\notepad++.exe',
          ]);
          whereCommands.addAll(['notepad++.exe', 'notepad++']);
          break;

        case ExternalEditor.nvim:
          candidates.addAll([
            r'C:\Program Files\Neovim\bin\nvim.exe',
            r'C:\Program Files (x86)\Neovim\bin\nvim.exe',
            '$progFiles\\Neovim\\bin\\nvim.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Neovim\\bin\\nvim.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Neovim\\bin\\nvim.exe',
            r'C:\tools\neovim\bin\nvim.exe',
            r'C:\ProgramData\chocolatey\bin\nvim.exe',
          ]);
          whereCommands.addAll(['nvim.exe', 'nvim']);
          break;

        case ExternalEditor.vscode:
          candidates.addAll([
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Microsoft VS Code\\Code.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Microsoft VS Code\\bin\\code.cmd',
            r'C:\Program Files\Microsoft VS Code\Code.exe',
            r'C:\Program Files\Microsoft VS Code\bin\code.cmd',
            '$progFiles\\Microsoft VS Code\\Code.exe',
            '$progFiles\\Microsoft VS Code\\bin\\code.cmd',
          ]);
          whereCommands.addAll(['code.cmd', 'code.exe', 'code']);
          break;

        case ExternalEditor.zed:
          candidates.addAll([
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Zed\\bin\\Zed.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Zed\\bin\\zed.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Programs\\Zed\\Zed.exe',
            if (localAppData.isNotEmpty) '$localAppData\\Zed\\zed.exe',
            r'C:\Program Files\Zed\zed.exe',
            '$progFiles\\Zed\\zed.exe',
          ]);
          whereCommands.addAll(['zed.exe', 'zed']);
          break;

        case ExternalEditor.internalViewer:
          return null;
      }

      for (final p in candidates) {
        if (File(p).existsSync()) {
          return p;
        }
      }

      for (final cmd in whereCommands) {
        try {
          final result = Process.runSync('where.exe', [cmd]);
          if (result.exitCode == 0) {
            final lines = (result.stdout as String).split(RegExp(r'[\r\n]+'));
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isNotEmpty && File(trimmed).existsSync()) {
                return trimmed;
              }
            }
          }
        } catch (e, st) {
          AppLog.warning('FileExplorer: locating external editor', e, st);
        }
      }
    } else if (Platform.isMacOS) {
      final candidates = <String>[];
      final whichCmds = <String>[];

      switch (editor) {
        case ExternalEditor.notepadPlusPlus:
          return null;
        case ExternalEditor.nvim:
          candidates.addAll([
            '/opt/homebrew/bin/nvim',
            '/usr/local/bin/nvim',
            '/usr/bin/nvim',
          ]);
          whichCmds.add('nvim');
          break;
        case ExternalEditor.vscode:
          candidates.addAll([
            '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code',
            '/usr/local/bin/code',
          ]);
          whichCmds.add('code');
          break;
        case ExternalEditor.zed:
          candidates.addAll([
            '/Applications/Zed.app/Contents/MacOS/Zed',
            '/usr/local/bin/zed',
          ]);
          whichCmds.add('zed');
          break;
        case ExternalEditor.internalViewer:
          return null;
      }

      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      for (final cmd in whichCmds) {
        try {
          final result = Process.runSync('which', [cmd]);
          if (result.exitCode == 0) {
            final trimmed = (result.stdout as String).trim();
            if (trimmed.isNotEmpty && File(trimmed).existsSync()) return trimmed;
          }
        } catch (e, st) {
          AppLog.warning('FileExplorer: locating external editor', e, st);
        }
      }
    } else {
      // Linux
      final candidates = <String>[];
      final whichCmds = <String>[];

      switch (editor) {
        case ExternalEditor.notepadPlusPlus:
          return null;
        case ExternalEditor.nvim:
          candidates.addAll([
            '/usr/bin/nvim',
            '/usr/local/bin/nvim',
            '/snap/bin/nvim',
          ]);
          whichCmds.add('nvim');
          break;
        case ExternalEditor.vscode:
          candidates.addAll([
            '/usr/bin/code',
            '/snap/bin/code',
            '/usr/local/bin/code',
          ]);
          whichCmds.add('code');
          break;
        case ExternalEditor.zed:
          candidates.addAll([
            '/usr/bin/zed',
            '/usr/local/bin/zed',
          ]);
          whichCmds.add('zed');
          break;
        case ExternalEditor.internalViewer:
          return null;
      }

      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      for (final cmd in whichCmds) {
        try {
          final result = Process.runSync('which', [cmd]);
          if (result.exitCode == 0) {
            final trimmed = (result.stdout as String).trim();
            if (trimmed.isNotEmpty && File(trimmed).existsSync()) return trimmed;
          }
        } catch (e, st) {
          AppLog.warning('FileExplorer: locating external editor', e, st);
        }
      }
    }

    return null;
  }

  bool isEditorInstalled(ExternalEditor editor) {
    if (editor == ExternalEditor.internalViewer) return true;
    return getEditorPath(editor) != null;
  }

  /// Launches an external editor opening [filePath].
  Future<bool> launchExternalEditor(ExternalEditor editor, String filePath) async {
    if (editor == ExternalEditor.internalViewer) return true;
    if (customEditorLauncher != null) {
      return await customEditorLauncher!(editor, filePath);
    }

    final exePath = getEditorPath(editor);
    if (exePath == null) return false;

    try {
      if (Platform.isWindows) {
        if (editor == ExternalEditor.nvim) {
          final userName = Platform.environment['USERNAME'] ?? '';
          final localApp = Platform.environment['LOCALAPPDATA'];
          final wtCandidates = [
            if (userName.isNotEmpty)
              'C:\\Users\\$userName\\AppData\\Local\\Microsoft\\WindowsApps\\wt.exe',
            if (localApp != null && localApp.isNotEmpty)
              '$localApp\\Microsoft\\WindowsApps\\wt.exe',
          ];
          String? wtPath;
          for (final w in wtCandidates) {
            if (File(w).existsSync()) {
              wtPath = w;
              break;
            }
          }
          if (wtPath != null) {
            await Process.start(wtPath, [exePath, filePath], mode: ProcessStartMode.detached);
          } else {
            await Process.start('cmd.exe', ['/c', 'start', '""', exePath, filePath], runInShell: true);
          }
          return true;
        } else if (exePath.toLowerCase().endsWith('.cmd') || exePath.toLowerCase().endsWith('.bat')) {
          await Process.start('cmd.exe', ['/c', exePath, filePath], mode: ProcessStartMode.detached);
          return true;
        } else {
          await Process.start(exePath, [filePath], mode: ProcessStartMode.detached);
          return true;
        }
      } else {
        await Process.start(exePath, [filePath], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (e) {
      debugPrint('Failed to launch editor $editor: $e');
      return false;
    }
  }
}
