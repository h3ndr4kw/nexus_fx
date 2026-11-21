import 'dart:io';

import 'package:window_manager/window_manager.dart';

import 'transfer_manager.dart';
import 'app_log.dart';

/// Mirrors the overall transfer progress on the app's taskbar icon (Windows)
/// or dock icon (macOS), so it stays visible while the window is minimised
/// or behind other windows. Cleared when no transfer is active.
class TransferTaskbarProgress {
  TransferTaskbarProgress(
    this.manager, {
    Future<void> Function(double progress)? setProgress,
  }) : _setProgress = setProgress ?? _setWindowProgress {
    manager.addListener(_sync);
    _sync();
  }

  final TransferManager manager;
  final Future<void> Function(double progress) _setProgress;

  /// Last value sent, in whole percent steps; null = bar cleared.
  double? _shown;

  void _sync() {
    final p = manager.aggregateProgress;
    // Whole-percent steps keep platform-channel traffic low.
    final next = p == null ? null : (p * 100).floorToDouble() / 100;
    if (next == _shown) return;
    _shown = next;
    _setProgress(next ?? -1);
  }

  static Future<void> _setWindowProgress(double progress) async {
    if (!(Platform.isWindows || Platform.isMacOS)) return;
    try {
      // window_manager: 0..1 shows the bar, a negative value removes it.
      await windowManager.setProgressBar(progress);
    } catch (e, st) {
      AppLog.warningUnlessPluginMissing('Taskbar: setting progress', e, st);
      // Not available in tests / before window_manager is initialised.
    }
  }

  void dispose() {
    manager.removeListener(_sync);
    if (_shown != null) _setProgress(-1);
  }
}
