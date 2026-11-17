import 'dart:async';

import 'package:flutter/foundation.dart';

/// A terminal with queued output that [TerminalOutputScheduler] feeds to
/// xterm.
abstract class TerminalDrainSink {
  /// Whether the terminal is on screen. Hidden terminals get a small share.
  bool get isForeground;

  bool get hasPendingOutput;

  /// Writes up to [maxChars] queued characters to the terminal and returns
  /// how many were written.
  int drainOutput(int maxChars);
}

/// Feeds queued output of every terminal to xterm under one shared time
/// budget, so several busy sessions together cannot hold the UI isolate
/// longer than one session could.
///
/// Each tick first gives hidden terminals [backgroundShare], then visible
/// ones the rest of [tickBudget], round-robin. After a full tick the next one
/// waits [restAfterFullTick] so frames, input and SSH decryption run. A
/// terminal that is not drained keeps its queue, which pauses its SSH stream
/// once it passes the high-water mark, so the server stops sending.
class TerminalOutputScheduler {
  TerminalOutputScheduler({
    this.tickBudget = const Duration(milliseconds: 6),
    this.backgroundShare = const Duration(milliseconds: 1),
    this.restAfterFullTick = const Duration(milliseconds: 6),
    this.backgroundInterval = const Duration(milliseconds: 16),
    this.sliceChars = 16 * 1024,
    this.backgroundSliceChars = 4 * 1024,
  });

  static final TerminalOutputScheduler instance = TerminalOutputScheduler();

  final Duration tickBudget;
  final Duration backgroundShare;
  final Duration restAfterFullTick;
  final Duration backgroundInterval;
  final int sliceChars;
  final int backgroundSliceChars;

  // Insertion order is the round-robin order: a drained sink moves to the end.
  final List<TerminalDrainSink> _waiting = [];
  Timer? _timer;
  Duration? _nextDelay;

  void request(TerminalDrainSink sink) {
    if (!_waiting.contains(sink)) _waiting.add(sink);
    if (_timer == null) _schedule(Duration.zero);
  }

  void cancel(TerminalDrainSink sink) {
    _waiting.remove(sink);
    if (_waiting.isEmpty) _stop();
  }

  void dispose() {
    _waiting.clear();
    _stop();
  }

  @visibleForTesting
  Duration runTickForTesting() {
    _timer?.cancel();
    _timer = null;
    return _tick();
  }

  @visibleForTesting
  Duration? get nextTickDelayForTesting => _nextDelay;

  @visibleForTesting
  bool get hasWaitingForTesting => _waiting.isNotEmpty;

  void _schedule(Duration delay) {
    _nextDelay = delay;
    _timer = Timer(delay, () {
      _timer = null;
      _tick();
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _nextDelay = null;
  }

  Duration _tick() {
    final sw = Stopwatch()..start();
    _waiting.removeWhere((s) => !s.hasPendingOutput);

    _drainRoundRobin(sw, backgroundShare, foreground: false,
        slice: backgroundSliceChars);
    final ranForeground =
        _drainRoundRobin(sw, tickBudget, foreground: true, slice: sliceChars);

    _waiting.removeWhere((s) => !s.hasPendingOutput);
    if (_waiting.isEmpty) {
      _stop();
    } else {
      final foregroundLeft = _waiting.any((s) => s.isForeground);
      _schedule(foregroundLeft
          ? (ranForeground ? restAfterFullTick : Duration.zero)
          : backgroundInterval);
    }
    return sw.elapsed;
  }

  /// Drains one slice per sink of the given kind, in turn, until [deadline]
  /// (measured by [sw]) or until they are empty. Returns whether any ran.
  bool _drainRoundRobin(Stopwatch sw, Duration deadline,
      {required bool foreground, required int slice}) {
    var ran = false;
    while (sw.elapsed < deadline) {
      final round = [
        for (final s in _waiting)
          if (s.isForeground == foreground && s.hasPendingOutput) s,
      ];
      if (round.isEmpty) break;
      for (final sink in round) {
        if (sw.elapsed >= deadline) break;
        sink.drainOutput(slice);
        ran = true;
        _waiting
          ..remove(sink)
          ..add(sink);
      }
    }
    return ran;
  }
}
