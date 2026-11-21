import 'package:flutter/widgets.dart';

import '../models/file_explorer_models.dart';

/// One file explorer tab: a pair of panes and the keyboard focus for them.
class FileExplorerTab {
  final String id;
  String label;
  ExplorerNodeTarget leftTarget;
  ExplorerNodeTarget rightTarget;
  final PaneSide initialActivePane;
  final FocusNode focusNode = FocusNode();

  FileExplorerTab({
    required this.id,
    required this.label,
    required this.leftTarget,
    required this.rightTarget,
    required this.initialActivePane,
  });

  void dispose() {
    focusNode.dispose();
  }
}

/// The open file explorer tabs and which one is active.
///
/// There is always at least one tab: closing the last one replaces it with
/// a fresh local tab.
class FileExplorerTabsController extends ChangeNotifier {
  FileExplorerTabsController() {
    _tabs.add(_newLocalTab());
  }

  final List<FileExplorerTab> _tabs = [];
  int _nextId = 1;
  int _activeIndex = 0;

  List<FileExplorerTab> get tabs => List.unmodifiable(_tabs);
  int get length => _tabs.length;
  int get activeIndex => _activeIndex;
  FileExplorerTab get activeTab => _tabs[_activeIndex];

  static String labelFor(ExplorerNodeTarget target) =>
      target.isLocal ? 'Local Explorer' : 'SFTP: ${target.label}';

  FileExplorerTab _newTab(ExplorerNodeTarget right) => FileExplorerTab(
        id: 'fe_tab_${_nextId++}',
        label: labelFor(right),
        leftTarget: ExplorerNodeTarget.local,
        rightTarget: right,
        initialActivePane: right.isLocal ? PaneSide.left : PaneSide.right,
      );

  FileExplorerTab _newLocalTab() => _newTab(ExplorerNodeTarget.local);

  /// Opens a tab with the local disk on the left and [target] on the right,
  /// and makes it active.
  FileExplorerTab open(ExplorerNodeTarget target) {
    final tab = _newTab(target);
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    return tab;
  }

  void activate(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Moves to the next ([delta] 1) or previous (-1) tab, wrapping around.
  void switchBy(int delta) {
    if (_tabs.length <= 1) return;
    _activeIndex = (_activeIndex + delta) % _tabs.length;
    if (_activeIndex < 0) _activeIndex += _tabs.length;
    notifyListeners();
  }

  /// Points [tab]'s right pane at [right] and relabels the tab to match.
  void retarget(FileExplorerTab tab, {required ExplorerNodeTarget right}) {
    tab.rightTarget = right;
    tab.label = labelFor(right);
    notifyListeners();
  }

  void close(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final removed = _tabs[index];
    if (_tabs.length <= 1) {
      _tabs
        ..clear()
        ..add(_newLocalTab());
      _activeIndex = 0;
    } else {
      _tabs.removeAt(index);
      if (_activeIndex >= _tabs.length) {
        _activeIndex = _tabs.length - 1;
      } else if (_activeIndex > index) {
        _activeIndex--;
      }
    }
    notifyListeners();
    removed.dispose();
  }

  void closeOthers(FileExplorerTab keep) {
    final removed = _tabs.where((t) => t.id != keep.id).toList();
    _tabs.removeWhere((t) => t.id != keep.id);
    _activeIndex = 0;
    notifyListeners();
    for (final tab in removed) {
      tab.dispose();
    }
  }

  void closeAll() {
    final removed = List<FileExplorerTab>.of(_tabs);
    _tabs
      ..clear()
      ..add(_newLocalTab());
    _activeIndex = 0;
    notifyListeners();
    for (final tab in removed) {
      tab.dispose();
    }
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }
}
