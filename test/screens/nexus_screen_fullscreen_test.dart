import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/screens/nexus_screen.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/services/window_state_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/session_fullscreen_overlay.dart';
import 'package:nexus_fx/widgets/ssh_tab_view.dart';

const _fsTooltip = 'Fullscreen session (Ctrl+Shift+Enter)';

SshConnection _conn(String id) {
  final c = SshConnection(id: id, host: '10.0.0.1', port: 22, label: id.toUpperCase());
  c.setConnectedForTesting(true);
  return c;
}

void main() {
  late GlobalKey<NexusScreenState> key;
  late List<bool> log;

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
    key = GlobalKey<NexusScreenState>();
    log = [];
  });

  tearDown(() {
    WindowStateService.instance.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  // standalone: no host callback, so NexusScreen owns the global shortcut
  // (inside MainScreen the host handles it).
  Future<NexusScreenState> pumpNexus(WidgetTester tester,
      {bool standalone = false}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: NexusScreen(
          key: key,
          onSessionFullscreenChanged: standalone ? null : log.add,
        ),
      ),
    ));
    await tester.pump();
    return key.currentState!;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> finishOverlayTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('enter hides the tab bar and shows the overlay; exit restores',
      (tester) async {
    final nexus = await pumpNexus(tester);
    nexus.addConnectionForTesting(_conn('a'));
    await settle(tester);
    expect(find.byTooltip(_fsTooltip), findsOneWidget);

    nexus.toggleSessionFullscreen();
    await settle(tester);
    expect(nexus.isSessionFullscreen, isTrue);
    expect(find.byTooltip(_fsTooltip), findsNothing);
    expect(find.byType(SessionFullscreenOverlay), findsOneWidget);
    expect(log, [true]);
    expect(WindowStateService.instance.isFullScreen, isTrue);

    nexus.exitSessionFullscreen();
    await settle(tester);
    expect(find.byTooltip(_fsTooltip), findsOneWidget);
    expect(find.byType(SessionFullscreenOverlay), findsNothing);
    expect(log, [true, false]);
    expect(WindowStateService.instance.isFullScreen, isFalse);
  });

  testWidgets('tab bar button enters fullscreen', (tester) async {
    final nexus = await pumpNexus(tester);
    nexus.addConnectionForTesting(_conn('a'));
    await settle(tester);
    await tester.tap(find.byTooltip(_fsTooltip));
    await settle(tester);
    expect(nexus.isSessionFullscreen, isTrue);
    nexus.exitSessionFullscreen();
    await finishOverlayTimers(tester);
  });

  testWidgets('SshTabView state is preserved across enter and exit',
      (tester) async {
    final nexus = await pumpNexus(tester);
    final a = _conn('a');
    nexus.addConnectionForTesting(a);
    await settle(tester);
    final before = tester.state(find.byKey(GlobalObjectKey(a)));

    nexus.toggleSessionFullscreen();
    await settle(tester);
    expect(tester.state(find.byKey(GlobalObjectKey(a))), same(before));

    nexus.exitSessionFullscreen();
    await settle(tester);
    expect(tester.state(find.byKey(GlobalObjectKey(a))), same(before));
    await finishOverlayTimers(tester);
  });

  testWidgets('split view with right target: left pane offstage, not disposed',
      (tester) async {
    final nexus = await pumpNexus(tester);
    final a = _conn('a');
    final b = _conn('b');
    nexus.addConnectionForTesting(a);
    nexus.toggleSplitView();
    nexus.addConnectionForTesting(b, isRightPane: true);
    await settle(tester);
    final leftState = tester.state(find.byKey(GlobalObjectKey(a)));

    nexus.toggleSessionFullscreen(b);
    await settle(tester);
    expect(find.byKey(GlobalObjectKey(a), skipOffstage: false), findsOneWidget);
    expect(find.byKey(GlobalObjectKey(a)), findsNothing);
    expect(find.byKey(GlobalObjectKey(b)), findsOneWidget);
    expect(tester.state(find.byKey(GlobalObjectKey(a), skipOffstage: false)),
        same(leftState));

    nexus.exitSessionFullscreen();
    await settle(tester);
    expect(find.byKey(GlobalObjectKey(a)), findsOneWidget);
    await finishOverlayTimers(tester);
  });

  testWidgets('closing the fullscreen session exits fullscreen', (tester) async {
    final nexus = await pumpNexus(tester);
    final a = _conn('a');
    nexus.addConnectionForTesting(a);
    nexus.addConnectionForTesting(_conn('b'));
    nexus.tabController.setActiveTab(0);
    await settle(tester);

    nexus.toggleSessionFullscreen();
    await settle(tester);
    tester.widget<SshTabView>(find.byKey(GlobalObjectKey(a))).onClose();
    await settle(tester);
    expect(nexus.isSessionFullscreen, isFalse);
    expect(find.byTooltip(_fsTooltip), findsOneWidget);
    await finishOverlayTimers(tester);
  });

  testWidgets('Ctrl+Shift+Enter in the terminal toggles and writes nothing',
      (tester) async {
    final nexus = await pumpNexus(tester, standalone: true);
    final a = _conn('a');
    nexus.addConnectionForTesting(a);
    await settle(tester);
    final written = <String>[];
    a.terminal.onOutput = written.add;

    await tester.tap(find.byKey(GlobalObjectKey(a)));
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(nexus.isSessionFullscreen, isTrue);
    expect(written, isEmpty);
    nexus.exitSessionFullscreen();
    await finishOverlayTimers(tester);
  });

  testWidgets('Ctrl+Tab does not switch tabs while fullscreen', (tester) async {
    final nexus = await pumpNexus(tester);
    nexus.addConnectionForTesting(_conn('a'));
    nexus.addConnectionForTesting(_conn('b'));
    nexus.tabController.setActiveTab(0);
    await settle(tester);

    nexus.toggleSessionFullscreen();
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(nexus.activeTabIndex, 0);
    nexus.exitSessionFullscreen();
    await finishOverlayTimers(tester);
  });
}
