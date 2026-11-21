import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import 'app_paths.dart';

/// One diagnostic record: where it came from and what went wrong.
class AppLogEntry {
  final DateTime time;
  final String level;
  final String where;
  final String message;
  final StackTrace? stack;

  const AppLogEntry({
    required this.time,
    required this.level,
    required this.where,
    required this.message,
    this.stack,
  });

  @override
  String toString() => '${time.toIso8601String()} $level [$where] $message';
}

/// The app's diagnostic log, for failures that are handled but that someone
/// debugging a connection or transfer needs to be able to see.
///
/// Entries go to `~/.nexus_fx/logs/app.log` and to [recent]. Logging never
/// throws: a failure to write the file is dropped, since the caller is
/// usually already on an error path.
class AppLog {
  AppLog._();

  static const int maxRecent = 500;
  static const int maxFileBytes = 1024 * 1024;

  static final Queue<AppLogEntry> _recent = Queue<AppLogEntry>();
  static String? _filePath = _defaultFilePath();

  /// Also print entries to the debug console. Off in release builds.
  static bool echoToConsole = kDebugMode;

  static String _defaultFilePath() {
    final sep = Platform.pathSeparator;
    return '${AppPaths.dataDir}${sep}logs${sep}app.log';
  }

  /// The newest entries, oldest first.
  static List<AppLogEntry> get recent => List.unmodifiable(_recent);

  /// A handled failure the app recovers from.
  static void warning(String where, Object error, [StackTrace? stack]) =>
      _add('WARN', where, error, stack);

  /// A failure that cost the user something: an operation did not happen.
  static void error(String where, Object error, [StackTrace? stack]) =>
      _add('ERROR', where, error, stack);

  /// For calls into desktop plugins (window_manager, notifications). A
  /// plugin that is not registered, as in widget tests, is not a failure.
  static void warningUnlessPluginMissing(String where, Object error, StackTrace stack) {
    if (error is MissingPluginException) return;
    warning(where, error, stack);
  }

  static void _add(String level, String where, Object error, StackTrace? stack) {
    final entry = AppLogEntry(
      time: DateTime.now(),
      level: level,
      where: where,
      message: error.toString(),
      stack: stack,
    );
    _recent.addLast(entry);
    while (_recent.length > maxRecent) {
      _recent.removeFirst();
    }
    if (echoToConsole) debugPrint(entry.toString());
    _appendToFile(entry);
  }

  static void _appendToFile(AppLogEntry entry) {
    final path = _filePath;
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        if (file.lengthSync() > maxFileBytes) {
          final old = File('$path.1');
          if (old.existsSync()) old.deleteSync();
          file.renameSync(old.path);
        }
      } else {
        file.parent.createSync(recursive: true);
      }
      final stack = entry.stack == null ? '' : '${entry.stack}\n';
      File(path).writeAsStringSync('$entry\n$stack', mode: FileMode.append);
    } on FileSystemException {
      // Nowhere left to report this: the log itself is what failed.
    }
  }

  /// Redirects the log file, or turns it off with null.
  @visibleForTesting
  static void setLogFileForTesting(String? path) => _filePath = path;

  @visibleForTesting
  static void clearForTesting() => _recent.clear();
}
