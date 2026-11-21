import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/screens/nexus_screen.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/services/window_state_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';

SshConnection _conn(String id, String label) {
  final c = SshConnection(
    id: id,
    host: '10.0.0.1',
    port: 2222,
    label: label,
    targetUsername: 'hendra',
    clusterName: 'lab',
  );
  c.setConnectedForTesting(true);
  return c;
}

void main() {
  late GlobalKey<NexusScreenState> key;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          if (call.method == 'isFullScreen') return false;
          if (call.method == 'isMaximized') return false;
          return null;
        });
    WindowStateService.instance.resetForTesting();
    key = GlobalKey<NexusScreenState>();
  });

  tearDown(() {
    for (final c in SshService.instance.connections.values.toList()) {
      SshService.instance.connections.remove(c.id);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  Future<NexusScreenState> pumpNexus(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: NexusScreen(key: key)),
      ),
    );
    await tester.pump();
    return key.currentState!;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  // A duplicate is unconnected, so its tab view dials the (unreachable) host;
  // let that attempt hit its socket timeout so no timer outlives the test.
  Future<void> drainConnectAttempt(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  // Clicks a tab's label (the pulse indicator handles its own taps). The tab
  // strip times double-clicks by pointer timestamps, which tester.tap leaves
  // at zero, so each click carries an explicit time.
  var clickPointer = 1;
  Future<void> tapTab(WidgetTester tester, String label, Duration at) async {
    final pointer = TestPointer(clickPointer++);
    final pos = tester.getCenter(find.text(label));
    await tester.sendEventToBinding(pointer.down(pos, timeStamp: at));
    await tester.sendEventToBinding(
      pointer.up(timeStamp: at + const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('double-click opens a duplicate right after the tab', (
    tester,
  ) async {
    final nexus = await pumpNexus(tester);
    nexus.addConnectionForTesting(_conn('a', 'Debian'));
    nexus.addConnectionForTesting(_conn('b', 'Ubuntu'));
    await settle(tester);

    await tapTab(tester, 'Debian', const Duration(seconds: 1));
    await tapTab(tester, 'Debian', const Duration(milliseconds: 1200));
    await settle(tester);

    expect(nexus.tabLabels, ['Debian', 'Debian #2', 'Ubuntu']);
    expect(nexus.activeTabIndex, 1);

    final dup = nexus.tabs[1];
    expect(dup.id, isNot('a'));
    expect(dup.host, '10.0.0.1');
    expect(dup.port, 2222);
    expect(dup.targetUsername, 'hendra');
    expect(dup.clusterName, 'lab');
    expect(dup.isConnected, isFalse);
    expect(SshService.instance.connections[dup.id], same(dup));
    await drainConnectAttempt(tester);
  });

  testWidgets('single or slow clicks switch tabs without duplicating', (
    tester,
  ) async {
    final nexus = await pumpNexus(tester);
    nexus.addConnectionForTesting(_conn('a', 'Debian'));
    nexus.addConnectionForTesting(_conn('b', 'Ubuntu'));
    await settle(tester);

    await tapTab(tester, 'Debian', const Duration(seconds: 1));
    expect(nexus.activeTabIndex, 0);
    final slow =
        const Duration(seconds: 1) +
        kDoubleTapTimeout +
        const Duration(milliseconds: 50);
    await tapTab(tester, 'Debian', slow);
    expect(nexus.tabLabels, ['Debian', 'Ubuntu']);
    await tapTab(tester, 'Ubuntu', slow + const Duration(milliseconds: 100));
    await settle(tester);

    expect(nexus.tabLabels, ['Debian', 'Ubuntu']);
    expect(nexus.activeTabIndex, 1);
  });

  testWidgets('right-click menu has Duplicate Tab', (tester) async {
    final nexus = await pumpNexus(tester);
    nexus.addConnectionForTesting(_conn('a', 'Debian'));
    await settle(tester);

    await tester.tap(find.text('Debian'), buttons: kSecondaryButton);
    await settle(tester);
    await tester.tap(find.text('Duplicate Tab'));
    await settle(tester);

    expect(nexus.tabLabels, ['Debian', 'Debian #2']);
    await drainConnectAttempt(tester);
  });

  testWidgets('repeated duplicates stay in number order', (tester) async {
    final nexus = await pumpNexus(tester);
    nexus.addConnectionForTesting(_conn('a', 'Debian'));
    nexus.addConnectionForTesting(_conn('b', 'Ubuntu'));
    await settle(tester);

    var t = const Duration(seconds: 1);
    for (var i = 0; i < 2; i++) {
      await tapTab(tester, 'Debian', t);
      await tapTab(tester, 'Debian', t + const Duration(milliseconds: 150));
      t += const Duration(seconds: 1);
      await settle(tester);
    }

    expect(nexus.tabLabels, ['Debian', 'Debian #2', 'Debian #3', 'Ubuntu']);
    await drainConnectAttempt(tester);
  });

  group('drag to reorder', () {
    Future<NexusScreenState> pumpThree(WidgetTester tester) async {
      final nexus = await pumpNexus(tester);
      for (final label in ['alpha', 'bravo', 'charlie']) {
        nexus.addConnectionForTesting(_conn(label, label));
      }
      await settle(tester);
      return nexus;
    }

    Rect tabRect(WidgetTester tester, String id) =>
        tester.getRect(find.byKey(ValueKey(id)));

    // Presses a tab, drags past the slop, then hovers [to].
    Future<TestGesture> dragTabTo(
      WidgetTester tester,
      String id,
      Offset to,
    ) async {
      final gesture = await tester.startGesture(tabRect(tester, id).center);
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(to);
      await tester.pump();
      return gesture;
    }

    testWidgets('drop on the right half of a tab puts it after that tab', (
      tester,
    ) async {
      final nexus = await pumpThree(tester);
      final c = tabRect(tester, 'charlie');
      final g = await dragTabTo(
        tester,
        'alpha',
        Offset(c.right - 4, c.center.dy),
      );
      expect(
        find.byKey(const ValueKey('nexus_tab_drop_indicator')),
        findsOneWidget,
      );
      await g.up();
      await settle(tester);

      expect(nexus.tabLabels, ['bravo', 'charlie', 'alpha']);
      expect(nexus.activeTabIndex, 2);
      expect(
        find.byKey(const ValueKey('nexus_tab_drop_indicator')),
        findsNothing,
      );
    });

    testWidgets('drop on the left half of a tab puts it before that tab', (
      tester,
    ) async {
      final nexus = await pumpThree(tester);
      final a = tabRect(tester, 'alpha');
      final g = await dragTabTo(
        tester,
        'charlie',
        Offset(a.left + 4, a.center.dy),
      );
      await g.up();
      await settle(tester);

      expect(nexus.tabLabels, ['charlie', 'alpha', 'bravo']);
    });

    testWidgets('drop on empty strip space moves it to the end', (
      tester,
    ) async {
      final nexus = await pumpThree(tester);
      final c = tabRect(tester, 'charlie');
      final g = await dragTabTo(
        tester,
        'alpha',
        Offset(c.right + 200, c.center.dy),
      );
      await g.up();
      await settle(tester);

      expect(nexus.tabLabels, ['bravo', 'charlie', 'alpha']);
    });

    testWidgets('hovering next to itself shows no indicator', (tester) async {
      final nexus = await pumpThree(tester);
      final b = tabRect(tester, 'bravo');
      final g = await dragTabTo(
        tester,
        'bravo',
        Offset(b.left + 4, b.center.dy),
      );
      expect(
        find.byKey(const ValueKey('nexus_tab_drop_indicator')),
        findsNothing,
      );
      await g.up();
      await settle(tester);

      expect(nexus.tabLabels, ['alpha', 'bravo', 'charlie']);
    });
  });
}
