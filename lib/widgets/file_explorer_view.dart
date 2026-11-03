import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/file_explorer_models.dart';
import '../services/file_explorer_service.dart';
import 'file_explorer_dialogs.dart';
import '../services/settings_service.dart';


class FileExplorerIconHelper {
  static IconData getIconData(FileExplorerItem item, FileExplorerIconTheme iconTheme) {
    if (item.isDir) {
      if (item.name == '..') {
        return Icons.drive_folder_upload_rounded;
      }
      return Icons.folder_rounded;
    }

    if (iconTheme == FileExplorerIconTheme.classic) {
      return Icons.insert_drive_file_outlined;
    }

    final name = item.name.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    final ext = dotIndex != -1 && dotIndex < name.length - 1 ? name.substring(dotIndex + 1) : '';

    switch (ext) {
      // Code & Scripts
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'html':
      case 'css':
      case 'c':
      case 'cpp':
      case 'h':
      case 'go':
      case 'rs':
      case 'java':
      case 'kt':
      case 'php':
      case 'rb':
      case 'sql':
        return Icons.code_rounded;
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'ps1':
      case 'bat':
      case 'cmd':
        return Icons.terminal_rounded;

      // Config & Data
      case 'yaml':
      case 'yml':
      case 'json':
      case 'xml':
      case 'toml':
      case 'ini':
      case 'conf':
      case 'cfg':
      case 'env':
      case 'properties':
        return Icons.tune_rounded;

      // Git & Lockfiles
      case 'gitignore':
      case 'gitattributes':
      case 'lock':
        return Icons.lock_outline;

      // Archives
      case 'zip':
      case 'tar':
      case 'gz':
      case 'tgz':
      case '7z':
      case 'rar':
      case 'bz2':
      case 'xz':
        return Icons.archive_outlined;

      // Images
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'ico':
      case 'webp':
      case 'bmp':
        return Icons.image_outlined;

      // Documents
      case 'txt':
      case 'md':
      case 'markdown':
      case 'doc':
      case 'docx':
      case 'pdf':
      case 'rtf':
        return Icons.description_outlined;

      // Logs
      case 'log':
      case 'out':
      case 'err':
        return Icons.article_outlined;

      // Network / Packet Captures
      case 'pcap':
      case 'pcapng':
      case 'cap':
        return Icons.network_check_rounded;

      // Binaries & Executables
      case 'exe':
      case 'dll':
      case 'so':
      case 'dylib':
      case 'bin':
      case 'msi':
      case 'apk':
        return Icons.settings_applications_outlined;

      // Certificates & Keys
      case 'pem':
      case 'crt':
      case 'cer':
      case 'key':
      case 'pub':
      case 'pfx':
      case 'p12':
        return Icons.key_rounded;

      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color getIconColor(FileExplorerItem item, FileExplorerIconTheme iconTheme, bool isSelected) {
    if (isSelected) {
      return const Color(0xFF98C379);
    }

    if (item.isDir) {
      if (item.name == '..') {
        return const Color(0xFF61AFEF);
      }
      return const Color(0xFFE5C07B);
    }

    if (iconTheme == FileExplorerIconTheme.classic) {
      return const Color(0xFFABB2BF);
    }

    final name = item.name.toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    final ext = dotIndex != -1 && dotIndex < name.length - 1 ? name.substring(dotIndex + 1) : '';

    switch (ext) {
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'html':
      case 'css':
      case 'c':
      case 'cpp':
      case 'h':
      case 'go':
      case 'rs':
      case 'java':
      case 'kt':
      case 'php':
      case 'rb':
      case 'sql':
        return const Color(0xFF56B6C2);
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'ps1':
      case 'bat':
      case 'cmd':
        return const Color(0xFF98C379);

      case 'yaml':
      case 'yml':
      case 'json':
      case 'xml':
      case 'toml':
      case 'ini':
      case 'conf':
      case 'cfg':
      case 'env':
      case 'properties':
        return const Color(0xFFE5C07B);

      case 'gitignore':
      case 'gitattributes':
      case 'lock':
        return const Color(0xFF828997);

      case 'zip':
      case 'tar':
      case 'gz':
      case 'tgz':
      case '7z':
      case 'rar':
      case 'bz2':
      case 'xz':
        return const Color(0xFFD19A66);

      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'ico':
      case 'webp':
      case 'bmp':
        return const Color(0xFFC678DD);

      case 'txt':
      case 'md':
      case 'markdown':
      case 'doc':
      case 'docx':
      case 'pdf':
      case 'rtf':
        return const Color(0xFF61AFEF);

      case 'log':
      case 'out':
      case 'err':
        return const Color(0xFFE06C75);

      case 'pcap':
      case 'pcapng':
      case 'cap':
        return const Color(0xFF98C379);

      case 'exe':
      case 'dll':
      case 'so':
      case 'dylib':
      case 'bin':
      case 'msi':
      case 'apk':
        return const Color(0xFF98C379);

      case 'pem':
      case 'crt':
      case 'cer':
      case 'key':
      case 'pub':
      case 'pfx':
      case 'p12':
        return const Color(0xFFE5C07B);

      default:
        return const Color(0xFFD8DEE9);
    }
  }
}

class FileExplorerView extends StatefulWidget {
  final VoidCallback? onExit;
  final String? initialLeftPath;
  final String? initialRightPath;
  final ExplorerNodeTarget? initialLeftTarget;
  final ExplorerNodeTarget? initialRightTarget;
  final PaneSide? initialActivePane;
  final ValueChanged<ExplorerNodeTarget>? onTargetChanged;
  final FileExplorerService? service;
  final FocusNode? focusNode;
  final bool isActive;
  final VoidCallback? onNewTab;
  final VoidCallback? onCloseTab;
  final ValueChanged<int>? onSwitchTab;

  const FileExplorerView({
    super.key,
    this.onExit,
    this.initialLeftPath,
    this.initialRightPath,
    this.initialLeftTarget,
    this.initialRightTarget,
    this.initialActivePane,
    this.onTargetChanged,
    this.service,
    this.focusNode,
    this.isActive = true,
    this.onNewTab,
    this.onCloseTab,
    this.onSwitchTab,
  });

  @override
  State<FileExplorerView> createState() => _FileExplorerViewState();
}

class _PaneController {
  ExplorerNodeTarget target;
  String currentPath;
  List<FileExplorerItem> items = [];
  List<FileExplorerItem> filteredItems = [];
  int selectedIndex = 0;
  int? selectionAnchorIndex;
  final ScrollController scrollController = ScrollController();
  final Set<String> multiSelected = {};
  bool isLoading = false;
  String? errorMessage;
  String filterText = '';
  final TextEditingController filterInputController = TextEditingController();
  final FocusNode filterFocusNode = FocusNode();
  bool isFiltering = false;
  RemoteSession? remoteSession;

  _PaneController({
    required this.target,
    required this.currentPath,
  });

  void dispose() {
    scrollController.dispose();
    filterInputController.dispose();
    filterFocusNode.dispose();
  }
}

class _FileExplorerViewState extends State<FileExplorerView> {
  FocusNode? _internalFocusNode;
  FocusNode get _focusNode => widget.focusNode ?? (_internalFocusNode ??= FocusNode());
  FileExplorerService get _service => widget.service ?? FileExplorerService.instance;

  bool _isDualPane = true;
  PaneSide _activePane = PaneSide.left;
  String _statusMessage = 'Ready. Press [F1] or [?] for Shortcuts Help.';
  Color _statusColor = const Color(0xFF5C6370);

  int _lastClickTime = 0;
  int? _lastClickIndex;
  PaneSide? _lastClickPane;

  late _PaneController _leftPane;
  late _PaneController _rightPane;

  _PaneController get activePaneState =>
      _activePane == PaneSide.left ? _leftPane : _rightPane;

  _PaneController get inactivePaneState =>
      _activePane == PaneSide.left ? _rightPane : _leftPane;

  @override
  void initState() {
    super.initState();
    final initialLocalPath = Directory.current.path;
    final leftTarget = widget.initialLeftTarget ?? ExplorerNodeTarget.local;
    final rightTarget = widget.initialRightTarget ?? ExplorerNodeTarget.local;

    _activePane = widget.initialActivePane ??
        (!rightTarget.isLocal ? PaneSide.right : PaneSide.left);

    _leftPane = _PaneController(
      target: leftTarget,
      currentPath: widget.initialLeftPath ??
          (leftTarget.isLocal ? initialLocalPath : '/home'),
    );

    _rightPane = _PaneController(
      target: rightTarget,
      currentPath: widget.initialRightPath ??
          (rightTarget.isLocal ? initialLocalPath : '/home'),
    );

    _loadPane(_leftPane);
    _loadPane(_rightPane);
    SettingsService.instance.addListener(_handleSettingsChanged);

    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.canRequestFocus) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(FileExplorerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isAnyFilterFocused =
        _leftPane.filterFocusNode.hasFocus || _rightPane.filterFocusNode.hasFocus;
    if (widget.isActive &&
        (!oldWidget.isActive || (!_focusNode.hasFocus && !isAnyFilterFocused))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentFilterFocused =
            _leftPane.filterFocusNode.hasFocus || _rightPane.filterFocusNode.hasFocus;
        final primary = FocusManager.instance.primaryFocus;
        final isExternalFocused = primary != null &&
            primary != _focusNode &&
            !primary.ancestors.contains(_focusNode);
        if (mounted && _focusNode.canRequestFocus && !currentFilterFocused && !isExternalFocused) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  void _handleSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_handleSettingsChanged);
    _internalFocusNode?.dispose();
    _leftPane.dispose();
    _rightPane.dispose();
    super.dispose();
  }

  void _applyFilter(_PaneController pane) {
    final query = pane.filterText.trim().toLowerCase();
    if (query.isEmpty) {
      pane.filteredItems = List.from(pane.items);
    } else {
      pane.filteredItems = pane.items
          .where((item) =>
              item.name.toLowerCase().contains(query) && !item.isParentDir)
          .toList();
    }
    for (final item in pane.filteredItems) {
      item.isSelected = pane.multiSelected.contains(item.path);
    }
    if (pane.filteredItems.isEmpty) {
      pane.selectedIndex = -1;
    } else if (pane.selectedIndex >= pane.filteredItems.length) {
      pane.selectedIndex = pane.filteredItems.length - 1;
    }
  }

  void _unselectAllAndUnfocus(_PaneController pane) {
    setState(() {
      pane.multiSelected.clear();
      for (final item in pane.filteredItems) {
        item.isSelected = false;
      }
      pane.selectedIndex = -1;
      pane.selectionAnchorIndex = null;
    });
  }

  void _openFilter(_PaneController pane) {
    setState(() {
      pane.isFiltering = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pane.filterFocusNode.canRequestFocus) {
        pane.filterFocusNode.requestFocus();
      }
    });
  }

  void _closeFilter(_PaneController pane) {
    setState(() {
      pane.isFiltering = false;
      pane.filterText = '';
      pane.filterInputController.clear();
      _applyFilter(pane);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _loadPane(_PaneController pane, {bool silent = false}) async {
    if (!silent && pane.items.isEmpty) {
      setState(() {
        pane.isLoading = true;
        pane.errorMessage = null;
      });
    } else {
      pane.errorMessage = null;
    }

    try {
      if (pane.target.isLocal) {
        final results = await _service.listLocal(
          pane.currentPath,
        );
        pane.items = results;
        for (final item in pane.items) {
          item.isSelected = pane.multiSelected.contains(item.path);
        }
        _applyFilter(pane);
      } else {
        // Remote node
        pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
        final results = await _service.listRemote(
          pane.remoteSession!,
          pane.currentPath,
        );
        pane.items = results;
        for (final item in pane.items) {
          item.isSelected = pane.multiSelected.contains(item.path);
        }
        _applyFilter(pane);
      }
    } catch (e) {
      pane.errorMessage = e.toString();
      _setStatus('Error loading path: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          pane.isLoading = false;
        });
      }
    }
  }

  void _setStatus(String msg, {bool isError = false, bool isSuccess = false}) {
    setState(() {
      _statusMessage = msg;
      if (isError) {
        _statusColor = const Color(0xFFE06C75);
      } else if (isSuccess) {
        _statusColor = const Color(0xFF98C379);
      } else {
        _statusColor = const Color(0xFFABB2BF);
      }
    });
  }

  // ==========================================
  // Navigation & Actions
  // ==========================================

  void _switchActivePane() {
    setState(() {
      _activePane = _activePane == PaneSide.left ? PaneSide.right : PaneSide.left;
    });
    _focusNode.requestFocus();
  }

  void _zoomIn() {
    final current = SettingsService.instance.fileExplorerDensity;
    if (current == FileExplorerDensity.compact) {
      SettingsService.instance.setFileExplorerDensity(FileExplorerDensity.standard);
    } else if (current == FileExplorerDensity.standard) {
      SettingsService.instance.setFileExplorerDensity(FileExplorerDensity.large);
    }
  }

  void _zoomOut() {
    final current = SettingsService.instance.fileExplorerDensity;
    if (current == FileExplorerDensity.large) {
      SettingsService.instance.setFileExplorerDensity(FileExplorerDensity.standard);
    } else if (current == FileExplorerDensity.standard) {
      SettingsService.instance.setFileExplorerDensity(FileExplorerDensity.compact);
    }
  }

  Future<void> _showSettingsDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const FileExplorerSettingsDialog(),
    );
    _focusNode.requestFocus();
  }

