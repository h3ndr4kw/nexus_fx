import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';
import 'package:nexus_fx/services/transfer_manager.dart';

FileExplorerItem _item(String name, {String dir = '/src'}) => FileExplorerItem(
      name: name,
      path: '$dir/$name',
      isDir: false,
      size: 1,
      modified: '',
    );

ExplorerNodeTarget _remote(String host) => ExplorerNodeTarget(
      type: ExplorerTargetType.customSsh,
      label: host,
      host: host,
      username: 'u',
    );

/// Runner whose jobs finish only when the test completes their gate; honours
/// cancellation like the real service does.
class _GatedRunner {
  final Map<int, Completer<void>> gates = {};
  final List<int> started = [];

  Future<void> call(TransferJob job, TransferReporter report) async {
    started.add(job.id);
    final gate = gates.putIfAbsent(job.id, Completer<void>.new);
    final unregister = job.cancelToken.onCancel(() {
      if (!gate.isCompleted) gate.complete();
    });
    report(currentFile: job.items.first.name, progress: 0.5, force: true);
    await gate.future;
    unregister();
    job.cancelToken.throwIfCancelled();
    job.transferredPaths.addAll(job.items.map((i) => i.path));
  }

  void finish(int id) => gates.putIfAbsent(id, Completer<void>.new).complete();
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _GatedRunner runner;
  late TransferManager manager;

  setUp(() {
    runner = _GatedRunner();
    manager = TransferManager(
      runner: runner.call,
      finishedLinger: null,
      maxConcurrent: 10,
    );
  });

  tearDown(() => manager.dispose());

  TransferJob enqueue({
    ExplorerNodeTarget src = ExplorerNodeTarget.local,
    ExplorerNodeTarget dest = ExplorerNodeTarget.local,
    bool isMove = false,
    String name = 'a.txt',
  }) =>
      manager.enqueue(
        items: [_item(name)],
        srcTarget: src,
        srcDirPath: '/src',
        destTarget: dest,
        destDirPath: '/dest',
        isMove: isMove,
      );

  test('enqueue returns immediately and the job runs in the background', () async {
    final finished = <TransferJob>[];
    manager.finished.listen(finished.add);

    final job = enqueue();
    // Returned while the transfer is still in flight.
    expect(job.isActive, isTrue);
    expect(manager.hasActiveJobs, isTrue);

    await _settle();
    expect(job.status, TransferStatus.running);
    expect(job.progress, 0.5);

    runner.finish(job.id);
    await _settle();
    await _settle();

    expect(job.status, TransferStatus.completed);
    expect(job.progress, 1.0);
    expect(job.transferredPaths, ['/src/a.txt']);
    expect(finished, [job]);
    expect(manager.hasActiveJobs, isFalse);
  });

  test('cancel stops a running job', () async {
    final job = enqueue();
    await _settle();
    expect(job.status, TransferStatus.running);

    manager.cancel(job);
    await _settle();
    await _settle();

    expect(job.status, TransferStatus.cancelled);
    expect(job.transferredPaths, isEmpty);
    expect(job.resultSummary, contains('cancelled'));
  });

  test('local jobs and jobs to different hosts run in parallel', () async {
    final a = enqueue(name: 'a');
    final b = enqueue(name: 'b');
    final c = enqueue(dest: _remote('host1'), name: 'c');
    final d = enqueue(dest: _remote('host2'), name: 'd');
    await _settle();

    expect(runner.started, containsAll([a.id, b.id, c.id, d.id]));
    for (final j in [a, b, c, d]) {
      expect(j.status, TransferStatus.running);
    }
  });

  test('jobs touching the same remote host run one at a time, in order', () async {
    final first = enqueue(dest: _remote('host1'), name: 'first');
    final second = enqueue(src: _remote('host1'), name: 'second');
    await _settle();

    expect(first.status, TransferStatus.running);
    expect(second.status, TransferStatus.queued);
    expect(runner.started, [first.id]);

    runner.finish(first.id);
    await _settle();
    await _settle();
    await _settle();

    expect(first.status, TransferStatus.completed);
    expect(second.status, TransferStatus.running);
    expect(runner.started, [first.id, second.id]);
  });

  test('cancelling a queued job ends it at once without letting the next overtake', () async {
    final first = enqueue(dest: _remote('host1'), name: 'first');
    final second = enqueue(dest: _remote('host1'), name: 'second');
    final third = enqueue(dest: _remote('host1'), name: 'third');
    await _settle();

    manager.cancel(second);
    await _settle();
    await _settle();

    expect(second.status, TransferStatus.cancelled);
    expect(runner.started, isNot(contains(second.id)));
    // The first job still holds the host, so the third must keep waiting.
    expect(first.status, TransferStatus.running);
    expect(third.status, TransferStatus.queued);

    runner.finish(first.id);
    for (var i = 0; i < 5; i++) {
      await _settle();
    }
    expect(third.status, TransferStatus.running);
  });

