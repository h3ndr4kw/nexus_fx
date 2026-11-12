import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';
import 'package:nexus_fx/services/transfer_manager.dart';

Future<void> _until(bool Function() cond, {String? reason}) async {
  for (var i = 0; i < 500; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('timed out waiting${reason == null ? '' : ': $reason'}');
}

void main() {
  group('TransferCancelToken pause gate', () {
    test('waitIfPaused returns at once when not paused', () async {
      final token = TransferCancelToken();
      await token.waitIfPaused();
      expect(token.isHalted, isFalse);
    });

    test('halts until resume and reports state changes', () async {
      final token = TransferCancelToken();
      var changes = 0;
      token.onPauseStateChanged = () => changes++;

      token.pause();
      expect(token.isPaused, isTrue);
      var released = false;
      final waiting = token.waitIfPaused().then((_) => released = true);
      await Future<void>.delayed(Duration.zero);
      expect(token.isHalted, isTrue);
      expect(released, isFalse);

      token.resume();
      await waiting;
      expect(released, isTrue);
      expect(token.isPaused, isFalse);
      expect(token.isHalted, isFalse);
      expect(changes, greaterThanOrEqualTo(4)); // pause, halt, resume, unhalt
    });

    test('cancel releases a halted loop with TransferCancelledException', () async {
      final token = TransferCancelToken()..pause();
      final waiting = token.waitIfPaused();
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await expectLater(waiting, throwsA(isA<TransferCancelledException>()));
      expect(token.isPaused, isFalse);
    });

    test('pause is ignored once cancelled', () {
      final token = TransferCancelToken()..cancel();
      token.pause();
      expect(token.isPaused, isFalse);
    });
  });

  group('pausing a real local copy through TransferManager', () {
    late Directory tmp;
    late File big;
    late Directory dest;
    late TransferManager manager;
    final sep = Platform.pathSeparator;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('fx_pause_test_');
      final src = Directory('${tmp.path}${sep}src')..createSync();
      dest = Directory('${tmp.path}${sep}dest')..createSync();
      big = File('${src.path}${sep}big.bin')
        ..writeAsBytesSync(List.filled(16 * 1024 * 1024, 7));
      manager = TransferManager(service: FileExplorerService(), finishedLinger: null);
    });

    tearDown(() async {
      manager.dispose();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    TransferJob startCopy() => manager.enqueue(
          items: [
            FileExplorerItem(
              name: 'big.bin',
              path: big.path,
              isDir: false,
              size: big.lengthSync(),
              modified: '',
            ),
          ],
          srcTarget: ExplorerNodeTarget.local,
          srcDirPath: big.parent.path,
          destTarget: ExplorerNodeTarget.local,
          destDirPath: dest.path,
          isMove: false,
        );

    test('pause halts mid-file, progress freezes, resume completes', () async {
      final job = startCopy();
      await _until(() => job.progress > 0 && job.progress < 1,
          reason: 'copy to start');

      expect(manager.canPause(job), isTrue);
      manager.pause(job);
      expect(job.isPaused, isTrue);
      expect(manager.canPause(job), isFalse);
      await _until(() => job.isHalted, reason: 'loop to halt');
      expect(job.eta, isNull, reason: 'no ETA while paused');

      final frozenAt = job.currentBytes;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(job.currentBytes, frozenAt, reason: 'no bytes move while paused');
      expect(job.status, TransferStatus.running);

      final pausedFor = const Duration(milliseconds: 120);
      manager.resume(job);
      expect(job.isPaused, isFalse);
      await _until(() => !job.isActive, reason: 'copy to finish');

      expect(job.status, TransferStatus.completed);
      expect(File('${dest.path}${sep}big.bin').lengthSync(), big.lengthSync());
      final wall = job.finishedAt!.difference(job.startedAt!);
      expect(job.activeElapsed, lessThanOrEqualTo(wall - pausedFor),
          reason: 'paused time is excluded from elapsed/ETA');
    });

    test('cancel while paused stops the job and removes the partial file', () async {
      final job = startCopy();
      await _until(() => job.progress > 0 && job.progress < 1,
          reason: 'copy to start');
      manager.pause(job);
      await _until(() => job.isHalted, reason: 'loop to halt');

      manager.cancel(job);
      await _until(() => !job.isActive, reason: 'job to end');

      expect(job.status, TransferStatus.cancelled);
      expect(job.isPaused, isFalse);
      expect(File('${dest.path}${sep}big.bin').existsSync(), isFalse);
    });
  });

  test('a job paused between items waits there (non-streamed operations)', () async {
    // Runner that only honours pause between items, like a server-side cp.
    final itemGate = Completer<void>();
    var itemsDone = 0;
    final manager = TransferManager(
      finishedLinger: null,
      runner: (job, report) async {
        for (final item in job.items) {
          if (job.cancelToken.isPaused) await job.cancelToken.waitIfPaused();
          if (itemsDone == 0) await itemGate.future; // a "long" first item
          itemsDone++;
          job.transferredPaths.add(item.path);
        }
      },
    );
    addTearDown(manager.dispose);

    FileExplorerItem item(String n) =>
        FileExplorerItem(name: n, path: '/s/$n', isDir: false, size: 1, modified: '');
    final job = manager.enqueue(
      items: [item('a'), item('b')],
      srcTarget: ExplorerNodeTarget.local,
      srcDirPath: '/s',
      destTarget: ExplorerNodeTarget.local,
      destDirPath: '/d',
      isMove: false,
    );
    await Future<void>.delayed(Duration.zero);

    manager.pause(job);
    expect(job.isPaused, isTrue);
    expect(job.isHalted, isFalse, reason: 'still finishing the current item');

    itemGate.complete();
    await _until(() => job.isHalted, reason: 'halt before the next item');
    expect(itemsDone, 1);

    manager.resume(job);
    await _until(() => !job.isActive);
    expect(job.status, TransferStatus.completed);
    expect(itemsDone, 2);
  });
}