  void _toggleDualPane() {
    setState(() {
      _isDualPane = !_isDualPane;
    });
    _focusNode.requestFocus();
  }

  void _moveCursorInPane(_PaneController pane, int delta) {
    if (pane.filteredItems.isEmpty) return;

    final baseIndex = pane.selectedIndex < 0
        ? (delta > 0 ? -1 : pane.filteredItems.length)
        : pane.selectedIndex;
    final newIndex = (baseIndex + delta).clamp(0, pane.filteredItems.length - 1);

    setState(() {
      pane.selectedIndex = newIndex;
      pane.selectionAnchorIndex = newIndex;
      if (pane.multiSelected.isNotEmpty) {
        pane.multiSelected.clear();
        for (final item in pane.filteredItems) {
          item.isSelected = false;
        }
      }
    });

    _scrollPaneToSelection(pane);
  }

  void _moveCursorWithSelectionInPane(_PaneController pane, int delta) {
    if (pane.filteredItems.isEmpty) return;

    final anchor = pane.selectionAnchorIndex ?? (pane.selectedIndex < 0 ? 0 : pane.selectedIndex);
    pane.selectionAnchorIndex = anchor;

    final cur = pane.selectedIndex < 0 ? anchor : pane.selectedIndex;
    final newIndex = (cur + delta).clamp(0, pane.filteredItems.length - 1);

    setState(() {
      pane.selectedIndex = newIndex;
      _selectRange(pane, anchor, newIndex);
    });

    _scrollPaneToSelection(pane);
  }

  void _scrollPaneToSelection(_PaneController pane) {
    if (pane.selectedIndex < 0) return;
    if (!pane.scrollController.hasClients) return;

    final rowHeight = SettingsService.instance.fileExplorerDensity.rowHeight;
    final targetTop = pane.selectedIndex * rowHeight;
    final targetBottom = targetTop + rowHeight;
    final currentOffset = pane.scrollController.offset;
    final viewportHeight = pane.scrollController.position.viewportDimension;

    if (viewportHeight <= 0) return;

    if (targetTop < currentOffset) {
      pane.scrollController.jumpTo(
        targetTop.clamp(0.0, pane.scrollController.position.maxScrollExtent),
      );
    } else if (targetBottom > currentOffset + viewportHeight) {
      final newOffset = targetBottom - viewportHeight;
      pane.scrollController.jumpTo(
        newOffset.clamp(0.0, pane.scrollController.position.maxScrollExtent),
      );
    }
  }

  Future<void> _enterActiveItem() async {
    final pane = activePaneState;
    if (pane.selectedIndex < 0 || pane.filteredItems.isEmpty) return;
    await _enterItemInPane(pane, pane.selectedIndex);
  }

  Future<void> _enterItemInPane(_PaneController pane, int index) async {
    if (index < 0 || index >= pane.filteredItems.length) return;
    final item = pane.filteredItems[index];

    if (item.isDir) {
      pane.currentPath = item.path;
      pane.selectedIndex = 0;
      pane.multiSelected.clear();
      pane.filterText = '';
      pane.filterInputController.clear();
      pane.isFiltering = false;
      await _loadPane(pane);
      _focusNode.requestFocus();
    } else {
      await _openViewFile(pane, item);
      _focusNode.requestFocus();
    }
  }