  test('at most maxConcurrent jobs run; the rest wait FIFO and cancel cleanly', () async {
    final limitedRunner = _GatedRunner();
    final limited = TransferManager(
      runner: limitedRunner.call,
      finishedLinger: null,
      maxConcurrent: 2,
    );
    addTearDown(limited.dispose);
    TransferJob add(String n) => limited.enqueue(
          items: [_item(n)],
          srcTarget: ExplorerNodeTarget.local,
          srcDirPath: '/src',
          destTarget: ExplorerNodeTarget.local,
          destDirPath: '/dest',
          isMove: false,
        );

    final a = add('a');
    final b = add('b');
    final c = add('c');
    final d = add('d');
    await _settle();
    expect(limitedRunner.started, [a.id, b.id]);
    expect(c.status, TransferStatus.queued);

    // Cancelling a job that waits for a slot ends it without using a slot.
    limited.cancel(c);
    await _settle();
    await _settle();
    expect(c.status, TransferStatus.cancelled);

    limitedRunner.finish(a.id);
    for (var i = 0; i < 4; i++) {
      await _settle();
    }
    expect(limitedRunner.started, [a.id, b.id, d.id]);

    // The slot count did not leak: after everything ends, two can run again.
    limitedRunner.finish(b.id);
    limitedRunner.finish(d.id);
    for (var i = 0; i < 4; i++) {
      await _settle();
    }
    final e = add('e');
    final f = add('f');
    await _settle();
    expect(e.status, TransferStatus.running);
    expect(f.status, TransferStatus.running);
  });

  test('a failure is reported with a readable message and stays listed', () async {
    final failing = TransferManager(
      runner: (job, report) async => throw Exception('disk full'),
      finishedLinger: const Duration(milliseconds: 10),
    );
    addTearDown(failing.dispose);

    final job = failing.enqueue(
      items: [_item('a')],
      srcTarget: ExplorerNodeTarget.local,
      srcDirPath: '/src',
      destTarget: ExplorerNodeTarget.local,
      destDirPath: '/dest',
      isMove: false,
    );
    await _settle();
    await _settle();

    expect(job.status, TransferStatus.failed);
    expect(job.error, 'disk full');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(failing.jobs, [job], reason: 'failed jobs wait for dismiss');

    failing.dismiss(job);
    expect(failing.jobs, isEmpty);
  });

  test('completed jobs disappear after the linger time', () async {
    final lingering = TransferManager(
      runner: (job, report) async {},
      finishedLinger: const Duration(milliseconds: 10),
    );
    addTearDown(lingering.dispose);

    final job = lingering.enqueue(
      items: [_item('a')],
      srcTarget: ExplorerNodeTarget.local,
      srcDirPath: '/src',
      destTarget: ExplorerNodeTarget.local,
      destDirPath: '/dest',
      isMove: false,
    );
    await _settle();
    await _settle();
    expect(job.status, TransferStatus.completed);
    expect(lingering.jobs, [job]);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(lingering.jobs, isEmpty);
  });

