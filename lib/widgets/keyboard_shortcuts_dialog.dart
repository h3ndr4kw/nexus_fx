import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class ShortcutEntry {
  final String command;
  final List<String> keys;
  final String when;
  final String source;

  const ShortcutEntry({
    required this.command,
    required this.keys,
    required this.when,
    required this.source,
  });
}

class KeyboardShortcutsDialog extends StatefulWidget {
  const KeyboardShortcutsDialog({super.key});

  @override
  State<KeyboardShortcutsDialog> createState() => _KeyboardShortcutsDialogState();
}

class _KeyboardShortcutsDialogState extends State<KeyboardShortcutsDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Offset _dialogOffset = Offset.zero;

  final List<ShortcutEntry> _allShortcuts = const [
    ShortcutEntry(
      command: 'Command Palette',
      keys: ['Ctrl', 'Shift', 'P'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Quick Search Nodes',
      keys: ['Ctrl', 'Space'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Toggle Sidebar',
      keys: ['Ctrl', 'B'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Sidebar: Shrink Left Sidebar',
      keys: ['Alt', 'LeftArrow'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Sidebar: Enlarge Left Sidebar',
      keys: ['Alt', 'RightArrow'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Focus Left Sidebar',
      keys: ['Ctrl', '0'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Sidebar: Select Previous Item',
      keys: ['↑', 'or', 'k'],
      when: 'sidebarFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Sidebar: Select Next Item',
      keys: ['↓', 'or', 'j'],
      when: 'sidebarFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Toggle Command Pane',
      keys: ['Ctrl', 'Shift', 'Space'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Toggle Runbook Sidebar',
      keys: ['Ctrl', 'Shift', 'B'],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Nexus: Enlarge Right Sidebar',
      keys: ['Alt', 'Shift', 'LeftArrow', 'or', 'h'],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Nexus: Shrink Right Sidebar',
      keys: ['Alt', 'Shift', 'RightArrow', 'or', 'l'],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Nexus: Reset Right Sidebar Width',
      keys: ['Alt', '='],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Nexus: Close Active SSH Tab',
      keys: ['Ctrl', 'W'],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Nexus: Next SSH Tab',
      keys: ['Ctrl', 'Tab', 'or', 'Ctrl', 'T'],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Nexus: Previous SSH Tab',
      keys: ['Ctrl', 'Shift', 'Tab', 'or', 'Ctrl', 'Shift', 'T'],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Nexus: Switch to SSH Tab 1-9',
      keys: ['Alt', '1-9'],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook: Focus Sidebar',
      keys: ['Alt', 'L'],
      when: 'nexusTabActive',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook: Focus Terminal',
      keys: ['Alt', 'H'],
      when: 'runbookSidebarFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook: Next Sidebar Tab',
      keys: ['Ctrl', 'Tab'],
      when: 'runbookSidebarFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook: Previous Sidebar Tab',
      keys: ['Ctrl', 'Shift', 'Tab'],
      when: 'runbookSidebarFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook: Close Active Tab',
      keys: ['Ctrl', 'W', 'or', ':', 'q'],
      when: 'runbookSidebarFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Files: Navigate Up/Down',
      keys: ['j', '/', 'k', 'or', '↓', '/', '↑'],
      when: 'runbookFilesFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Files: Expand/Open File',
      keys: ['l', 'or', 'Enter'],
      when: 'runbookFilesFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Files: Collapse/Parent',
      keys: ['h', 'or', '←'],
      when: 'runbookFilesFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Cell: Execute Script',
      keys: ['Ctrl', 'Enter', 'or', 'Shift', 'Enter'],
      when: 'runbookCellFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Add Script Cell Above',
      keys: ['a', 'or', 'Ctrl', 'Alt', 'A'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Add Script Cell Below',
      keys: ['b', 'or', 'Ctrl', 'Alt', 'B'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Add Text Box Above',
      keys: ['Shift', 'A', 'or', 'Ctrl', 'Alt', 'Shift', 'A'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Add Text Box Below',
      keys: ['Shift', 'B', 'or', 'Ctrl', 'Alt', 'Shift', 'B'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Navigate Cells',
      keys: ['j', '/', 'k', 'or', '↓', '/', '↑'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Edit Selected Cell',
      keys: ['Enter'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Exit Edit Mode',
      keys: ['Escape'],
      when: 'runbookCellFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Delete Selected Cell',
      keys: ['d', 'or', 'Ctrl', 'Alt', 'D'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Yank (Copy) Block',
      keys: ['y'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Paste Block Below',
      keys: ['p'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Paste Block Above',
      keys: ['Shift', 'P'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Undo Delete Block',
      keys: ['u', 'or', 'Ctrl', 'Z'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Duplicate Block',
      keys: ['Ctrl', 'D'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Move Block Up',
      keys: ['Alt', '↑', 'or', 'Shift', 'K'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Move Block Down',
      keys: ['Alt', '↓', 'or', 'Shift', 'J'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Jump to First Block',
      keys: ['g', 'g'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Jump to Last Block',
      keys: ['Shift', 'G'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Save Document',
      keys: ['Ctrl', 'S', 'or', ':', 'w'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Save to New File',
      keys: [':', 'w', ' ', '<filename>'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Runbook Doc: Close Document',
      keys: ['Ctrl', 'W', 'or', ':', 'q'],
      when: 'runbookDocFocused',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Toggle Full Screen',
      keys: ['F11'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Exit Application',
      keys: ['Ctrl', 'Q'],
      when: 'global',
      source: 'Smart-E HE',
    ),
    ShortcutEntry(
      command: 'Accept Inline Completion',
      keys: ['Ctrl', '/'],
      when: "accessibleViewIsShown && accessibleViewCurrentProviderId == 'inlineCompl...",
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Accept Inline Suggestion',
      keys: ['Tab'],
      when: 'inlineEditIsVisible && tabShouldAcceptInlineEdit && !editorHoverFocused...',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Accept Inline Suggestion Alternative Action',
      keys: ['Shift', 'Tab'],
      when: 'inlineEditsPreviewEditor',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Accept Next Word of Inline Suggestion',
      keys: ['Ctrl', 'RightArrow'],
      when: 'cursorBeforeGhostText && inlineSuggestionVisible && !accessibilityModeEn...',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Accessible Diff Viewer: Go to Next Difference',
      keys: ['F7'],
      when: 'isInDiffEditor',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Accessible Diff Viewer: Go to Previous Difference',
      keys: ['Shift', 'F7'],
      when: 'isInDiffEditor',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Add Cursor Above',
      keys: ['Ctrl', 'Alt', 'UpArrow'],
      when: 'editorTextFocus',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Add Cursor Below',
      keys: ['Ctrl', 'Alt', 'DownArrow'],
      when: 'editorTextFocus',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Add Cursors to Line Ends',
      keys: ['Shift', 'Alt', 'I'],
      when: 'editorTextFocus',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Add Line Comment',
      keys: ['Ctrl', 'K', 'Ctrl', 'C'],
      when: 'editorTextFocus && !editorReadonly',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Add Selection to Next Find Match',
      keys: ['Ctrl', 'D'],
      when: 'editorFocus',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Announce Cursor Position',
      keys: ['Ctrl', 'Shift', 'Alt', 'G'],
      when: 'accessibilityModeEnabled && editorTextFocus',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Antigravity: Add Selection to Chat',
      keys: ['Ctrl', 'L'],
      when: 'editorTextFocus',
      source: 'Google Antigravity',
    ),
    ShortcutEntry(
      command: 'Antigravity: Add Terminal Selection or Output to Chat',
      keys: ['Ctrl', 'L'],
      when: 'false',
      source: 'Google Antigravity',
    ),
    ShortcutEntry(
      command: 'Auto Fix...',
      keys: ['Shift', 'Alt', '.'],
      when: 'textInputFocus && !editorReadonly && supportedCodeAction =~ /(^\\s|^)quick...',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Add Element to Chat',
      keys: ['Ctrl', 'Shift', 'C'],
      when: 'browserHasUrl && chatIsEnabled && !browserHasError && activeEditor == \'w...',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Add to Favorites',
      keys: ['Ctrl', 'D'],
      when: 'browserHasUrl && activeEditor == \'workbench.editor.browser\'',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Comment on Elements',
      keys: ['Ctrl', 'Alt', 'C'],
      when: 'browserHasUrl && chatIsEnabled && !browserHasError && activeEditor == \'w...',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Developer Tools',
      keys: ['F12'],
      when: 'browserHasUrl && !browserHasError && activeEditor == \'workbench.editor.b...',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Find in Page',
      keys: ['Ctrl', 'F'],
      when: 'browserHasUrl && !browserHasError && activeEditor == \'workbench.editor.b...',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Focus URL Input',
      keys: ['Ctrl', 'L'],
      when: 'activeEditor == \'workbench.editor.browser\'',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Go Back',
      keys: ['BrowserBack'],
      when: 'browserCanGoBack && activeEditor == \'workbench.editor.browser\'',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Go Back',
      keys: ['Alt', 'LeftArrow'],
      when: 'browserCanGoBack && activeEditor == \'workbench.editor.browser\'',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Go Forward',
      keys: ['BrowserForward'],
      when: 'browserCanGoForward && activeEditor == \'workbench.editor.browser\'',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Go Forward',
      keys: ['Alt', 'RightArrow'],
      when: 'browserCanGoForward && activeEditor == \'workbench.editor.browser\'',
      source: 'System',
    ),
    ShortcutEntry(
      command: 'Browser: Hard Reload',
      keys: ['Ctrl', 'F5'],
      when: 'browserFocused && activeEditor == \'workbench.editor.browser\'',
      source: 'System',
    ),
    // File Explorer & Terminal specific shortcuts
    ShortcutEntry(
      command: 'File Explorer: Help / Shortcuts',
      keys: ['F1'],
      when: 'fileExplorerFocus',
      source: 'File Explorer',
    ),
    ShortcutEntry(
      command: 'File Explorer: Switch Active Pane',
      keys: ['Tab'],
      when: 'fileExplorerFocus',
      source: 'File Explorer',
    ),
    ShortcutEntry(
      command: 'File Explorer: Select / Unselect Item',
      keys: ['Space'],
      when: 'fileExplorerFocus',
      source: 'File Explorer',
    ),
    ShortcutEntry(
      command: 'File Explorer: Copy Selected Files',
      keys: ['C'],
      when: 'fileExplorerFocus',
      source: 'File Explorer',
    ),
    ShortcutEntry(
      command: 'File Explorer: Move Selected Files',
      keys: ['M'],
      when: 'fileExplorerFocus',
      source: 'File Explorer',
    ),
    ShortcutEntry(
      command: 'File Explorer: Delete Item',
      keys: ['Del'],
      when: 'fileExplorerFocus',
      source: 'File Explorer',
    ),
    ShortcutEntry(
      command: 'File Explorer: Refresh Directory',
      keys: ['R'],
      when: 'fileExplorerFocus',
      source: 'File Explorer',
    ),
    ShortcutEntry(
      command: 'Terminal: Copy Selection',
      keys: ['Ctrl', 'Shift', 'C'],
      when: 'terminalFocus',
      source: 'Nexus Terminal',
    ),
    ShortcutEntry(
      command: 'Terminal: Paste Clipboard',
      keys: ['Ctrl', 'Shift', 'V'],
      when: 'terminalFocus',
      source: 'Nexus Terminal',
    ),
    ShortcutEntry(
      command: 'Terminal: Zoom In',
      keys: ['Ctrl', 'Shift', '+ / Scroll Up'],
      when: 'terminalFocus',
      source: 'Nexus Terminal',
    ),
    ShortcutEntry(
      command: 'Terminal: Zoom Out',
      keys: ['Ctrl', 'Shift', '- / Scroll Down'],
      when: 'terminalFocus',
      source: 'Nexus Terminal',
    ),
    ShortcutEntry(
      command: 'Terminal: Reset Zoom',
      keys: ['Ctrl', 'Shift', '0'],
      when: 'terminalFocus',
      source: 'Nexus Terminal',
    ),
    // Interactive Runbook & Notebook shortcuts
    ShortcutEntry(
      command: 'Runbook: Save Document',
      keys: ['Ctrl', 'S'],
      when: 'runbookDocumentOpen',
      source: 'Runbook Sidebar',
    ),
    ShortcutEntry(
      command: 'Runbook: Find in Document',
      keys: ['Ctrl', 'F'],
      when: 'runbookDocumentOpen',
      source: 'Runbook Sidebar',
    ),
    ShortcutEntry(
      command: 'Runbook: Open Selected File',
      keys: ['Enter'],
      when: 'runbookFilesFocus',
      source: 'Runbook Sidebar',
    ),
    ShortcutEntry(
      command: 'Runbook: Rename File / Folder',
      keys: ['F2'],
      when: 'runbookFilesFocus',
      source: 'Runbook Sidebar',
    ),
    ShortcutEntry(
      command: 'Runbook: Delete File / Folder',
      keys: ['Del'],
      when: 'runbookFilesFocus',
      source: 'Runbook Sidebar',
    ),
    ShortcutEntry(
      command: 'Runbook: Cut Selection',
      keys: ['Ctrl', 'X'],
      when: 'runbookFilesFocus',
      source: 'Runbook Sidebar',
    ),
    ShortcutEntry(
      command: 'Runbook: Copy Selection',
      keys: ['Ctrl', 'C'],
      when: 'runbookFilesFocus',
      source: 'Runbook Sidebar',
    ),
    ShortcutEntry(
      command: 'Runbook: Paste Selection',
      keys: ['Ctrl', 'V'],
      when: 'runbookFilesFocus',
      source: 'Runbook Sidebar',
    ),
  ];

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<ShortcutEntry> get _filteredShortcuts {
    if (_searchQuery.trim().isEmpty) {
      return _allShortcuts;
    }
    final query = _searchQuery.toLowerCase();
    return _allShortcuts.where((item) {
      final matchCommand = item.command.toLowerCase().contains(query);
      final matchKeys = item.keys.any((k) => k.toLowerCase().contains(query));
      final matchWhen = item.when.toLowerCase().contains(query);
      final matchSource = item.source.toLowerCase().contains(query);
      return matchCommand || matchKeys || matchWhen || matchSource;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.activePalette;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Transform.translate(
          offset: _dialogOffset,
          child: Container(
            width: 1080,
            height: 640,
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: palette.inputBorderColor,
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header bar
                MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) {
                      setState(() {
                        _dialogOffset += details.delta;
                      });
                    },
                    onDoubleTap: () {
                      setState(() {
                        _dialogOffset = Offset.zero;
                      });
                    },
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF2B2B2B), width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.keyboard_outlined,
                            size: 18,
                            color: Color(0xFFCCCCCC),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Keyboard Shortcuts',
                            style: TextStyle(
                              color: Color(0xFFCCCCCC),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Courier',
                            ),
                          ),
                          const Spacer(),
                          // Top right icons
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Color(0xFF888888)),
                                tooltip: 'Close',
                                onPressed: () => Navigator.of(context).pop(),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Search bar row
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF252526),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: palette.inputBorderColor,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.search,
                              size: 16,
                              color: Color(0xFF858585),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontFamily: 'Courier',
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Type to search in keybindings',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF858585),
                                    fontSize: 12,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _searchQuery = val;
                                  });
                                },
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 14, color: Color(0xFF858585)),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Keyboard icon action
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF252526),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: palette.inputBorderColor, width: 1),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.keyboard, size: 16, color: Color(0xFF858585)),
                          SizedBox(width: 6),
                          Icon(Icons.filter_list, size: 16, color: Color(0xFF858585)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Table header
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF2D2D2D), width: 1),
                  ),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        'Command',
                        style: TextStyle(
                          color: Color(0xFFCCCCCC),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Keybinding',
                        style: TextStyle(
                          color: Color(0xFFCCCCCC),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        'When',
                        style: TextStyle(
                          color: Color(0xFFCCCCCC),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Source',
                        style: TextStyle(
                          color: Color(0xFFCCCCCC),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Table content list
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredShortcuts.length,
                  itemBuilder: (context, index) {
                    final item = _filteredShortcuts[index];
                    final isAntigravity = item.source == 'Google Antigravity';
                    final isSmartE = item.source == 'Smart-E HE';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                      decoration: BoxDecoration(
                        color: index.isEven ? const Color(0xFF181818) : const Color(0xFF1C1C1C),
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFF222222), width: 0.8),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Command
                          Expanded(
                            flex: 4,
                            child: Text(
                              item.command,
                              style: const TextStyle(
                                color: Color(0xFFCCCCCC),
                                fontSize: 12,
                                fontFamily: 'Courier',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // Keybinding
                          Expanded(
                            flex: 3,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const ClampingScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (int i = 0; i < item.keys.length; i++) ...[
                                    _buildKeyCap(item.keys[i]),
                                    if (i < item.keys.length - 1)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 3),
                                        child: Text(
                                          '+',
                                          style: TextStyle(
                                            color: Color(0xFF888888),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          // When
                          Expanded(
                            flex: 5,
                            child: Text(
                              item.when,
                              style: const TextStyle(
                                color: Color(0xFF7A7A7A),
                                fontSize: 11,
                                fontFamily: 'Courier',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),

                          // Source
                          Expanded(
                            flex: 2,
                            child: Text(
                              item.source,
                              style: TextStyle(
                                color: isAntigravity
                                    ? const Color(0xFF4FC1FF)
                                    : isSmartE
                                        ? const Color(0xFF98C379)
                                        : const Color(0xFF888888),
                                fontSize: 11,
                                fontFamily: 'Courier',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildKeyCap(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: const Color(0xFF3C3C3C),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFCCCCCC),
          fontSize: 11,
          fontFamily: 'Courier',
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
