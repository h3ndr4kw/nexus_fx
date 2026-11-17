import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/terminal_output_scheduler.dart';

/// A sink whose every slice costs [costPerSlice] of real CPU time, like xterm
/// parsing a chunk of output.
class _BusySink implements TerminalDrainSink {
  _BusySink({required this.isForeground, this.pending = 1 << 30});

  @override
  bool isForeground;
  int pending;
  int drained = 0;
  int slices = 0;
  static const costPerSlice = Duration(microseconds: 500);

  @override
  bool get hasPendingOutput => pending > 0;

  @override
  int drainOutput(int maxChars) {
    final sw = Stopwatch()..start();
    while (sw.elapsed < costPerSlice) {}
    final n = maxChars < pending ? maxChars : pending;
    pending -= n;
    drained += n;
    slices++;
    return n;
  }
}

void main() {
  test('one tick stays within the budget however many terminals are busy', () {
    final scheduler = TerminalOutputScheduler();
    final sinks = [
      for (var i = 0; i < 6; i++) _BusySink(isForeground: true),
      for (var i = 0; i < 6; i++) _BusySink(isForeground: false),
    ];
    sinks.forEach(scheduler.request);
    scheduler.runTickForTesting(); // warm-up (JIT)

    final elapsed = scheduler.runTickForTesting();

    // One slice may overrun the deadline; allow scheduling noise on top.
    expect(elapsed,
        lessThan(scheduler.tickBudget + const Duration(milliseconds: 3)),
        reason: 'the UI isolate must get control back every tick');
    scheduler.dispose();
  });

  test('the visible terminal gets most of the time, background is not starved',
      () {
    final scheduler = TerminalOutputScheduler();
    final visible = _BusySink(isForeground: true);
    final hidden = [for (var i = 0; i < 2; i++) _BusySink(isForeground: false)];
    scheduler.request(visible);
    hidden.forEach(scheduler.request);

    for (var i = 0; i < 20; i++) {
      scheduler.runTickForTesting();
    }

    for (final h in hidden) {
      expect(h.drained, greaterThan(0), reason: 'hidden tabs keep progressing');
      expect(visible.drained, greaterThan(h.drained * 3));
    }
    scheduler.dispose();
  });

  test('after a full tick the next one waits so frames and input can run', () {
    final scheduler = TerminalOutputScheduler();
    scheduler.request(_BusySink(isForeground: true));
    scheduler.runTickForTesting();
    expect(scheduler.nextTickDelayForTesting,
        greaterThanOrEqualTo(scheduler.restAfterFullTick));
    scheduler.dispose();
  });

  test('background-only output is drained at a slow, frame-spaced pace', () {
    final scheduler = TerminalOutputScheduler();
    scheduler.request(_BusySink(isForeground: false));
    scheduler.runTickForTesting(); // warm-up (JIT)
    final elapsed = scheduler.runTickForTesting();
    expect(elapsed,
        lessThan(scheduler.backgroundShare + const Duration(milliseconds: 3)));
    expect(scheduler.nextTickDelayForTesting,
        greaterThanOrEqualTo(scheduler.backgroundInterval));
    scheduler.dispose();
  });

  test('sinks that run dry leave the queue and no tick is scheduled', () {
    final scheduler = TerminalOutputScheduler();
    final sink = _BusySink(isForeground: true, pending: 100);
    scheduler.request(sink);
    scheduler.runTickForTesting();
    expect(sink.pending, 0);
    expect(scheduler.hasWaitingForTesting, isFalse);
    expect(scheduler.nextTickDelayForTesting, isNull);
    scheduler.dispose();
  });

  test('a cancelled sink is not drained', () {
    final scheduler = TerminalOutputScheduler();
    final sink = _BusySink(isForeground: true);
    scheduler.request(sink);
    scheduler.cancel(sink);
    scheduler.runTickForTesting();
    expect(sink.slices, 0);
    scheduler.dispose();
  });
}
