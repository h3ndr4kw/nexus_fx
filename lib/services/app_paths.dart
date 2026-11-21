import 'dart:io';

/// Where the app keeps files that are not tied to a user-chosen location.
///
/// Everything lives under `~/.nexus_fx` (`%USERPROFILE%\.nexus_fx` on
/// Windows), next to sessions.json, known_hosts.json and snippets.json. The
/// working folder is never used when a home is known: it depends on how the
/// app was launched, and an install under Program Files is read-only.
class AppPaths {
  AppPaths._();

  static String? _homeFrom(Map<String, String> env, {required bool isWindows}) {
    final home = isWindows ? (env['USERPROFILE'] ?? env['HOME']) : env['HOME'];
    return home == null || home.isEmpty ? null : home;
  }

  static String? get _home => _homeFrom(Platform.environment, isWindows: Platform.isWindows);

  /// The data folder for a given environment; [dataDir] is this for the
  /// running process. Falls back to [cwd] only when no home is set.
  static String resolveDataDir({
    required Map<String, String> env,
    required bool isWindows,
    required String cwd,
  }) {
    final home = _homeFrom(env, isWindows: isWindows);
    if (home == null) return cwd;
    final sep = isWindows ? r'\' : '/';
    return '$home$sep.nexus_fx';
  }

  /// Base directory for settings (`config/`) and session logs (`logs/`).
  static String get dataDir => resolveDataDir(
        env: Platform.environment,
        isWindows: Platform.isWindows,
        cwd: Directory.current.path,
      );

  /// The settings file.
  static String get settingsFile {
    final sep = Platform.pathSeparator;
    return '$dataDir${sep}config${sep}settings.yaml';
  }

  /// Where Windows builds before this change kept settings: relative to the
  /// working folder.
  static String get legacySettingsFile {
    final sep = Platform.pathSeparator;
    return '${Directory.current.path}${sep}config${sep}settings.yaml';
  }

  /// Copies [legacyPath] to [targetPath] when only the old file exists, so an
  /// upgrade keeps the user's settings. Returns true if it copied.
  static bool migrateLegacySettings({required String legacyPath, required String targetPath}) {
    try {
      final target = File(targetPath);
      if (target.existsSync()) return false;
      final legacy = File(legacyPath);
      if (!legacy.existsSync()) return false;
      target.parent.createSync(recursive: true);
      legacy.copySync(targetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Where the local file browser opens when it has no better place.
  static String get defaultLocalDir => _home ?? Directory.current.path;
}
