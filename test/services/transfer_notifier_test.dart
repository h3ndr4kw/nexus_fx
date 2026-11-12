import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';
import 'package:nexus_fx/services/transfer_manager.dart';
import 'package:nexus_fx/services/transfer_notifier.dart';

class _Sent {
  _Sent(this.title, this.body, this.onClick);
  final String title;
  final String body;
  final VoidCallback? onClick;
}

const _batch = Duration(milliseconds: 20);
Future<void> _afterBatch() => Future<void>.delayed(_batch * 3);

FileExplorerItem _item(String name) =>
    FileExplorerItem(name: name, path: '/src/$name', isDir: false, size: 1, modified: '');

void main() {
  late List<_Sent> sent;
  late bool inForeground;
  late bool enabled;
  late int activations;

  setUp(() {
    sent = [];
    inForeground = false;
    enabled = true;
    activations = 0;
  });

  TransferNotifier notifierFor(
    TransferManager manager, {
    Duration minDuration = Duration.zero,
  }) {
    final notifier = TransferNotifier(
      manager,
      isEnabled: () => enabled,
      send: (title, body, {onClick}) async => sent.add(_Sent(title, body, onClick)),
      isWindowInForeground: () async => inForeground,
      onActivate: () => activations++,
      minDuration: minDuration,
      batchWindow: _batch,
    );
    addTearDown(notifier.dispose);
    return notifier;
  }

  /// Manager whose jobs end as directed by the item name: 'fail*' fails,
  /// 'cancel*' is cancelled, anything else completes.
  TransferManager scripted() {
    final m = TransferManager(
      finishedLinger: null,
      runner: (job, report) async {
        final name = job.items.first.name;
        if (name.startsWith('fail')) throw Exception('disk full');
        if (name.startsWith('cancel')) {
          job.cancelToken.cancel();
          job.cancelToken.throwIfCancelled();
        }
        job.transferredPaths.addAll(job.items.map((i) => i.path));
      },
    );
    addTearDown(m.dispose);
    return m;
  }

  TransferJob run(TransferManager m, String name) => m.enqueue(
        items: [_item(name)],
        srcTarget: ExplorerNodeTarget.local,
        srcDirPath: '/src',
        destTarget: ExplorerNodeTarget.local,
        destDirPath: '/dest',
        isMove: false,
      );

  test('notifies a finished transfer while the window is in the background', () async {
    final m = scripted();
    notifierFor(m);
    run(m, 'report.pdf');
    await _afterBatch();

    expect(sent, hasLength(1));
    expect(sent.single.title, 'Transfer complete');
    expect(sent.single.body, contains('Copied 1 item(s) to /dest'));

    sent.single.onClick!();
    expect(activations, 1, reason: 'clicking brings the window forward');
  });

  test('stays quiet while the window is in the foreground', () async {
    inForeground = true;
    final m = scripted();
    notifierFor(m);
    run(m, 'a');
    run(m, 'fail-b');
    await _afterBatch();
    expect(sent, isEmpty);
  });

  test('stays quiet when disabled in settings', () async {
    enabled = false;
    final m = scripted();
    notifierFor(m);
    run(m, 'fail-a');
    await _afterBatch();
    expect(sent, isEmpty);
  });

  test('short successes are skipped but failures always notify', () async {
    final m = scripted();
    notifierFor(m, minDuration: const Duration(minutes: 1));
    run(m, 'quick.txt');
    await _afterBatch();
    expect(sent, isEmpty);

    run(m, 'fail-quick.txt');
    await _afterBatch();
    expect(sent.single.title, 'Transfer failed');
    expect(sent.single.body, contains('disk full'));
  });

  test('user-cancelled transfers never notify', () async {
    final m = scripted();
    notifierFor(m);
    final job = run(m, 'cancel-me');
    await _afterBatch();
    expect(job.status, TransferStatus.cancelled);
    expect(sent, isEmpty);
  });

  test('transfers finishing close together are combined', () async {
    final m = scripted();
    notifierFor(m);
    run(m, 'a');
    run(m, 'b');
    run(m, 'fail-c');
    run(m, 'd');
    await _afterBatch();

    expect(sent, hasLength(1));
    expect(sent.single.title, '4 transfers finished, 1 failed');
    final lines = sent.single.body.split('\n');
    expect(lines, hasLength(4));
    expect(lines.last, '+1 more');
  });

  group('name conflicts (real local I/O)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('fx_notify_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('announce a pending conflict once, and not when in the foreground', () async {
      final sep = Platform.pathSeparator;
      final src = Directory('${tmp.path}${sep}src')..createSync();
      final dest = Directory('${tmp.path}${sep}dest')..createSync();
      final a = File('${src.path}${sep}a.txt')..writeAsStringSync('new');
      File('${dest.path}${sep}a.txt').writeAsStringSync('old');

      final m = TransferManager(service: FileExplorerService(), finishedLinger: null);
      addTearDown(m.dispose);
      notifierFor(m, minDuration: const Duration(minutes: 1));

      TransferJob copy() => m.enqueue(
            items: [
              FileExplorerItem(name: 'a.txt', path: a.path, isDir: false, size: 3, modified: ''),
            ],
            srcTarget: ExplorerNodeTarget.local,
            srcDirPath: src.path,
            destTarget: ExplorerNodeTarget.local,
            destDirPath: dest.path,
            isMove: false,
          );

      Future<void> untilConflict(TransferJob job) async {
        for (var i = 0; i < 200 && job.pendingConflict == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(job.pendingConflict, isNotNull);
      }

      final job = copy();
      await untilConflict(job);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // More manager notifications (another job running and finishing)
      // must not repeat the announcement.
      final other = Directory('${tmp.path}${sep}other')..createSync();
      final b = File('${src.path}${sep}b.txt')..writeAsStringSync('b');
      final otherJob = m.enqueue(
        items: [FileExplorerItem(name: 'b.txt', path: b.path, isDir: false, size: 1, modified: '')],
        srcTarget: ExplorerNodeTarget.local,
        srcDirPath: src.path,
        destTarget: ExplorerNodeTarget.local,
        destDirPath: other.path,
        isMove: false,
      );
      for (var i = 0; i < 200 && otherJob.isActive; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(sent, hasLength(1));
      expect(sent.single.title, 'Transfer needs your decision');
      expect(sent.single.body, contains("File 'a.txt' already exists"));

      m.resolveConflict(job, ConflictChoice.skip);
      for (var i = 0; i < 200 && job.isActive; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      inForeground = true;
      final second = copy();
      await untilConflict(second);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sent, hasLength(1), reason: 'in the foreground the bar shows it');
      m.cancel(second);
    });
  });
}
