import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/controllers/terminal_tab_controller.dart';
import 'package:nexus_fx/services/ssh_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalTabController Tests', () {
    late TerminalTabController controller;

    setUp(() {
      controller = TerminalTabController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('Initial state is clean and empty', () {
      expect(controller.tabs, isEmpty);
      expect(controller.rightTabs, isEmpty);
      expect(controller.activeTab, 0);
      expect(controller.activeRightTab, 0);
      expect(controller.isSplitView, isFalse);
      expect(controller.lastActivePaneIsRight, isFalse);
      expect(controller.activeConnection, isNull);
    });

    test('Adding tabs to left pane updates tabs list and active index', () {
      final conn1 = SshConnection(
        id: 'conn-1',
        host: '10.0.0.1',
        port: 22,
        label: 'Server 1',
      );
      final conn2 = SshConnection(
        id: 'conn-2',
        host: '10.0.0.2',
        port: 22,
        label: 'Server 2',
      );

      controller.addTab(conn1);
      expect(controller.tabs.length, 1);
      expect(controller.activeTab, 0);
      expect(controller.activeConnection?.id, 'conn-1');
      expect(controller.tabLabels, ['Server 1']);

      controller.addTab(conn2);
      expect(controller.tabs.length, 2);
      expect(controller.activeTab, 1);
      expect(controller.activeConnection?.id, 'conn-2');
    });

    test('Adding tabs to right pane updates rightTabs and auto enables split view', () {
      final connRight = SshConnection(
        id: 'conn-right-1',
        host: '10.0.0.3',
        port: 22,
        label: 'Right Server',
      );

      controller.addTabToRight(connRight);
      expect(controller.rightTabs.length, 1);
      expect(controller.activeRightTab, 0);
      expect(controller.rightTabLabels, ['Right Server']);
      expect(controller.isSplitView, isTrue);
    });

    test('Switching active tabs notifies listeners', () {
      final conn1 = SshConnection(id: 'c1', host: '10.0.0.1', port: 22, label: 'S1');
      final conn2 = SshConnection(id: 'c2', host: '10.0.0.2', port: 22, label: 'S2');
      controller.addTab(conn1);
      controller.addTab(conn2);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.setActiveTab(0);
      expect(controller.activeTab, 0);
      expect(controller.activeConnection?.id, 'c1');
      expect(notifyCount, 1);
    });

    test('Closing tab removes connection and clamps active index', () {
      final conn1 = SshConnection(id: 'c1', host: '10.0.0.1', port: 22, label: 'S1');
      final conn2 = SshConnection(id: 'c2', host: '10.0.0.2', port: 22, label: 'S2');
      controller.addTab(conn1);
      controller.addTab(conn2);
      expect(controller.activeTab, 1);

      controller.closeTabAt(1);
      expect(controller.tabs.length, 1);
      expect(controller.activeTab, 0);
      expect(controller.activeConnection?.id, 'c1');
    });

    test('closeTabForConnection closes tab matching connection id', () {
      final conn1 = SshConnection(id: 'c1', host: '10.0.0.1', port: 22, label: 'S1');
      final conn2 = SshConnection(id: 'c2', host: '10.0.0.2', port: 22, label: 'S2');
      controller.addTab(conn1);
      controller.addTab(conn2);

      controller.closeTabForConnection('c1');
      expect(controller.tabs.length, 1);
      expect(controller.tabs.first.id, 'c2');
    });

    test('Moving tab between panes transfers connection', () {
      final conn1 = SshConnection(id: 'c1', host: '10.0.0.1', port: 22, label: 'S1');
      controller.addTab(conn1);

      expect(controller.tabs.length, 1);
      expect(controller.rightTabs.length, 0);

      controller.moveTabBetweenPanes(0, fromRightPane: false);
      expect(controller.tabs.length, 0);
      expect(controller.rightTabs.length, 1);
      expect(controller.rightTabs.first.id, 'c1');
      expect(controller.isSplitView, isTrue);
    });
  });
}