  group('default runner (real local I/O)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('fx_transfer_mgr_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('copies and moves local files in the background', () async {
      final sep = Platform.pathSeparator;
      final src = Directory('${tmp.path}${sep}src')..createSync();
      final dest = Directory('${tmp.path}${sep}dest')..createSync();
      final a = File('${src.path}${sep}a.bin')..writeAsBytesSync(List.filled(64 * 1024, 1));
      final b = File('${src.path}${sep}b.bin')..writeAsBytesSync(List.filled(32 * 1024, 2));

      final real = TransferManager(service: FileExplorerService(), finishedLinger: null);
      addTearDown(real.dispose);

      FileExplorerItem fileItem(File f) => FileExplorerItem(
            name: f.uri.pathSegments.last,
            path: f.path,
            isDir: false,
            size: f.lengthSync(),
            modified: '',
          );

      final copy = real.enqueue(
        items: [fileItem(a)],
        srcTarget: ExplorerNodeTarget.local,
        srcDirPath: src.path,
        destTarget: ExplorerNodeTarget.local,
        destDirPath: dest.path,
        isMove: false,
      );
      final move = real.enqueue(
        items: [fileItem(b)],
        srcTarget: ExplorerNodeTarget.local,
        srcDirPath: src.path,
        destTarget: ExplorerNodeTarget.local,
        destDirPath: dest.path,
        isMove: true,
      );

      await real.finished.take(2).toList();

      expect(copy.status, TransferStatus.completed);
      expect(move.status, TransferStatus.completed);
      expect(File('${dest.path}${sep}a.bin').lengthSync(), 64 * 1024);
      expect(File('${dest.path}${sep}b.bin').lengthSync(), 32 * 1024);
      expect(a.existsSync(), isTrue);
      expect(b.existsSync(), isFalse);
    });

    group('name conflicts', () {
      final sep = Platform.pathSeparator;
      late Directory src;
      late Directory dest;
      late TransferManager real;

      setUp(() {
        src = Directory('${tmp.path}${sep}src')..createSync();
        dest = Directory('${tmp.path}${sep}dest')..createSync();
        real = TransferManager(service: FileExplorerService(), finishedLinger: null);
      });

      tearDown(() => real.dispose());

      FileExplorerItem entry(FileSystemEntity e) => FileExplorerItem(
            name: e.path.split(sep).last,
            path: e.path,
            isDir: e is Directory,
            size: 0,
            modified: '',
          );

      File write(Directory dir, String name, String content) =>
          File('${dir.path}$sep$name')..writeAsStringSync(content);

      TransferJob copy(List<FileSystemEntity> items, {Directory? to}) => real.enqueue(
            items: items.map(entry).toList(),
            srcTarget: ExplorerNodeTarget.local,
            srcDirPath: src.path,
            destTarget: ExplorerNodeTarget.local,
            destDirPath: (to ?? dest).path,
            isMove: false,
          );

      Future<TransferConflict> conflictOf(TransferJob job) async {
        for (var i = 0; i < 200; i++) {
          final c = job.pendingConflict;
          if (c != null) return c;
          if (!job.isActive) fail('job ended (${job.status}) without asking');
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('no conflict raised');
      }

      Future<void> done(TransferJob job) async {
        while (job.isActive) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      test('pauses on an existing file; Skip leaves it and continues', () async {
        final a = write(src, 'a.txt', 'new');
        final b = write(src, 'b.txt', 'bee');
        write(dest, 'a.txt', 'old');

        final job = copy([a, b]);
        final conflict = await conflictOf(job);
        expect(conflict.itemName, 'a.txt');
        expect(conflict.existingIsDir, isFalse);
        expect(conflict.remainingItems, 1);
        expect(job.needsAttention, isTrue);

        real.resolveConflict(job, ConflictChoice.skip);
        await done(job);

        expect(job.status, TransferStatus.completed);
        expect(job.skippedPaths, [a.path]);
        expect(job.transferredPaths, [b.path]);
        expect(File('${dest.path}${sep}a.txt').readAsStringSync(), 'old');
        expect(File('${dest.path}${sep}b.txt').readAsStringSync(), 'bee');
        expect(job.resultSummary, contains('skipped 1'));
      });

      test('Replace with apply-to-all overwrites every clash after one prompt', () async {
        final a = write(src, 'a.txt', 'new-a');
        final b = write(src, 'b.txt', 'new-b');
        write(dest, 'a.txt', 'old-a');
        write(dest, 'b.txt', 'old-b');

        final job = copy([a, b]);
        await conflictOf(job);
        real.resolveConflict(job, ConflictChoice.replace, applyToAll: true);
        await done(job);

        expect(job.status, TransferStatus.completed);
        expect(File('${dest.path}${sep}a.txt').readAsStringSync(), 'new-a');
        expect(File('${dest.path}${sep}b.txt').readAsStringSync(), 'new-b');
      });

      test('Replace on a folder swaps it instead of merging or nesting', () async {
        final srcDir = Directory('${src.path}${sep}d')..createSync();
        write(srcDir, 'new.txt', 'n');
        final destDir = Directory('${dest.path}${sep}d')..createSync();
        write(destDir, 'old.txt', 'o');

        final job = copy([srcDir]);
        final conflict = await conflictOf(job);
        expect(conflict.existingIsDir, isTrue);
        real.resolveConflict(job, ConflictChoice.replace);
        await done(job);

        expect(job.status, TransferStatus.completed);
        final names = destDir.listSync().map((e) => e.path.split(sep).last).toList();
        expect(names, ['new.txt']);
      });

      test('cancelling while paused on a conflict cancels the job', () async {
        final a = write(src, 'a.txt', 'new');
        write(dest, 'a.txt', 'old');

        final job = copy([a]);
        await conflictOf(job);
        real.cancel(job);
        await done(job);

        expect(job.status, TransferStatus.cancelled);
        expect(job.pendingConflict, isNull);
        expect(File('${dest.path}${sep}a.txt').readAsStringSync(), 'old');
      });

      test('copying into the source folder skips instead of truncating', () async {
        final a = write(src, 'a.txt', 'precious');

        final job = copy([a], to: src);
        await done(job);

        expect(job.status, TransferStatus.completed);
        expect(job.skippedPaths, [a.path]);
        expect(a.readAsStringSync(), 'precious');
      });
    });
  });
}
