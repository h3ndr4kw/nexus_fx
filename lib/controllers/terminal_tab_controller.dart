import 'package:flutter/foundation.dart';
import '../services/settings_service.dart';
import '../services/ssh_service.dart';

/// Controller managing multi-tab terminal workspaces and split-screen state.
class TerminalTabController extends ChangeNotifier {
  final List<SshConnection> _tabs = [];
  final List<SshConnection> _rightTabs = [];
  int _activeTab = 0;
  int _activeRightTab = 0;
  bool _isSplitView = false;
  bool _lastActivePaneIsRight = false;

  void Function(SshConnection connection)? onTabAdded;
  void Function(SshConnection connection)? onTabRemoved;

  List<SshConnection> get tabs => _tabs;
  List<SshConnection> get rightTabs => _rightTabs;
  int get activeTab => _activeTab;
  int get activeRightTab => _activeRightTab;
  bool get isSplitView => _isSplitView;
  bool get lastActivePaneIsRight => _lastActivePaneIsRight;

  List<String> get tabLabels => _tabs.map((c) => c.currentLabel).toList();
  List<String> get rightTabLabels =>
      _rightTabs.map((c) => c.currentLabel).toList();

  int get leftConnectedCount => _tabs.where((c) => c.isConnected).length;
  int get rightConnectedCount => _rightTabs.where((c) => c.isConnected).length;

  SshConnection? get activeConnection {
    if (_lastActivePaneIsRight) {
      if (_rightTabs.isNotEmpty && _activeRightTab < _rightTabs.length) {
        return _rightTabs[_activeRightTab];
      }
    }
    if (_tabs.isNotEmpty && _activeTab < _tabs.length) {
      return _tabs[_activeTab];
    }
    return null;
  }

  /// Label for a duplicate of a tab labelled [sourceLabel]: `<base> #N` with
  /// the lowest free N >= 2. The undecorated base counts as #1.
  static String nextDuplicateLabel(
    String sourceLabel,
    Iterable<String> existingLabels,
  ) {
    final base = sourceLabel.replaceFirst(_duplicateSuffix, '');
    final used = <int>{
      for (final label in existingLabels) ?_duplicateNumber(base, label),
    };
    var n = 2;
    while (used.contains(n)) {
      n++;
    }
    return '$base #$n';
  }

  /// Where a duplicate labelled [newLabel] goes in a pane showing
  /// [paneLabels]: after the last tab of its group with a lower number, so
  /// `<base>, #2, #3, ...` stay in order. [fallback] is used when the pane
  /// has no such tab.
  static int duplicateInsertIndex(
    List<String> paneLabels,
    String newLabel,
    int fallback,
  ) {
    final base = newLabel.replaceFirst(_duplicateSuffix, '');
    final n = _duplicateNumber(base, newLabel)!;
    for (var i = paneLabels.length - 1; i >= 0; i--) {
      final m = _duplicateNumber(base, paneLabels[i]);
      if (m != null && m < n) return i + 1;
    }
    return fallback;
  }

  /// 1 for [base] itself, N for `<base> #N`, null for any other label.
  static int? _duplicateNumber(String base, String label) {
    if (label == base) return 1;
    final match = _duplicateSuffix.firstMatch(label);
    if (match != null && label.substring(0, match.start) == base) {
      return int.parse(match.group(1)!);
    }
    return null;
  }

  static final RegExp _duplicateSuffix = RegExp(r' #(\d+)$');

  /// Moves the tab [connectionId] to slot [toIndex] of the left or right
  /// pane and activates it. [toIndex] is a gap between tabs as the
  /// destination pane looks before the move (0 = before the first tab).
  void moveTab(
    String connectionId, {
    required bool toRightPane,
    required int toIndex,
  }) {
    final fromRight = _rightTabs.any((c) => c.id == connectionId);
    final source = fromRight ? _rightTabs : _tabs;
    final fromIndex = source.indexWhere((c) => c.id == connectionId);
    if (fromIndex == -1) return;
    final dest = toRightPane ? _rightTabs : _tabs;

    var target = toIndex.clamp(0, dest.length);
    if (identical(source, dest) && fromIndex < target) target--;
    if (identical(source, dest) && target == fromIndex) {
      _activate(toRightPane, fromIndex);
      notifyListeners();
      return;
    }

    final activeSourceConn = _activeIn(fromRight);
    final conn = source.removeAt(fromIndex);
    dest.insert(target, conn);

    // Keep the other pane's active tab on the same connection.
    if (!identical(source, dest) &&
        activeSourceConn != null &&
        activeSourceConn.id != conn.id) {
      final kept = source.indexWhere((c) => c.id == activeSourceConn.id);
      if (fromRight) {
        _activeRightTab = kept;
      } else {
        _activeTab = kept;
      }
    } else if (!identical(source, dest)) {
      final clamped = source.isEmpty
          ? 0
          : fromIndex.clamp(0, source.length - 1);
      if (fromRight) {
        _activeRightTab = clamped;
      } else {
        _activeTab = clamped;
      }
    }

    _activate(toRightPane, target);
    if (_rightTabs.isEmpty) {
      _isSplitView = false;
      _lastActivePaneIsRight = false;
    } else if (toRightPane) {
      _isSplitView = true;
    }
    notifyListeners();
  }

