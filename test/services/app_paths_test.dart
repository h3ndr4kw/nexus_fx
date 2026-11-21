import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/app_paths.dart';

void main() {
  group('AppPaths.resolveDataDir', () {
    test('Windows uses %USERPROFILE%\\.nexus_fx, not the working folder', () {
      final dir = AppPaths.resolveDataDir(
        env: const {'USERPROFILE': r'C:\Users\alice'},
        isWindows: true,
        cwd: r'C:\Program Files\NexusFX',
      );
      expect(dir, r'C:\Users\alice\.nexus_fx');
    });

    test('macOS/Linux use \$HOME/.nexus_fx', () {
      final dir = AppPaths.resolveDataDir(
        env: const {'HOME': '/home/alice'},
        isWindows: false,
        cwd: '/',
      );
      expect(dir, '/home/alice/.nexus_fx');
    });

    test('falls back to the working folder when no home is set', () {
      expect(AppPaths.resolveDataDir(env: const {}, isWindows: true, cwd: r'C:\app'), r'C:\app');
      expect(AppPaths.resolveDataDir(env: const {'USERPROFILE': ''}, isWindows: true, cwd: r'C:\app'),
          r'C:\app');
    });
  });

  group('AppPaths.migrateLegacySettings', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('nexus_fx_paths_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('copies the old working-folder settings into the new location', () {
      final legacy = File('${tmp.path}/old/config/settings.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('app_theme: light\n');
      final target = '${tmp.path}/new/config/settings.yaml';

      expect(AppPaths.migrateLegacySettings(legacyPath: legacy.path, targetPath: target), isTrue);
      expect(File(target).readAsStringSync(), 'app_theme: light\n');
      expect(legacy.existsSync(), isTrue, reason: 'the old file is left in place');
    });

    test('never overwrites settings that already exist in the new location', () {
      final legacy = File('${tmp.path}/old/settings.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('old\n');
      final target = File('${tmp.path}/new/settings.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('new\n');

      expect(AppPaths.migrateLegacySettings(legacyPath: legacy.path, targetPath: target.path), isFalse);
      expect(target.readAsStringSync(), 'new\n');
    });

    test('does nothing when there is no old file', () {
      final target = '${tmp.path}/new/settings.yaml';
      expect(
        AppPaths.migrateLegacySettings(legacyPath: '${tmp.path}/missing.yaml', targetPath: target),
        isFalse,
      );
      expect(File(target).existsSync(), isFalse);
    });
  });
}
