import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/session_fullscreen_overlay.dart';

const _hint = 'Press Ctrl+Shift+Enter to exit fullscreen';
const _bar = ValueKey('session_fullscreen_bar');

Widget _wrap(Widget overlay) => MaterialApp(
      home: Scaffold(
        body: Stack(children: [Positioned.fill(child: overlay)]),
      ),
    );

void main() {
  setUp(() {});

  testWidgets('hint shows on enter and disappears after 2s', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 600));
    await t.pumpWidget(
        _wrap(SessionFullscreenOverlay(label: 'root@db', onExit: () {})));
    expect(find.text(_hint), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text(_hint), findsNothing);
  });

  testWidgets('hovering the top edge shows the bar; Exit calls onExit',
      (t) async {
    await t.binding.setSurfaceSize(const Size(800, 600));
    var exits = 0;
    await t.pumpWidget(
        _wrap(SessionFullscreenOverlay(label: 'root@db', onExit: () => exits++)));
    expect(find.byKey(_bar), findsNothing);

    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await mouse.moveTo(const Offset(400, 2));
    await t.pumpAndSettle();
    expect(find.byKey(_bar), findsOneWidget);
    expect(find.text('root@db'), findsOneWidget);

    await t.tap(find.text('Exit fullscreen'));
    expect(exits, 1);

    await mouse.moveTo(const Offset(400, 300));
    await t.pump(const Duration(milliseconds: 1500));
    await t.pumpAndSettle();
    expect(find.byKey(_bar), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('pointer below the hot zone does not show the bar', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 600));
    await t.pumpWidget(
        _wrap(SessionFullscreenOverlay(label: 'root@db', onExit: () {})));
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await mouse.moveTo(const Offset(400, 50));
    await t.pumpAndSettle();
    expect(find.byKey(_bar), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('taps outside the hot zone and bar reach the content below',
      (t) async {
    await t.binding.setSurfaceSize(const Size(800, 600));
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
            ),
          ),
          Positioned.fill(
            child: SessionFullscreenOverlay(label: 'root@db', onExit: () {}),
          ),
        ]),
      ),
    ));
    await t.tapAt(const Offset(400, 300));
    expect(taps, 1);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
  });
}
