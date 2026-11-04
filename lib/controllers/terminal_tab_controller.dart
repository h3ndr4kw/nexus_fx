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
  List<String> get rightTabLabels => _rightTabs.map((c) => c.currentLabel).toList();

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

  void addTab(SshConnection conn, {bool isRightPane = false}) {
    conn.onClosed = () {
      if (SettingsService.instance.nexusAutoCloseTabOnDisconnect) {
        closeTabForConnection(conn.id);
      }
    };

    if (isRightPane) {
      _rightTabs.add(conn);
      _activeRightTab = _rightTabs.length - 1;
      _isSplitView = true;
      _lastActivePaneIsRight = true;
    } else {
      _tabs.add(conn);
      _activeTab = _tabs.length - 1;
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
