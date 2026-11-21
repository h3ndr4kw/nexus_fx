import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/file_explorer_dialogs.dart';

Future<void> _open(WidgetTester tester, Widget dialog, ValueSetter<Object?> onResult) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => onResult(await showDialog<Object?>(
                context: context,
                builder: (_) => dialog,
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('confirm dialog', () {
    testWidgets('default button is focused and Tab moves to the other one', (tester) async {
      Object? result = 'unset';
      await _open(
        tester,
        const FileExplorerConfirmDialog(
          title: 'DELETE',
          message1: 'Delete it?',
          defaultYes: false,
        ),
        (r) => result = r,
      );

      // Default is No; Tab reaches Yes and Enter confirms.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, true);
    });

    testWidgets('Enter on the default No button answers false', (tester) async {
      Object? result = 'unset';
      await _open(
        tester,
        const FileExplorerConfirmDialog(
          title: 'DELETE',
          message1: 'Delete it?',
          defaultYes: false,
        ),
        (r) => result = r,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, false);
    });

    testWidgets('buttons are exposed as buttons', (tester) async {
      await _open(
        tester,
        const FileExplorerConfirmDialog(title: 'T', message1: 'm'),
        (_) {},
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Yes')),
        matchesSemantics(
          label: 'Yes',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('prompt dialog', () {
    testWidgets('empty value shows an error and keeps the dialog open', (tester) async {
      Object? result = 'unset';
      await _open(
        tester,
        const FileExplorerPromptDialog(title: 'CHANGE DIRECTORY', promptLabel: 'Enter absolute path:'),
        (r) => result = r,
      );
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.text('This field cannot be empty.'), findsOneWidget);
      expect(result, 'unset');
    });

    testWidgets('validator error keeps the dialog open, valid value returns', (tester) async {
      Object? result = 'unset';
      await _open(
        tester,
        FileExplorerPromptDialog(
          title: 'CHANGE DIRECTORY',
          promptLabel: 'Enter absolute path:',
          validator: (v) => v.startsWith('/') ? null : 'Use an absolute path starting with /.',
        ),
        (r) => result = r,
      );
      await tester.enterText(find.byType(TextField), 'tmp');
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.text('Use an absolute path starting with /.'), findsOneWidget);
      expect(result, 'unset');

      await tester.enterText(find.byType(TextField), '/tmp');
      await tester.pump();
      expect(find.text('Use an absolute path starting with /.'), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, '/tmp');
    });
  });

  group('settings dialog', () {
    testWidgets('Enter does not close the dialog; tiles are tab stops', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _open(tester, const FileExplorerSettingsDialog(), (_) {});
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Explorer Appearance & Font Settings'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Explorer Appearance & Font Settings'), findsNothing);
    });
  });

  group('progress dialog', () {
    FileTransferProgress progress({String? error, String? note, double value = 0.4}) =>
        FileTransferProgress(
          title: 'Copying 5 items',
          currentFile: 'a.log',
          completedItems: 2,
          totalItems: 5,
          progress: value,
          errorMessage: error,
          note: note,
        );

    testWidgets('shows counts, follows the notifier, Esc and the button go to background',
        (tester) async {
      final notifier = ValueNotifier(progress());
      var background = 0;
      var cancelled = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileExplorerProgressDialog(
            progressNotifier: notifier,
            onBackground: () => background++,
            onCancel: () => cancelled++,
          ),
        ),
      ));
      expect(find.text('Copying 5 items'), findsOneWidget);
      expect(find.textContaining('[2/5] items (40%)'), findsOneWidget);

      notifier.value = progress(value: 0.8, note: 'Cancelling...');
      await tester.pump();
      expect(find.textContaining('(80%)'), findsOneWidget);
      expect(find.text('Cancelling...'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(background, 1);
      expect(cancelled, 0);

      await tester.tap(find.text('Cancel transfer'));
      expect(cancelled, 1);
    });

    testWidgets('a failed transfer shows the error and only Close', (tester) async {
      var background = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileExplorerProgressDialog(
            progressNotifier: ValueNotifier(progress(error: 'Permission denied')),
            onBackground: () => background++,
            onCancel: () {},
          ),
        ),
      ));
      expect(find.text('Copying 5 items failed'), findsOneWidget);
      expect(find.text('Permission denied'), findsOneWidget);
      expect(find.text('Cancel transfer'), findsNothing);
      await tester.tap(find.text('Close'));
      expect(background, 1);
    });
  });
}
