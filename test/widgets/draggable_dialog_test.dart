import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/draggable_dialog.dart';

void main() {
  testWidgets(
    'title bar moves with Alt+arrows, Shift steps further, Alt+Home resets',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DraggableDialog(
              title: 'Probe',
              minWidth: 300,
              minHeight: 200,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );

      // Tab onto the title bar (the first focusable thing in the dialog).
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      final start = tester.getTopLeft(find.text('Probe'));

      // Plain arrows belong to the dialog content and must not move it.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(tester.getTopLeft(find.text('Probe')), start);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('Probe')) - start,
        const Offset(16, 0),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('Probe')) - start,
        const Offset(16, 64),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(tester.getTopLeft(find.text('Probe')), start);
    },
  );
}
