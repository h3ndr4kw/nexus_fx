import 'dart:async';

import 'app_log.dart';

/// Turns per-file progress callbacks into one cumulative progress stream
/// across a whole directory tree, so the bar does not reset for every file.
class TransferProgressAggregator {
  TransferProgressAggregator(this.total, this._sink);

  final int total;
  final void Function(int sentBytes, int totalBytes) _sink;
  int _done = 0;

  void Function(int sentBytes, int totalBytes) forFile() {
    var last = 0;
    return (sent, _) {
      if (sent > last) {
        _done += sent - last;
        last = sent;
      }
      final effectiveTotal = total > 0 ? total : _done;
      _sink(_done.clamp(0, effectiveTotal), effectiveTotal);
    };
  }
}

/// Thrown when the user cancels a transfer.
class TransferCancelledException implements Exception {
  const TransferCancelledException([this.message = 'Transfer cancelled']);
  final String message;
  @override
  String toString() => message;
}

/// Cooperative control for file transfers.
///
/// Cancel: loops poll [throwIfCancelled], and blocking operations (an SSH
/// channel waiting on a stalled peer) register an [onCancel] hook that
/// aborts them.
///
/// Pause: byte loops call [waitIfPaused] between chunks, which halts them
/// (applying back-pressure to the source stream) until [resume]. The native
/// engine follows [addPauseListener] and reports its own halt through
/// [enterHalt]. Operations with no chunk loop (server-side `cp`/`mv`) cannot
/// stop mid-file; they halt at the next pause point instead.
class TransferCancelToken {
  bool _cancelled = false;
  final List<void Function()> _hooks = [];
  final List<void Function()> _pauseListeners = [];

  bool _paused = false;
  Completer<void>? _resumed;
  int _haltedLoops = 0;

  /// Called whenever [isPaused] or [isHalted] changes.
  void Function()? onPauseStateChanged;

  bool get isCancelled => _cancelled;

  /// Pause was requested and not yet resumed.
  bool get isPaused => _paused;

  /// A transfer loop is actually stopped at a pause point right now (as
  /// opposed to a pause that is still waiting for the current file).
  bool get isHalted => _haltedLoops > 0;

  void pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    _resumed = Completer<void>();
    _pauseRequestChanged();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _resumed?.complete();
    _resumed = null;
    _pauseRequestChanged();
  }

  void _pauseRequestChanged() {
    onPauseStateChanged?.call();
    for (final listener in List.of(_pauseListeners)) {
      try {
        listener();
      } catch (e, st) {
        AppLog.error('FileExplorer: transfer pause listener threw', e, st);
      }
    }
  }

  /// Calls [listener] whenever [isPaused] flips; returns an unregister
  /// function. For transfers that do not run a Dart byte loop.
  void Function() addPauseListener(void Function() listener) {
    _pauseListeners.add(listener);
    return () => _pauseListeners.remove(listener);
  }

  /// Marks the transfer as actually stopped (see [isHalted]) until the
  /// returned function is called. Calling it more than once is harmless.
  void Function() enterHalt() {
    _haltedLoops++;
    onPauseStateChanged?.call();
    var left = false;
    return () {
      if (left) return;
      left = true;
      _haltedLoops--;
      onPauseStateChanged?.call();
    };
  }

  /// Returns at once unless paused; otherwise waits for [resume] or
  /// [cancel] (then throws [TransferCancelledException]).
  Future<void> waitIfPaused() async {
    throwIfCancelled();
    if (!_paused) return;
    _haltedLoops++;
    onPauseStateChanged?.call();
    try {
      while (_paused && !_cancelled) {
        await _resumed!.future;
      }
    } finally {
      _haltedLoops--;
      onPauseStateChanged?.call();
    }
    throwIfCancelled();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    // Release loops halted on a pause so they can observe the cancel.
    if (_paused) {
      _paused = false;
      _resumed?.complete();
      _resumed = null;
    }
    for (final hook in List.of(_hooks)) {
      try {
        hook();
      } catch (e, st) {
        AppLog.error('FileExplorer: cancel hook threw', e, st);
      }
    }
    _hooks.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const TransferCancelledException();
  }

  /// Registers [hook] to run on cancel; returns a function that unregisters.
  void Function() onCancel(void Function() hook) {
    if (_cancelled) {
      hook();
      return () {};
    }
    _hooks.add(hook);
    return () => _hooks.remove(hook);
  }
}
