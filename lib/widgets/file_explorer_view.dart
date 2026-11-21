import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/file_explorer_models.dart';
import '../services/archive_commands.dart';
import '../services/file_explorer_service.dart';
import '../services/transfer_manager.dart';
import 'file_explorer_dialogs.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../services/app_paths.dart';


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
  final TransferManager? transferManager;

  /// Tags jobs started here (e.g. the hosting tab's id) so the tab strip can
  /// show which tab has transfers running. Defaults to this view's state.
  final Object? transferOwnerId;
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
    this.transferManager,
    this.transferOwnerId,
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
  TransferManager get _transfers => widget.transferManager ?? TransferManager.instance;
  StreamSubscription<TransferJob>? _transferSub;
  Object get _transferOwner => widget.transferOwnerId ?? this;

  bool _isDualPane = true;
  PaneSide _activePane = PaneSide.left;
  static const double _paneControlHeight = 30;
  static const String _defaultStatus = 'Ready';
  static const Color _defaultStatusColor = Color(0xFFD8DEE9);
  static const Color _errorStatusColor = Color(0xFFE06C75);
  String _statusMessage = _defaultStatus;
  Color _statusColor = _defaultStatusColor;
  Timer? _statusTimer;

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
    final initialLocalPath = AppPaths.defaultLocalDir;
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
    _transferSub = _transfers.finished.listen(_onTransferFinished);

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
    _statusTimer?.cancel();
    _transferSub?.cancel();
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
    _statusTimer?.cancel();
    _statusTimer = Timer(Duration(seconds: isError ? 8 : 4), () {
      if (!mounted) return;
      setState(() {
        _statusMessage = _defaultStatus;
        _statusColor = _defaultStatusColor;
      });
    });
    setState(() {
      _statusMessage = msg;
      if (isError) {
        _statusColor = _errorStatusColor;
      } else if (isSuccess) {
        _statusColor = const Color(0xFF98C379);
      } else {
        _statusColor = _defaultStatusColor;
      }
    });
  }

  // Navigation and pane actions

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
        pane.currentPath = selected.isLocal ? AppPaths.defaultLocalDir : '/home';
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
          InputDecoration field(String label, {Widget? suffixIcon}) {
            OutlineInputBorder outline(Color color, [double width = 1]) =>
                OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: color, width: width),
                );
            return InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              filled: true,
              fillColor: AppTheme.bgSurfaceSecondary,
              isDense: true,
              suffixIcon: suffixIcon,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: outline(const Color(0xFF6B7280)),
              enabledBorder: outline(const Color(0xFF6B7280)),
              focusedBorder: outline(AppTheme.accentPrimary, 1.5),
            );
          }

          void connect() {
            final newTarget = pane.target.copyWith(
              username: userCtrl.text.trim(),
              password: passCtrl.text,
            );
            Navigator.pop(ctx, newTarget);
          }

          return FileExplorerDialogFrame(
            title: 'Credentials for ${pane.target.label}',
            icon: Icons.key,
            width: 420,
            onClose: () => Navigator.pop(ctx),
            actions: [
              FileExplorerDialogButton(
                label: 'Cancel',
                onTap: () => Navigator.pop(ctx),
              ),
              FileExplorerDialogButton(
                label: 'Connect',
                primary: true,
                onTap: connect,
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: userCtrl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                    decoration: field('Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                    onSubmitted: (_) => connect(),
                    decoration: field(
                      'Password',
                      suffixIcon: IconButton(
                        tooltip: obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

  // File actions (copy, move, delete)

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
          confirmText: 'Move',
          cancelText: 'Cancel',
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

  /// Hands the copy/move to the app-wide [TransferManager] and returns at
  /// once. Progress and cancel live in the global transfer bar, so this tab,
  /// other tabs and other pages stay usable while the job runs.
  Future<void> _executeTransfer({
    required _PaneController src,
    required _PaneController dest,
    required List<FileExplorerItem> targets,
    required String destDirPath,
    required bool isMove,
  }) async {
    if (targets.isEmpty) return;
    final job = _transfers.enqueue(
      items: List.of(targets),
      srcTarget: src.target,
      srcDirPath: src.currentPath,
      destTarget: dest.target,
      destDirPath: destDirPath,
      isMove: isMove,
      owner: _transferOwner,
    );
    _setStatus('${job.title} → ${job.destLabel} (in background, see transfer bar)');
  }

  /// Refreshes any pane showing the job's source or destination folder, and
  /// reports the outcome in the status line of the tab that started it.
  void _onTransferFinished(TransferJob job) {
    if (!mounted) return;
    final panes = [_leftPane, _rightPane];
    if (job.owner == _transferOwner) {
      for (final pane in panes) {
        pane.multiSelected.removeAll(job.transferredPaths);
      }
      _setStatus(
        job.resultSummary,
        isError: job.status == TransferStatus.failed,
        isSuccess: job.status == TransferStatus.completed,
      );
    }
    for (final pane in panes) {
      if (_paneShows(pane, job.srcTarget, job.srcDirPath) ||
          _paneShows(pane, job.destTarget, job.destDirPath)) {
        _loadPane(pane, silent: true);
      }
    }
  }

  bool _paneShows(_PaneController pane, ExplorerNodeTarget target, String dirPath) {
    if (!pane.target.isSameTarget(target)) return false;
    String norm(String p) {
      var s = p;
      while (s.length > 1 && (s.endsWith('/') || s.endsWith('\\'))) {
        s = s.substring(0, s.length - 1);
      }
      return target.isLocal && Platform.isWindows ? s.toLowerCase() : s;
    }
    return norm(pane.currentPath) == norm(dirPath);
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
        confirmText: 'Copy',
        cancelText: 'Cancel',
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
        confirmText: 'Move',
        cancelText: 'Cancel',
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
        confirmText: 'Delete',
        cancelText: 'Cancel',
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

  bool _archiveBusy = false;

  /// Last path segment of [path], local or remote; empty at a root.
  String _dirName(String path) {
    final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '';
    final last = parts.last;
    return last.endsWith(':') ? '' : last;
  }

  String _childPath(_PaneController pane, String name) {
    final dir = pane.currentPath;
    if (pane.target.isLocal) return '$dir${Platform.pathSeparator}$name';
    final clean = dir.length > 1 && dir.endsWith('/')
        ? dir.substring(0, dir.length - 1)
        : dir;
    return clean == '/' ? '/$name' : '$clean/$name';
  }

  Set<String> _existingNames(_PaneController pane) =>
      pane.items.where((i) => i.name != '..').map((i) => i.name).toSet();

  /// Error text for a new item name in [pane], or null when it is usable.
  String? _newNameProblem(_PaneController pane, String name) {
    if (name.isEmpty) return 'Name is empty.';
    if (name.contains('/') || (pane.target.isLocal && name.contains(r'\'))) {
      return 'Name cannot contain a path separator.';
    }
    if (name == '.' || name == '..') return 'Invalid name.';
    if (_existingNames(pane).contains(name)) return "'$name' already exists here.";
    return null;
  }

  Future<void> _initiateCompress() async {
    final targets = _getTargetItems();
    if (targets.isEmpty) {
      _setStatus('No item selected to compress.');
      return;
    }
    if (_archiveBusy) {
      _setStatus('A compress or extract is still running.');
      return;
    }

    final pane = activePaneState;
    final format = SettingsService.instance.fileExplorerArchiveFormat;
    final suggested = defaultArchiveName(
      targets.map((t) => ArchiveSource(t.name, isDir: t.isDir)).toList(),
      currentDirName: _dirName(pane.currentPath),
      format: format,
      existing: _existingNames(pane),
    );

    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => FileExplorerPromptDialog(
        title: 'COMPRESS',
        promptLabel: targets.length > 1
            ? 'Archive ${targets.length} items as (${format.label}, change in Settings):'
            : "Archive '${targets.first.name}' as (${format.label}, change in Settings):",
        initialValue: suggested,
      ),
    );
    final name = input?.trim();
    if (name == null || name.isEmpty || !mounted) {
      _focusNode.requestFocus();
      return;
    }
    final problem = _newNameProblem(pane, name);
    if (problem != null) {
      _setStatus('Compress failed: $problem', isError: true);
      _focusNode.requestFocus();
      return;
    }

    final names = targets.map((t) => t.name).toList();
    _archiveBusy = true;
    _setStatus("Compressing ${targets.length} item(s) into '$name'...");
    try {
      if (pane.target.isLocal) {
        await compressLocalArchive(
          dir: pane.currentPath,
          names: names,
          archiveName: name,
          format: format,
        );
      } else {
        pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
        await _service.compressRemote(
            pane.remoteSession!, pane.currentPath, names, name, format);
      }
      pane.multiSelected.clear();
      _setStatus("Created archive '$name'.", isSuccess: true);
      await _loadPane(pane);
    } catch (e) {
      _setStatus('Compress failed: $e', isError: true);
    } finally {
      _archiveBusy = false;
    }
    _focusNode.requestFocus();
  }

  Future<void> _initiateExtract() async {
    final targets = _getTargetItems();
    if (targets.length != 1) {
      _setStatus(targets.isEmpty
          ? 'No archive selected to extract.'
          : 'Select a single archive to extract.');
      return;
    }
    final archive = targets.first;
    final kind = archive.isDir ? null : archiveKindOf(archive.name);
    if (kind == null) {
      _setStatus(
        "'${archive.name}' is not an archive (tar.gz, tgz, tar, tar.bz2, tar.xz, zip).",
        isError: true,
      );
      return;
    }
    if (_archiveBusy) {
      _setStatus('A compress or extract is still running.');
      return;
    }

    final pane = activePaneState;
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => FileExplorerPromptDialog(
        title: 'EXTRACT',
        promptLabel: "Extract '${archive.name}' into new folder:",
        initialValue:
            uniqueName(archiveBaseName(archive.name), _existingNames(pane)),
      ),
    );
    final folder = input?.trim();
    if (folder == null || folder.isEmpty || !mounted) {
      _focusNode.requestFocus();
      return;
    }
    final problem = _newNameProblem(pane, folder);
    if (problem != null) {
      _setStatus('Extract failed: $problem', isError: true);
      _focusNode.requestFocus();
      return;
    }

    final destDir = _childPath(pane, folder);
    _archiveBusy = true;
    _setStatus("Extracting '${archive.name}' into '$folder'...");
    try {
      if (pane.target.isLocal) {
        await extractLocalArchive(
            archivePath: archive.path, destDir: destDir, kind: kind);
      } else {
        pane.remoteSession ??= await _service.getOrConnectRemote(pane.target);
        await _service.extractRemote(
            pane.remoteSession!, archive.path, destDir, kind);
      }
      _setStatus("Extracted '${archive.name}' into '$folder'.", isSuccess: true);
      await _loadPane(pane);
    } catch (e) {
      _setStatus('Extract failed: $e', isError: true);
    } finally {
      _archiveBusy = false;
    }
    _focusNode.requestFocus();
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const FileExplorerHelpDialog(),
    ).then((_) => _focusNode.requestFocus());
  }

  // Keyboard handler

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

    if (isDownOnly && !isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _initiateCompress();
      return KeyEventResult.handled;
    }

    if (isDownOnly && !isCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
      _initiateExtract();
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

  // View composition

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
                  _buildPaneFooter(pane),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _promptChangeDirectory(_PaneController pane, PaneSide side) async {
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
        validator: (value) {
          final localWindows = pane.target.isLocal && Platform.isWindows;
          final ok = localWindows
              ? RegExp(r'^([A-Za-z]:[\\/]|\\\\)').hasMatch(value)
              : value.startsWith('/') || (!pane.target.isLocal && value.startsWith('~'));
          if (ok) return null;
          return localWindows
              ? r'Use an absolute path, e.g. C:\Users or \\server\share.'
              : 'Use an absolute path starting with /.';
        },
      ),
    );
    if (newPath != null && newPath.trim().isNotEmpty && mounted) {
      pane.currentPath = newPath.trim();
      await _loadPane(pane);
    }
  }

  Widget _buildBreadcrumbs(_PaneController pane, PaneSide side, {required bool isActive}) {
    final crumbs = splitPathCrumbs(
      pane.currentPath,
      windowsStyle: pane.target.isLocal && Platform.isWindows,
    );
    final fontFamily = SettingsService.instance.fileExplorerFontFamily.fontFamily;
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final crumb = crumbs[i];
      final isLast = i == crumbs.length - 1;
      // The POSIX root crumb "/" reads as the leading slash of the first folder.
      if (i > 1 || (i == 1 && crumbs.first.label != '/')) {
        children.add(
          Text(
            '/',
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              color: const Color(0xFF5C6370),
            ),
          ),
        );
      }
      children.add(
        InkWell(
          borderRadius: BorderRadius.circular(2),
          onTap: () {
            if (_activePane != side) {
              setState(() => _activePane = side);
            }
            _focusNode.requestFocus();
            if (crumb.path != pane.currentPath) {
              pane.currentPath = crumb.path;
              _loadPane(pane);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Text(
              crumb.label,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 12,
                fontWeight: isLast && isActive ? FontWeight.bold : FontWeight.normal,
                color: isLast && isActive ? const Color(0xFFE5E9F0) : const Color(0xFFABB2BF),
              ),
            ),
          ),
        ),
      );
    }
    // reverse: the deepest folder stays visible when the path is longer than the bar.
    // The minWidth keeps short paths flush left; reverse only matters on overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(children: children),
        ),
      ),
    );
  }

  /// Local panes read blue, SSH panes green; the same color tints the path bar
  /// of the active pane and the node selector.
  static const Color _localAccent = Color(0xFF61AFEF);
  static const Color _remoteAccent = Color(0xFF98C379);
  static const Color _controlSurface = Color(0xFF21252B);
  static const Color _controlBorder = Color(0xFF3E4451);
  static const Color _columnTextColor = Color(0xFF8B93A1);
  static const Color _cursorAccent = Color(0xFF61AFEF);

  /// Outline alpha for accent-bordered controls, matching the selected
  /// left-sidebar item, so the outline marks state without competing with
  /// the file list.
  static const double _accentOutlineAlpha = 0.4;

  String _nodeSelectorLabel(_PaneController pane) {
    if (!pane.target.isLocal) return 'SFTP: ${pane.target.label}';
    final drive = RegExp(r'^[A-Za-z]:').firstMatch(pane.currentPath)?.group(0);
    if (Platform.isWindows && drive != null) {
      return 'Local Drive (${drive.toUpperCase()})';
    }
    return 'Local';
  }

  Widget _buildPaneHeader(_PaneController pane, PaneSide side, {required bool isActive}) {
    final accent = pane.target.isLocal ? _localAccent : _remoteAccent;
    return Row(
      children: [
        // Path bar: each segment is a link to that folder; the pencil (or the empty
        // space) opens the typed-path dialog. The active pane gets an accent outline
        // and brighter text, so the file list stays the focal point.
        Expanded(
          child: Container(
            height: _paneControlHeight,
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              color: _controlSurface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive
                    ? accent.withValues(alpha: _accentOutlineAlpha)
                    : _controlBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  pane.target.isLocal
                      ? Icons.storage_rounded
                      : Icons.cloud_outlined,
                  size: 16,
                  color: isActive ? accent : const Color(0xFF8B93A1),
                ),
                const SizedBox(width: 6),
                Expanded(child: _buildBreadcrumbs(pane, side, isActive: isActive)),
                IconButton(
                  tooltip: 'Type a path',
                  icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF8B93A1)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _promptChangeDirectory(pane, side),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Node selector: same height and radius as the path bar, outlined in the
        // node's accent (blue local, green SSH).
        Tooltip(
          message: 'Change source (local or SSH host)',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              if (_activePane != side) {
                setState(() => _activePane = side);
              }
              _focusNode.requestFocus();
              _selectNodeTarget(pane);
            },
            child: Container(
              height: _paneControlHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _controlSurface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: accent.withValues(alpha: _accentOutlineAlpha),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pane.target.isLocal ? Icons.storage_rounded : Icons.cloud_outlined,
                    size: 14,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _nodeSelectorLabel(pane),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE5E9F0),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF8B93A1)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // Refresh icon
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh, size: 16, color: Color(0xFFABB2BF)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: _paneControlHeight,
            minHeight: _paneControlHeight,
          ),
          style: IconButton.styleFrom(
            backgroundColor: _controlSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: _controlBorder),
            ),
          ),
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
    final sizeWidth = density == FileExplorerDensity.large ? 95.0 : 80.0;
    final modWidth = density == FileExplorerDensity.large ? 130.0 : 110.0;

    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: density.fontSize - 1,
      fontWeight: FontWeight.w600,
      color: _columnTextColor,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          SizedBox(width: 22 + density.iconSize + 6), // Spacer for Checkbox (22) + Icon + Padding (6)
          Expanded(
            child: Row(
              children: [
                Text('Name', style: style),
                const SizedBox(width: 4),
                // Listings are always sorted by name, folders first.
                const Icon(Icons.arrow_downward, size: 12, color: _columnTextColor),
              ],
            ),
          ),
          SizedBox(
            width: sizeWidth,
            child: Text('Size', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(
            width: modWidth,
            child: Text('Modified', textAlign: TextAlign.right, style: style),
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

          final isParent = item.isParentDir;
          // The cursor row in the active pane is tinted blue; in the other pane it
          // only gets a neutral lift. Multi-selection keeps its green.
          final isCursor = isFocused && isActive && !isSelected;

          Color rowBg;
          if (isSelected) {
            rowBg = const Color(0xFF22352A);
          } else if (isFocused) {
            rowBg = isActive ? const Color(0xFF1B2B40) : const Color(0xFF242932);
          } else {
            rowBg = Colors.transparent;
          }

          final textColor = isSelected
              ? const Color(0xFF98C379)
              : isCursor || isParent
                  ? _cursorAccent
                  : item.isDir
                      ? const Color(0xFFE5E9F0)
                      : const Color(0xFFD8DEE9);
          final columnColor = isSelected
              ? const Color(0xFF98C379)
              : isCursor
                  ? _cursorAccent
                  : _columnTextColor;
          final columnStyle = TextStyle(
            fontFamily: 'monospace',
            fontSize: density.fontSize - 1,
            color: columnColor,
          );

          final String sizeText;
          final String modText;
          if (isParent) {
            sizeText = '[DIR]';
            modText = '–';
          } else if (item.isDir) {
            sizeText = '[DIR]';
            modText = item.modifiedDateTime != null
                ? FileExplorerItem.formatDateTime(item.modifiedDateTime!)
                : '–';
          } else {
            sizeText = FileExplorerItem.formatSize(item.size);
            modText = item.modified;
          }

          final rowContent = Container(
            decoration: BoxDecoration(
              color: rowBg,
              border: const Border(
                bottom: BorderSide(color: Color(0xFF1F232B)),
              ),
            ),
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
                  child: isParent
                      ? Icon(Icons.arrow_upward, size: density.iconSize, color: _cursorAccent)
                      : Icon(
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
                  child: Text(sizeText, textAlign: TextAlign.right, style: columnStyle),
                ),

                // Modified
                SizedBox(
                  width: modWidth,
                  child: Text(modText, textAlign: TextAlign.right, style: columnStyle),
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

  /// Selection and item count for one pane. Without a multi-selection the cursor
  /// row counts as the selection, matching what keyboard actions operate on.
  Widget _buildPaneFooter(_PaneController pane) {
    final entries = pane.filteredItems.where((i) => !i.isParentDir).toList();
    final List<FileExplorerItem> selected;
    if (pane.multiSelected.isNotEmpty) {
      selected = entries.where((i) => pane.multiSelected.contains(i.path)).toList();
    } else {
      final idx = pane.selectedIndex;
      final cursor = idx >= 0 && idx < pane.filteredItems.length
          ? pane.filteredItems[idx]
          : null;
      selected = cursor == null || cursor.isParentDir ? const [] : [cursor];
    }
    final n = selected.length;
    final noun = n > 0 && selected.every((i) => i.isDir) ? 'folder' : 'item';
    final selectionText = '$n $noun${n == 1 ? '' : 's'} selected';
    final totalText = '${entries.length} item${entries.length == 1 ? '' : 's'} total';
    final hasSelection = n > 0;

    const textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: _columnTextColor,
    );
    return Container(
      padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2C313C))),
      ),
      child: Row(
        children: [
          Icon(
            hasSelection ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 13,
            color: hasSelection ? _cursorAccent : _columnTextColor,
          ),
          const SizedBox(width: 6),
          Text(
            selectionText,
            style: textStyle.copyWith(
              color: hasSelection ? _cursorAccent : _columnTextColor,
            ),
          ),
          const Text('  |  ', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF3E4451))),
          Expanded(
            child: Text(totalText, overflow: TextOverflow.ellipsis, style: textStyle),
          ),
          if (!pane.target.isLocal)
            Flexible(
              child: Text(
                'Server: ${pane.target.label}',
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
        ],
      ),
    );
  }

  /// Muted text for the status bar while no message is showing (4.7:1 on the
  /// bar background).
  static const Color _idleStatusColor = Color(0xFF8A919D);

  /// Idle line for [FileExplorerStatusBarStyle.detailed]: the active pane's
  /// node, item count, and selection with its size.
  String _idleStatusText(FileExplorerStatusBarStyle style) {
    if (style == FileExplorerStatusBarStyle.minimal) return _defaultStatus;
    final pane = activePaneState;
    final entries = pane.filteredItems.where((i) => !i.isParentDir).toList();
    final parts = <String>[
      pane.target.label,
      '${entries.length} item${entries.length == 1 ? '' : 's'}',
    ];
    if (pane.multiSelected.isNotEmpty) {
      final selected =
          entries.where((i) => pane.multiSelected.contains(i.path)).toList();
      final bytes = selected
          .where((i) => !i.isDir)
          .fold<int>(0, (sum, i) => sum + i.size);
      parts.add('${selected.length} selected');
      if (bytes > 0) parts.add(FileExplorerItem.formatSize(bytes));
    }
    return parts.join('  ·  ');
  }

  Widget _buildBottomStatusBar() {
    final style = SettingsService.instance.fileExplorerStatusBarStyle;
    final idle = _statusMessage == _defaultStatus;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13161C),
        border: Border(top: BorderSide(color: Color(0xFF2C313C), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // The dot is green unless the last message is an error.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _statusColor == _errorStatusColor
                  ? _errorStatusColor
                  : const Color(0xFF98C379),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              idle ? _idleStatusText(style) : _statusMessage,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                // Idle text recedes; only events (info, success, error) stand out.
                color: idle
                    ? _idleStatusColor
                    : _statusColor == _errorStatusColor ||
                          _statusColor == const Color(0xFF98C379)
                    ? _statusColor
                    : _defaultStatusColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Global controls. Only the toggle carries the accent: it is the one
          // control with a state. On = filled chip + accent icon, never color alone.
          _statusBarButton(
            tooltip: 'Toggle Dual Pane [Ctrl+d]',
            icon: _isDualPane ? Icons.view_column : Icons.view_agenda,
            selected: _isDualPane,
            onPressed: _toggleDualPane,
          ),
          _statusBarButton(
            tooltip: 'Appearance & Font Settings [Ctrl+Shift+S]',
            icon: Icons.tune_rounded,
            onPressed: _showSettingsDialog,
          ),
          _statusBarButton(
            tooltip: 'Help (Shortcuts) [F1/?]',
            icon: Icons.help_outline,
            onPressed: _showHelpDialog,
          ),
        ],
      ),
    );
  }

  Widget _statusBarButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool? selected,
  }) {
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      style: IconButton.styleFrom(
        backgroundColor:
            selected == true ? const Color(0xFF2C313C) : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      icon: Icon(
        icon,
        size: 16,
        color: selected == true ? const Color(0xFF56B6C2) : const Color(0xFFABB2BF),
      ),
      onPressed: onPressed,
    );
  }
}


