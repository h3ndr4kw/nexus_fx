import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/screens/main_screen.dart';
import 'package:nexus_fx/screens/nexus_screen.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/services/window_state_service.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/draggable_dialog.dart';
import 'package:nexus_fx/widgets/sidebar_icon.dart';

void main() {
  late Directory tempDir;
  late File sessionFile;
  late SessionManagerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nexus_fx_main_test_');
    sessionFile = File('${tempDir.path}/sessions.json');
    service = SessionManagerService.forTesting();
    await service.loadSessions(customFilePath: sessionFile.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget createTestWidget() {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: MainScreen(
        sessionManager: service,
        suppressStartupDialog: true,
      ),
    );
  }

  testWidgets('MainScreen boots directly to Nexus view and displays primary navigation tabs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Verify primary navigation items in sidebar
    expect(find.text('Nexus'), findsOneWidget);
    expect(find.text('File Explorer'), findsOneWidget);
    // Session Manager and Settings are top bar icon buttons
    expect(find.byTooltip('Session Manager'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    // Verify initial active tab is Nexus
    expect(find.byIcon(Icons.terminal), findsWidgets);

    // Tap Session Manager button in top bar -> opens Sessions dialog
    await tester.tap(find.byTooltip('Session Manager'));
    await tester.pumpAndSettle();

    // Verify Sessions dialog is open
    expect(find.byType(DraggableDialog), findsOneWidget);
    expect(find.text('All Sessions'), findsOneWidget);
    expect(find.text('LOCAL'), findsWidgets);

    // Close Sessions dialog
    await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
    await tester.pumpAndSettle();

    // Tap Settings button in top bar
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    // Verify Settings view is rendered
    expect(find.text('Startup & Sessions'), findsOneWidget);
    expect(find.text('Show Sessions Manager dialog at startup'), findsOneWidget);
  });

  testWidgets('MainScreen preserves Nexus SSH terminal sessions when navigating to File Explorer and back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Switch to Nexus tab
    await tester.tap(find.textContaining('Nexus').first);
    await tester.pumpAndSettle();

    // Verify LOCAL session exists
    final sessions = service.sessions;
    expect(sessions.any((s) => s.isLocal), isTrue);
    
    // Quick connect LOCAL session from UI or command palette
    await tester.sendKeyEvent(LogicalKeyboardKey.space, platform: 'windows'); // with ctrl pressed
    // Use Alt+2 / direct tab switch
    await tester.tap(find.textContaining('File Explorer').first);
    await tester.pumpAndSettle();

    // Verify File Explorer view is visible with tab header
    expect(find.text('Local Explorer'), findsOneWidget);
    expect(find.byKey(const ValueKey('file_explorer_new_tab_button')), findsOneWidget);

    // Switch back to Nexus tab
    await tester.tap(find.textContaining('Nexus').first);
    await tester.pumpAndSettle();

    // Verify Nexus tab is still active and mounted without crash or reset
    expect(find.byIcon(Icons.terminal), findsWidgets);
  });

  testWidgets('Global shortcuts work: Ctrl+B toggles sidebar, Alt+2 switches tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Verify sidebar is initially visible
    expect(find.text('Nexus'), findsOneWidget);

    // Press Ctrl+B to toggle sidebar collapse
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Sidebar should be collapsed
    expect(find.text('Nexus'), findsNothing);

    // Press Ctrl+B again to expand
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Sidebar should be visible again
    expect(find.text('Nexus'), findsOneWidget);

    // Press Alt+2 to switch directly to Nexus tab
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // Nexus is now active
    expect(find.byIcon(Icons.terminal), findsWidgets);

    // Press Ctrl+Shift+Space to toggle Command Pane OPEN
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Verify command pane TextField is visible (command input is opened)
    expect(find.byType(TextField), findsWidgets);

    // Press Ctrl+Shift+Space to toggle Command Pane CLOSED
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Verify command pane TextField is gone
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('MainScreen shows draggable SessionsDialog on startup when enabled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MainScreen(
          sessionManager: service,
          suppressStartupDialog: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The Sessions modal dialog should be displayed with DraggableDialog header
    expect(find.byType(DraggableDialog), findsOneWidget);
    expect(find.text('Show this dialog box at startup'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Close'), findsWidgets);

    // Verify dragging the dialog title bar moves the dialog
    final headerFinder = find.descendant(
      of: find.byType(DraggableDialog),
      matching: find.byType(GestureDetector),
    );
    await tester.drag(headerFinder.first, const Offset(50, 50), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Close the dialog using Close button
    await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
    await tester.pumpAndSettle();

    // Dialog dismissed, MainScreen still visible
    expect(find.byType(DraggableDialog), findsNothing);
    expect(find.byTooltip('Session Manager'), findsOneWidget);
    expect(find.text('Nexus'), findsOneWidget);
  });

  testWidgets('Pressing Enter on Nexus terminal view does not trigger background SessionsScreen connect', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Switch to Nexus tab (Alt+2)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // Verify Nexus tab is active
    expect(find.byIcon(Icons.terminal), findsWidgets);

    // Send Enter key (as when running a command in terminal)
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Verify no unexpected session dialog or duplicate connection error occurred
    expect(find.byType(DraggableDialog), findsNothing);
  });

  testWidgets('Left sidebar can be resized to minimum (icon-only mode) and restored', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Initially labels are visible
    expect(find.text('Nexus'), findsOneWidget);
    expect(find.text('File Explorer'), findsOneWidget);

    // Find resize divider handle
    final resizeHandle = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
    );
    expect(resizeHandle, findsOneWidget);

    // Drag the handle far to the left (-200 pixels)
    await tester.drag(resizeHandle, const Offset(-200, 0));
    await tester.pumpAndSettle();

    // Now in compact icon-only mode: text labels are gone, icons remain
    expect(find.text('Nexus'), findsNothing);
    expect(find.text('File Explorer'), findsNothing);
    expect(find.byIcon(Icons.terminal), findsWidgets);
    expect(find.byIcon(Icons.folder_open), findsWidgets);

    // Double tap the handle to restore default width
    await tester.tap(resizeHandle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(resizeHandle);
    await tester.pumpAndSettle();

    // Labels are visible again
    expect(find.text('Nexus'), findsOneWidget);
    expect(find.text('File Explorer'), findsOneWidget);

    // Test Alt+ArrowLeft to shrink sidebar to icon-only mode
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    // Press ArrowLeft multiple times to shrink down to 50px
    for (int i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // In icon-only mode, text labels are hidden
    expect(find.text('Nexus'), findsNothing);
    expect(find.byIcon(Icons.terminal), findsWidgets);

    // Test Alt+ArrowRight to enlarge sidebar back
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    // Labels are restored
    expect(find.text('Nexus'), findsOneWidget);
    expect(find.text('File Explorer'), findsOneWidget);
  });

  testWidgets('File Explorer supports multi-tab management, new tab button, and close all tabs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Switch to File Explorer tab
    await tester.tap(find.text('File Explorer'));
    await tester.pumpAndSettle();

    // Verify initial state: default Local Explorer tab is open, (+) button is present, Close All button is not present
    expect(find.text('Local Explorer'), findsOneWidget);
    expect(find.byKey(const ValueKey('file_explorer_new_tab_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('file_explorer_close_all_button')), findsNothing);

    // Tap (+) new tab button -> opens SELECT NODE node picker dialog
    await tester.tap(find.byKey(const ValueKey('file_explorer_new_tab_button')));
    await tester.pumpAndSettle();

    expect(find.text('Connect Custom SSH Node...'), findsOneWidget);

    // Select the Local Filesystem target
    await tester.tap(find.text('Local Filesystem').last);
    await tester.pumpAndSettle();

    // Now we should have 2 tabs, both 'Local Explorer', and the 'Close All' button is visible
    expect(find.byKey(const ValueKey('file_explorer_close_all_button')), findsOneWidget);
    expect(find.text('Local Explorer'), findsNWidgets(2));

    // Test closing one tab by tapping its close (X) icon
    final closeButtons = find.byTooltip('Close Tab (Ctrl+W)');
    expect(closeButtons, findsNWidgets(2));
    await tester.tap(closeButtons.first);
    await tester.pumpAndSettle();

    // Now only 1 tab remains, 'Close All' is hidden
    expect(find.byKey(const ValueKey('file_explorer_close_all_button')), findsNothing);
    expect(find.text('Local Explorer'), findsOneWidget);
  });

  testWidgets('Right sidebar toggle button only appears on Nexus page and Left sidebar toggle updates state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Initially on Nexus tab: both sidebar toggles are present
    expect(find.byType(SidebarToggleButton), findsOneWidget);
    expect(find.byType(RightSidebarToggleButton), findsOneWidget);

    // Switch to File Explorer tab
    await tester.tap(find.text('File Explorer'));
    await tester.pumpAndSettle();

    // On File Explorer tab: Right sidebar toggle is hidden
    expect(find.byType(RightSidebarToggleButton), findsNothing);

    // Switch back to Nexus tab
    await tester.tap(find.text('Nexus'));
    await tester.pumpAndSettle();

    // On Nexus tab: Right sidebar toggle is visible again
    expect(find.byType(RightSidebarToggleButton), findsOneWidget);

    // Switch to Settings tab via top bar
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    // On Settings tab: Right sidebar toggle is hidden
    expect(find.byType(RightSidebarToggleButton), findsNothing);

    // Test Left sidebar toggle button tap
    final leftToggleFinder = find.byType(SidebarToggleButton);
    expect(leftToggleFinder, findsOneWidget);
    var leftIcon = tester.widget<SidebarIcon>(find.descendant(of: leftToggleFinder, matching: find.byType(SidebarIcon)));
    expect(leftIcon.isVisible, isTrue);

    await tester.tap(leftToggleFinder);
    await tester.pumpAndSettle();

    leftIcon = tester.widget<SidebarIcon>(find.descendant(of: leftToggleFinder, matching: find.byType(SidebarIcon)));
    expect(leftIcon.isVisible, isFalse);
  });

  testWidgets('3-dot sash gripper fades in on mouse move and fades out on selecting main widget or 3s idle', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    final resizeHandle = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
    );
    expect(resizeHandle, findsOneWidget);

    final sashOpacityFinder = find.descendant(
      of: resizeHandle,
      matching: find.byType(AnimatedOpacity),
    );
    expect(sashOpacityFinder, findsOneWidget);

    // 1. Move mouse: dots fade in
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(50, 50));
    await gesture.moveTo(const Offset(60, 60));
    await tester.pump(const Duration(milliseconds: 250));

    var animatedOpacity = tester.widget<AnimatedOpacity>(sashOpacityFinder);
    expect(animatedOpacity.opacity, equals(1.0));

    // 2. Idle for 3 seconds: dots fade out automatically
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 250));

    animatedOpacity = tester.widget<AnimatedOpacity>(sashOpacityFinder);
    expect(animatedOpacity.opacity, equals(0.0));

    // 3. Move mouse again: dots fade in
    await gesture.moveTo(const Offset(70, 70));
    await tester.pump(const Duration(milliseconds: 250));

    animatedOpacity = tester.widget<AnimatedOpacity>(sashOpacityFinder);
    expect(animatedOpacity.opacity, equals(1.0));

    // 4. Tap on the main body content area to select the main widget: dots fade out immediately
    await tester.tapAt(const Offset(600, 300));
    await tester.pump(const Duration(milliseconds: 250));

    animatedOpacity = tester.widget<AnimatedOpacity>(sashOpacityFinder);
    expect(animatedOpacity.opacity, equals(0.0));
  });
  group('session fullscreen', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'),
              (call) async {
        if (call.method == 'isFullScreen') {
          return WindowStateService.instance.isFullScreen;
        }
        if (call.method == 'isMaximized') return false;
        return null;
      });
      WindowStateService.instance.resetForTesting();
    });

    tearDown(() {
      WindowStateService.instance.resetForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    });

    Future<NexusScreenState> pumpWithSession(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      final nexus = tester.state<NexusScreenState>(find.byType(NexusScreen));
      final conn = SshConnection(id: 'a', host: '10.0.0.1', port: 22, label: 'A');
      conn.setConnectedForTesting(true);
      nexus.addConnectionForTesting(conn);
      await tester.pump();
      return nexus;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> drainOverlay(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> pressCtrlShiftEnter(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }

    testWidgets('hides title bar and sidebar; exit restores them',
        (tester) async {
      final nexus = await pumpWithSession(tester);
      expect(find.byTooltip('Session Manager'), findsOneWidget);
      expect(find.text('File Explorer'), findsOneWidget);
      final nexusState = nexus;

      nexus.toggleSessionFullscreen();
      await settle(tester);
      expect(find.byTooltip('Session Manager'), findsNothing);
      expect(find.text('File Explorer'), findsNothing);
      // NexusScreen keeps its state while the chrome around it changes.
      expect(tester.state(find.byType(NexusScreen)), same(nexusState));

      nexus.exitSessionFullscreen();
      await settle(tester);
      expect(find.byTooltip('Session Manager'), findsOneWidget);
      expect(find.text('File Explorer'), findsOneWidget);
      expect(tester.state(find.byType(NexusScreen)), same(nexusState));
      await drainOverlay(tester);
    });

    testWidgets('Ctrl+Shift+Enter toggles session fullscreen', (tester) async {
      final nexus = await pumpWithSession(tester);
      await pressCtrlShiftEnter(tester);
      await settle(tester);
      expect(nexus.isSessionFullscreen, isTrue);
      await pressCtrlShiftEnter(tester);
      await settle(tester);
      expect(nexus.isSessionFullscreen, isFalse);
      expect(find.byTooltip('Session Manager'), findsOneWidget);
      await drainOverlay(tester);
    });

    testWidgets('switching to File Explorer exits session fullscreen',
        (tester) async {
      final nexus = await pumpWithSession(tester);
      nexus.toggleSessionFullscreen();
      await settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await settle(tester);
      expect(nexus.isSessionFullscreen, isFalse);
      expect(find.text('File Explorer'), findsWidgets);
      await drainOverlay(tester);
    });

    testWidgets('command palette lists Toggle Session Fullscreen',
        (tester) async {
      await pumpWithSession(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Toggle Session Fullscreen'), findsOneWidget);
    });
  });
}
