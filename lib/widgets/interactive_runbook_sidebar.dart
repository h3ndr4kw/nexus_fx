import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nexus_fx/models/playbook_models.dart';
import 'package:nexus_fx/services/playbook_parser.dart';
import 'package:nexus_fx/services/settings_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/script_cell_widget.dart';

part 'interactive_runbook_sidebar_files.dart';
part 'interactive_runbook_sidebar_document.dart';
part 'interactive_runbook_sidebar_view.dart';
part 'interactive_runbook_sidebar_blocks.dart';
part 'interactive_runbook_sidebar_buttons.dart';

class _OpenRunbookTab {
  final String filePath;
  final String fileName;
  final PlaybookDocument? document;
  final String? errorMessage;
  bool showSavedFeedback = false;

  _OpenRunbookTab({
    required this.filePath,
    required this.fileName,
    this.document,
    this.errorMessage,
  });
}

class _FileTreeNode {
  final FileSystemEntity entity;
  final String path;
  final String name;
  final int depth;
  final bool isDirectory;
  final bool isExpanded;

  const _FileTreeNode({
    required this.entity,
    required this.path,
    required this.name,
    required this.depth,
    required this.isDirectory,
    this.isExpanded = false,
  });
}

class _SearchMatchLocation {
  final int blockIndex;
  final int matchIndexInBlock;

  const _SearchMatchLocation({
    required this.blockIndex,
    required this.matchIndexInBlock,
  });
}

/// Interactive Runbook & Playbook right sidebar with left-edge resize handle,
/// tab bar (permanent Files tab + opened documents), hierarchical file explorer
/// with New File / New Folder / Refresh / Collapse All actions, and
/// interactive notebook-style document renderer with Find, Edit & Save, and Scrollbar.
class InteractiveRunbookSidebar extends StatefulWidget {
  final VoidCallback onClose;
  final List<String> activeConnections;
  final String syncedCommandPaneTarget;
  final Future<void> Function(String targetNode, List<String> lines)
  onExecuteScript;
  final String defaultDirectoryPath;
  final VoidCallback? onFocusNexusTerminal;

  const InteractiveRunbookSidebar({
    super.key,
    required this.onClose,
    required this.activeConnections,
    required this.syncedCommandPaneTarget,
    required this.onExecuteScript,
    this.defaultDirectoryPath = 'nxnb',
    this.onFocusNexusTerminal,
  });

  @override
  InteractiveRunbookSidebarState createState() =>
      InteractiveRunbookSidebarState();
}

class InteractiveRunbookSidebarState extends State<InteractiveRunbookSidebar> {
  final FocusScopeNode _sidebarScopeNode = FocusScopeNode();

  bool get isFocused {
    final primary = FocusManager.instance.primaryFocus;
    return _sidebarScopeNode.hasFocus ||
        _sidebarFocusNode.hasFocus ||
        _docFocusNode.hasFocus ||
        (primary != null &&
            (primary.ancestors.contains(_sidebarScopeNode) ||
                primary == _sidebarFocusNode ||
                primary == _docFocusNode ||
                primary == _findFocusNode));
  }

  void focusSidebar() {
    if (!mounted) return;
    if (_activeTabIndex == 0) {
      if (_selectedNodeIndex == -1 && _treeNodes.isNotEmpty) {
        _selectNodeAtIndex(0);
      }
      _sidebarFocusNode.requestFocus();
    } else {
      _docFocusNode.requestFocus();
    }
  }

  void unfocusSidebar() {
    _findFocusNode.unfocus();
    _sidebarFocusNode.unfocus();
    _docFocusNode.unfocus();
    _sidebarScopeNode.unfocus();
  }

  void _focusNexusTerminal() {
    unfocusSidebar();
    widget.onFocusNexusTerminal?.call();
  }
  static const Set<String> _supportedExtensions = {
    '.nxnb',
    '.md',
    '.markdown',
    '.docx',
    '.sh',
    '.bash',
    '.txt',
    '.conf',
  };

