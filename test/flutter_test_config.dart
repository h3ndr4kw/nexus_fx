import 'dart:async';
import 'dart:io';

import 'package:nexus_fx/services/settings_service.dart';

/// Runs before every test file under test/ (picked up by `flutter test`).
///
/// SettingsService saves to `~/.nexus_fx/config/settings.yaml`, which is
/// the developer's real config: a test that changes a setting
/// would overwrite it. Point it at a throwaway file instead.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final dir = Directory.systemTemp.createTempSync('nexus_fx_test_config_');
  SettingsService.instance
      .setConfigPathForTesting('${dir.path}${Platform.pathSeparator}settings.yaml');
  try {
    await testMain();
  } finally {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
