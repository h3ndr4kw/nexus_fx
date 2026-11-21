import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';
import 'package:nexus_fx/widgets/file_explorer_dialogs.dart';
import 'package:nexus_fx/widgets/file_explorer_view.dart';

class _FakeService extends FileExplorerService {
  final List<FileExplorerItem> files;
  final Map<String, List<int>> contents;
  _FakeService(this.files, this.contents);

  @override
  Future<List<FileExplorerItem>> listLocal(String dirPath, {String filter = ''}) async => List.of(files);

  @override
  Future<Uint8List> readLocalBytes(String filePath) async => Uint8List.fromList(contents[filePath]!);
}

String _summary(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('compare-summary'))).textSpan!.toPlainText();

Future<void> _openDialog(WidgetTester tester, CompareSource left, CompareSource right) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => FileExplorerCompareDialog(left: left, right: right),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('compare dialog', () {
    testWidgets('shows both sides, counts changes and steps with F7', (tester) async {
      await _openDialog(
        tester,
        const CompareSource(name: 'a.txt', location: 'Local: /a.txt', text: 'one\ntwo\nthree'),
        const CompareSource(name: 'b.txt', location: 'Local: /b.txt', text: 'one\nTWO\nthree\nfour'),
      );

      expect(find.text('a.txt ↔ b.txt'), findsOneWidget);
      expect(find.text('Local: /a.txt'), findsOneWidget);
      expect(find.text('Local: /b.txt'), findsOneWidget);
      expect(_summary(tester), contains('2 changes'));
      expect(_summary(tester), contains('1 of 2'));
      expect(_summary(tester), contains('+2'));
      expect(_summary(tester), contains('−1'));

      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pump();
      expect(_summary(tester), contains('2 of 2'));

      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pump();
      expect(_summary(tester), contains('1 of 2'), reason: 'navigation wraps like VS Code');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(_summary(tester), contains('2 of 2'));
    });

    testWidgets('whitespace toggle and swap recompute the diff', (tester) async {
      await _openDialog(
        tester,
        const CompareSource(name: 'a.txt', location: 'L', text: 'x\n  y'),
        const CompareSource(name: 'b.txt', location: 'R', text: 'x\ny'),
      );
      expect(_summary(tester), contains('No differences'));

      await tester.tap(find.text('Ignore whitespace'));
      await tester.pumpAndSettle();
      expect(_summary(tester), contains('1 change'));

      await tester.tap(find.byTooltip('Swap Sides'));
      await tester.pumpAndSettle();
      expect(find.text('b.txt ↔ a.txt'), findsOneWidget);
    });
  });

  group('explorer compare actions', () {
    late _FakeService service;

    setUp(() {
      service = _FakeService(
        [
          FileExplorerItem(name: '..', path: '/', isDir: true, size: 0, modified: '- -'),
          FileExplorerItem(name: 'a.txt', path: '/root/a.txt', isDir: false, size: 10, modified: 'Jan 01 10:00'),
          FileExplorerItem(name: 'b.txt', path: '/root/b.txt', isDir: false, size: 10, modified: 'Jan 01 10:00'),
          FileExplorerItem(name: 'c.bin', path: '/root/c.bin', isDir: false, size: 3, modified: 'Jan 01 10:00'),
        ],
        {
          '/root/a.txt': utf8.encode('alpha\nbeta\n'),
          '/root/b.txt': utf8.encode('alpha\nBETA\n'),
          '/root/c.bin': [1, 0, 2],
        },
      );
    });

    Future<void> pumpExplorer(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileExplorerView(service: service, initialLeftPath: '/root', initialRightPath: '/root'),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> rightClick(WidgetTester tester, String name) async {
      await tester.tap(find.text(name).first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
    }

    testWidgets('Select for Compare then Compare with opens the diff', (tester) async {
      await pumpExplorer(tester);

      await rightClick(tester, 'a.txt');
      expect(find.text('Compare Selected'), findsNothing);
      await tester.tap(find.text('Select for Compare'));
      await tester.pumpAndSettle();

      debugPrint('SEL: ${find.textContaining("selected").evaluate().map((e) => (e.widget as Text).data).toList()}');
      await rightClick(tester, 'b.txt');
      await tester.tap(find.text("Compare with 'a.txt'"));
      await tester.pumpAndSettle();

      expect(find.byType(FileExplorerCompareDialog), findsOneWidget);
      expect(find.text('a.txt ↔ b.txt'), findsOneWidget);
      expect(_summary(tester), contains('1 change'));
    });

    testWidgets('two marked files offer Compare Selected', (tester) async {
      await pumpExplorer(tester);

      await tester.tap(find.text('a.txt').first);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('b.txt').first);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 items selected'), findsOneWidget);

      await rightClick(tester, 'b.txt');
      expect(find.text('Compare Selected'), findsOneWidget);
      expect(find.text('Select for Compare'), findsNothing);
      await tester.tap(find.text('Compare Selected'));
      await tester.pumpAndSettle();

      expect(find.text('a.txt ↔ b.txt'), findsOneWidget);
    });

    testWidgets('= picks a file, then = on another compares', (tester) async {
      await pumpExplorer(tester);

      await tester.tap(find.text('a.txt').first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();

      await tester.tap(find.text('b.txt').first);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();

      expect(find.text('a.txt ↔ b.txt'), findsOneWidget);
    });

    testWidgets('binary files get a notice instead of a text diff', (tester) async {
      await pumpExplorer(tester);

      await rightClick(tester, 'a.txt');
      await tester.tap(find.text('Select for Compare'));
      await tester.pumpAndSettle();
      await rightClick(tester, 'c.bin');
      await tester.tap(find.text("Compare with 'a.txt'"));
      await tester.pumpAndSettle();

      expect(find.byType(FileExplorerCompareDialog), findsNothing);
      expect(find.text("'a.txt' and 'c.bin' differ."), findsOneWidget);
    });
  });
}