  final List<_OpenRunbookTab> _openTabs = [];
  int _activeTabIndex = 0; // 0 = Files tab, 1..N = _openTabs[index - 1]
  DateTime? _lastDividerTapTime;

  late String _resolvedDirPath;
  final Set<String> _expandedFolders = {};
  String? _selectedFolderPath;
  String? _selectedFilePath;
  String? _clipboardPath;
  bool _isCutOperation = false;
  List<_FileTreeNode> _treeNodes = [];
  String? _selectedBlockId;
  String? _lastSelectedBlockId;

  final ScrollController _filesScrollController = ScrollController();
  final ScrollController _docScrollController = ScrollController();

  final FocusNode _sidebarFocusNode = FocusNode();
  final FocusNode _docFocusNode = FocusNode();

  // Find bar state
  bool _isFindBarOpen = false;
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  String _searchQuery = '';
  List<_SearchMatchLocation> _searchMatches = [];
  int _currentMatchIndex = 0;
  final Map<String, GlobalKey> _blockKeys = {};
  final Map<String, GlobalKey<ScriptCellWidgetState>> _scriptCellKeys = {};
  final Map<String, GlobalKey<_EditablePlaybookTextBlockState>> _textBlockKeys = {};
  Timer? _saveFeedbackTimer;
  String _vimCommand = '';
  Timer? _vimCommandTimer;
  DateTime? _lastTabClosedByVimTime;
  PlaybookBlock? _clipboardBlock;
  final List<_DeletedBlockHistory> _deletedBlockHistory = [];
  bool _pendingG = false;
  Timer? _pendingGTimer;
  String _vimStatusMessage = '';
  Timer? _vimStatusTimer;

  bool _isDividerHovered = false;
  bool _isDraggingDivider = false;
  bool _showSashDots = false;
  bool _isMainWidgetSelected = false;
  Timer? _sashIdleTimer;

