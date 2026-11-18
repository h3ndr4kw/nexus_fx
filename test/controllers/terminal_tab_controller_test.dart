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

    test(
      'Adding tabs to right pane updates rightTabs and auto enables split view',
      () {
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
      },
    );

    test('Switching active tabs notifies listeners', () {
      final conn1 = SshConnection(
        id: 'c1',
        host: '10.0.0.1',
        port: 22,
        label: 'S1',
      );
      final conn2 = SshConnection(
        id: 'c2',
        host: '10.0.0.2',
        port: 22,
        label: 'S2',
      );
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
      final conn1 = SshConnection(
        id: 'c1',
        host: '10.0.0.1',
        port: 22,
        label: 'S1',
      );
      final conn2 = SshConnection(
        id: 'c2',
        host: '10.0.0.2',
        port: 22,
        label: 'S2',
      );
      controller.addTab(conn1);
      controller.addTab(conn2);
      expect(controller.activeTab, 1);

      controller.closeTabAt(1);
      expect(controller.tabs.length, 1);
      expect(controller.activeTab, 0);
      expect(controller.activeConnection?.id, 'c1');
    });

    test('closeTabForConnection closes tab matching connection id', () {
      final conn1 = SshConnection(
        id: 'c1',
        host: '10.0.0.1',
        port: 22,
        label: 'S1',
      );
      final conn2 = SshConnection(
        id: 'c2',
        host: '10.0.0.2',
        port: 22,
        label: 'S2',
      );
      controller.addTab(conn1);
      controller.addTab(conn2);

      controller.closeTabForConnection('c1');
      expect(controller.tabs.length, 1);
      expect(controller.tabs.first.id, 'c2');
    });

    test('Moving tab between panes transfers connection', () {
      final conn1 = SshConnection(
        id: 'c1',
        host: '10.0.0.1',
        port: 22,
        label: 'S1',
      );
      controller.addTab(conn1);

      expect(controller.tabs.length, 1);
      expect(controller.rightTabs.length, 0);

      controller.moveTabBetweenPanes(0, fromRightPane: false);
      expect(controller.tabs.length, 0);
      expect(controller.rightTabs.length, 1);
      expect(controller.rightTabs.first.id, 'c1');
      expect(controller.isSplitView, isTrue);
    });
    test('addTab with insertIndex inserts after source and activates it', () {
      final a = SshConnection(id: 'a', host: 'h', label: 'A');
      final b = SshConnection(id: 'b', host: 'h', label: 'B');
      final dup = SshConnection(id: 'a2', host: 'h', label: 'A #2');
      controller.addTab(a);
      controller.addTab(b);
      controller.addTab(dup, insertIndex: 1);
      expect(controller.tabs.map((c) => c.id), ['a', 'a2', 'b']);
      expect(controller.activeTab, 1);
    });
  });

  group('nextDuplicateLabel', () {
    String next(String source, List<String> existing) =>
        TerminalTabController.nextDuplicateLabel(source, existing);

    test('first duplicate is #2', () {
      expect(next('Debian', ['Debian']), 'Debian #2');
    });

    test('takes the lowest free number', () {
      expect(next('Debian', ['Debian', 'Debian #2', 'Debian #3']), 'Debian #4');
      expect(next('Debian', ['Debian', 'Debian #3']), 'Debian #2');
    });

    test('duplicating a duplicate uses the base label', () {
      expect(next('Debian #2', ['Debian', 'Debian #2']), 'Debian #3');
    });

    test('ignores other targets with similar names', () {
      expect(
        next('Debian', ['Debian', 'Debian 12 #2', 'Ubuntu #2']),
        'Debian #2',
      );
    });
    test('duplicateInsertIndex keeps a group in number order', () {
      int at(List<String> pane, String label) =>
          TerminalTabController.duplicateInsertIndex(pane, label, 99);
      expect(at(['Debian', 'Ubuntu'], 'Debian #2'), 1);
      expect(at(['Debian', 'Debian #2', 'Ubuntu'], 'Debian #3'), 2);
      expect(at(['Debian', 'Debian #3', 'Ubuntu'], 'Debian #2'), 1);
      expect(at(['Ubuntu', 'Debian #3'], 'Debian #2'), 99);
    });
  });

  group('moveTab', () {
    late TerminalTabController controller;
    SshConnection c(String id) => SshConnection(id: id, host: 'h', label: id);
    List<String> left() => controller.tabs.map((t) => t.id).toList();
    List<String> right() => controller.rightTabs.map((t) => t.id).toList();

    setUp(() {
      controller = TerminalTabController();
      for (final id in ['a', 'b', 'c', 'd']) {
        controller.addTab(c(id));
      }
    });

    tearDown(() => controller.dispose());

    test('moves right within a pane', () {
      controller.moveTab('a', toRightPane: false, toIndex: 3);
      expect(left(), ['b', 'c', 'a', 'd']);
      expect(controller.activeTab, 2);
    });

    test('moves left within a pane', () {
      controller.moveTab('d', toRightPane: false, toIndex: 1);
      expect(left(), ['a', 'd', 'b', 'c']);
      expect(controller.activeTab, 1);
    });

    test('moves to the end', () {
      controller.moveTab('b', toRightPane: false, toIndex: 4);
      expect(left(), ['a', 'c', 'd', 'b']);
      expect(controller.activeTab, 3);
    });

    test('drop next to itself changes nothing', () {
      controller.moveTab('b', toRightPane: false, toIndex: 2);
      expect(left(), ['a', 'b', 'c', 'd']);
      expect(controller.activeTab, 1);
    });

    test('moves into a position of the other pane', () {
      controller.addTab(c('x'), isRightPane: true);
      controller.addTab(c('y'), isRightPane: true);
      controller.setActiveTab(3); // d
      controller.moveTab('b', toRightPane: true, toIndex: 1);
      expect(left(), ['a', 'c', 'd']);
      expect(right(), ['x', 'b', 'y']);
      expect(controller.activeRightTab, 1);
      expect(controller.lastActivePaneIsRight, isTrue);
      expect(controller.activeTab, 2, reason: 'left pane keeps d active');
    });

    test('emptying the right pane leaves split view', () {
      controller.addTab(c('x'), isRightPane: true);
      controller.moveTab('x', toRightPane: false, toIndex: 0);
      expect(left(), ['x', 'a', 'b', 'c', 'd']);
      expect(controller.isSplitView, isFalse);
      expect(controller.lastActivePaneIsRight, isFalse);
      expect(controller.activeTab, 0);
    });
  });
}
