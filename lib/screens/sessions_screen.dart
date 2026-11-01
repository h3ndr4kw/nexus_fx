import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/session_models.dart';
import '../services/session_manager_service.dart';
import '../theme/app_theme.dart';
import '../widgets/draggable_dialog.dart';
import '../widgets/session_properties_dialog.dart';

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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late bool _showAtStartup;

  @override
  void initState() {
    super.initState();
    _mgr = widget.sessionManager ?? SessionManagerService.instance;
    _mgr.addListener(_onManagerChanged);
    _showAtStartup = widget.initialShowAtStartup ?? false;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _mgr.removeListener(_onManagerChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (!widget.isActive) return false;
    if (event is! KeyDownEvent) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;

    // Do not intercept if a child modal route is open
    final route = ModalRoute.of(context);
    final isCurrentRoute = route == null || route.isCurrent;
    if (!isCurrentRoute) return false;

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

    // Ctrl+N -> New Session
    if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyN) {
      _createNewSession();
      return true;
    }
    // Ctrl+Shift+N -> New Folder
    if (isCtrl && isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyN) {
      _createNewFolder();
      return true;
    }
    // Ctrl+D -> Duplicate Session
    if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyD) {
      _duplicateSelected();
      return true;
    }
    // Ctrl+C -> Copy
    if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelected();
      return true;
    }
    // Ctrl+X -> Cut
    if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyX) {
      _cutSelected();
      return true;
    }
    // Ctrl+V -> Paste
    if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyV) {
      _paste();
      return true;
    }
    // Delete -> Delete Selected
    if (!isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.delete) {
      _deleteSelected();
      return true;
    }
    // Alt+Enter -> Edit Properties
    if (isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.enter) {
      _editSelectedProperties();
      return true;
    }
    // Enter -> Connect session or enter folder
    if (!isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedSessionId != null) {
        final s = _mgr.sessions.where((e) => e.id == _selectedSessionId).firstOrNull;
        if (s != null) {
          widget.onConnectSessions([s]);
          widget.onCloseDialog?.call();
          return true;
        }
      } else if (_selectedFolderId != null) {
        setState(() {
          _currentFolderId = _selectedFolderId;
          _selectedFolderId = null;
        });
        return true;
      }
    }

    return false;
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  void _navigateToFolder(String? folderId) {
    setState(() {
      _currentFolderId = folderId;
      _selectedSessionId = null;
      _selectedFolderId = null;
    });
  }

  void _navigateUp() {
    if (_currentFolderId == null) return;
    final cur = _mgr.folders.where((f) => f.id == _currentFolderId).firstOrNull;
    _navigateToFolder(cur?.parentId);
  }

  Future<void> _createNewSession() async {
    final result = await SessionPropertiesDialog.show(
      context,
      parentFolderId: _currentFolderId,
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

  Future<void> _createNewFolder() async {
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
        parentId: _currentFolderId,
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
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search sessions...',
                hintStyle: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search, size: 16, color: AppTheme.textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
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
          InkWell(
            onTap: () => _navigateToFolder(null),
            child: Text(
              'All Sessions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: _currentFolderId == null ? FontWeight.bold : FontWeight.normal,
                color: _currentFolderId == null ? AppTheme.accentPrimary : AppTheme.textSecondary,
              ),
            ),
          ),
          for (final f in crumbs) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.chevron_right, size: 14, color: AppTheme.textMuted),
            ),
            InkWell(
              onTap: () => _navigateToFolder(f.id),
              child: Text(
                f.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: f.id == _currentFolderId ? FontWeight.bold : FontWeight.normal,
                  color: f.id == _currentFolderId ? AppTheme.accentPrimary : AppTheme.textSecondary,
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16, color: AppTheme.textSecondary),
            tooltip: 'Up one folder',
            onPressed: _currentFolderId != null ? _navigateUp : null,
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final folder in folders) _buildFolderRow(folder),
              for (final session in sessions) _buildSessionRow(session),
            ],
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
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFolderId = folder.id;
          _selectedSessionId = null;
        });
      },
      onDoubleTap: () => _navigateToFolder(folder.id),
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

    return InkWell(
      onTap: () {
        setState(() {
          _selectedSessionId = session.id;
          _selectedFolderId = null;
        });
      },
      onDoubleTap: () {
        widget.onConnectSessions([session]);
        if (widget.isDialogMode) widget.onCloseDialog?.call();
      },
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