  Future<void> _navigateParent() async {
    final pane = activePaneState;
    if (pane.target.isLocal) {
      final curDir = Directory(pane.currentPath);
      final parent = curDir.parent;
      if (parent.path != curDir.path) {
        pane.currentPath = parent.path;
        pane.selectedIndex = 0;
        pane.multiSelected.clear();
        await _loadPane(pane);
      }
    } else {
      if (pane.currentPath != '/' && pane.currentPath.isNotEmpty) {
        final lastSlash = pane.currentPath.lastIndexOf('/');
        final parent = lastSlash <= 0 ? '/' : pane.currentPath.substring(0, lastSlash);
        pane.currentPath = parent;
        pane.selectedIndex = 0;
        pane.multiSelected.clear();
        await _loadPane(pane);
      }
    }
  }

  void _toggleSelectCurrent() {
    final pane = activePaneState;
    if (pane.selectedIndex >= 0 && pane.selectedIndex < pane.filteredItems.length) {
      _toggleSelectItem(pane, pane.selectedIndex);
    }
  }

  void _toggleSelectItem(_PaneController pane, int idx) {
    if (idx < 0 || idx >= pane.filteredItems.length) return;
    final item = pane.filteredItems[idx];
    if (item.name == '..') return;

    setState(() {
      if (pane.multiSelected.contains(item.path)) {
        pane.multiSelected.remove(item.path);
        item.isSelected = false;
      } else {
        pane.multiSelected.add(item.path);
        item.isSelected = true;
      }
      pane.selectedIndex = idx;
      pane.selectionAnchorIndex = idx;
    });
  }

  void _toggleSelectItemWithCtrl(_PaneController pane, int clickedIdx) {
    if (clickedIdx < 0 || clickedIdx >= pane.filteredItems.length) return;
    final clickedItem = pane.filteredItems[clickedIdx];
    if (clickedItem.name == '..') return;

    setState(() {
      // If multiSelected was empty, also add the previously focused item
      if (pane.multiSelected.isEmpty &&
          pane.selectedIndex >= 0 &&
          pane.selectedIndex < pane.filteredItems.length &&
          pane.selectedIndex != clickedIdx) {
        final prev = pane.filteredItems[pane.selectedIndex];
        if (prev.name != '..') {
          pane.multiSelected.add(prev.path);
          prev.isSelected = true;
        }
      }

      if (pane.multiSelected.contains(clickedItem.path)) {
        pane.multiSelected.remove(clickedItem.path);
        clickedItem.isSelected = false;
      } else {
        pane.multiSelected.add(clickedItem.path);
        clickedItem.isSelected = true;
      }
      pane.selectedIndex = clickedIdx;
      pane.selectionAnchorIndex = clickedIdx;
    });
  }

  void _selectRange(_PaneController pane, int fromIdx, int toIdx) {
    if (pane.filteredItems.isEmpty) return;
    final start = fromIdx.clamp(0, pane.filteredItems.length - 1);
    final end = toIdx.clamp(0, pane.filteredItems.length - 1);
    final minIdx = start < end ? start : end;
    final maxIdx = start > end ? start : end;

    setState(() {
      pane.multiSelected.clear();
      for (int i = 0; i < pane.filteredItems.length; i++) {
        final item = pane.filteredItems[i];
        if (item.name == '..') {
          item.isSelected = false;
          continue;
        }
        if (i >= minIdx && i <= maxIdx) {
          pane.multiSelected.add(item.path);
          item.isSelected = true;
        } else {
          item.isSelected = false;
        }
      }
    });
  }

  void _selectAll() {
    final pane = activePaneState;
    final allSelected = pane.filteredItems
        .where((i) => i.name != '..')
        .every((i) => pane.multiSelected.contains(i.path));

    setState(() {
      for (final item in pane.filteredItems) {
        if (item.name == '..') continue;
        if (allSelected) {
          item.isSelected = false;
          pane.multiSelected.remove(item.path);
        } else {
          item.isSelected = true;
          pane.multiSelected.add(item.path);
        }
      }
    });
  }

  Future<void> _selectNodeTarget(_PaneController pane) async {
    final selected = await showDialog<ExplorerNodeTarget>(
      context: context,
      builder: (ctx) => FileExplorerNodePickerDialog(currentTarget: pane.target),
    );

    if (selected != null && mounted) {
      setState(() {
        pane.target = selected;
        pane.remoteSession = null;
        pane.items.clear();
        pane.filteredItems.clear();
        pane.filterText = '';
        pane.filterInputController.clear();
        pane.isFiltering = false;
        pane.currentPath = selected.isLocal ? Directory.current.path : '/home';
        pane.selectedIndex = 0;
        pane.multiSelected.clear();
        pane.isLoading = true;
        pane.errorMessage = null;
      });
      _setStatus('Connecting to ${selected.label}...');
      widget.onTargetChanged?.call(selected);
      await _loadPane(pane);
      if (pane.errorMessage == null) {
        _setStatus('Connected to ${selected.label}', isSuccess: true);
      }
    }
    _focusNode.requestFocus();
  }

