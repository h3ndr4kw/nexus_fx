import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/controllers/file_explorer_tabs_controller.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';

ExplorerNodeTarget _remote(String label) => ExplorerNodeTarget(
      type: ExplorerTargetType.sessionSsh,
      label: label,
      host: '10.0.0.1',
      port: 22,
      username: 'root',
      sessionId: 'sess_$label',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileExplorerTabsController tabs;
  late int notifications;

  setUp(() {
    tabs = FileExplorerTabsController();
    notifications = 0;
    tabs.addListener(() => notifications++);
  });

  tearDown(() => tabs.dispose());

  List<String> labels() => tabs.tabs.map((t) => t.label).toList();

  test('starts with one local tab', () {
    expect(labels(), ['Local Explorer']);
    expect(tabs.activeIndex, 0);
    expect(tabs.activeTab.leftTarget.isLocal, isTrue);
    expect(tabs.activeTab.rightTarget.isLocal, isTrue);
    expect(tabs.activeTab.initialActivePane, PaneSide.left);
  });

  test('opening a remote target adds an active tab with the remote on the right', () {
    final tab = tabs.open(_remote('db1'));

    expect(labels(), ['Local Explorer', 'SFTP: db1']);
    expect(tabs.activeTab, same(tab));
    expect(tab.leftTarget.isLocal, isTrue);
    expect(tab.rightTarget.label, 'db1');
    expect(tab.initialActivePane, PaneSide.right);
    expect(notifications, 1);
  });

  test('opening a local target starts on the left pane', () {
    final tab = tabs.open(ExplorerNodeTarget.local);

    expect(tab.label, 'Local Explorer');
    expect(tab.initialActivePane, PaneSide.left);
  });

  test('every tab gets a distinct id, also after tabs were closed', () {
    tabs.open(_remote('a'));
    tabs.close(1);
    tabs.open(_remote('b'));
    tabs.closeAll();
    tabs.open(_remote('c'));

    final ids = <String>{for (final t in tabs.tabs) t.id};
    expect(ids, hasLength(tabs.tabs.length));
    expect(ids, isNot(contains('fe_tab_1')));
  });

  group('switching', () {
    setUp(() {
      tabs.open(_remote('a'));
      tabs.open(_remote('b')); // tabs: local, a, b — active: b
      notifications = 0;
    });

    test('wraps around in both directions', () {
      tabs.switchBy(1);
      expect(tabs.activeIndex, 0);

      tabs.switchBy(-1);
      expect(tabs.activeIndex, 2);
      expect(notifications, 2);
    });

    test('activate selects a tab by index and ignores an invalid one', () {
      tabs.activate(1);
      expect(tabs.activeTab.label, 'SFTP: a');

      tabs.activate(7);
      tabs.activate(-1);
      expect(tabs.activeIndex, 1);
      expect(notifications, 1);
    });

    test('does nothing with a single tab', () {
      tabs.closeAll();
      notifications = 0;

      tabs.switchBy(1);

      expect(tabs.activeIndex, 0);
      expect(notifications, 0);
    });
  });

  group('closing', () {
    setUp(() {
      tabs.open(_remote('a'));
      tabs.open(_remote('b')); // tabs: local, a, b — active: b
      notifications = 0;
    });

    test('closing the active last tab activates the new last tab', () {
      tabs.close(2);

      expect(labels(), ['Local Explorer', 'SFTP: a']);
      expect(tabs.activeIndex, 1);
    });

    test('closing a tab before the active one keeps the same tab active', () {
      final active = tabs.activeTab;

      tabs.close(0);

      expect(tabs.activeTab, same(active));
      expect(tabs.activeIndex, 1);
    });

    test('closing a tab after the active one leaves the index alone', () {
      tabs.activate(0);

      tabs.close(2);

      expect(tabs.activeIndex, 0);
      expect(labels(), ['Local Explorer', 'SFTP: a']);
    });

    test('closing the only tab replaces it with a fresh local tab', () {
      tabs.closeAll();
      final only = tabs.activeTab;

      tabs.close(0);

      expect(labels(), ['Local Explorer']);
      expect(tabs.activeTab, isNot(same(only)));
      expect(tabs.activeIndex, 0);
    });

    test('an invalid index is ignored', () {
      tabs.close(9);
      tabs.close(-1);

      expect(tabs.tabs, hasLength(3));
      expect(notifications, 0);
    });

    test('close others keeps only the given tab, active', () {
      final keep = tabs.tabs[1];

      tabs.closeOthers(keep);

      expect(tabs.tabs, [keep]);
      expect(tabs.activeIndex, 0);
    });

    test('close all leaves one fresh local tab', () {
      tabs.closeAll();

      expect(labels(), ['Local Explorer']);
      expect(tabs.activeIndex, 0);
      expect(notifications, 1);
    });

    test('a closed tab releases its focus node', () {
      final closed = tabs.tabs[1];

      tabs.close(1);

      // A disposed FocusNode asserts when a listener is added.
      expect(() => closed.focusNode.addListener(() {}), throwsFlutterError);
    });
  });

  test('retargeting a tab relabels it and notifies', () {
    final tab = tabs.open(_remote('a'));
    notifications = 0;

    tabs.retarget(tab, right: _remote('b'));

    expect(tab.rightTarget.label, 'b');
    expect(tab.label, 'SFTP: b');
    expect(notifications, 1);
  });
}
