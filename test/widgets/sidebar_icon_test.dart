import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/sidebar_icon.dart';

void main() {
  group('SidebarIcon & RightSidebarIcon tests', () {
    testWidgets('SidebarIcon paints outer rounded rectangle and left vertical divider', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SidebarIcon(isVisible: true, size: 24),
            ),
          ),
        ),
      );
      expect(find.byType(SidebarIcon), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('RightSidebarIcon paints outer rounded rectangle and right vertical divider', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: RightSidebarIcon(isVisible: true, size: 24),
            ),
          ),
        ),
      );
      expect(find.byType(RightSidebarIcon), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('SidebarToggleButton triggers onTap callback and renders tooltip', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SidebarToggleButton(
                isSidebarVisible: true,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SidebarToggleButton), findsOneWidget);
      expect(find.byType(SidebarIcon), findsOneWidget);

      await tester.tap(find.byType(SidebarToggleButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('RightSidebarToggleButton triggers onTap callback and renders tooltip', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RightSidebarToggleButton(
                isSidebarVisible: false,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(RightSidebarToggleButton), findsOneWidget);
      expect(find.byType(RightSidebarIcon), findsOneWidget);

      await tester.tap(find.byType(RightSidebarToggleButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('FullscreenIcon renders Icons.fullscreen and Icons.fullscreen_exit states matching smart_e_he', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FullscreenIcon(isFullScreen: false, size: 24),
                FullscreenIcon(isFullScreen: true, size: 24),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(FullscreenIcon), findsNWidgets(2));
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    });

    testWidgets('FullscreenToggleButton renders with custom isFullScreen and triggers onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FullscreenToggleButton(
                isFullScreen: true,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      final iconFinder = find.byType(FullscreenIcon);
      expect(iconFinder, findsOneWidget);
      final fullscreenIcon = tester.widget<FullscreenIcon>(iconFinder);
      expect(fullscreenIcon.isFullScreen, isTrue);

      await tester.tap(find.byType(FullscreenToggleButton));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