  void _showDotsWithAutoFade() {
    _sashIdleTimer?.cancel();
    if (!_showSashDots && mounted) {
      setState(() => _showSashDots = true);
    }
    _sashIdleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isDividerHovered && !_isDraggingDivider) {
        setState(() => _showSashDots = false);
      }
    });
  }

  void onGlobalHover() {
    if (!_isMainWidgetSelected) {
      _showDotsWithAutoFade();
    }
  }

  void onSelectMainWidget() {
    _sashIdleTimer?.cancel();
    if (mounted && (_showSashDots || !_isMainWidgetSelected)) {
      setState(() {
        _isMainWidgetSelected = true;
        _showSashDots = false;
      });
    }
  }

  void _onSidebarOrSashPointer() {
    if (_isMainWidgetSelected && mounted) {
      setState(() => _isMainWidgetSelected = false);
    }
    _showDotsWithAutoFade();
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalHardwareKey);
    _resolvedDirPath = _resolveDirectoryPath(widget.defaultDirectoryPath);
    _selectedFolderPath = _resolvedDirPath;
    _loadFiles();
    _findController.addListener(_onFindQueryChanged);
  }

  @override
  void didUpdateWidget(InteractiveRunbookSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.defaultDirectoryPath != oldWidget.defaultDirectoryPath) {
      _resolvedDirPath = _resolveDirectoryPath(widget.defaultDirectoryPath);
      _selectedFolderPath = _resolvedDirPath;
      _expandedFolders.clear();
      _loadFiles();
    }
  }

  @override
  void dispose() {
    _sashIdleTimer?.cancel();
    _saveFeedbackTimer?.cancel();
    _vimCommandTimer?.cancel();
    _pendingGTimer?.cancel();
    _vimStatusTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleGlobalHardwareKey);
    _findController.removeListener(_onFindQueryChanged);
    _findController.dispose();
    _findFocusNode.dispose();
    _sidebarFocusNode.dispose();
    _docFocusNode.dispose();
    _sidebarScopeNode.dispose();
    _filesScrollController.dispose();
    _docScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.activePalette;

    return FocusScope(
      node: _sidebarScopeNode,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
            if (_activeTabIndex > 0) {
              _openFindBar();
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
            if (_activeTabIndex > 0) {
              _openFindBar();
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            final tab = _activeOpenTab;
            if (tab != null && tab.document != null) {
              _saveDocument(tab);
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            final tab = _activeOpenTab;
            if (tab != null && tab.document != null) {
              _saveDocument(tab);
            }
          },
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_isFindBarOpen) {
              _closeFindBar();
            }
          },
        },
      child: MouseRegion(
        onHover: (_) => _onSidebarOrSashPointer(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _onSidebarOrSashPointer(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left drag handle for resizing
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    onEnter: (_) {
                      setState(() {
                        _isDividerHovered = true;
                        _isMainWidgetSelected = false;
                      });
                    },
                    onExit: (_) => setState(() => _isDividerHovered = false),
                    onHover: (_) => _onSidebarOrSashPointer(),
                    child: Listener(
                      onPointerDown: (_) {
                        final now = DateTime.now();
                        if (_lastDividerTapTime != null &&
                            now.difference(_lastDividerTapTime!) <
                                const Duration(milliseconds: 350)) {
                          SettingsService.instance.setRightSidebarWidth(
                            440.0,
                            persist: true,
                          );
                          _lastDividerTapTime = null;
                        } else {
                          _lastDividerTapTime = now;
                        }
                      },
                      child: GestureDetector(
                        key: const Key('runbook_sidebar_drag_handle'),
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: (_) {
                          setState(() {
                            _isDraggingDivider = true;
                            _isMainWidgetSelected = false;
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          final currentWidth =
                              SettingsService.instance.rightSidebarWidth;
                          final newWidth = (currentWidth - details.delta.dx).clamp(
                            320.0,
                            1200.0,
                          );
                          SettingsService.instance.setRightSidebarWidth(
                            newWidth,
                            persist: false,
                          );
                        },
                        onHorizontalDragEnd: (_) {
                          setState(() => _isDraggingDivider = false);
                          SettingsService.instance.setRightSidebarWidth(
                            SettingsService.instance.rightSidebarWidth,
                            persist: true,
                          );
                          _showDotsWithAutoFade();
                        },
                        child: Container(
                          width: 5,
                          color: Colors.transparent,
                          child: Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_isDraggingDivider || _isDividerHovered)
                                  Container(
                                    width: 1,
                                    height: double.infinity,
                                    color: palette.primaryColor.withValues(alpha: 0.5),
                                  ),
                                AnimatedOpacity(
                                  opacity: (_isDraggingDivider ||
                                          _isDividerHovered ||
                                          (_showSashDots && !_isMainWidgetSelected))
                                      ? 1.0
                                      : 0.0,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildSashDot((_isDraggingDivider || _isDividerHovered)
                                          ? palette.primaryColor
                                          : palette.dimText(0.5)),
                                      const SizedBox(height: 3),
                                      _buildSashDot((_isDraggingDivider || _isDividerHovered)
                                          ? palette.primaryColor
                                          : palette.dimText(0.5)),
                                      const SizedBox(height: 3),
                                      _buildSashDot((_isDraggingDivider || _isDividerHovered)
                                          ? palette.primaryColor
                                          : palette.dimText(0.5)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Sidebar main content
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(top: 3, bottom: 3, right: 3),
                      child: Material(
                        color: palette.background,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: palette.inputBorderColor.withValues(alpha: 0.6),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTabBar(palette),
                            Expanded(
                              child: _activeTabIndex == 0
                                  ? _buildFilesTab(palette)
                                  : _buildDocumentTab(
                                      palette,
                                      _openTabs[_activeTabIndex - 1],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
        ),
      ),
    ),
  );
}

}

class _DeletedBlockHistory {
  final PlaybookBlock block;
  final int originalIndex;
  final String docFilePath;

  _DeletedBlockHistory({
    required this.block,
    required this.originalIndex,
    required this.docFilePath,
  });
}

/// A desktop toolbar button matching the title bar button design:
/// 24x24 px, rounded rectangle hover state (4px radius), smooth hover highlight,
/// danger highlight on hover for destructive actions, and elegant tooltip.