/// One clickable segment of a pane's path bar.
class PathCrumb {
  const PathCrumb(this.label, this.path);
  final String label;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is PathCrumb && other.label == label && other.path == path;

  @override
  int get hashCode => Object.hash(label, path);

  @override
  String toString() => 'PathCrumb($label, $path)';
}

/// Splits [path] into cumulative segments, root first. [windowsStyle] accepts both
/// `\` and `/` and treats a leading `C:` as the root; otherwise paths are POSIX.
List<PathCrumb> splitPathCrumbs(String path, {required bool windowsStyle}) {
  const bs = '\\';
  final parts = path
      .split(windowsStyle ? RegExp('[\\\\/]') : '/')
      .where((s) => s.isNotEmpty)
      .toList();
  if (windowsStyle) {
    if (parts.isEmpty) return const [];
    final root = parts.first.endsWith(':') ? '${parts.first}$bs' : parts.first;
    final crumbs = <PathCrumb>[PathCrumb(parts.first, root)];
    var acc = root.endsWith(bs) ? root : '$root$bs';
    for (var i = 1; i < parts.length; i++) {
      acc = i == 1 ? '$acc${parts[i]}' : '$acc$bs${parts[i]}';
      crumbs.add(PathCrumb(parts[i], acc));
    }
    return crumbs;
  }
  final crumbs = <PathCrumb>[const PathCrumb('/', '/')];
  var acc = '';
  for (final part in parts) {
    acc = '$acc/$part';
    crumbs.add(PathCrumb(part, acc));
  }
  return crumbs;
}
