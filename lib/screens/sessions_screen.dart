import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/session_models.dart';
import '../services/session_manager_service.dart';
import '../theme/app_theme.dart';
import '../widgets/draggable_dialog.dart';
import '../widgets/session_properties_dialog.dart';

enum _ItemType { parent, folder, session }

class _NavigableItem {
  final _ItemType type;
  final String? id;
  final SessionFolder? folder;
  final SessionProfile? session;

  const _NavigableItem.parent()
      : type = _ItemType.parent,
        id = null,
        folder = null,
        session = null;

  _NavigableItem.folder(this.folder)
      : type = _ItemType.folder,
        id = folder?.id,
        session = null;

  _NavigableItem.session(this.session)
      : type = _ItemType.session,
        id = session?.id,
        folder = null;
}

class SessionsScreen extends StatefulWidget {
  final SessionManagerService? sessionManager;
  final void Function(List<SessionProfile> sessions, {bool openInRightSplit}) onConnectSessions;
  final void Function(SessionProfile session) onOpenInFileExplorer;
  final bool isDialogMode;
  final VoidCallback? onCloseDialog;
  final bool? initialShowAtStartup;
  final ValueChanged<bool>? onToggleShowAtStartup;
  final bool isActive;

  const SessionsScreen({
    super.key,
    this.sessionManager,
    required this.onConnectSessions,
    required this.onOpenInFileExplorer,
    this.isDialogMode = false,
    this.onCloseDialog,
    this.initialShowAtStartup,
    this.onToggleShowAtStartup,
    this.isActive = true,
  });

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late final SessionManagerService _mgr;
  String? _currentFolderId;
  String? _selectedSessionId;
  String? _selectedFolderId;
  bool _selectedParent = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  late bool _showAtStartup;

