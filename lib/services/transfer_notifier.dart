import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'transfer_manager.dart';

/// Shows one desktop notification. [onClick] runs when the user clicks it.
typedef TransferNotificationSender = Future<void> Function(
  String title,
  String body, {
  VoidCallback? onClick,
});

/// Desktop notifications for transfers, only while the window is in the
/// background (in the foreground the transfer bar already shows it all):
///
/// * a job that finished after at least [minDuration] of active transfer
///   time, so quick copies stay quiet;
/// * any failed job, however short;
/// * a job paused on a name conflict, since it otherwise waits silently.
///
/// Jobs cancelled by the user never notify. Jobs finishing within
/// [batchWindow] of each other are combined into one notification.
class TransferNotifier {
  TransferNotifier(
    this.manager, {
    required bool Function() isEnabled,
    TransferNotificationSender? send,
    Future<bool> Function()? isWindowInForeground,
    VoidCallback? onActivate,
    this.minDuration = const Duration(seconds: 10),
    this.batchWindow = const Duration(seconds: 2),
    String appName = 'NexusFX',
  })  : _enabledCheck = isEnabled,
        _send = send ?? LocalNotifierSender(appName).call,
        _isWindowInForeground = isWindowInForeground ?? _windowInForeground,
        _onActivate = onActivate ?? _activateWindow {
    _finishedSub = manager.finished.listen(_onFinished);
    manager.addListener(_checkConflicts);
  }

  final TransferManager manager;
  final Duration minDuration;
  final Duration batchWindow;

  final bool Function() _enabledCheck;
  final TransferNotificationSender _send;
  final Future<bool> Function() _isWindowInForeground;
  final VoidCallback _onActivate;

  late final StreamSubscription<TransferJob> _finishedSub;
  final List<TransferJob> _batch = [];
  Timer? _batchTimer;

  /// Conflicts already announced, so each one notifies at most once.
  final Set<TransferConflict> _announcedConflicts = {};
  bool _disposed = false;

  void _onFinished(TransferJob job) {
    if (!_enabledCheck()) return;
    final worthIt = switch (job.status) {
      TransferStatus.failed => true,
      TransferStatus.completed => job.activeElapsed >= minDuration,
      _ => false,
    };
    if (!worthIt) return;
    _batch.add(job);
    _batchTimer ??= Timer(batchWindow, _flushBatch);
  }

  Future<void> _flushBatch() async {
    _batchTimer = null;
    final jobs = List.of(_batch);
    _batch.clear();
    if (jobs.isEmpty || _disposed || !_enabledCheck()) return;
    if (await _isWindowInForeground()) return;

    final failed = jobs.where((j) => j.status == TransferStatus.failed).length;
    final String title;
    final String body;
    if (jobs.length == 1) {
      final job = jobs.single;
      title = failed == 1 ? 'Transfer failed' : 'Transfer complete';
      body = job.resultSummary;
    } else {
      title = failed == 0
          ? '${jobs.length} transfers complete'
          : '${jobs.length} transfers finished, $failed failed';
      const shown = 3;
      body = [
        for (final j in jobs.take(shown)) '• ${j.resultSummary}',
        if (jobs.length > shown) '+${jobs.length - shown} more',
      ].join('\n');
    }
    await _safeSend(title, body);
  }

  void _checkConflicts() {
    final pending = <TransferConflict>{};
    for (final job in manager.activeJobs) {
      final conflict = job.pendingConflict;
      if (conflict == null) continue;
      pending.add(conflict);
      if (_announcedConflicts.add(conflict)) _announceConflict(job, conflict);
    }
    // Forget resolved conflicts so the set does not grow forever.
    _announcedConflicts.retainAll(pending);
  }

  Future<void> _announceConflict(TransferJob job, TransferConflict conflict) async {
    if (!_enabledCheck() || await _isWindowInForeground()) return;
    if (_disposed || !identical(job.pendingConflict, conflict)) return;
    final what = conflict.existingIsDir ? 'Folder' : 'File';
    await _safeSend(
      'Transfer needs your decision',
      "$what '${conflict.itemName}' already exists in ${job.destLabel}. "
          'Choose Replace, Keep both or Skip in the transfer bar.',
    );
  }

  Future<void> _safeSend(String title, String body) async {
    try {
      await _send(title, body, onClick: _onActivate);
    } catch (e) {
      debugPrint('Transfer notification failed: $e');
    }
  }

  static Future<bool> _windowInForeground() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return true;
    try {
      if (await windowManager.isMinimized()) return false;
      return await windowManager.isFocused();
    } catch (_) {
      // Unknown (tests, window_manager not ready): stay quiet.
      return true;
    }
  }

  static void _activateWindow() {
    () async {
      try {
        if (await windowManager.isMinimized()) await windowManager.restore();
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }();
  }

  void dispose() {
    _disposed = true;
    _finishedSub.cancel();
    manager.removeListener(_checkConflicts);
    _batchTimer?.cancel();
    _batch.clear();
  }
}

/// [TransferNotificationSender] backed by `local_notifier`. Set up lazily on
/// the first notification: on Windows that creates the Start-menu shortcut
/// toasts need, so users who never get a notification never get one.
class LocalNotifierSender {
  LocalNotifierSender(this.appName);

  final String appName;
  Future<void>? _setup;

  Future<void> call(String title, String body, {VoidCallback? onClick}) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    _setup ??= localNotifier.setup(appName: appName).catchError((Object e) {
      _setup = null; // try again next time
      throw e;
    });
    await _setup;
    final notification = LocalNotification(title: title, body: body)
      ..onClick = onClick;
    await localNotifier.notify(notification);
  }
}
