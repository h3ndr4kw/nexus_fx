import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/controllers/explorer_pane_controller.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';

FileExplorerItem _item(String name, {bool isDir = false}) => FileExplorerItem(
      name: name,
      path: '/home/$name',
      isDir: isDir,
      size: 1,
      modified: '',
    );

void main() {
  late ExplorerPaneController pane;
  late int notifications;

  /// A pane showing `..`, a, b, c, d (indexes 0..4).
  setUp(() {
    pane = ExplorerPaneController(target: ExplorerNodeTarget.local, currentPath: '/home')
      ..items = [
        _item('..', isDir: true),
        _item('a'),
        _item('b'),
        _item('c'),
        _item('d'),
      ];
    pane.applyFilter();
    notifications = 0;
    pane.addListener(() => notifications++);
  });

  tearDown(() => pane.dispose());

  List<String> selectedNames() =>
      pane.filteredItems.where((i) => i.isSelected).map((i) => i.name).toList();

  group('filter', () {
    test('an empty filter shows every item', () {
      expect(pane.filteredItems.map((i) => i.name), ['..', 'a', 'b', 'c', 'd']);
    });

    test('matches names case-insensitively and hides the parent entry', () {
      pane.items = [_item('..', isDir: true), _item('Report.txt'), _item('notes.md')];
      pane.filterText = 'REP';

      pane.applyFilter();

      expect(pane.filteredItems.map((i) => i.name), ['Report.txt']);
      expect(notifications, 1);
    });

    test('pulls the cursor back when the list gets shorter', () {
      pane.selectedIndex = 4;
      pane.filterText = 'a';

      pane.applyFilter();

      expect(pane.selectedIndex, 0);
    });

    test('leaves no cursor when nothing matches', () {
      pane.filterText = 'zzz';

      pane.applyFilter();

      expect(pane.filteredItems, isEmpty);
      expect(pane.selectedIndex, -1);
    });

    test('a selected item is still selected after filtering', () {
      pane.toggleSelect(2);
      pane.filterText = 'b';

      pane.applyFilter();

      expect(selectedNames(), ['b']);
    });

    test('closing the filter clears the text and restores the list', () {
      pane.openFilter();
      pane.filterText = 'a';
      pane.filterInputController.text = 'a';
      pane.applyFilter();

      pane.closeFilter();

      expect(pane.isFiltering, isFalse);
      expect(pane.filterText, isEmpty);
      expect(pane.filterInputController.text, isEmpty);
      expect(pane.filteredItems, hasLength(5));
    });
  });

  group('cursor', () {
    test('moves by the delta and stops at the ends', () {
      pane.moveCursor(2);
      expect(pane.selectedIndex, 2);

      pane.moveCursor(100);
      expect(pane.selectedIndex, 4);

      pane.moveCursor(-100);
      expect(pane.selectedIndex, 0);
      expect(notifications, 3);
    });

    test('with no cursor, down starts at the first row and up at the last', () {
      pane.selectedIndex = -1;
      pane.moveCursor(1);
      expect(pane.selectedIndex, 0);

      pane.selectedIndex = -1;
      pane.moveCursor(-1);
      expect(pane.selectedIndex, 4);
    });

    test('a plain move drops the multi-selection', () {
      pane.toggleSelect(1);
      pane.toggleSelect(2);

      pane.moveCursor(1);

      expect(pane.multiSelected, isEmpty);
      expect(selectedNames(), isEmpty);
    });

    test('does nothing in an empty pane', () {
      pane.items = [];
      pane.applyFilter();
      notifications = 0;

      pane.moveCursor(1);
      pane.moveCursorExtendingSelection(1);

      expect(pane.selectedIndex, -1);
      expect(notifications, 0);
    });

    test('shift-move selects from the anchor to the cursor', () {
      pane.moveCursor(1); // cursor and anchor on "a"

      pane.moveCursorExtendingSelection(1);
      pane.moveCursorExtendingSelection(1);

      expect(selectedNames(), ['a', 'b', 'c']);
      expect(pane.selectedIndex, 3);
    });

    test('shift-move back past the anchor selects the other direction', () {
      pane.moveCursor(3); // anchor on "c"

      pane.moveCursorExtendingSelection(-2);

      expect(selectedNames(), ['a', 'b', 'c']);
      expect(pane.selectedIndex, 1);
    });
  });

  group('selection', () {
    test('toggle selects an item, then unselects it, and moves the cursor there', () {
      pane.toggleSelect(2);
      expect(pane.multiSelected, {'/home/b'});
      expect(pane.selectedIndex, 2);

      pane.toggleSelect(2);
      expect(pane.multiSelected, isEmpty);
      expect(selectedNames(), isEmpty);
    });

    test('the parent entry cannot be selected', () {
      pane.toggleSelect(0);
      pane.toggleSelectKeepingCursorItem(0);

      expect(pane.multiSelected, isEmpty);
      expect(notifications, 0);
    });

    test('an out-of-range index is ignored', () {
      pane.toggleSelect(99);
      pane.toggleSelect(-1);

      expect(pane.multiSelected, isEmpty);
    });

    test('ctrl-click also keeps the item the cursor was on', () {
      pane.moveCursor(1); // cursor on "a", nothing selected

      pane.toggleSelectKeepingCursorItem(3);

      expect(selectedNames(), ['a', 'c']);
      expect(pane.selectedIndex, 3);
    });

    test('ctrl-click on a selected item unselects only that item', () {
      pane.selectRange(1, 3);

      pane.toggleSelectKeepingCursorItem(2);

      expect(selectedNames(), ['a', 'c']);
    });

    test('a range replaces the selection and skips the parent entry', () {
      pane.toggleSelect(4);

      pane.selectRange(2, 0);

      expect(selectedNames(), ['a', 'b']);
      expect(pane.multiSelected, {'/home/a', '/home/b'});
    });

    test('select all selects everything but the parent entry, then clears', () {
      pane.toggleSelectAll();
      expect(selectedNames(), ['a', 'b', 'c', 'd']);

      pane.toggleSelectAll();
      expect(selectedNames(), isEmpty);
      expect(pane.multiSelected, isEmpty);
    });

    test('select all completes a partial selection', () {
      pane.toggleSelect(1);

      pane.toggleSelectAll();

      expect(selectedNames(), ['a', 'b', 'c', 'd']);
    });

    test('clearing the selection also removes the cursor and anchor', () {
      pane.selectRange(1, 2);
      pane.selectedIndex = 2;
      pane.selectionAnchorIndex = 1;

      pane.clearSelection();

      expect(pane.multiSelected, isEmpty);
      expect(selectedNames(), isEmpty);
      expect(pane.selectedIndex, -1);
      expect(pane.selectionAnchorIndex, isNull);
    });
  });
}
