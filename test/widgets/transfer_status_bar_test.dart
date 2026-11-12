import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';
import 'package:nexus_fx/services/transfer_manager.dart';
import 'package:nexus_fx/widgets/transfer_status_bar.dart';

/// Runner that never finishes on its own, only on cancel.
Future<void> _untilCancelled(TransferJob job, TransferReporter report) async {
  final done = Completer<void>();
  job.cancelToken.onCancel(() {
    if (!done.isCompleted) done.complete();
  });
  report(currentFile: job.items.first.name, progress: 0.4, force: true);
  await done.future;
  job.cancelToken.throwIfCancelled();
}

TransferJob _enqueue(TransferManager m, String name) => m.enqueue(
      items: [
        FileExplorerItem(name: name, path: '/src/$name', isDir: false, size: 1, modified: ''),
      ],
      srcTarget: ExplorerNodeTarget.local,
      srcDirPath: '/src',
      destTarget: ExplorerNodeTarget.local,
      destDirPath: '/dest',
      isMove: false,
    );

Widget _host(TransferManager m) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: Center(child: Text('page content'))),
            TransferStatusBar(manager: m),
          ],
        ),
      ),
    );

void main() {
  late TransferManager manager;

  setUp(() {
    manager = TransferManager(runner: _untilCancelled, finishedLinger: null);
  });

  tearDown(() => manager.dispose());

  testWidgets('is hidden when there are no transfers', (tester) async {
    await tester.pumpWidget(_host(manager));
    expect(find.byKey(const ValueKey('transfer_status_bar')), findsNothing);
  });

  testWidgets('shows a running job without blocking the page, and cancels it',
      (tester) async {
    await tester.pumpWidget(_host(manager));
    final job = _enqueue(manager, 'big.iso');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('transfer_status_bar')), findsOneWidget);
    expect(find.textContaining('Copying big.iso'), findsOneWidget);
    expect(find.textContaining('40%'), findsOneWidget);
    // Non-modal: no dialog route, page still on screen.
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('page content'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('transfer_cancel_${job.id}')));
    await tester.pump();
    await tester.pump();

    expect(job.status, TransferStatus.cancelled);
    expect(find.textContaining('Copy cancelled'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('transfer_dismiss_${job.id}')));
    await tester.pump();
    expect(find.byKey(const ValueKey('transfer_status_bar')), findsNothing);
  });

  testWidgets('summarises several jobs and expands to a per-job list',
      (tester) async {
    await tester.pumpWidget(_host(manager));
    final a = _enqueue(manager, 'a.log');
    final b = _enqueue(manager, 'b.log');
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('2 transfers running'), findsOneWidget);
    expect(find.byKey(ValueKey('transfer_job_${a.id}')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transfer_status_toggle')));
    await tester.pump();

    expect(find.byKey(ValueKey('transfer_job_${a.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('transfer_job_${b.id}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transfer_cancel_all')));
    await tester.pump();
    await tester.pump();

    expect(a.status, TransferStatus.cancelled);
    expect(b.status, TransferStatus.cancelled);
  });

  testWidgets('shows a non-modal conflict prompt and passes the choice on',
      (tester) async {
    final conflictDir =
        await tester.runAsync(() => Directory.systemTemp.createTemp('fx_bar_conflict_'));
    addTearDown(() => conflictDir!.deleteSync(recursive: true));
    final sep = Platform.pathSeparator;
    final srcDir = Directory('${conflictDir!.path}${sep}src')..createSync();
    final destDir = Directory('${conflictDir.path}${sep}dest')..createSync();
    final a = File('${srcDir.path}${sep}a.txt')..writeAsStringSync('new');
    final b = File('${srcDir.path}${sep}b.txt')..writeAsStringSync('b');
    File('${destDir.path}${sep}a.txt').writeAsStringSync('old');

    final real = TransferManager(service: FileExplorerService(), finishedLinger: null);
    addTearDown(real.dispose);
    await tester.pumpWidget(_host(real));

    late TransferJob job;
    await tester.runAsync(() async {
      job = real.enqueue(
        items: [
          for (final f in [a, b])
            FileExplorerItem(
                name: f.path.split(sep).last, path: f.path, isDir: false, size: 0, modified: ''),
        ],
        srcTarget: ExplorerNodeTarget.local,
        srcDirPath: srcDir.path,
        destTarget: ExplorerNodeTarget.local,
        destDirPath: destDir.path,
        isMove: false,
      );
      while (job.pendingConflict == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(find.byKey(ValueKey('transfer_conflict_${job.id}')), findsOneWidget);
    expect(find.textContaining("File 'a.txt' already exists"), findsOneWidget);
    expect(find.textContaining('Apply to all (1 more)'), findsOneWidget);
    expect(find.text('page content'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('transfer_conflict_skip_${job.id}')));
    await tester.runAsync(() async {
      while (job.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(job.skippedPaths, [a.path]);
    expect(job.transferredPaths, [b.path]);
    expect(find.byKey(ValueKey('transfer_conflict_${job.id}')), findsNothing);
  });
}
