import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/settings_service.dart';

void main() {
  test('tests never write the real config/settings.yaml', () async {
    final real = File('config/settings.yaml');
    final before = real.existsSync() ? real.readAsStringSync() : null;
    final settings = SettingsService.instance;
    final old = settings.nexusTerminalFontSize;

    await settings.setNexusTerminalFontSize(old == 13.0 ? 14.0 : 13.0);
    await settings.setNexusTerminalFontSize(old);

    final after = real.existsSync() ? real.readAsStringSync() : null;
    expect(after, before);
  });
}