  @override
  void initState() {
    super.initState();
    _mgr = widget.sessionManager ?? SessionManagerService.instance;
    _mgr.addListener(_onManagerChanged);
    _showAtStartup = widget.initialShowAtStartup ?? false;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selectedFolderId == null && _selectedSessionId == null && !_selectedParent) {
        final items = _getVisibleItems();
        if (items.isNotEmpty) {
          _selectItemAtIndex(0, visibleItems: items);
        }
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _mgr.removeListener(_onManagerChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<_NavigableItem> _getVisibleItems() {
    final List<_NavigableItem> items = [];
    if (_currentFolderId != null && _searchQuery.isEmpty) {
      items.add(const _NavigableItem.parent());
    }

    List<SessionFolder> folders = _mgr.getChildFolders(_currentFolderId);
    List<SessionProfile> sessions = _mgr.getChildSessions(_currentFolderId);

    if (_searchQuery.isNotEmpty) {
      folders = _mgr.folders.where((f) => f.name.toLowerCase().contains(_searchQuery)).toList();
      sessions = _mgr.sessions.where((s) =>
          s.name.toLowerCase().contains(_searchQuery) ||
          s.host.toLowerCase().contains(_searchQuery) ||
          s.username.toLowerCase().contains(_searchQuery) ||
          s.description.toLowerCase().contains(_searchQuery)).toList();
    }

    for (final f in folders) {
      items.add(_NavigableItem.folder(f));
    }
    for (final s in sessions) {
      items.add(_NavigableItem.session(s));
    }
    return items;
  }

  int _getSelectedIndex(List<_NavigableItem> items) {
    if (items.isEmpty) return -1;
    if (_selectedParent) {
      final idx = items.indexWhere((it) => it.type == _ItemType.parent);
      if (idx != -1) return idx;
    }
    if (_selectedFolderId != null) {
      final idx = items.indexWhere((it) => it.type == _ItemType.folder && it.id == _selectedFolderId);
      if (idx != -1) return idx;
    }
    if (_selectedSessionId != null) {
      final idx = items.indexWhere((it) => it.type == _ItemType.session && it.id == _selectedSessionId);
      if (idx != -1) return idx;
    }
    return -1;
  }

  void _selectItemAtIndex(int index, {List<_NavigableItem>? visibleItems}) {
    final items = visibleItems ?? _getVisibleItems();
    if (items.isEmpty) {
      setState(() {
        _selectedParent = false;
        _selectedFolderId = null;
        _selectedSessionId = null;
      });
      return;
    }
    final clampedIndex = index.clamp(0, items.length - 1);
    final item = items[clampedIndex];
    setState(() {
      switch (item.type) {
        case _ItemType.parent:
          _selectedParent = true;
          _selectedFolderId = null;
          _selectedSessionId = null;
          break;
        case _ItemType.folder:
          _selectedParent = false;
          _selectedFolderId = item.id;
          _selectedSessionId = null;
          break;
        case _ItemType.session:
          _selectedParent = false;
          _selectedFolderId = null;
          _selectedSessionId = item.id;
          break;
      }
    });
    _scrollToIndex(clampedIndex);
  }

  void _moveCursor(int delta) {
    final items = _getVisibleItems();
    if (items.isEmpty) return;
    final current = _getSelectedIndex(items);
    int nextIndex;
    if (current == -1) {
      nextIndex = delta > 0 ? 0 : items.length - 1;
    } else {
      nextIndex = (current + delta).clamp(0, items.length - 1);
    }
    _selectItemAtIndex(nextIndex, visibleItems: items);
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const rowHeight = 30.0;
    final itemTop = index * rowHeight;
    final itemBottom = itemTop + rowHeight;
    final currentScroll = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;

    if (itemTop < currentScroll) {
      _scrollController.jumpTo(itemTop);
    } else if (itemBottom > currentScroll + viewportHeight) {
      _scrollController.jumpTo((itemBottom - viewportHeight).clamp(0.0, _scrollController.position.maxScrollExtent));
    }
  }

  void _openOrConnectActiveItem() {
    final items = _getVisibleItems();
    final current = _getSelectedIndex(items);
    if (current == -1 || current >= items.length) return;
    final item = items[current];

    switch (item.type) {
      case _ItemType.parent:
        _navigateUp();
        break;
      case _ItemType.folder:
        if (item.folder != null) {
          if (_searchQuery.isNotEmpty) {
            _searchController.clear();
            setState(() => _searchQuery = '');
            _searchFocusNode.unfocus();
          }
          _navigateToFolder(item.folder!.id);
        }
        break;
      case _ItemType.session:
        if (item.session != null) {
          widget.onConnectSessions([item.session!]);
          if (widget.isDialogMode) widget.onCloseDialog?.call();
        }
        break;
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (!widget.isActive) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;

    // Do not intercept if a child modal route is open
    final route = ModalRoute.of(context);
    final isCurrentRoute = route == null || route.isCurrent;
    if (!isCurrentRoute) return false;

    final isDownOnly = event is KeyDownEvent;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
    final isShift = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
    final isAlt = HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altRight);

    // If search text field has focus
    if (_searchFocusNode.hasFocus) {
      if (isDownOnly && event.logicalKey == LogicalKeyboardKey.escape) {
        if (_searchController.text.isNotEmpty) {
          _searchController.clear();
          setState(() {
            _searchQuery = '';
            final items = _getVisibleItems();
            if (items.isNotEmpty) _selectItemAtIndex(0, visibleItems: items);
          });
        }
        _searchFocusNode.unfocus();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _moveCursor(1);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _moveCursor(-1);
        return true;
      }
      if (isDownOnly && !isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.enter) {
        _openOrConnectActiveItem();
        return true;
      }
      return false;
    }

    // Ctrl+N -> New Session
    if (isDownOnly && isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyN) {
      _createNewSession();
      return true;
    }
    // Ctrl+Shift+N -> New Folder
    if (isDownOnly && isCtrl && isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyN) {
      _createNewFolder();
      return true;
    }
    // Ctrl+D -> Duplicate Session
    if (isDownOnly && isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyD) {
      _duplicateSelected();
      return true;
    }
    // Ctrl+C -> Copy
    if (isDownOnly && isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelected();
      return true;
    }
    // Ctrl+X -> Cut
    if (isDownOnly && isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyX) {
      _cutSelected();
      return true;
    }
    // Ctrl+V -> Paste
    if (isDownOnly && isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyV) {
      _paste();
      return true;
    }
    // Delete -> Delete Selected
    if (isDownOnly && !isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.delete) {
      _deleteSelected();
      return true;
    }
    // Alt+Enter -> Edit Properties
    if (isDownOnly && isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.enter) {
      _editSelectedProperties();
      return true;
    }

    // Ctrl+F or / -> Focus search field
    final isSlash = event.logicalKey == LogicalKeyboardKey.slash ||
        event.logicalKey == LogicalKeyboardKey.numpadDivide ||
        event.physicalKey == PhysicalKeyboardKey.slash ||
        event.physicalKey == PhysicalKeyboardKey.numpadDivide ||
        (!isCtrl && !isAlt && event.character == '/');
    if (isDownOnly && !isCtrl && !isAlt && !isShift && isSlash) {
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
      return true;
    }
    if (isDownOnly && isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
      return true;
    }

    // Vim-style / Arrow down (Down & Repeat)
    if (!isCtrl && !isAlt && !isShift &&
        (event.logicalKey == LogicalKeyboardKey.arrowDown ||
         event.logicalKey == LogicalKeyboardKey.keyJ)) {
      _moveCursor(1);
      return true;
    }

    // Vim-style / Arrow up (Down & Repeat)
    if (!isCtrl && !isAlt && !isShift &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
         event.logicalKey == LogicalKeyboardKey.keyK)) {
      _moveCursor(-1);
      return true;
    }

    // PageDown / PageUp
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _moveCursor(10);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _moveCursor(-10);
      return true;
    }

    // Home / End
    if (isDownOnly && event.logicalKey == LogicalKeyboardKey.home) {
      _selectItemAtIndex(0);
      return true;
    }
    if (isDownOnly && event.logicalKey == LogicalKeyboardKey.end) {
      _selectItemAtIndex(999999);
      return true;
    }

    // Enter / ArrowRight / l -> Connect session or enter folder
    if (isDownOnly && !isCtrl && !isShift && !isAlt &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
         event.logicalKey == LogicalKeyboardKey.arrowRight ||
         event.logicalKey == LogicalKeyboardKey.keyL)) {
      _openOrConnectActiveItem();
      return true;
    }

