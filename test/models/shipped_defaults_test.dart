import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/network_manager_config.dart';
import 'package:nexus_fx/services/settings_service.dart';

/// The app must not ship anyone's hosts, accounts or credentials as defaults.
void main() {
  test('Network Manager is unconfigured by default', () {
    const c = NetworkManagerConfig();
    expect(c.host, isEmpty);
    expect(c.username, isEmpty);
    expect(c.password, isEmpty);

    final fromEmpty = NetworkManagerConfig.fromMap(const {});
    expect(fromEmpty.host, isEmpty);
    expect(fromEmpty.username, isEmpty);
    expect(fromEmpty.port, 22);
  });

  test('settings ship no dashboard account or update path', () {
    final s = SettingsService.instance;
    expect(s.gilanDashboardUrl, isEmpty);
    expect(s.gilanDashboardUsername, isEmpty);
    expect(s.gilanDashboardPassword, isEmpty);
    expect(s.updateRemotePath, isEmpty);
  });
}
