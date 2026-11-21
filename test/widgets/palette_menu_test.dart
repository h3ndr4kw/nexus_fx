import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/palette_widgets.dart';

void main() {
  Future<Future<String?>> openMenu(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      })),
    ));
    final result = showPaletteMenu<String>(
      context: ctx,
      position: const Offset(20, 20),
      items: const [
        PaletteMenuItem(value: 'open', label: 'Open', shortcut: 'Enter'),
        PaletteMenuDivider(),
        PaletteMenuItem(value: 'rename', label: 'Rename', enabled: false),
      ],
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('tapping a row returns its value', (tester) async {
    final result = await openMenu(tester);
    expect(find.text('Enter'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(await result, 'open');
  });

  testWidgets('disabled row ignores taps', (tester) async {
    await openMenu(tester);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('keyboard focus then Enter selects', (tester) async {
    final result = await openMenu(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await result, 'open');
  });
}