    // Backspace / ArrowLeft / h -> Navigate to parent folder
    if (isDownOnly && !isCtrl && !isShift && !isAlt &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
         event.logicalKey == LogicalKeyboardKey.arrowLeft ||
         event.logicalKey == LogicalKeyboardKey.keyH)) {
      if (_currentFolderId != null) {
        _navigateUp();
        return true;
      }
    }

    return false;
  }

  void _onManagerChanged() {
    if (mounted) {
      setState(() {
        final items = _getVisibleItems();
        final idx = _getSelectedIndex(items);
        if (idx == -1 && items.isNotEmpty) {
          _selectItemAtIndex(0, visibleItems: items);
        }
      });
    }
  }

  void _navigateToFolder(String? folderId, {String? selectItemId, bool isFolder = true}) {
    setState(() {
      _currentFolderId = folderId;
      if (selectItemId != null) {
        if (isFolder) {
          _selectedFolderId = selectItemId;
          _selectedSessionId = null;
          _selectedParent = false;
        } else {
          _selectedSessionId = selectItemId;
          _selectedFolderId = null;
          _selectedParent = false;
        }
      } else {
        final childFolders = _mgr.getChildFolders(folderId);
        final childSessions = _mgr.getChildSessions(folderId);
        if (childFolders.isNotEmpty) {
          _selectedFolderId = childFolders.first.id;
          _selectedSessionId = null;
          _selectedParent = false;
        } else if (childSessions.isNotEmpty) {
          _selectedSessionId = childSessions.first.id;
          _selectedFolderId = null;
          _selectedParent = false;
        } else if (folderId != null) {
          _selectedParent = true;
          _selectedFolderId = null;
          _selectedSessionId = null;
        } else {
          _selectedParent = false;
          _selectedFolderId = null;
          _selectedSessionId = null;
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final items = _getVisibleItems();
      final idx = _getSelectedIndex(items);
      if (idx != -1) {
        _scrollToIndex(idx);
      }
    });
  }

  void _navigateUp() {
    if (_currentFolderId == null) return;
    final cur = _mgr.folders.where((f) => f.id == _currentFolderId).firstOrNull;
    final previousFolderId = _currentFolderId;
    _navigateToFolder(cur?.parentId, selectItemId: previousFolderId, isFolder: true);
  }

  Future<void> _createNewSession({String? targetFolderId}) async {
    final folderId = targetFolderId ?? _selectedFolderId ?? _currentFolderId;
    final result = await SessionPropertiesDialog.show(
      context,
      parentFolderId: folderId,
      sessionManager: _mgr,
    );
    if (result != null) {
      await _mgr.createSession(result.savedSession);
      setState(() => _selectedSessionId = result.savedSession.id);
      if (result.connectNow) {
        widget.onConnectSessions([result.savedSession]);
        if (widget.isDialogMode) widget.onCloseDialog?.call();
      }
    }
  }

  Future<void> _createNewFolder({String? targetParentId}) async {
    final parent = targetParentId ?? _selectedFolderId ?? _currentFolderId;
    final nameCtrl = TextEditingController(text: 'New Folder');
    final descCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: const Text('Create New Folder', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Folder Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentPrimary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final f = await _mgr.createFolder(
        name: nameCtrl.text.trim(),
        parentId: parent,
        description: descCtrl.text.trim(),
      );
      setState(() => _selectedFolderId = f.id);
    }
  }

  Future<void> _editSelectedProperties() async {
    if (_selectedSessionId != null) {
      final s = _mgr.sessions.where((sess) => sess.id == _selectedSessionId).firstOrNull;
      if (s == null) return;
      final result = await SessionPropertiesDialog.show(
        context,
        initialSession: s,
        parentFolderId: s.parentId,
        sessionManager: _mgr,
      );
      if (result != null) {
        await _mgr.updateSession(result.savedSession);
        if (result.connectNow) {
          widget.onConnectSessions([result.savedSession]);
          if (widget.isDialogMode) widget.onCloseDialog?.call();
        }
      }
    } else if (_selectedFolderId != null) {
      final f = _mgr.folders.where((fld) => fld.id == _selectedFolderId).firstOrNull;
      if (f == null) return;
      final nameCtrl = TextEditingController(text: f.name);
      final descCtrl = TextEditingController(text: f.description);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          title: const Text('Folder Properties', style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Folder Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentPrimary),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (ok == true && nameCtrl.text.trim().isNotEmpty) {
        await _mgr.updateFolder(f.copyWith(name: nameCtrl.text.trim(), description: descCtrl.text.trim()));
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedSessionId != null) {
      final s = _mgr.sessions.where((sess) => sess.id == _selectedSessionId).firstOrNull;
      if (s == null) return;
      final deps = _mgr.getDependentSessions(s.id);
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          title: Text('Delete Session "${s.name}"?'),
          content: Text(
            deps.isNotEmpty
                ? 'This session is currently used as a Jump Host for ${deps.length} other session(s). Deleting it will reset those sessions to Direct connection. Continue?'
                : 'Are you sure you want to permanently delete this session?',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusError),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await _mgr.deleteSession(s.id);
        setState(() => _selectedSessionId = null);
      }
    } else if (_selectedFolderId != null) {
      final f = _mgr.folders.where((fld) => fld.id == _selectedFolderId).firstOrNull;
      if (f == null) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          title: Text('Delete Folder "${f.name}"?'),
          content: const Text(
            'Deleting this folder will delete all subfolders and sessions inside it. Continue?',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusError),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete All', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await _mgr.deleteFolder(f.id);
        setState(() => _selectedFolderId = null);
      }
    }
  }

  void _copySelected() {
    if (_selectedSessionId != null) {
      _mgr.copyItem(sessionId: _selectedSessionId);
    } else if (_selectedFolderId != null) {
      _mgr.copyItem(folderId: _selectedFolderId);
    }
  }

  void _cutSelected() {
    if (_selectedSessionId != null) {
      _mgr.cutItem(sessionId: _selectedSessionId);
    } else if (_selectedFolderId != null) {
      _mgr.cutItem(folderId: _selectedFolderId);
    }
  }

  Future<void> _paste() async {
    try {
      await _mgr.pasteInto(_currentFolderId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot paste: $e'), backgroundColor: AppTheme.statusError),
      );
    }
  }

  Future<void> _duplicateSelected() async {
    if (_selectedSessionId != null) {
      final dup = await _mgr.duplicateSession(_selectedSessionId!);
      setState(() => _selectedSessionId = dup.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bgSurface,
      child: Column(
        children: [
          _buildToolbar(),
          _buildBreadcrumbBar(),
          Expanded(child: _buildTableView()),
          if (widget.isDialogMode) _buildDialogFooter(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurfaceSecondary,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'New Item',
            color: AppTheme.bgSurface,
            onSelected: (val) {
              if (val == 'session') _createNewSession();
              if (val == 'folder') _createNewFolder();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'session',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 16, color: AppTheme.accentPrimary),
                    SizedBox(width: 8),
                    Text('New Session (Ctrl+N)', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'folder',
                child: Row(
                  children: [
                    Icon(Icons.create_new_folder_outlined, size: 16, color: Color(0xFFFFCA28)),
                    SizedBox(width: 8),
                    Text('New Folder (Ctrl+Shift+N)', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add, size: 16, color: AppTheme.accentPrimary),
                  SizedBox(width: 4),
                  Text('New', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.accentPrimary)),
                  Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.accentPrimary),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildToolbarIcon(Icons.content_cut, 'Cut (Ctrl+X)', _selectedSessionId != null || _selectedFolderId != null ? _cutSelected : null),
          _buildToolbarIcon(Icons.copy_outlined, 'Copy (Ctrl+C)', _selectedSessionId != null || _selectedFolderId != null ? _copySelected : null),
          _buildToolbarIcon(Icons.control_point_duplicate, 'Duplicate (Ctrl+D)', _selectedSessionId != null ? _duplicateSelected : null),
          _buildToolbarIcon(Icons.paste_outlined, 'Paste (Ctrl+V)', _mgr.hasClipboardItem ? _paste : null),
          _buildToolbarIcon(Icons.delete_outline, 'Delete (Del)', _selectedSessionId != null || _selectedFolderId != null ? _deleteSelected : null),
          const SizedBox(width: 8),
          const SizedBox(height: 20, child: VerticalDivider(width: 1, color: AppTheme.borderSubtle)),
          const SizedBox(width: 8),
          _buildToolbarIcon(Icons.settings_ethernet, 'Properties (Alt+Enter)', _selectedSessionId != null || _selectedFolderId != null ? _editSelectedProperties : null),
          const Spacer(),
          SizedBox(
            width: 240,
            height: 32,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim().toLowerCase();
                  final items = _getVisibleItems();
                  if (items.isNotEmpty) {
                    _selectItemAtIndex(0, visibleItems: items);
                  } else {
                    _selectedParent = false;
                    _selectedFolderId = null;
                    _selectedSessionId = null;
                  }
                });
              },
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search sessions... (/ or Ctrl+F)',
                hintStyle: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search, size: 16, color: AppTheme.textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            final items = _getVisibleItems();
                            if (items.isNotEmpty) {
                              _selectItemAtIndex(0, visibleItems: items);
                            }
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarIcon(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      color: onPressed != null ? AppTheme.textPrimary : AppTheme.textMuted.withValues(alpha: 0.4),
      splashRadius: 16,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
    );
  }

  Future<void> _handleDrop(_SessionDragPayload payload, String? targetFolderId) async {
    if (payload.parentId == targetFolderId) return;

    try {
      if (payload.isSession) {
        await _mgr.moveSession(payload.session!.id, targetFolderId);
      } else if (payload.isFolder) {
        await _mgr.moveFolder(payload.folder!.id, targetFolderId);
      }

      final targetName = targetFolderId == null
          ? 'Root (All Sessions)'
          : (_mgr.folders.where((f) => f.id == targetFolderId).firstOrNull?.name ?? 'Folder');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Moved "${payload.name}" to $targetName'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.accentPrimary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to move: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: AppTheme.statusError,
          ),
        );
      }
    }
  }

  Widget _buildDragFeedback(String name, IconData icon, Color iconColor) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.bgSurfaceSecondary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.accentPrimary, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Text(
              name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderContextMenu(BuildContext context, Offset position, SessionFolder folder) {
    setState(() {
      _selectedFolderId = folder.id;
      _selectedSessionId = null;
      _selectedParent = false;
    });

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: AppTheme.bgSurface,
      items: [
        const PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: AppTheme.accentPrimary),
              SizedBox(width: 8),
              Text('Open Folder', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'new_session',
          child: Row(
            children: [
              Icon(Icons.add, size: 16, color: AppTheme.accentPrimary),
              SizedBox(width: 8),
              Text('New Session Here', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'new_subfolder',
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined, size: 16, color: Color(0xFFFFCA28)),
              SizedBox(width: 8),
              Text('New Subfolder', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'cut',
          child: Row(
            children: [
              Icon(Icons.content_cut, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text('Cut (Ctrl+X)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text('Copy (Ctrl+C)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'properties',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text('Rename / Properties', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: AppTheme.statusError),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(fontSize: 12, color: AppTheme.statusError)),
            ],
          ),
        ),
      ],
    ).then((val) {
      if (val == 'open') _navigateToFolder(folder.id);
      if (val == 'new_session') _createNewSession(targetFolderId: folder.id);
      if (val == 'new_subfolder') _createNewFolder(targetParentId: folder.id);
      if (val == 'cut') _cutSelected();
      if (val == 'copy') _copySelected();
      if (val == 'properties') _editSelectedProperties();
      if (val == 'delete') _deleteSelected();
    });
  }

  void _showSessionContextMenu(BuildContext context, Offset position, SessionProfile session) {
    setState(() {
      _selectedSessionId = session.id;
      _selectedFolderId = null;
      _selectedParent = false;
    });

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: AppTheme.bgSurface,
      items: [
        const PopupMenuItem(
          value: 'connect',
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 16, color: AppTheme.accentPrimary),
              SizedBox(width: 8),
              Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'file_explorer',
          child: Row(
            children: [
              Icon(Icons.folder_shared, size: 16, color: AppTheme.accentPrimary),
              SizedBox(width: 8),
              Text('Open in File Explorer', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.control_point_duplicate, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text('Duplicate (Ctrl+D)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'cut',
          child: Row(
            children: [
              Icon(Icons.content_cut, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text('Cut (Ctrl+X)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy_outlined, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text('Copy (Ctrl+C)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'properties',
          child: Row(
            children: [
              Icon(Icons.settings_ethernet, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text('Properties (Alt+Enter)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: AppTheme.statusError),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(fontSize: 12, color: AppTheme.statusError)),
            ],
          ),
        ),
      ],
    ).then((val) {
      if (val == 'connect') {
        widget.onConnectSessions([session]);
        if (widget.isDialogMode) widget.onCloseDialog?.call();
      }
      if (val == 'file_explorer') widget.onOpenInFileExplorer(session);
      if (val == 'duplicate') _duplicateSelected();
      if (val == 'cut') _cutSelected();
      if (val == 'copy') _copySelected();
      if (val == 'properties') _editSelectedProperties();
      if (val == 'delete') _deleteSelected();
    });
  }

  void _showEmptyAreaContextMenu(BuildContext context, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: AppTheme.bgSurface,
      items: [
        const PopupMenuItem(
          value: 'new_session',
          child: Row(
            children: [
              Icon(Icons.add, size: 16, color: AppTheme.accentPrimary),
              SizedBox(width: 8),
              Text('New Session (Ctrl+N)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'new_folder',
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined, size: 16, color: Color(0xFFFFCA28)),
              SizedBox(width: 8),
              Text('New Folder (Ctrl+Shift+N)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        if (_mgr.hasClipboardItem) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'paste',
            child: Row(
              children: [
                Icon(Icons.paste_outlined, size: 16, color: AppTheme.textSecondary),
                SizedBox(width: 8),
                Text('Paste (Ctrl+V)', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ],
    ).then((val) {
      if (val == 'new_session') _createNewSession();
      if (val == 'new_folder') _createNewFolder();
      if (val == 'paste') _paste();
    });
  }

  Widget _buildBreadcrumbBar() {
    final crumbs = _mgr.getBreadcrumbPath(_currentFolderId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          DragTarget<_SessionDragPayload>(
            onWillAcceptWithDetails: (details) {
              return details.data.parentId != null;
            },
            onAcceptWithDetails: (details) {
              _handleDrop(details.data, null);
            },
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;
              return InkWell(
                onTap: () => _navigateToFolder(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isHovered ? AppTheme.accentPrimary.withValues(alpha: 0.25) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: isHovered ? Border.all(color: AppTheme.accentPrimary, width: 1.5) : null,
                  ),
                  child: Text(
                    isHovered ? 'All Sessions (Drop to move to Root)' : 'All Sessions',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _currentFolderId == null || isHovered ? FontWeight.bold : FontWeight.normal,
                      color: _currentFolderId == null || isHovered ? AppTheme.accentPrimary : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
          for (final f in crumbs) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.chevron_right, size: 14, color: AppTheme.textMuted),
            ),
            DragTarget<_SessionDragPayload>(
              onWillAcceptWithDetails: (details) {
                if (details.data.id == f.id) return false;
                if (details.data.isFolder && _mgr.isFolderDescendantOf(f.id, details.data.id)) return false;
                return details.data.parentId != f.id;
              },
              onAcceptWithDetails: (details) {
                _handleDrop(details.data, f.id);
              },
              builder: (context, candidateData, rejectedData) {
                final isHovered = candidateData.isNotEmpty;
                return InkWell(
                  onTap: () => _navigateToFolder(f.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isHovered ? AppTheme.accentPrimary.withValues(alpha: 0.25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: isHovered ? Border.all(color: AppTheme.accentPrimary, width: 1.5) : null,
                    ),
                    child: Text(
                      isHovered ? '${f.name} (Drop here)' : f.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: f.id == _currentFolderId || isHovered ? FontWeight.bold : FontWeight.normal,
                        color: f.id == _currentFolderId || isHovered ? AppTheme.accentPrimary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          const Spacer(),
          DragTarget<_SessionDragPayload>(
            onWillAcceptWithDetails: (details) {
              if (_currentFolderId == null) return false;
              final parentFolderId = _mgr.folders.where((f) => f.id == _currentFolderId).firstOrNull?.parentId;
              return details.data.parentId != parentFolderId;
            },
            onAcceptWithDetails: (details) {
              final parentFolderId = _mgr.folders.where((f) => f.id == _currentFolderId).firstOrNull?.parentId;
              _handleDrop(details.data, parentFolderId);
            },
            builder: (context, candidateData, rejectedData) {
              final isHovered = candidateData.isNotEmpty;
              return Container(
                decoration: BoxDecoration(
                  color: isHovered ? AppTheme.accentPrimary.withValues(alpha: 0.3) : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: isHovered ? Border.all(color: AppTheme.accentPrimary, width: 1.5) : null,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  color: isHovered ? AppTheme.accentPrimary : AppTheme.textSecondary,
                  tooltip: isHovered ? 'Drop to move up one folder' : 'Up one folder',
                  onPressed: _currentFolderId != null ? _navigateUp : null,
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16, color: AppTheme.textSecondary),
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildParentFolderRow() {
    final parentFolderId = _mgr.folders.where((f) => f.id == _currentFolderId).firstOrNull?.parentId;
    final parentFolderName = parentFolderId == null
        ? 'All Sessions (Root)'
        : (_mgr.folders.where((f) => f.id == parentFolderId).firstOrNull?.name ?? 'Parent Folder');

    return DragTarget<_SessionDragPayload>(
      onWillAcceptWithDetails: (details) {
        return details.data.parentId == _currentFolderId;
      },
      onAcceptWithDetails: (details) {
        _handleDrop(details.data, parentFolderId);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return InkWell(
          onTap: () {
            setState(() {
              _selectedParent = true;
              _selectedFolderId = null;
              _selectedSessionId = null;
            });
          },
          onDoubleTap: () => _navigateUp(),
          child: Container(
            height: 30,
            decoration: BoxDecoration(
              color: isHovered
                  ? AppTheme.accentPrimary.withValues(alpha: 0.25)
                  : (_selectedParent
                      ? AppTheme.accentPrimary.withValues(alpha: 0.15)
                      : Colors.transparent),
              border: Border(
                bottom: const BorderSide(color: AppTheme.borderSubtle, width: 0.5),
                top: isHovered ? const BorderSide(color: AppTheme.accentPrimary, width: 1.5) : BorderSide.none,
                left: isHovered ? const BorderSide(color: AppTheme.accentPrimary, width: 1.5) : BorderSide.none,
                right: isHovered ? const BorderSide(color: AppTheme.accentPrimary, width: 1.5) : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(
                  isHovered ? Icons.drive_folder_upload : Icons.arrow_upward,
                  size: 16,
                  color: isHovered ? AppTheme.accentPrimary : const Color(0xFFFFCA28),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    isHovered ? '.. [Drop here to move to $parentFolderName]' : '..',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isHovered ? AppTheme.accentPrimary : AppTheme.textSecondary,
                    ),
                  ),
                ),
                const Expanded(flex: 2, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                const Expanded(flex: 2, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                const Expanded(flex: 1, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                const Expanded(flex: 1, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                const Expanded(flex: 2, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Up to $parentFolderName',
                    style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted),
                  ),
                ),
                const Expanded(flex: 2, child: Text('-', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableView() {
    List<SessionFolder> folders = _mgr.getChildFolders(_currentFolderId);
    List<SessionProfile> sessions = _mgr.getChildSessions(_currentFolderId);

    if (_searchQuery.isNotEmpty) {
      folders = _mgr.folders.where((f) => f.name.toLowerCase().contains(_searchQuery)).toList();
      sessions = _mgr.sessions.where((s) =>
          s.name.toLowerCase().contains(_searchQuery) ||
          s.host.toLowerCase().contains(_searchQuery) ||
          s.username.toLowerCase().contains(_searchQuery) ||
          s.description.toLowerCase().contains(_searchQuery)).toList();
    }

    return Column(
      children: [
        _buildTableHeader(),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_searchFocusNode.hasFocus) {
                _searchFocusNode.unfocus();
              }
            },
            onSecondaryTapUp: (details) => _showEmptyAreaContextMenu(context, details.globalPosition),
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              children: [
                if (_currentFolderId != null && _searchQuery.isEmpty) _buildParentFolderRow(),
                for (final folder in folders) _buildFolderRow(folder),
                for (final session in sessions) _buildSessionRow(session),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: AppTheme.bgSurfaceSecondary,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: const Row(
        children: [
          SizedBox(width: 32),
          Expanded(flex: 3, child: Text('Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
          Expanded(flex: 2, child: Text('Host', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
          Expanded(flex: 2, child: Text('User Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
          Expanded(flex: 1, child: Text('Protocol', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
          Expanded(flex: 1, child: Text('Port', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
          Expanded(flex: 2, child: Text('Route', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
          Expanded(flex: 3, child: Text('Description', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
          Expanded(flex: 2, child: Text('Modified', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary))),
        ],
      ),
    );
  }

  Widget _buildFolderRow(SessionFolder folder) {
    final isSelected = _selectedFolderId == folder.id;

    final rowWidget = InkWell(
      onTap: () {
        setState(() {
          _selectedFolderId = folder.id;
          _selectedSessionId = null;
          _selectedParent = false;
        });
      },
      onDoubleTap: () => _navigateToFolder(folder.id),
      onSecondaryTapUp: (details) => _showFolderContextMenu(context, details.globalPosition, folder),
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentPrimary.withValues(alpha: 0.15) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: AppTheme.borderSubtle, width: 0.5)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.folder, size: 16, color: Color(0xFFFFCA28)),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: Text(folder.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
            const Expanded(flex: 2, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
            const Expanded(flex: 2, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
            const Expanded(flex: 1, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
            const Expanded(flex: 1, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
            const Expanded(flex: 2, child: Text('-', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))),
            Expanded(flex: 3, child: Text(folder.description, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
            Expanded(flex: 2, child: Text(_formatDate(folder.modifiedAt), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
          ],
        ),
      ),
    );

    final draggableRow = Draggable<_SessionDragPayload>(
      data: _SessionDragPayload.folder(folder),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _buildDragFeedback(folder.name, Icons.folder, const Color(0xFFFFCA28)),
      childWhenDragging: Opacity(opacity: 0.3, child: rowWidget),
      child: rowWidget,
    );

    return DragTarget<_SessionDragPayload>(
      onWillAcceptWithDetails: (details) {
        if (details.data.id == folder.id) return false;
        if (details.data.isFolder && _mgr.isFolderDescendantOf(folder.id, details.data.id)) return false;
        return details.data.parentId != folder.id;
      },
      onAcceptWithDetails: (details) {
        _handleDrop(details.data, folder.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        if (!isHovered) return draggableRow;

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.accentPrimary.withValues(alpha: 0.25),
            border: Border.all(color: AppTheme.accentPrimary, width: 1.5),
          ),
          child: draggableRow,
        );
      },
    );
  }

  Widget _buildSessionRow(SessionProfile session) {
    final isSelected = _selectedSessionId == session.id;
    final isLocal = session.protocol == SessionProtocol.local;

    String routeText = 'Direct';
    if (!isLocal) {
      if (session.jumpHostMode == JumpHostMode.existingSession) {
        final js = _mgr.sessions.where((s) => s.id == session.jumpSessionId).firstOrNull;
        routeText = 'Via: ${js?.name ?? 'Unknown'}';
      } else if (session.jumpHostMode == JumpHostMode.customJumpHost) {
        routeText = 'Via: ${session.customJumpHost ?? '-'}';
      }
    }

    final rowWidget = InkWell(
      onTap: () {
        setState(() {
          _selectedSessionId = session.id;
          _selectedFolderId = null;
          _selectedParent = false;
        });
      },
      onDoubleTap: () {
        widget.onConnectSessions([session]);
        if (widget.isDialogMode) widget.onCloseDialog?.call();
      },
      onSecondaryTapUp: (details) => _showSessionContextMenu(context, details.globalPosition, session),
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentPrimary.withValues(alpha: 0.15) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: AppTheme.borderSubtle, width: 0.5)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(
              isLocal ? Icons.terminal : Icons.cloud_queue,
              size: 16,
              color: isLocal ? const Color(0xFF64B5F6) : const Color(0xFFFF7043),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: Text(session.name, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary))),
            Expanded(flex: 2, child: Text(isLocal ? '-' : session.host, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
            Expanded(flex: 2, child: Text(isLocal ? '-' : session.username, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
            Expanded(flex: 1, child: Text(isLocal ? 'LOCAL' : 'SSH', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentPrimary))),
            Expanded(flex: 1, child: Text(isLocal ? '-' : session.port.toString(), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
            Expanded(flex: 2, child: Text(routeText, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
            Expanded(flex: 3, child: Text(session.description, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
            Expanded(flex: 2, child: Text(_formatDate(session.modifiedAt), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted))),
          ],
        ),
      ),
    );

    return Draggable<_SessionDragPayload>(
      data: _SessionDragPayload.session(session),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _buildDragFeedback(
        session.name,
        isLocal ? Icons.terminal : Icons.cloud_queue,
        isLocal ? const Color(0xFF64B5F6) : const Color(0xFFFF7043),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: rowWidget),
      child: rowWidget,
    );
  }

  Widget _buildDialogFooter() {
    final selectedSession = _selectedSessionId != null
        ? _mgr.sessions.where((s) => s.id == _selectedSessionId).firstOrNull
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurfaceSecondary,
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _showAtStartup,
            onChanged: (val) {
              setState(() => _showAtStartup = val ?? false);
              widget.onToggleShowAtStartup?.call(_showAtStartup);
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 6),
          const Text('Show this dialog box at startup', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: selectedSession != null
                ? () {
                    widget.onConnectSessions([selectedSession]);
                    widget.onCloseDialog?.call();
                  }
                : null,
            child: const Text('Connect', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.borderSubtle),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: widget.onCloseDialog ?? () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class SessionsDialog {
  static Future<void> show(
    BuildContext context, {
    SessionManagerService? sessionManager,
    required void Function(List<SessionProfile> sessions, {bool openInRightSplit}) onConnectSessions,
    required void Function(SessionProfile session) onOpenInFileExplorer,
    bool? initialShowAtStartup,
    ValueChanged<bool>? onToggleShowAtStartup,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DraggableDialog(
        title: 'Sessions',
        icon: Icons.dns_outlined,
        maxWidth: 1020,
        maxHeight: 660,
        minWidth: 800,
        minHeight: 500,
        onClose: () => Navigator.of(ctx).pop(),
        child: SessionsScreen(
          sessionManager: sessionManager,
          onConnectSessions: onConnectSessions,
          onOpenInFileExplorer: onOpenInFileExplorer,
          isDialogMode: true,
          initialShowAtStartup: initialShowAtStartup,
          onToggleShowAtStartup: onToggleShowAtStartup,
          onCloseDialog: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }
}

class _SessionDragPayload {
  final SessionProfile? session;
  final SessionFolder? folder;

  const _SessionDragPayload.session(SessionProfile this.session) : folder = null;
  const _SessionDragPayload.folder(SessionFolder this.folder) : session = null;

  bool get isSession => session != null;
  bool get isFolder => folder != null;
  String get name => session?.name ?? folder?.name ?? '';
  String? get parentId => session?.parentId ?? folder?.parentId;
  String get id => session?.id ?? folder?.id ?? '';
}