  Future<void> _showEditCredentialsDialog(_PaneController pane) async {
    final userCtrl = TextEditingController(text: pane.target.username);
    final passCtrl = TextEditingController(text: pane.target.password);
    bool obscure = true;

    final updated = await showDialog<ExplorerNodeTarget>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E222B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: Color(0xFF56B6C2), width: 1.5),
            ),
            title: Row(
              children: [
                const Icon(Icons.key, color: Color(0xFF56B6C2), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CREDENTIALS FOR ${pane.target.label}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: Color(0xFF5C6370)),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2C313C)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF56B6C2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Color(0xFF5C6370)),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2C313C)),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF56B6C2)),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: const Color(0xFF5C6370),
                        ),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF5C6370))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF56B6C2),
                  foregroundColor: const Color(0xFF1E222B),
                ),
                onPressed: () {
                  final newTarget = pane.target.copyWith(
                    username: userCtrl.text.trim(),
                    password: passCtrl.text,
                  );
                  Navigator.pop(ctx, newTarget);
                },
                child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        pane.target = updated;
        pane.remoteSession = null;
        pane.errorMessage = null;
      });
      await _loadPane(pane);
      if (pane.errorMessage == null) {
        _setStatus('Connected to ${updated.label}', isSuccess: true);
      }
    }
  }

  // ==========================================
  // Standard File Actions (Copy, Move, Del, etc.)
  // ==========================================

  List<FileExplorerItem> _getTargetItems() {
    final pane = activePaneState;
    if (pane.multiSelected.isNotEmpty) {
      return pane.filteredItems
          .where((i) => pane.multiSelected.contains(i.path) && i.name != '..')
          .toList();
    }
    if (pane.selectedIndex >= 0 && pane.selectedIndex < pane.filteredItems.length) {
      final active = pane.filteredItems[pane.selectedIndex];
      if (active.name != '..') return [active];
    }
    return [];
  }

  Widget _buildDragFeedback(FileExplorerItem item, int count) {
    final iconTheme = SettingsService.instance.fileExplorerIconTheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E222B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF56B6C2), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FileExplorerIconHelper.getIconData(item, iconTheme),
              size: 16,
              color: FileExplorerIconHelper.getIconColor(item, iconTheme, false),
            ),
            const SizedBox(width: 8),
            Text(
              count > 1 ? '${item.name} (+$count items)' : item.name,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canDropIntoDirectory(FileDragPayload payload, ExplorerNodeTarget destTarget, String targetDirPath) {
    if (payload.sourceTarget.isSameTarget(destTarget) && payload.sourceDirPath == targetDirPath) {
      return false;
    }

    final isLocal = destTarget.isLocal;
    final separator = isLocal ? Platform.pathSeparator : '/';

    for (final dragged in payload.items) {
      if (dragged.path == targetDirPath) return false;
      if (dragged.isDir) {
        final prefix = dragged.path.endsWith(separator) ? dragged.path : '${dragged.path}$separator';
        if (targetDirPath.startsWith(prefix)) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _handleDropOnTarget({
    required FileDragPayload payload,
    required PaneSide destSide,
    required String destDirPath,
    required String targetFolderName,
  }) async {
    final srcPane = payload.sourceSide == PaneSide.left ? _leftPane : _rightPane;
    final destPane = destSide == PaneSide.left ? _leftPane : _rightPane;

    if (payload.items.isEmpty) return;

    if (payload.sourceSide == destSide) {
      // Intra-pane drop into subfolder: Move
      final count = payload.items.length;
      final msg = count > 1
          ? "Are you sure you want to move $count items into '$targetFolderName'?"
          : "Are you sure you want to move '${payload.items.first.name}' into '$targetFolderName'?";

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => FileExplorerConfirmDialog(
          title: 'MOVE TO FOLDER',
          message1: msg,
          message2: 'Destination: $destDirPath',
          borderColor: const Color(0xFF56B6C2),
        ),
      );

      if (confirmed == true && mounted) {
        await _executeTransfer(
          src: srcPane,
          dest: destPane,
          targets: payload.items,
          destDirPath: destDirPath,
          isMove: true,
        );
      }
    } else {
      // Cross-pane drop: Ask Copy or Move
      final count = payload.items.length;
      final msg = count > 1
          ? 'Transfer $count items to ${destPane.target.label} ($targetFolderName)?'
          : "Transfer '${payload.items.first.name}' to ${destPane.target.label} ($targetFolderName)?";

      final chosenAction = await showDialog<FileDropAction>(
        context: context,
        builder: (ctx) => FileExplorerDropActionDialog(
          title: 'DRAG & DROP TRANSFER',
          message: msg,
          destPath: destDirPath,
        ),
      );

      if (chosenAction != null && mounted) {
        await _executeTransfer(
          src: srcPane,
          dest: destPane,
          targets: payload.items,
          destDirPath: destDirPath,
          isMove: chosenAction == FileDropAction.move,
        );
      }
    }
    _focusNode.requestFocus();
  }

  Future<void> _executeTransfer({
    required _PaneController src,
    required _PaneController dest,
    required List<FileExplorerItem> targets,
    required String destDirPath,
    required bool isMove,
  }) async {
    if (targets.isEmpty) return;

    final actionLabel = isMove ? 'Moving' : 'Copying';
    final progressNotifier = ValueNotifier<FileTransferProgress>(
      FileTransferProgress(
        title: '$actionLabel ${targets.length} item(s)...',
        currentFile: targets.first.name,
        completedItems: 0,
        totalItems: targets.length,
        progress: 0.0,
      ),
    );

    bool isCancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FileExplorerProgressDialog(
        progressNotifier: progressNotifier,
        onCancel: () {
          isCancelled = true;
          Navigator.of(ctx).pop();
        },
      ),
    );

    int transferredCount = 0;
    try {
      final isSameTarget = src.target.isSameTarget(dest.target);

      for (int i = 0; i < targets.length; i++) {
        if (isCancelled) break;
        final item = targets[i];

        void updateItemProgress(int sentBytes, int totalBytes, {double stageOffset = 0.0, double stageMultiplier = 1.0}) {
          if (isCancelled) return;
          final fileRatio = totalBytes > 0 ? (sentBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
          final combinedRatio = stageOffset + (fileRatio * stageMultiplier);
          final overallProgress = (i + combinedRatio) / targets.length;
          progressNotifier.value = FileTransferProgress(
            title: '$actionLabel ${targets.length} item(s)...',
            currentFile: item.name,
            completedItems: i,
            totalItems: targets.length,
            progress: overallProgress,
            currentBytes: sentBytes,
            totalBytes: totalBytes,
          );
        }

        final progressFraction = i / targets.length;
        progressNotifier.value = FileTransferProgress(
          title: '$actionLabel ${targets.length} item(s)...',
          currentFile: item.name,
          completedItems: i,
          totalItems: targets.length,
          progress: progressFraction,
        );
        _setStatus('[${i + 1}/${targets.length}] $actionLabel ${item.name} (${(progressFraction * 100).toInt()}%)...');

        if (src.target.isLocal && dest.target.isLocal) {
          // Local to Local
          if (isMove) {
            await _service.moveLocal(item.path, destDirPath);
          } else {
            await _service.copyLocal(
              item.path,
              destDirPath,
              onProgress: (sent, total) => updateItemProgress(sent, total),
            );
          }
        } else if (isSameTarget && !src.target.isLocal) {
          // Same Remote to Same Remote (optimized direct remote shell/sftp command)
          src.remoteSession ??= await _service.getOrConnectRemote(src.target);
          if (isMove) {
            await _service.moveRemote(src.remoteSession!, item.path, destDirPath);
          } else {
            await _service.copyRemote(src.remoteSession!, item.path, destDirPath);
          }
        } else if (src.target.isLocal && !dest.target.isLocal) {
          // Local to Remote (Upload)
          dest.remoteSession ??= await _service.getOrConnectRemote(dest.target);
          await _service.uploadLocalToRemote(
            item.path,
            dest.remoteSession!,
            destDirPath,
            onProgress: (sent, total) => updateItemProgress(sent, total),
          );
          if (isMove) {
            await _service.deleteLocal(item.path);
          }
        } else if (!src.target.isLocal && dest.target.isLocal) {
          // Remote to Local (Download)
          src.remoteSession ??= await _service.getOrConnectRemote(src.target);
          await _service.downloadRemoteToLocal(
            src.remoteSession!,
            item.path,
            item.isDir,
            destDirPath,
            onProgress: (rcv, total) => updateItemProgress(rcv, total),
          );
          if (isMove) {
            await _service.deleteRemote(src.remoteSession!, item.path, item.isDir);
          }
        } else {
          // Cross Remote to Different Remote
          _setStatus('Remote-to-remote transfer in progress...');
          final tempDir = await Directory.systemTemp.createTemp('he_transfer_');
          try {
            src.remoteSession ??= await _service.getOrConnectRemote(src.target);
            await _service.downloadRemoteToLocal(
              src.remoteSession!,
              item.path,
              item.isDir,
              tempDir.path,
              onProgress: (rcv, total) => updateItemProgress(rcv, total, stageOffset: 0.0, stageMultiplier: 0.5),
            );
            final downloadedPath = '${tempDir.path}${Platform.pathSeparator}${item.name}';
            dest.remoteSession ??= await _service.getOrConnectRemote(dest.target);
            await _service.uploadLocalToRemote(
              downloadedPath,
              dest.remoteSession!,
              destDirPath,
              onProgress: (sent, total) => updateItemProgress(sent, total, stageOffset: 0.5, stageMultiplier: 0.5),
            );
            if (isMove) {
              await _service.deleteRemote(src.remoteSession!, item.path, item.isDir);
            }
          } finally {
            await tempDir.delete(recursive: true);
          }
        }

        transferredCount++;
        src.multiSelected.remove(item.path);
      }

      progressNotifier.value = FileTransferProgress(
        title: 'Complete',
        currentFile: '',
        completedItems: transferredCount,
        totalItems: targets.length,
        progress: 1.0,
      );
    } catch (e) {
      _setStatus('$actionLabel failed: $e', isError: true);
    } finally {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      progressNotifier.dispose();
      if (isCancelled) {
        _setStatus('$actionLabel cancelled ($transferredCount/${targets.length} items transferred).');
      } else if (transferredCount > 0) {
        _setStatus('Successfully ${isMove ? "moved" : "copied"} $transferredCount item(s).', isSuccess: true);
        src.multiSelected.clear();
      }
      await _loadPane(src, silent: true);
      if (src != dest || destDirPath != src.currentPath) {
        await _loadPane(dest, silent: true);
      }
    }
  }

  Future<void> _initiateCopy() async {
    final targets = _getTargetItems();
    if (targets.isEmpty) {
      _setStatus('No item selected to copy.');
      return;
    }

    final dest = inactivePaneState;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => FileExplorerConfirmDialog(
        title: 'COPY CONFIRMATION',
        message1: targets.length > 1
            ? 'Are you sure you want to copy ${targets.length} items?'
            : "Are you sure you want to copy '${targets.first.name}'?",
        message2: 'To: ${dest.currentPath} (${dest.target.label})',
        borderColor: const Color(0xFF98C379),
      ),
    );

    if (confirmed == true && mounted) {
      await _executeTransfer(
        src: activePaneState,
        dest: inactivePaneState,
        targets: targets,
        destDirPath: inactivePaneState.currentPath,
        isMove: false,
      );
    }
    _focusNode.requestFocus();
  }

  Future<void> _initiateMove() async {
    final targets = _getTargetItems();
    if (targets.isEmpty) {
      _setStatus('No item selected to move.');
      return;
    }

    final dest = inactivePaneState;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => FileExplorerConfirmDialog(
        title: 'MOVE CONFIRMATION',
        message1: targets.length > 1
            ? 'Are you sure you want to move ${targets.length} items?'
            : "Are you sure you want to move '${targets.first.name}'?",
        message2: 'To: ${dest.currentPath} (${dest.target.label})',
        borderColor: const Color(0xFF56B6C2),
      ),
    );

    if (confirmed == true && mounted) {
      await _executeTransfer(
        src: activePaneState,
        dest: inactivePaneState,
        targets: targets,
        destDirPath: inactivePaneState.currentPath,
        isMove: true,
      );
    }
    _focusNode.requestFocus();
  }

  Future<void> _initiateDelete() async {
    final targets = _getTargetItems();
    if (targets.isEmpty) {
      _setStatus('No item selected to delete.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => FileExplorerConfirmDialog(
        title: 'DELETE CONFIRMATION',
        message1: targets.length > 1
            ? 'Are you sure you want to delete ${targets.length} items?'
            : "Are you sure you want to delete '${targets.first.name}'?",
        message2: 'This operation is permanent and cannot be undone.',
        borderColor: const Color(0xFFE06C75),
        defaultYes: false,
      ),
    );

    if (confirmed == true && mounted) {
      final pane = activePaneState;
      _setStatus('Deleting ${targets.length} item(s)...');
      try {
        for (final item in targets) {
          if (pane.target.isLocal) {
            await _service.deleteLocal(item.path);
          } else {
            pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
            await _service.deleteRemote(pane.remoteSession!, item.path, item.isDir);
          }
        }
        pane.multiSelected.clear();
        _setStatus('Successfully deleted ${targets.length} item(s).', isSuccess: true);
        await _loadPane(pane);
      } catch (e) {
        _setStatus('Delete failed: $e', isError: true);
      }
    }
    _focusNode.requestFocus();
  }

  Future<void> _initiateNewFile() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const FileExplorerPromptDialog(
        title: 'NEW FILE',
        promptLabel: 'Enter file name:',
      ),
    );

    if (name != null && name.trim().isNotEmpty && mounted) {
      final pane = activePaneState;
      try {
        if (pane.target.isLocal) {
          await _service.createLocalFile(pane.currentPath, name.trim());
        } else {
          pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
          await _service.createRemoteFile(pane.remoteSession!, pane.currentPath, name.trim());
        }
        _setStatus("Created file '${name.trim()}'.", isSuccess: true);
        await _loadPane(pane);
      } catch (e) {
        _setStatus('Create file failed: $e', isError: true);
      }
    }
    _focusNode.requestFocus();
  }

  Future<void> _initiateNewFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const FileExplorerPromptDialog(
        title: 'NEW FOLDER',
        promptLabel: 'Enter folder name:',
      ),
    );

    if (name != null && name.trim().isNotEmpty && mounted) {
      final pane = activePaneState;
      try {
        if (pane.target.isLocal) {
          await _service.createLocalDir(pane.currentPath, name.trim());
        } else {
          pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
          await _service.createRemoteDir(pane.remoteSession!, pane.currentPath, name.trim());
        }
        _setStatus("Created directory '${name.trim()}'.", isSuccess: true);
        await _loadPane(pane);
      } catch (e) {
        _setStatus('Create directory failed: $e', isError: true);
      }
    }
    _focusNode.requestFocus();
  }

  Future<void> _initiateRename() async {
    final targets = _getTargetItems();
    if (targets.isEmpty) {
      _setStatus('No item selected to rename.');
      return;
    }
    final active = targets.first;

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => FileExplorerPromptDialog(
        title: 'RENAME',
        promptLabel: 'Rename to:',
        initialValue: active.name,
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && mounted) {
      final pane = activePaneState;
      try {
        if (pane.target.isLocal) {
          await _service.renameLocal(active.path, newName.trim());
        } else {
          pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
          await _service.renameRemote(pane.remoteSession!, active.path, newName.trim());
        }
        _setStatus("Renamed to '${newName.trim()}'.", isSuccess: true);
        await _loadPane(pane);
      } catch (e) {
        _setStatus('Rename failed: $e', isError: true);
      }
    }
    _focusNode.requestFocus();
  }

  bool _isLogOrTextFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.log') || lower.endsWith('.txt');
  }

  bool _isPcapFile(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.pcap') ||
        lower.endsWith('.pcapng') ||
        lower.endsWith('.cap');
  }

  Future<void> _openViewFile(_PaneController pane, FileExplorerItem item) async {
    if (_isLogOrTextFile(item.name)) {
      final chosenEditor = await showDialog<ExternalEditor>(
        context: context,
        builder: (ctx) => FileExplorerOpenWithDialog(
          fileName: item.name,
          defaultEditor: ExternalEditor.notepadPlusPlus,
        ),
      );

      if (chosenEditor == null) {
        _focusNode.requestFocus();
        return;
      }

      if (chosenEditor != ExternalEditor.internalViewer) {
        String targetPath = item.path;
        if (!pane.target.isLocal) {
          _setStatus("Downloading '${item.name}' for preview in ${chosenEditor.label}...");
          try {
            pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
            targetPath = await _service.downloadRemoteToTemp(pane.remoteSession!, item.path, item.name);
          } catch (e) {
            if (mounted) {
              _setStatus("Failed to download '${item.name}': $e", isError: true);
              await showDialog(
                context: context,
                builder: (ctx) => FileExplorerNotificationDialog(
                  title: 'DOWNLOAD FAILED',
                  message: "Failed to download remote file '${item.name}'.",
                  subMessage: e.toString(),
                  borderColor: const Color(0xFFE06C75),
                  icon: Icons.error_outline,
                ),
              );
            }
            _focusNode.requestFocus();
            return;
          }
        }

        final launched = await _service.launchExternalEditor(chosenEditor, targetPath);
        if (mounted) {
          if (launched) {
            _setStatus("Opening '${item.name}' in ${chosenEditor.label}...", isSuccess: true);
          } else {
            _setStatus("${chosenEditor.label} is not installed or failed to launch.", isError: true);
            await showDialog(
              context: context,
              builder: (ctx) => FileExplorerNotificationDialog(
                title: 'EDITOR NOT FOUND',
                message: "${chosenEditor.label} is not installed or executable not found on this system.",
                subMessage: "Unable to open '${item.name}'. Please make sure ${chosenEditor.label} is installed and available in your PATH.",
                borderColor: const Color(0xFFE06C75),
                icon: Icons.warning_amber_rounded,
              ),
            );
          }
        }
        _focusNode.requestFocus();
        return;
      }
    }

    if (_isPcapFile(item.name)) {
      if (!pane.target.isLocal) {
        if (mounted) {
          _setStatus("Remote pcap '${item.name}' must be copied to local filesystem to open in Wireshark.", isError: true);
          await showDialog(
            context: context,
            builder: (ctx) => FileExplorerNotificationDialog(
              title: 'REMOTE PCAP FILE',
              message: "Cannot open remote pcap '${item.name}' directly in Wireshark GUI.",
              subMessage: 'Please copy/transfer this file to the Local Filesystem first, then open it in Wireshark.',
              borderColor: const Color(0xFFE5C07B),
              icon: Icons.info_outline,
            ),
          );
        }
        _focusNode.requestFocus();
        return;
      }

      // Local filesystem pcap file: Open in Wireshark GUI
      final wiresharkPath = _service.getWiresharkPath();
      if (wiresharkPath != null) {
        final launched = await _service.launchWireshark(item.path);
        if (mounted) {
          if (launched) {
            _setStatus("Opening '${item.name}' in Wireshark GUI...", isSuccess: true);
          } else {
            _setStatus("Failed to start Wireshark for '${item.name}'.", isError: true);
            await showDialog(
              context: context,
              builder: (ctx) => FileExplorerNotificationDialog(
                title: 'LAUNCH FAILED',
                message: "Failed to launch Wireshark GUI for '${item.name}'.",
                subMessage: 'Please check system permissions or try opening Wireshark manually.',
                borderColor: const Color(0xFFE06C75),
                icon: Icons.error_outline,
              ),
            );
          }
        }
      } else {
        // Wireshark is NOT installed
        if (mounted) {
          _setStatus("Wireshark is not installed. Unable to open '${item.name}'.", isError: true);
          await showDialog(
            context: context,
            builder: (ctx) => FileExplorerNotificationDialog(
              title: 'WIRESHARK NOT FOUND',
              message: 'Wireshark GUI is not installed on this system.',
              subMessage: "Cannot open '${item.name}'.\nPlease install Wireshark from https://www.wireshark.org or make sure Wireshark.exe is in your PATH.",
              borderColor: const Color(0xFFE06C75),
              icon: Icons.warning_amber_rounded,
            ),
          );
        }
      }
      _focusNode.requestFocus();
      return;
    }

    String content = '';
    try {
      if (pane.target.isLocal) {
        content = await _service.readLocalText(item.path);
      } else {
        pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
        content = await _service.readRemoteText(pane.remoteSession!, item.path);
      }
    } catch (e) {
      content = '[Error reading file content: $e]';
    }

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => FileExplorerViewFileDialog(
          fileName: item.name,
          initialContent: content,
          readOnly: false,
          onSave: (newContent) async {
            if (pane.target.isLocal) {
              await _service.writeLocalText(item.path, newContent);
            } else {
              pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
              await _service.writeRemoteText(pane.remoteSession!, item.path, newContent);
            }
            _setStatus("Saved changes to '${item.name}'.", isSuccess: true);
          },
        ),
      );
    }
    _focusNode.requestFocus();
  }

  Future<void> _initiateMerge() async {
    final targets = _getTargetItems();
    if (targets.length < 2) {
      _setStatus('Please select at least 2 files to merge.');
      return;
    }

    final ext = targets.first.name.contains('.')
        ? targets.first.name.split('.').last
        : 'txt';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final defaultMergedName = 'merged_$timestamp.$ext';

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => FileExplorerPromptDialog(
        title: 'MERGE FILES',
        promptLabel: 'Enter new filename for merged output:',
        initialValue: defaultMergedName,
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && mounted) {
      final pane = activePaneState;
      _setStatus('Merging ${targets.length} files into $newName...');
      try {
        final paths = targets.map((t) => t.path).toList();
        if (pane.target.isLocal) {
          await _service.mergeLocal(paths, pane.currentPath, newName.trim());
        } else {
          pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
          await _service.mergeRemote(pane.remoteSession!, paths, pane.currentPath, newName.trim());
        }
        pane.multiSelected.clear();
        _setStatus("Successfully merged ${targets.length} files into '$newName'.", isSuccess: true);
        await _loadPane(pane);
      } catch (e) {
        _setStatus('Merge failed: $e', isError: true);
      }
    }
    _focusNode.requestFocus();
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const FileExplorerHelpDialog(),
    ).then((_) => _focusNode.requestFocus());
  }

  // ==========================================
  // Keyboard Handler
  // ==========================================

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final isDownOnly = event is KeyDownEvent;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    final pane = activePaneState;

    // If filter input is active, handle Esc/Enter/Arrows, or allow typing into TextField
    if (pane.isFiltering) {
      if (isDownOnly && event.logicalKey == LogicalKeyboardKey.escape) {
        _closeFilter(pane);
        return KeyEventResult.handled;
      }
      if (pane.filterFocusNode.hasFocus) {
        if (isDownOnly && event.logicalKey == LogicalKeyboardKey.enter) {
          _enterActiveItem();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveCursorInPane(pane, 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveCursorInPane(pane, -1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
    }

    if (isDownOnly && !isCtrl && event.logicalKey == LogicalKeyboardKey.tab) {
      _switchActivePane();
      return KeyEventResult.handled;
    }

    // Vim-style Window Switch: Ctrl+H (Left pane) and Ctrl+L (Right pane)
    if (isDownOnly && isCtrl && event.logicalKey == LogicalKeyboardKey.keyH) {
      if (_activePane != PaneSide.left) {
        setState(() => _activePane = PaneSide.left);
      }
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (isDownOnly && isCtrl && event.logicalKey == LogicalKeyboardKey.keyL) {
      if (_activePane != PaneSide.right) {
        setState(() => _activePane = PaneSide.right);
      }
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // Browse Dest / Target picker: Ctrl+Space or F2
    if (isDownOnly &&
        ((isCtrl && event.logicalKey == LogicalKeyboardKey.space) ||
         event.logicalKey == LogicalKeyboardKey.f2)) {
      _selectNodeTarget(pane);
      return KeyEventResult.handled;
    }

    if (isDownOnly && isCtrl && event.logicalKey == LogicalKeyboardKey.keyD) {
      _toggleDualPane();
      return KeyEventResult.handled;
    }

    // Zoom In: Ctrl + Plus / Ctrl + Equal / Ctrl + NumpadAdd
    if (isDownOnly && isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
         event.logicalKey == LogicalKeyboardKey.add ||
         event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
      _zoomIn();
      return KeyEventResult.handled;
    }

    // Zoom Out: Ctrl + Minus / Ctrl + NumpadSubtract
    if (isDownOnly && isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
         event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      _zoomOut();
      return KeyEventResult.handled;
    }

    // Appearance & Font Settings: Ctrl+Shift+S
    if (isDownOnly && isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyS) {
      _showSettingsDialog();
      return KeyEventResult.handled;
    }

    if (isDownOnly && isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }

    if (isDownOnly && isCtrl && event.logicalKey == LogicalKeyboardKey.keyJ) {
      _initiateMerge();
      return KeyEventResult.handled;
    }

    final isSlash = event.logicalKey == LogicalKeyboardKey.slash ||
        event.logicalKey == LogicalKeyboardKey.numpadDivide ||
        event.physicalKey == PhysicalKeyboardKey.slash ||
        event.physicalKey == PhysicalKeyboardKey.numpadDivide ||
        (!isCtrl && event.character == '/');

    if (isDownOnly && !isCtrl && isSlash) {
      _openFilter(pane);
      return KeyEventResult.handled;
    }

    if (isDownOnly && !isCtrl && event.logicalKey == LogicalKeyboardKey.space) {
      _toggleSelectCurrent();
      return KeyEventResult.handled;
    }

    // Vim-style cursor movement: k (up), j (down) - supports holding key via KeyRepeatEvent
    if (!isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
         event.logicalKey == LogicalKeyboardKey.keyK)) {
      if (isShift) {
        _moveCursorWithSelectionInPane(pane, -1);
      } else {
        _moveCursorInPane(pane, -1);
      }
      return KeyEventResult.handled;
    }

    if (!isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.arrowDown ||
         event.logicalKey == LogicalKeyboardKey.keyJ)) {
      if (isShift) {
        _moveCursorWithSelectionInPane(pane, 1);
      } else {
        _moveCursorInPane(pane, 1);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      if (isShift) {
        _moveCursorWithSelectionInPane(pane, -10);
      } else {
        _moveCursorInPane(pane, -10);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      if (isShift) {
        _moveCursorWithSelectionInPane(pane, 10);
      } else {
        _moveCursorInPane(pane, 10);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.home) {
      if (isShift) {
        _moveCursorWithSelectionInPane(pane, -pane.selectedIndex);
      } else {
        _moveCursorInPane(pane, -pane.selectedIndex);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.end) {
      if (isShift) {
        _moveCursorWithSelectionInPane(pane, pane.filteredItems.length - 1 - pane.selectedIndex);
      } else {
        _moveCursorInPane(pane, pane.filteredItems.length - 1 - pane.selectedIndex);
      }
      return KeyEventResult.handled;
    }

    // Vim-style enter/parent navigation: l (enter), h (parent)
    if (isDownOnly &&
        !isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
         event.logicalKey == LogicalKeyboardKey.arrowRight ||
         event.logicalKey == LogicalKeyboardKey.keyL)) {
      _enterActiveItem();
      return KeyEventResult.handled;
    }

    if (isDownOnly &&
        !isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
         event.logicalKey == LogicalKeyboardKey.arrowLeft ||
         event.logicalKey == LogicalKeyboardKey.keyH)) {
      _navigateParent();
      return KeyEventResult.handled;
    }

    if (isDownOnly && !isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      _initiateCopy();
      return KeyEventResult.handled;
    }

    if (isDownOnly && !isCtrl && event.logicalKey == LogicalKeyboardKey.keyM) {
      _initiateMove();
      return KeyEventResult.handled;
    }

    if (isDownOnly &&
        !isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
         event.logicalKey == LogicalKeyboardKey.keyD)) {
      _initiateDelete();
      return KeyEventResult.handled;
    }

    if (isDownOnly && !isCtrl && event.logicalKey == LogicalKeyboardKey.keyN) {
      if (isShift) {
        _initiateNewFolder();
      } else {
        _initiateNewFile();
      }
      return KeyEventResult.handled;
    }

    if (isDownOnly && !isCtrl && event.logicalKey == LogicalKeyboardKey.keyR) {
      _initiateRename();
      return KeyEventResult.handled;
    }

    if (isDownOnly &&
        !isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.keyO ||
         event.logicalKey == LogicalKeyboardKey.keyV)) {
      if (pane.filteredItems.isNotEmpty) {
        _openViewFile(pane, pane.filteredItems[pane.selectedIndex]);
      }
      return KeyEventResult.handled;
    }

    if (isDownOnly &&
        (event.logicalKey == LogicalKeyboardKey.f1 ||
         event.logicalKey == LogicalKeyboardKey.question)) {
      _showHelpDialog();
      return KeyEventResult.handled;
    }

    if (isDownOnly &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
         (!isCtrl && event.logicalKey == LogicalKeyboardKey.keyQ))) {
      if (pane.multiSelected.isNotEmpty || pane.selectedIndex != -1) {
        _unselectAllAndUnfocus(pane);
        return KeyEventResult.handled;
      }
      widget.onExit?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ==========================================
  // UI Builder
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          final isFilterFocused = _leftPane.filterFocusNode.hasFocus ||
              _rightPane.filterFocusNode.hasFocus;
          if (!isFilterFocused && !_focusNode.hasFocus && _focusNode.canRequestFocus) {
            _focusNode.requestFocus();
          }
        },
        child: Container(
          color: const Color(0xFF171B24), // Slate dark terminal background
        child: Column(
          children: [
            // Subtitle header to satisfy test: "Remote & Local File Explorer"
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFF13161C),
              child: Row(
                children: [
                  const Text(
                    'Remote & Local File Explorer',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF56B6C2),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  // Dual pane toggle button
                  IconButton(
                    tooltip: 'Toggle Dual Pane [Ctrl+d]',
                    icon: Icon(
                      _isDualPane ? Icons.view_column : Icons.view_agenda,
                      size: 18,
                      color: _isDualPane ? const Color(0xFF56B6C2) : const Color(0xFF5C6370),
                    ),
                    onPressed: _toggleDualPane,
                  ),
                  // Appearance & Font Settings button
                  IconButton(
                    tooltip: 'Appearance & Font Settings [Ctrl+Shift+S]',
                    icon: const Icon(Icons.tune_rounded, size: 18, color: Color(0xFF56B6C2)),
                    onPressed: _showSettingsDialog,
                  ),
                  // Help button
                  IconButton(
                    tooltip: 'Help (Shortcuts) [F1/?]',
                    icon: const Icon(Icons.help_outline, size: 18, color: Color(0xFF98C379)),
                    onPressed: _showHelpDialog,
                  ),
                ],
              ),
            ),

            // Panes Area
            Expanded(
              child: Row(
                children: [
                  // Left Pane
                  Expanded(
                    child: _buildPaneWidget(
                      _leftPane,
                      PaneSide.left,
                      isActive: _activePane == PaneSide.left,
                    ),
                  ),

                  // Center vertical divider in dual pane
                  if (_isDualPane) ...[
                    Container(
                      width: 1.5,
                      color: const Color(0xFF2C313C),
                    ),
                    // Right Pane
                    Expanded(
                      child: _buildPaneWidget(
                        _rightPane,
                        PaneSide.right,
                        isActive: _activePane == PaneSide.right,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Bottom Status / Shortcut Bar
            _buildBottomStatusBar(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildPaneWidget(
    _PaneController pane,
    PaneSide side, {
    required bool isActive,
  }) {
    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          if (_activePane != side) {
            setState(() => _activePane = side);
          }
          _focusNode.requestFocus();

          final dy = pointerSignal.scrollDelta.dy;
          if (dy != 0) {
            int delta;
            if (dy > 0) {
              delta = (dy / 80.0).ceil().clamp(1, 5);
            } else {
              delta = (dy / 80.0).floor().clamp(-5, -1);
            }

            final isShift = HardwareKeyboard.instance.isShiftPressed;
            if (isShift) {
              _moveCursorWithSelectionInPane(pane, delta);
            } else {
              _moveCursorInPane(pane, delta);
            }
          }
        }
      },
      child: DragTarget<FileDragPayload>(
        onWillAcceptWithDetails: (details) {
          return details.data.sourceSide != side ||
              _canDropIntoDirectory(details.data, pane.target, pane.currentPath);
        },
        onAcceptWithDetails: (details) {
          _handleDropOnTarget(
            payload: details.data,
            destSide: side,
            destDirPath: pane.currentPath,
            targetFolderName: pane.currentPath,
          );
        },
        builder: (context, candidateData, rejectedData) {
          final isDropHovered = candidateData.isNotEmpty;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_activePane != side) {
                setState(() => _activePane = side);
              }
              _focusNode.requestFocus();
              _unselectAllAndUnfocus(pane);
            },
            child: Container(
              decoration: BoxDecoration(
                color: isDropHovered
                    ? const Color(0xFF56B6C2).withValues(alpha: 0.08)
                    : Colors.transparent,
                border: isDropHovered
                    ? Border.all(color: const Color(0xFF56B6C2).withValues(alpha: 0.6), width: 1.5)
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Directory header pill & Node indicator
                  _buildPaneHeader(pane, side, isActive: isActive),
                  const SizedBox(height: 6),

                  // Filter bar if active
                  if (pane.isFiltering) _buildFilterBar(pane),

                  // Table Column Headers
                  _buildTableHeader(),
                  const Divider(color: Color(0xFF2C313C), height: 1, thickness: 1),

                  // Item List
                  Expanded(
                    child: (pane.isLoading && pane.items.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sync,
                                  size: 20,
                                  color: Color(0xFF56B6C2),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Connecting to ${pane.target.label}...',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF56B6C2),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pane.currentPath,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: Color(0xFF5C6370),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : pane.errorMessage != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Color(0xFFE06C75),
                                        size: 36,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        pane.errorMessage!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: Color(0xFFE06C75),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        alignment: WrapAlignment.center,
                                        children: [
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.refresh, size: 14),
                                            label: const Text(
                                              'Retry',
                                              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF2C313C),
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: () {
                                              pane.remoteSession = null;
                                              _loadPane(pane);
                                            },
                                          ),
                                          if (!pane.target.isLocal && pane.target.type != ExplorerTargetType.fe)
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.key, size: 14),
                                              label: const Text(
                                                'Edit Credentials',
                                                style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF56B6C2),
                                                foregroundColor: const Color(0xFF1E222B),
                                              ),
                                              onPressed: () => _showEditCredentialsDialog(pane),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : _buildItemsList(pane, side, isActive: isActive),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaneHeader(_PaneController pane, PaneSide side, {required bool isActive}) {
    return Row(
      children: [
        // Path pill matching image 1 & 2
        Expanded(
          child: InkWell(
            onTap: () async {
              if (_activePane != side) {
                setState(() => _activePane = side);
              }
              _focusNode.requestFocus();
              final newPath = await showDialog<String>(
                context: context,
                builder: (ctx) => FileExplorerPromptDialog(
                  title: 'CHANGE DIRECTORY',
                  promptLabel: 'Enter absolute path:',
                  initialValue: pane.currentPath,
                ),
              );
              if (newPath != null && newPath.trim().isNotEmpty && mounted) {
                pane.currentPath = newPath.trim();
                await _loadPane(pane);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF56B6C2) : const Color(0xFF2C313C),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  Icon(
                    isActive ? Icons.folder_open_rounded : Icons.folder_rounded,
                    size: 16,
                    color: isActive ? Colors.black87 : const Color(0xFFE5C07B),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pane.currentPath,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: SettingsService.instance.fileExplorerFontFamily.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.black : const Color(0xFFABB2BF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Node Selector Pill
        InkWell(
          onTap: () {
            if (_activePane != side) {
              setState(() => _activePane = side);
            }
            _focusNode.requestFocus();
            _selectNodeTarget(pane);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222B),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: pane.target.isLocal ? const Color(0xFF98C379) : const Color(0xFF61AFEF),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  pane.target.isLocal ? Icons.computer : Icons.cloud_outlined,
                  size: 13,
                  color: pane.target.isLocal ? const Color(0xFF98C379) : const Color(0xFF61AFEF),
                ),
                const SizedBox(width: 4),
                Text(
                  pane.target.label,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: pane.target.isLocal ? const Color(0xFF98C379) : const Color(0xFF61AFEF),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF5C6370)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),

        // Refresh icon
        IconButton(
          icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF5C6370)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () {
            if (_activePane != side) {
              setState(() => _activePane = side);
            }
            _focusNode.requestFocus();
            _loadPane(pane);
          },
        ),
      ],
    );
  }

  Widget _buildFilterBar(_PaneController pane) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF181A20),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF98C379)),
      ),
      child: Row(
        children: [
          const Text(
            'Filter: ',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF98C379),
            ),
          ),
          Expanded(
            child: TextField(
              controller: pane.filterInputController,
              focusNode: pane.filterFocusNode,
              autofocus: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFD8DEE9),
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                hintText: 'Type to filter... [Esc to clear, Enter to open]',
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF5C6370),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  pane.filterText = val;
                  _applyFilter(pane);
                });
              },
              onSubmitted: (_) {
                _enterActiveItem();
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: Color(0xFF5C6370)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Clear filter [Esc]',
            onPressed: () => _closeFilter(pane),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    final density = SettingsService.instance.fileExplorerDensity;
    final fontFamily = SettingsService.instance.fileExplorerFontFamily.fontFamily;
    final sizeWidth = density == FileExplorerDensity.large ? 95.0 : 80.0;
    final modWidth = density == FileExplorerDensity.large ? 130.0 : 110.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 22 + density.iconSize + 6), // Spacer for Checkbox (22) + Icon + Padding (6)
          Expanded(
            child: Text(
              'Name',
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: density.fontSize,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF5C6370),
              ),
            ),
          ),
          SizedBox(
            width: sizeWidth,
            child: Text(
              'Size',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: density.fontSize,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF5C6370),
              ),
            ),
          ),
          SizedBox(
            width: modWidth,
            child: Text(
              'Mod',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: density.fontSize,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF5C6370),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(_PaneController pane, PaneSide side, {required bool isActive}) {
    if (pane.filteredItems.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_activePane != side) {
            setState(() => _activePane = side);
          }
          _focusNode.requestFocus();
          _unselectAllAndUnfocus(pane);
        },
        child: const Center(
          child: Text(
            '(Empty folder)',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFF5C6370),
            ),
          ),
        ),
      );
    }

    final density = SettingsService.instance.fileExplorerDensity;
    final iconTheme = SettingsService.instance.fileExplorerIconTheme;
    final fontFamily = SettingsService.instance.fileExplorerFontFamily.fontFamily;
    final sizeWidth = density == FileExplorerDensity.large ? 95.0 : 80.0;
    final modWidth = density == FileExplorerDensity.large ? 130.0 : 110.0;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (event) {
        final totalItemsHeight = pane.filteredItems.length * density.rowHeight;
        final scrollOffset = pane.scrollController.hasClients ? pane.scrollController.offset : 0.0;
        final visibleItemsHeight = totalItemsHeight - scrollOffset;
        if (event.localPosition.dy > visibleItemsHeight) {
          if (_activePane != side) {
            setState(() => _activePane = side);
          }
          _focusNode.requestFocus();
          _unselectAllAndUnfocus(pane);
        }
      },
      child: ListView.builder(
        controller: pane.scrollController,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: pane.filteredItems.length,
        itemExtent: density.rowHeight,
        itemBuilder: (context, idx) {
          final item = pane.filteredItems[idx];
          final isFocused = idx == pane.selectedIndex;
          final isSelected = pane.multiSelected.contains(item.path);

          Color rowBg;
          if (isSelected) {
            rowBg = const Color(0xFF22352A);
          } else if (isFocused) {
            rowBg = isActive ? const Color(0xFF2B3A4A) : const Color(0xFF1F242C);
          } else {
            rowBg = Colors.transparent;
          }

          final textColor = isSelected
              ? const Color(0xFF98C379)
              : item.isDir
                  ? const Color(0xFFE5C07B)
                  : const Color(0xFFD8DEE9);

          final rowContent = Container(
            color: rowBg,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                // Selection indicator checkbox (directly clickable)
                InkWell(
                  onTap: () {
                    if (_activePane != side) {
                      setState(() => _activePane = side);
                    }
                    _focusNode.requestFocus();
                    _toggleSelectItem(pane, idx);
                  },
                  child: SizedBox(
                    width: 22,
                    child: Text(
                      isSelected ? '[*]' : '   ',
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontSize: density.fontSize - 1,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF98C379),
                      ),
                    ),
                  ),
                ),

                // Icon
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    FileExplorerIconHelper.getIconData(item, iconTheme),
                    size: density.iconSize,
                    color: FileExplorerIconHelper.getIconColor(item, iconTheme, isSelected),
                  ),
                ),

                // Name
                Expanded(
                  child: Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: density.fontSize,
                      fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
                      color: textColor,
                    ),
                  ),
                ),

                // Size
                SizedBox(
                  width: sizeWidth,
                  child: Text(
                    item.isDir ? '-' : FileExplorerItem.formatSize(item.size),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: density.fontSize,
                      color: const Color(0xFFABB2BF),
                    ),
                  ),
                ),

                // Mod
                SizedBox(
                  width: modWidth,
                  child: Text(
                    item.modified,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: density.fontSize,
                      color: const Color(0xFFABB2BF),
                    ),
                  ),
                ),
              ],
            ),
          );

          final itemWidget = InkWell(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            onTap: () async {
              final isCtrl = HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed;
              final isShift = HardwareKeyboard.instance.isShiftPressed;

              if (_activePane != side) {
                setState(() => _activePane = side);
              }
              _focusNode.requestFocus();

              final now = DateTime.now().millisecondsSinceEpoch;
              final isDoubleClick = _lastClickPane == side &&
                  _lastClickIndex == idx &&
                  (now - _lastClickTime) < 500;

              _lastClickTime = now;
              _lastClickIndex = idx;
              _lastClickPane = side;

              if (isDoubleClick) {
                await _enterItemInPane(pane, idx);
                return;
              }

              if (isCtrl) {
                _toggleSelectItemWithCtrl(pane, idx);
              } else if (isShift) {
                final anchor = pane.selectionAnchorIndex ?? (pane.selectedIndex >= 0 ? pane.selectedIndex : 0);
                pane.selectionAnchorIndex = anchor;
                setState(() {
                  pane.selectedIndex = idx;
                  _selectRange(pane, anchor, idx);
                });
              } else {
                setState(() {
                  pane.multiSelected.clear();
                  for (final it in pane.filteredItems) {
                    it.isSelected = false;
                  }
                  pane.selectedIndex = idx;
                  pane.selectionAnchorIndex = idx;
                });
              }
            },
            child: rowContent,
          );

          // Make draggable if not '..'
          Widget row = itemWidget;
          if (item.name != '..') {
            final draggedItems = pane.multiSelected.contains(item.path)
                ? pane.filteredItems.where((i) => pane.multiSelected.contains(i.path) && i.name != '..').toList()
                : [item];

            final payload = FileDragPayload(
              sourceSide: side,
              sourceTarget: pane.target,
              sourceDirPath: pane.currentPath,
              items: draggedItems,
            );

            row = Draggable<FileDragPayload>(
              data: payload,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _buildDragFeedback(item, draggedItems.length),
              childWhenDragging: Opacity(opacity: 0.35, child: itemWidget),
              child: itemWidget,
            );
          }

          // If directory, make it a DragTarget
          if (item.isDir) {
            final targetChild = row;
            final String targetDirPath;
            if (item.name == '..') {
              if (pane.target.isLocal) {
                targetDirPath = Directory(pane.currentPath).parent.path;
              } else {
                final lastSlash = pane.currentPath.lastIndexOf('/');
                targetDirPath = lastSlash <= 0 ? '/' : pane.currentPath.substring(0, lastSlash);
              }
            } else {
              targetDirPath = item.path;
            }

            row = DragTarget<FileDragPayload>(
              onWillAcceptWithDetails: (details) {
                return _canDropIntoDirectory(details.data, pane.target, targetDirPath);
              },
              onAcceptWithDetails: (details) {
                _handleDropOnTarget(
                  payload: details.data,
                  destSide: side,
                  destDirPath: targetDirPath,
                  targetFolderName: item.name == '..' ? 'Parent Folder (..)' : item.name,
                );
              },
              builder: (context, candidateData, rejectedData) {
                final isHovered = candidateData.isNotEmpty;
                if (!isHovered) return targetChild;
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF56B6C2).withValues(alpha: 0.25),
                    border: Border.all(color: const Color(0xFF56B6C2), width: 1.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: targetChild,
                );
              },
            );
          }

          return row;
        },
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13161C),
        border: Border(top: BorderSide(color: Color(0xFF2C313C), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            'STATUS: ',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _statusColor,
            ),
          ),
          Expanded(
            child: Text(
              _statusMessage,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: _statusColor,
              ),
            ),
          ),
          if (activePaneState.multiSelected.isNotEmpty) ...[
            Text(
              '[${activePaneState.multiSelected.length} sel] ',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF98C379),
              ),
            ),
            const SizedBox(width: 4),
          ],
          InkWell(
            key: const ValueKey('file_explorer_active_pane_indicator'),
            onTap: _switchActivePane,
            child: Text(
              'Active: ${_activePane == PaneSide.left ? "LEFT" : "RIGHT"}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF56B6C2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
