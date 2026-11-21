import 'package:flutter/widgets.dart';

import '../models/file_explorer_models.dart';
import '../services/remote_session.dart';

/// State of one file explorer pane: where it points, what it lists, the
/// filter, the cursor and the multi-selection.
///
/// The cursor, selection and filter operations notify listeners. Fields that
/// a load replaces together ([items], [isLoading], [errorMessage]...) are
/// plain: the view sets them and then calls [applyFilter], which notifies.
class ExplorerPaneController extends ChangeNotifier {
  ExplorerNodeTarget target;
  String currentPath;
  List<FileExplorerItem> items = [];

  /// [items] narrowed by [filterText]; what the pane shows.
  List<FileExplorerItem> filteredItems = [];

  /// Index of the cursor row in [filteredItems], or -1 for none.
  int selectedIndex = 0;

  /// Where a shift-extended selection started.
  int? selectionAnchorIndex;

  /// Paths of the multi-selected items; survives filtering.
  final Set<String> multiSelected = {};

  final ScrollController scrollController = ScrollController();
  bool isLoading = false;
  String? errorMessage;
  String filterText = '';
  final TextEditingController filterInputController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  bool isFiltering = false;
  RemoteSession? remoteSession;

  ExplorerPaneController({
    required this.target,
    required this.currentPath,
  });

  static bool _selectable(FileExplorerItem item) => item.name != '..';

  bool _inRange(int index) => index >= 0 && index < filteredItems.length;

  /// Rebuilds [filteredItems] from [items] and [filterText], keeping the
  /// selection and pulling the cursor back inside the list.
  void applyFilter() {
    final query = filterText.trim().toLowerCase();
    if (query.isEmpty) {
      filteredItems = List.from(items);
    } else {
      filteredItems = items
          .where((item) => item.name.toLowerCase().contains(query) && !item.isParentDir)
          .toList();
    }
    for (final item in filteredItems) {
      item.isSelected = multiSelected.contains(item.path);
    }
    if (filteredItems.isEmpty) {
      selectedIndex = -1;
    } else if (selectedIndex >= filteredItems.length) {
      selectedIndex = filteredItems.length - 1;
    }
    notifyListeners();
  }

  void openFilter() {
    isFiltering = true;
    notifyListeners();
  }

  void closeFilter() {
    isFiltering = false;
    filterText = '';
    filterInputController.clear();
    applyFilter();
  }

  /// Drops the multi-selection, the cursor and the anchor.
  void clearSelection() {
    _unselectAll();
    selectedIndex = -1;
    selectionAnchorIndex = null;
    notifyListeners();
  }

  void _unselectAll() {
    multiSelected.clear();
    for (final item in filteredItems) {
      item.isSelected = false;
    }
  }

  /// Moves the cursor by [delta] rows, clamped to the list, and drops any
  /// multi-selection. With no cursor, moving down starts at the first row
  /// and moving up at the last.
  void moveCursor(int delta) {
    if (filteredItems.isEmpty) return;
    final base = selectedIndex < 0 ? (delta > 0 ? -1 : filteredItems.length) : selectedIndex;
    final newIndex = (base + delta).clamp(0, filteredItems.length - 1);

    selectedIndex = newIndex;
    selectionAnchorIndex = newIndex;
    if (multiSelected.isNotEmpty) _unselectAll();
    notifyListeners();
  }

  /// Moves the cursor by [delta] rows and selects everything between the
  /// anchor and the new cursor position (shift + arrows).
  void moveCursorExtendingSelection(int delta) {
    if (filteredItems.isEmpty) return;
    final anchor = selectionAnchorIndex ?? (selectedIndex < 0 ? 0 : selectedIndex);
    selectionAnchorIndex = anchor;
    final current = selectedIndex < 0 ? anchor : selectedIndex;

    selectedIndex = (current + delta).clamp(0, filteredItems.length - 1);
    _setRange(anchor, selectedIndex);
    notifyListeners();
  }

  /// Selects or unselects the item at [index] and puts the cursor on it.
  void toggleSelect(int index) {
    if (!_inRange(index)) return;
    final item = filteredItems[index];
    if (!_selectable(item)) return;

    _toggle(item);
    selectedIndex = index;
    selectionAnchorIndex = index;
    notifyListeners();
  }

  /// Ctrl-click: like [toggleSelect], but when nothing was selected yet the
  /// item under the cursor joins the selection too, so the first ctrl-click
  /// extends what the user was already pointing at.
  void toggleSelectKeepingCursorItem(int index) {
    if (!_inRange(index)) return;
    final clicked = filteredItems[index];
    if (!_selectable(clicked)) return;

    if (multiSelected.isEmpty && _inRange(selectedIndex) && selectedIndex != index) {
      final previous = filteredItems[selectedIndex];
      if (_selectable(previous)) {
        multiSelected.add(previous.path);
        previous.isSelected = true;
      }
    }
    _toggle(clicked);
    selectedIndex = index;
    selectionAnchorIndex = index;
    notifyListeners();
  }

  void _toggle(FileExplorerItem item) {
    if (multiSelected.remove(item.path)) {
      item.isSelected = false;
    } else {
      multiSelected.add(item.path);
      item.isSelected = true;
    }
  }

  /// Replaces the selection with the rows between [from] and [to], in
  /// either order.
  void selectRange(int from, int to) {
    if (filteredItems.isEmpty) return;
    _setRange(from, to);
    notifyListeners();
  }

  void _setRange(int from, int to) {
    final start = from.clamp(0, filteredItems.length - 1);
    final end = to.clamp(0, filteredItems.length - 1);
    final low = start < end ? start : end;
    final high = start > end ? start : end;

    multiSelected.clear();
    for (var i = 0; i < filteredItems.length; i++) {
      final item = filteredItems[i];
      final selected = _selectable(item) && i >= low && i <= high;
      item.isSelected = selected;
      if (selected) multiSelected.add(item.path);
    }
  }

  /// Selects every item, or clears the selection when all already are.
  void toggleSelectAll() {
    final selectable = filteredItems.where(_selectable);
    final allSelected = selectable.every((i) => multiSelected.contains(i.path));
    for (final item in selectable) {
      if (allSelected) {
        item.isSelected = false;
        multiSelected.remove(item.path);
      } else {
        item.isSelected = true;
        multiSelected.add(item.path);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    scrollController.dispose();
    filterInputController.dispose();
    filterFocusNode.dispose();
    super.dispose();
  }
}
