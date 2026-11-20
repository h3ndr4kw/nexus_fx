import 'dart:io';

/// Where the app keeps files that are not tied to a user-chosen location.
///
/// On Windows these stay relative to the working directory, as they always
/// have. A macOS or Linux GUI launch starts in "/" (read-only on macOS) or
/// wherever the launcher happened to be, so there they live under
/// `~/.nexus_fx`, next to sessions.json and known_hosts.json.
class AppPaths {
  AppPaths._();

  static String? get _home {
    final home = Platform.environment['HOME'];
    return home == null || home.isEmpty ? null : home;
  }

  /// Base directory for settings (`config/`) and session logs (`logs/`).
  static String get dataDir {
    final home = _home;
    if (Platform.isWindows || home == null) return Directory.current.path;
    return '$home/.nexus_fx';
  }

  /// The settings file, relative on Windows to keep existing installs.
  static String get settingsFile =>
      Platform.isWindows || _home == null ? 'config/settings.yaml' : '$dataDir/config/settings.yaml';

  /// Where the local file browser opens when it has no better place.
  static String get defaultLocalDir {
    final home = _home;
    if (Platform.isWindows || home == null) return Directory.current.path;
    return home;
  }
}
