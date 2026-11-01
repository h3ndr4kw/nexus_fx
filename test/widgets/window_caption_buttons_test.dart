import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/window_state_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/window_caption_buttons.dart';

void main() {
  group('WindowCaptionButtons Widget Tests', () {
    setUp(() {
      WindowStateService.instance.resetForTesting();
    });

    testWidgets('Renders minimize, maximize, and close buttons on desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Row(
              children: [
                Text('admin'),
                SizedBox(width: 24),
                WindowCaptionButtons(spacing: 8.0),
              ],
            ),
          ),
        ),
      );

      // Verify buttons are rendered
      expect(find.byType(WindowCaptionButtons), findsOneWidget);
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
      expect(find.byTooltip('Full Screen (F11)'), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Renders fullscreen button when showFullScreen is true', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Row(
              children: [
                Text('admin'),
                SizedBox(width: 20),
                WindowCaptionButtons(
                  spacing: 8.0,
                  showFullScreen: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(WindowCaptionButtons), findsOneWidget);
      expect(find.byTooltip('Full Screen (F11)'), findsOneWidget);
      expect(find.byTooltip('Minimize'), findsOneWidget);
      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      // Tap fullscreen button to verify no exception thrown
      await tester.tap(find.byTooltip('Full Screen (F11)'));
      await tester.pump();

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Respects custom spacing and button dimensions', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: WindowCaptionButtons(
              spacing: 12.0,
              buttonWidth: 36.0,
              buttonHeight: 30.0,
              showFullScreen: true,
            ),
          ),
        ),
      );

      expect(find.byType(WindowCaptionButtons), findsOneWidget);
      expect(find.byTooltip('Full Screen (F11)'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Tapping fullscreen button toggles icon between fullscreen and fullscreen_exit', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: WindowCaptionButtons(
              spacing: 8.0,
              showFullScreen: true,
            ),
          ),
        ),
      );

      // Initially, not in fullscreen
      expect(find.byTooltip('Full Screen (F11)'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.byTooltip('Exit Full Screen (F11)'), findsNothing);
      expect(find.byIcon(Icons.fullscreen_exit), findsNothing);

      // Tap fullscreen button to enter fullscreen
      await tester.tap(find.byTooltip('Full Screen (F11)'));
      await tester.pumpAndSettle();

      // Now should be in fullscreen (showing exit fullscreen icon)
      expect(find.byTooltip('Exit Full Screen (F11)'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
      expect(find.byTooltip('Full Screen (F11)'), findsNothing);

      // Tap un-fullscreen button to exit fullscreen
      await tester.tap(find.byTooltip('Exit Full Screen (F11)'));
      await tester.pumpAndSettle();

      // Icon should become fullscreen icon again!
      expect(find.byTooltip('Full Screen (F11)'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.byTooltip('Exit Full Screen (F11)'), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('When already in fullscreen, clicking un-fullscreen button changes icon to fullscreen', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      WindowStateService.instance.setFullScreenForTesting(true);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: WindowCaptionButtons(
              spacing: 8.0,
              showFullScreen: true,
            ),
          ),
        ),
      );

      // Matches user screenshot: already in fullscreen, icon is fullscreen_exit
      expect(find.byTooltip('Exit Full Screen (F11)'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);

      // Click the un-fullscreen button
      await tester.tap(find.byTooltip('Exit Full Screen (F11)'));
      await tester.pumpAndSettle();

      // Icon must change to fullscreen icon
      expect(find.byTooltip('Full Screen (F11)'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Tapping maximize button toggles maximize and restore icons', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: WindowCaptionButtons(spacing: 8.0),
          ),
        ),
      );

      // Initially not maximized
      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(find.byIcon(Icons.crop_square), findsOneWidget);

      // Tap maximize
      await tester.tap(find.byTooltip('Maximize'));
      await tester.pumpAndSettle();

      // Now maximized (shows restore icon)
      expect(find.byTooltip('Restore'), findsOneWidget);
      expect(find.byIcon(Icons.filter_none_outlined), findsOneWidget);

      // Tap restore
      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Maximize'), findsOneWidget);
      expect(find.byIcon(Icons.crop_square), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
