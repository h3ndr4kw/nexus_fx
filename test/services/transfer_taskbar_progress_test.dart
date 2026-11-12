import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/transfer_manager.dart';
import 'package:nexus_fx/services/transfer_taskbar_progress.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('mirrors overall progress in whole percents and clears when idle', () async {
    final gate = Completer<void>();
    late TransferReporter reporter;
    final manager = TransferManager(
      finishedLinger: null,
      runner: (job, report) async {
        reporter = report;
        await gate.future;
      },
    );
    addTearDown(manager.dispose);

    final sent = <double>[];
    final taskbar = TransferTaskbarProgress(manager, setProgress: (v) async => sent.add(v));
    addTearDown(taskbar.dispose);
    expect(sent, isEmpty, reason: 'nothing to show while idle');

    manager.enqueue(
      items: [FileExplorerItem(name: 'a', path: '/s/a', isDir: false, size: 1, modified: '')],
      srcTarget: ExplorerNodeTarget.local,
      srcDirPath: '/s',
      destTarget: ExplorerNodeTarget.local,
      destDirPath: '/d',
      isMove: false,
    );
    await _settle();
    expect(sent, [0.0]);

    reporter(progress: 0.421, force: true);
    reporter(progress: 0.425, force: true); // same whole percent: not re-sent
    expect(sent, [0.0, 0.42]);

    gate.complete();
    await _settle();
    await _settle();
    expect(sent.last, -1, reason: 'bar removed once no job is active');
  });
}