  SshConnection? _activeIn(bool rightPane) {
    final list = rightPane ? _rightTabs : _tabs;
    final index = rightPane ? _activeRightTab : _activeTab;
    return index >= 0 && index < list.length ? list[index] : null;
  }

  void _activate(bool rightPane, int index) {
    if (rightPane) {
      _activeRightTab = index;
    } else {
      _activeTab = index;
    }
    _lastActivePaneIsRight = rightPane;
  }

  /// Appends [conn] to its pane, or inserts it at [insertIndex], and makes it
  /// the active tab.
  void addTab(
    SshConnection conn, {
    bool isRightPane = false,
    int? insertIndex,
  }) {
    conn.onClosed = () {
      if (SettingsService.instance.nexusAutoCloseTabOnDisconnect) {
        closeTabForConnection(conn.id);
      }
    };

    final list = isRightPane ? _rightTabs : _tabs;
    final index = (insertIndex ?? list.length).clamp(0, list.length);
    list.insert(index, conn);
    if (isRightPane) {
      _activeRightTab = index;
      _isSplitView = true;
      _lastActivePaneIsRight = true;
    } else {
      _activeTab = index;
      _lastActivePaneIsRight = false;
    }

    onTabAdded?.call(conn);
    notifyListeners();
  }

  void addTabToRight(SshConnection conn) => addTab(conn, isRightPane: true);

  void setActiveTab(int index) {
    if (_tabs.isEmpty) {
      _activeTab = 0;
      return;
    }
    final clamped = index.clamp(0, _tabs.length - 1);
    if (_activeTab != clamped || _lastActivePaneIsRight) {
      _activeTab = clamped;
      _lastActivePaneIsRight = false;
      notifyListeners();
    }
  }

  void setActiveRightTab(int index) {
    if (_rightTabs.isEmpty) {
      _activeRightTab = 0;
      return;
    }
    final clamped = index.clamp(0, _rightTabs.length - 1);
    if (_activeRightTab != clamped || !_lastActivePaneIsRight) {
      _activeRightTab = clamped;
      _lastActivePaneIsRight = true;
      notifyListeners();
    }
  }

  void setLastActivePaneIsRight(bool isRight) {
    if (_lastActivePaneIsRight != isRight) {
      _lastActivePaneIsRight = isRight;
      notifyListeners();
    }
  }

  void setSplitView(bool value) {
    if (_isSplitView != value) {
      _isSplitView = value;
      notifyListeners();
    }
  }

  void toggleSplitView() {
    _isSplitView = !_isSplitView;
    notifyListeners();
  }

  void closeTabAt(int index, {bool isRightPane = false}) {
    final list = isRightPane ? _rightTabs : _tabs;
    if (index < 0 || index >= list.length) return;

    final conn = list.removeAt(index);
    conn.disconnect();
    onTabRemoved?.call(conn);

    if (isRightPane) {
      if (_activeRightTab >= _rightTabs.length) {
        _activeRightTab = (_rightTabs.length - 1).clamp(0, _rightTabs.length);
      }
      if (_rightTabs.isEmpty) {
        _isSplitView = false;
        _lastActivePaneIsRight = false;
      }
    } else {
      if (_activeTab >= _tabs.length) {
        _activeTab = (_tabs.length - 1).clamp(0, _tabs.length);
      }
    }

    notifyListeners();
  }

  void closeTabForConnection(String id) {
    final leftIdx = _tabs.indexWhere((c) => c.id == id);
    if (leftIdx != -1) {
      closeTabAt(leftIdx, isRightPane: false);
      return;
    }

    final rightIdx = _rightTabs.indexWhere((c) => c.id == id);
    if (rightIdx != -1) {
      closeTabAt(rightIdx, isRightPane: true);
    }
  }

  void moveTabBetweenPanes(int fromIndex, {required bool fromRightPane}) {
    final sourceList = fromRightPane ? _rightTabs : _tabs;
    final destList = fromRightPane ? _tabs : _rightTabs;

    if (fromIndex < 0 || fromIndex >= sourceList.length) return;

    final conn = sourceList.removeAt(fromIndex);
    destList.add(conn);

    if (fromRightPane) {
      _activeTab = destList.length - 1;
      _lastActivePaneIsRight = false;
      if (_activeRightTab >= _rightTabs.length) {
        _activeRightTab = (_rightTabs.length - 1).clamp(0, _rightTabs.length);
      }
      if (_rightTabs.isEmpty) {
        _isSplitView = false;
      }
    } else {
      _activeRightTab = destList.length - 1;
      _isSplitView = true;
      _lastActivePaneIsRight = true;
      if (_activeTab >= _tabs.length) {
        _activeTab = (_tabs.length - 1).clamp(0, _tabs.length);
      }
    }

    notifyListeners();
  }

  void closeAllTabs() {
    for (final conn in [..._tabs, ..._rightTabs]) {
      conn.disconnect();
      onTabRemoved?.call(conn);
    }
    _tabs.clear();
    _rightTabs.clear();
    _activeTab = 0;
    _activeRightTab = 0;
    _isSplitView = false;
    _lastActivePaneIsRight = false;
    notifyListeners();
  }
}
