import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexus_fx/models/playbook_models.dart';
import 'package:nexus_fx/services/playbook_parser.dart';
import 'package:nexus_fx/services/settings_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/script_cell_widget.dart';

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

  String _resolveDirectoryPath(String configuredPath) {
    if (Directory(configuredPath).existsSync()) {
      return configuredPath;
    }
    if (configuredPath == 'nxnb' || configuredPath == 'general') {
      const fallbacks = [
        'nxnb',
        '../nxnb',
        'general',
        '../general',
        r'c:\Dev\projects\header_enrichment\smart_e_he\smart_e_he_app\general',
        r'c:\Dev\projects\header_enrichment\smart_e_he\general',
      ];
      for (final candidate in fallbacks) {
        if (Directory(candidate).existsSync()) {
          return candidate;
        }
      }
      if (configuredPath == 'nxnb') {
        try {
          final dir = Directory('nxnb');
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          return 'nxnb';
        } catch (_) {}
      }
    }
    return configuredPath;
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/');
  }

  String _extractFileName(String path) {
    final normalized = _normalizePath(path);
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.last : path;
  }

  String _extractExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0) return '';
    return fileName.substring(dotIndex).toLowerCase();
  }

  void _loadFiles() {
    final rootDir = Directory(_resolvedDirPath);
    if (!rootDir.existsSync()) {
      if (mounted) {
        setState(() {
          _treeNodes = [];
        });
      }
      return;
    }

    final nodes = <_FileTreeNode>[];

    void scanDirectory(Directory dir, int depth) {
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync();
      } catch (_) {
        return;
      }

      final subDirs = <Directory>[];
      final files = <File>[];

      for (final e in entries) {
        if (e is Directory) {
          subDirs.add(e);
        } else if (e is File) {
          final name = _extractFileName(e.path);
          final ext = _extractExtension(name);
          if (_supportedExtensions.contains(ext)) {
            files.add(e);
          }
        }
      }

      subDirs.sort(
        (a, b) => _extractFileName(
          a.path,
        ).toLowerCase().compareTo(_extractFileName(b.path).toLowerCase()),
      );

      files.sort(
        (a, b) => _extractFileName(
          a.path,
        ).toLowerCase().compareTo(_extractFileName(b.path).toLowerCase()),
      );

      for (final subDir in subDirs) {
        final normPath = _normalizePath(subDir.path);
        final isExpanded = _expandedFolders.contains(normPath);
        nodes.add(
          _FileTreeNode(
            entity: subDir,
            path: subDir.path,
            name: _extractFileName(subDir.path),
            depth: depth,
            isDirectory: true,
            isExpanded: isExpanded,
          ),
        );
        if (isExpanded) {
          scanDirectory(subDir, depth + 1);
        }
      }

      for (final file in files) {
        nodes.add(
          _FileTreeNode(
            entity: file,
            path: file.path,
            name: _extractFileName(file.path),
            depth: depth,
            isDirectory: false,
          ),
        );
      }
    }

    scanDirectory(rootDir, 0);

    if (mounted) {
      setState(() {
        _treeNodes = nodes;
      });
    }
  }

  void _collapseAllFolders() {
    _expandedFolders.clear();
    _selectedFolderPath = _resolvedDirPath;
    _selectedFilePath = null;
    _loadFiles();
  }

  void _toggleFolder(_FileTreeNode node) {
    final normPath = _normalizePath(node.path);
    if (_expandedFolders.contains(normPath)) {
      _expandedFolders.remove(normPath);
    } else {
      _expandedFolders.add(normPath);
    }
    _selectedFolderPath = node.path;
    _selectedFilePath = null;
    _loadFiles();
  }

  String _targetCreationDirectory() {
    if (_selectedFolderPath != null &&
        Directory(_selectedFolderPath!).existsSync()) {
      return _selectedFolderPath!;
    }
    if (_selectedFilePath != null) {
      final parentDir = File(_selectedFilePath!).parent;
      if (parentDir.existsSync()) {
        return parentDir.path;
      }
    }
    return _resolvedDirPath;
  }

  bool get _canDeleteSelection {
    if (_selectedFilePath != null) {
      return File(_selectedFilePath!).existsSync();
    }
    if (_selectedFolderPath != null) {
      final normSelected = _normalizePath(_selectedFolderPath!);
      final normRoot = _normalizePath(_resolvedDirPath);
      return normSelected != normRoot &&
          Directory(_selectedFolderPath!).existsSync();
    }
    return false;
  }

  void _deleteCurrentSelection() {
    if (_selectedFilePath != null) {
      _confirmAndDeleteFile(_selectedFilePath!);
    } else if (_selectedFolderPath != null && _canDeleteSelection) {
      _confirmAndDeleteFolder(_selectedFolderPath!);
    }
  }

  Future<void> _confirmAndDeleteFile(String filePath) async {
    final fileName = _extractFileName(filePath);
    final palette = AppTheme.activePalette;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.surfaceColor,
          title: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                color: palette.errorColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Delete File',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: palette.errorColor,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete "$fileName"?',
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 12,
              color: palette.textColor,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Courier',
                  color: palette.textColor,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.errorColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
      final normPath = _normalizePath(filePath);
      final openIdx = _openTabs.indexWhere(
        (t) => _normalizePath(t.filePath) == normPath,
      );
      if (openIdx != -1) {
        _closeTab(openIdx);
      }
      if (_selectedFilePath != null &&
          _normalizePath(_selectedFilePath!) == normPath) {
        setState(() {
          _selectedFilePath = null;
        });
      }
      _loadFiles();
    } catch (_) {}
  }

  Future<void> _confirmAndDeleteFolder(String folderPath) async {
    final folderName = _extractFileName(folderPath);
    final palette = AppTheme.activePalette;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.surfaceColor,
          title: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                color: palette.errorColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Delete Folder',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: palette.errorColor,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete folder "$folderName" and all its contents?',
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 12,
              color: palette.textColor,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Courier',
                  color: palette.textColor,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.errorColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Delete',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final dir = Directory(folderPath);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      final normDir = _normalizePath(folderPath);
      final prefix = normDir.endsWith('/') ? normDir : '$normDir/';
      _openTabs.removeWhere((t) {
        final normTab = _normalizePath(t.filePath);
        return normTab.startsWith(prefix) || normTab == normDir;
      });
      if (_openTabs.isEmpty) {
        _activeTabIndex = 0;
      } else if (_activeTabIndex > _openTabs.length) {
        _activeTabIndex = _openTabs.length;
      }
      setState(() {
        _expandedFolders.remove(normDir);
        _selectedFolderPath = _resolvedDirPath;
        _selectedFilePath = null;
      });
      _loadFiles();
    } catch (_) {}
  }

  Future<void> _promptCreateNewFile() async {
    final palette = AppTheme.activePalette;
    final controller = TextEditingController();
    final targetDir = _targetCreationDirectory();

    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.surfaceColor,
          title: Text(
            'New Nexus Notebook',
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: palette.primaryColor,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location: $targetDir',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  color: palette.textColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('runbook_new_file_input'),
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  color: palette.textColor,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. checklist',
                  hintStyle: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    color: palette.textColor.withValues(alpha: 0.4),
                  ),
                  suffixText: '.nxnb',
                  suffixStyle: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 13,
                    color: palette.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.inputBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.primaryColor),
                  ),
                ),
                onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Courier',
                  color: palette.textColor,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primaryColor,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text(
                'Create',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (createdName == null || createdName.isEmpty) return;

    var baseName = createdName.trim();
    if (baseName.toLowerCase().endsWith('.nxnb')) {
      baseName = baseName.substring(0, baseName.length - 5);
    }
    for (final supportedExt in _supportedExtensions) {
      if (baseName.toLowerCase().endsWith(supportedExt)) {
        baseName = baseName.substring(0, baseName.length - supportedExt.length);
        break;
      }
    }
    if (baseName.isEmpty) return;
    final finalName = '$baseName.nxnb';

    try {
      final dir = Directory(targetDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final newFile = File('${dir.path}${Platform.pathSeparator}$finalName');
      if (!newFile.existsSync()) {
        newFile.writeAsStringSync('# $baseName\n');
      }
      _expandedFolders.add(_normalizePath(targetDir));
      _loadFiles();
      _openFileInTab(newFile);
    } catch (_) {
      // Ignore creation errors
    }
  }

  Future<void> _promptCreateNewFolder() async {
    final palette = AppTheme.activePalette;
    final controller = TextEditingController();
    final targetDir = _targetCreationDirectory();

    final folderName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.surfaceColor,
          title: Text(
            'New Folder',
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: palette.primaryColor,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location: $targetDir',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  color: palette.textColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('runbook_new_folder_input'),
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  color: palette.textColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Folder name',
                  hintStyle: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    color: palette.textColor.withValues(alpha: 0.4),
                  ),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.inputBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.primaryColor),
                  ),
                ),
                onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Courier',
                  color: palette.textColor,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primaryColor,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text(
                'Create',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (folderName == null || folderName.isEmpty) return;

    try {
      final newDir = Directory(
        '$targetDir${Platform.pathSeparator}$folderName',
      );
      if (!newDir.existsSync()) {
        newDir.createSync(recursive: true);
      }
      _expandedFolders.add(_normalizePath(targetDir));
      _selectedFolderPath = newDir.path;
      _loadFiles();
    } catch (_) {
      // Ignore folder creation errors
    }
  }

  bool get _canOperateOnSelection {
    if (_selectedFilePath != null) {
      return File(_selectedFilePath!).existsSync();
    }
    if (_selectedFolderPath != null) {
      final normSelected = _normalizePath(_selectedFolderPath!);
      final normRoot = _normalizePath(_resolvedDirPath);
      return normSelected != normRoot &&
          Directory(_selectedFolderPath!).existsSync();
    }
    return false;
  }

  bool get _canPaste {
    if (_clipboardPath == null) return false;
    return File(_clipboardPath!).existsSync() ||
        Directory(_clipboardPath!).existsSync();
  }

  void _cutSelection() {
    if (!_canOperateOnSelection) return;
    setState(() {
      _clipboardPath = _selectedFilePath ?? _selectedFolderPath;
      _isCutOperation = true;
    });
  }

  void _copySelection() {
    if (!_canOperateOnSelection) return;
    setState(() {
      _clipboardPath = _selectedFilePath ?? _selectedFolderPath;
      _isCutOperation = false;
    });
  }

  void _pasteSelection() {
    if (!_canPaste) return;
    final sourcePath = _clipboardPath!;
    final isCut = _isCutOperation;
    final isSourceDir = Directory(sourcePath).existsSync();
    final isSourceFile = File(sourcePath).existsSync();
    if (!isSourceDir && !isSourceFile) return;

    final targetDir = _targetCreationDirectory();
    final sourceName = _extractFileName(sourcePath);

    if (isSourceDir) {
      final normSource = _normalizePath(sourcePath);
      final normTarget = _normalizePath(targetDir);
      if (normTarget == normSource || normTarget.startsWith('$normSource/')) {
        return;
      }

      String destDirName = sourceName;
      String destPath = '$targetDir${Platform.pathSeparator}$destDirName';

      if (isCut) {
        if (_normalizePath(Directory(sourcePath).parent.path) == normTarget) {
          setState(() {
            _clipboardPath = null;
            _isCutOperation = false;
          });
          return;
        }
        try {
          Directory(sourcePath).renameSync(destPath);
          _updateOpenTabsAfterMoveOrRename(sourcePath, destPath, true);
          setState(() {
            _clipboardPath = null;
            _isCutOperation = false;
            _selectedFolderPath = destPath;
            _selectedFilePath = null;
          });
          _loadFiles();
        } catch (_) {}
      } else {
        if (Directory(destPath).existsSync()) {
          destDirName = '${sourceName}_copy';
          destPath = '$targetDir${Platform.pathSeparator}$destDirName';
          int copyIdx = 2;
          while (Directory(destPath).existsSync()) {
            destDirName = '${sourceName}_copy_$copyIdx';
            destPath = '$targetDir${Platform.pathSeparator}$destDirName';
            copyIdx++;
          }
        }
        try {
          _copyDirectoryRecursively(Directory(sourcePath), Directory(destPath));
          setState(() {
            _selectedFolderPath = destPath;
            _selectedFilePath = null;
          });
          _loadFiles();
        } catch (_) {}
      }
    } else {
      final ext = _extractExtension(sourceName);
      final baseName = ext.isNotEmpty && sourceName.endsWith(ext)
          ? sourceName.substring(0, sourceName.length - ext.length)
          : sourceName;

      String destFileName = sourceName;
      String destPath = '$targetDir${Platform.pathSeparator}$destFileName';

      if (isCut) {
        final sourceParent = File(sourcePath).parent.path;
        if (_normalizePath(sourceParent) == _normalizePath(targetDir)) {
          setState(() {
            _clipboardPath = null;
            _isCutOperation = false;
          });
          return;
        }
        try {
          File(sourcePath).renameSync(destPath);
          _updateOpenTabsAfterMoveOrRename(sourcePath, destPath, false);
          setState(() {
            _clipboardPath = null;
            _isCutOperation = false;
            _selectedFilePath = destPath;
            _selectedFolderPath = null;
          });
          _loadFiles();
        } catch (_) {}
      } else {
        if (File(destPath).existsSync()) {
          destFileName = '${baseName}_copy$ext';
          destPath = '$targetDir${Platform.pathSeparator}$destFileName';
          int copyIdx = 2;
          while (File(destPath).existsSync()) {
            destFileName = '${baseName}_copy_$copyIdx$ext';
            destPath = '$targetDir${Platform.pathSeparator}$destFileName';
            copyIdx++;
          }
        }
        try {
          File(sourcePath).copySync(destPath);
          setState(() {
            _selectedFilePath = destPath;
            _selectedFolderPath = null;
          });
          _loadFiles();
        } catch (_) {}
      }
    }
  }

  void _copyDirectoryRecursively(Directory src, Directory dst) {
    if (!dst.existsSync()) {
      dst.createSync(recursive: true);
    }
    for (final entity in src.listSync(recursive: false)) {
      final name = _extractFileName(entity.path);
      final destPath = '${dst.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        _copyDirectoryRecursively(entity, Directory(destPath));
      } else if (entity is File) {
        entity.copySync(destPath);
      }
    }
  }

  void _updateOpenTabsAfterMoveOrRename(
    String oldPath,
    String newPath,
    bool isDir,
  ) {
    if (!isDir) {
      final normOld = _normalizePath(oldPath);
      for (int i = 0; i < _openTabs.length; i++) {
        if (_normalizePath(_openTabs[i].filePath) == normOld) {
          final newName = _extractFileName(newPath);
          final updatedDoc = _openTabs[i].document?.copyWith(
            filePath: newPath,
            title: newName,
          );
          _openTabs[i] = _OpenRunbookTab(
            filePath: newPath,
            fileName: newName,
            document: updatedDoc,
            errorMessage: _openTabs[i].errorMessage,
          );
        }
      }
    } else {
      final normOld = _normalizePath(oldPath);
      final prefix = normOld.endsWith('/') ? normOld : '$normOld/';
      final normNew = _normalizePath(newPath);
      for (int i = 0; i < _openTabs.length; i++) {
        final normTab = _normalizePath(_openTabs[i].filePath);
        if (normTab.startsWith(prefix)) {
          final relative = normTab.substring(prefix.length);
          final newTabPath = '$normNew/$relative';
          final newName = _extractFileName(newTabPath);
          final updatedDoc = _openTabs[i].document?.copyWith(
            filePath: newTabPath,
            title: newName,
          );
          _openTabs[i] = _OpenRunbookTab(
            filePath: newTabPath,
            fileName: newName,
            document: updatedDoc,
            errorMessage: _openTabs[i].errorMessage,
          );
        }
      }
    }
  }

  Future<void> _promptRenameSelection() async {
    if (!_canOperateOnSelection) return;
    final isDir = _selectedFolderPath != null;
    final currentPath = isDir ? _selectedFolderPath! : _selectedFilePath!;
    final currentName = _extractFileName(currentPath);
    final ext = isDir ? '' : _extractExtension(currentName);
    final baseName = !isDir && ext.isNotEmpty && currentName.endsWith(ext)
        ? currentName.substring(0, currentName.length - ext.length)
        : currentName;

    final palette = AppTheme.activePalette;
    final controller = TextEditingController(
      text: isDir ? currentName : baseName,
    );

    final newNameInput = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.surfaceColor,
          title: Row(
            children: [
              Icon(
                Icons.drive_file_rename_outline_rounded,
                color: palette.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isDir ? 'Rename Folder' : 'Rename File',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: palette.primaryColor,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: $currentName',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  color: palette.textColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('runbook_rename_input'),
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  color: palette.textColor,
                ),
                decoration: InputDecoration(
                  hintText: 'New name',
                  hintStyle: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    color: palette.textColor.withValues(alpha: 0.4),
                  ),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.inputBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.primaryColor),
                  ),
                ),
                onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Courier',
                  color: palette.textColor,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.primaryColor,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text(
                'Rename',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (newNameInput == null || newNameInput.isEmpty) return;

    String finalName = newNameInput;
    if (!isDir) {
      final inputExt = _extractExtension(newNameInput);
      if (inputExt.isEmpty && ext.isNotEmpty) {
        finalName = '$newNameInput$ext';
      }
    }

    final parentDir = isDir
        ? Directory(currentPath).parent.path
        : File(currentPath).parent.path;
    final newPath = '$parentDir${Platform.pathSeparator}$finalName';

    if (_normalizePath(currentPath) == _normalizePath(newPath)) return;

    try {
      if (isDir) {
        Directory(currentPath).renameSync(newPath);
        _updateOpenTabsAfterMoveOrRename(currentPath, newPath, true);
        setState(() {
          _selectedFolderPath = newPath;
          _selectedFilePath = null;
        });
      } else {
        File(currentPath).renameSync(newPath);
        _updateOpenTabsAfterMoveOrRename(currentPath, newPath, false);
        setState(() {
          _selectedFilePath = newPath;
          _selectedFolderPath = null;
        });
      }
      _loadFiles();
    } catch (_) {}
  }

  Future<void> _showContextMenuForNode(
    BuildContext context,
    TapDownDetails details,
    _FileTreeNode node,
  ) async {
    final palette = AppTheme.activePalette;
    setState(() {
      if (node.isDirectory) {
        _selectedFolderPath = node.path;
        _selectedFilePath = null;
      } else {
        _selectedFilePath = node.path;
        _selectedFolderPath = null;
      }
    });

    final position = details.globalPosition;
    final isDir = node.isDirectory;
    final canOperate = _canOperateOnSelection;
    final canPasteNow = _canPaste;

    final selectedAction = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (!isDir)
          PopupMenuItem(
            value: 'open',
            child: Row(
              children: [
                Icon(
                  Icons.file_open_outlined,
                  size: 16,
                  color: palette.textColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Open',
                  style: TextStyle(fontFamily: 'Courier', fontSize: 12),
                ),
              ],
            ),
          ),
        if (canOperate) ...[
          PopupMenuItem(
            value: 'cut',
            child: Row(
              children: [
                Icon(
                  Icons.content_cut_rounded,
                  size: 16,
                  color: palette.textColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Cut (Ctrl+X)',
                  style: TextStyle(fontFamily: 'Courier', fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'copy',
            child: Row(
              children: [
                Icon(
                  Icons.content_copy_rounded,
                  size: 16,
                  color: palette.textColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Copy (Ctrl+C)',
                  style: TextStyle(fontFamily: 'Courier', fontSize: 12),
                ),
              ],
            ),
          ),
        ],
        if (canPasteNow)
          PopupMenuItem(
            value: 'paste',
            child: Row(
              children: [
                Icon(
                  Icons.content_paste_rounded,
                  size: 16,
                  color: palette.textColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Paste (Ctrl+V)',
                  style: TextStyle(fontFamily: 'Courier', fontSize: 12),
                ),
              ],
            ),
          ),
        if (canOperate)
          PopupMenuItem(
            value: 'rename',
            child: Row(
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: palette.textColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Rename (F2)',
                  style: TextStyle(fontFamily: 'Courier', fontSize: 12),
                ),
              ],
            ),
          ),
        if (_canDeleteSelection) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: palette.errorColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Delete',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    color: palette.errorColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (selectedAction == 'open' && !isDir && node.entity is File) {
      _openFileInTab(node.entity as File);
    } else if (selectedAction == 'cut') {
      _cutSelection();
    } else if (selectedAction == 'copy') {
      _copySelection();
    } else if (selectedAction == 'paste') {
      _pasteSelection();
    } else if (selectedAction == 'rename') {
      _promptRenameSelection();
    } else if (selectedAction == 'delete') {
      _deleteCurrentSelection();
    }
  }

  Future<void> _showContextMenuForBackground(
    BuildContext context,
    TapDownDetails details,
  ) async {
    final palette = AppTheme.activePalette;
    final position = details.globalPosition;
    final canPasteNow = _canPaste;

    final selectedAction = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'new_file',
          child: Row(
            children: [
              Icon(Icons.note_add_outlined, size: 16, color: palette.textColor),
              const SizedBox(width: 8),
              const Text(
                'New File',
                style: TextStyle(fontFamily: 'Courier', fontSize: 12),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'new_folder',
          child: Row(
            children: [
              Icon(
                Icons.create_new_folder_outlined,
                size: 16,
                color: palette.textColor,
              ),
              const SizedBox(width: 8),
              const Text(
                'New Folder',
                style: TextStyle(fontFamily: 'Courier', fontSize: 12),
              ),
            ],
          ),
        ),
        if (canPasteNow)
          PopupMenuItem(
            value: 'paste',
            child: Row(
              children: [
                Icon(
                  Icons.content_paste_rounded,
                  size: 16,
                  color: palette.textColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Paste (Ctrl+V)',
                  style: TextStyle(fontFamily: 'Courier', fontSize: 12),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 16, color: palette.textColor),
              const SizedBox(width: 8),
              const Text(
                'Refresh',
                style: TextStyle(fontFamily: 'Courier', fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );

    if (selectedAction == 'new_file') {
      _promptCreateNewFile();
    } else if (selectedAction == 'new_folder') {
      _promptCreateNewFolder();
    } else if (selectedAction == 'paste') {
      _pasteSelection();
    } else if (selectedAction == 'refresh') {
      _loadFiles();
    }
  }

  int get _selectedNodeIndex {
    if (_treeNodes.isEmpty) return -1;
    if (_selectedFilePath != null) {
      final norm = _normalizePath(_selectedFilePath!);
      final idx = _treeNodes.indexWhere(
        (n) => !n.isDirectory && _normalizePath(n.path) == norm,
      );
      if (idx != -1) return idx;
    }
    if (_selectedFolderPath != null) {
      final norm = _normalizePath(_selectedFolderPath!);
      final normRoot = _normalizePath(_resolvedDirPath);
      if (norm != normRoot) {
        final idx = _treeNodes.indexWhere(
          (n) => n.isDirectory && _normalizePath(n.path) == norm,
        );
        if (idx != -1) return idx;
      }
    }
    return -1;
  }

  void _selectNodeAtIndex(int index) {
    if (index < 0 || index >= _treeNodes.length) return;
    final node = _treeNodes[index];
    setState(() {
      if (node.isDirectory) {
        _selectedFolderPath = node.path;
        _selectedFilePath = null;
      } else {
        _selectedFilePath = node.path;
        _selectedFolderPath = null;
      }
    });
    _scrollToTreeNodeIndex(index);
  }

  void _scrollToTreeNodeIndex(int index) {
    if (!_filesScrollController.hasClients || index < 0 || index >= _treeNodes.length) return;
    const estimatedItemHeight = 32.0;
    final targetTop = index * estimatedItemHeight;
    final targetBottom = targetTop + estimatedItemHeight;
    final currentOffset = _filesScrollController.offset;
    final viewportHeight = _filesScrollController.position.viewportDimension;
    if (viewportHeight <= 0) return;
    if (targetTop < currentOffset) {
      _filesScrollController.animateTo(
        targetTop.clamp(0.0, _filesScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (targetBottom > currentOffset + viewportHeight) {
      final newOffset = targetBottom - viewportHeight;
      _filesScrollController.animateTo(
        newOffset.clamp(0.0, _filesScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _moveCursorInTree(int delta) {
    if (_treeNodes.isEmpty) return;
    final currentIdx = _selectedNodeIndex;
    int targetIdx;
    if (currentIdx == -1) {
      targetIdx = delta > 0 ? 0 : _treeNodes.length - 1;
    } else {
      targetIdx = (currentIdx + delta).clamp(0, _treeNodes.length - 1);
    }
    _selectNodeAtIndex(targetIdx);
  }

  void _jumpTreeTo(int index) {
    if (_treeNodes.isEmpty) return;
    final targetIdx = index.clamp(0, _treeNodes.length - 1);
    _selectNodeAtIndex(targetIdx);
  }

  void _navigateTreeLeft() {
    if (_treeNodes.isEmpty) return;
    final currentIdx = _selectedNodeIndex;
    if (currentIdx == -1) {
      _selectNodeAtIndex(0);
      return;
    }
    final node = _treeNodes[currentIdx];
    if (node.isDirectory && node.isExpanded) {
      _toggleFolder(node);
    } else if (node.depth > 0) {
      for (int i = currentIdx - 1; i >= 0; i--) {
        final candidate = _treeNodes[i];
        if (candidate.isDirectory && candidate.depth == node.depth - 1) {
          _selectNodeAtIndex(i);
          break;
        }
      }
    }
  }

  void _navigateTreeRight() {
    if (_treeNodes.isEmpty) return;
    final currentIdx = _selectedNodeIndex;
    if (currentIdx == -1) {
      _selectNodeAtIndex(0);
      return;
    }
    final node = _treeNodes[currentIdx];
    if (node.isDirectory) {
      if (!node.isExpanded) {
        _toggleFolder(node);
      } else if (currentIdx + 1 < _treeNodes.length &&
          _treeNodes[currentIdx + 1].depth > node.depth) {
        _selectNodeAtIndex(currentIdx + 1);
      }
    } else {
      _openSelectedFile();
    }
  }

  void _openSelectedFile() {
    final currentIdx = _selectedNodeIndex;
    if (currentIdx >= 0 && currentIdx < _treeNodes.length) {
      final node = _treeNodes[currentIdx];
      if (node.isDirectory) {
        _toggleFolder(node);
      } else {
        final file = File(node.path);
        if (file.existsSync()) {
          _openFileInTab(file);
        }
      }
      return;
    }
    if (_selectedFilePath != null) {
      final file = File(_selectedFilePath!);
      if (file.existsSync()) {
        _openFileInTab(file);
      }
    } else if (_selectedFolderPath != null) {
      final match = _treeNodes.where(
        (n) =>
            n.isDirectory &&
            _normalizePath(n.path) == _normalizePath(_selectedFolderPath!),
      );
      if (match.isNotEmpty) {
        _toggleFolder(match.first);
      }
    }
  }

  KeyEventResult _handleFilesKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
    final isAlt = HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altRight);
    final isShift = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);

    if (isCtrl || isAlt) return KeyEventResult.ignored;

    // j / ArrowDown -> Navigate down
    if (event.logicalKey == LogicalKeyboardKey.keyJ ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveCursorInTree(1);
      return KeyEventResult.handled;
    }

    // k / ArrowUp -> Navigate up
    if (event.logicalKey == LogicalKeyboardKey.keyK ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveCursorInTree(-1);
      return KeyEventResult.handled;
    }

    // h / ArrowLeft -> Collapse folder or navigate to parent
    if (event.logicalKey == LogicalKeyboardKey.keyH ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _navigateTreeLeft();
      return KeyEventResult.handled;
    }

    // l / ArrowRight -> Expand folder, enter child, or open file
    if (event.logicalKey == LogicalKeyboardKey.keyL ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _navigateTreeRight();
      return KeyEventResult.handled;
    }

    // Enter / NumpadEnter -> Toggle folder or open file
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_lastTabClosedByVimTime != null &&
          DateTime.now().difference(_lastTabClosedByVimTime!).inMilliseconds < 500) {
        _lastTabClosedByVimTime = null;
        return KeyEventResult.handled;
      }
      _openSelectedFile();
      return KeyEventResult.handled;
    }

    // a -> New File / A -> New Folder
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      if (isShift) {
        _promptCreateNewFolder();
      } else {
        _promptCreateNewFile();
      }
      return KeyEventResult.handled;
    }

    // r -> Rename
    if (event.logicalKey == LogicalKeyboardKey.keyR && !isShift) {
      if (_canOperateOnSelection) {
        _promptRenameSelection();
      }
      return KeyEventResult.handled;
    }

    // d -> Delete
    if (event.logicalKey == LogicalKeyboardKey.keyD && !isShift) {
      if (_canDeleteSelection) {
        _deleteCurrentSelection();
      }
      return KeyEventResult.handled;
    }

    // Home -> Jump to first item
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _jumpTreeTo(0);
      return KeyEventResult.handled;
    }

    // End -> Jump to last item
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _jumpTreeTo(_treeNodes.length - 1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _selectNextSidebarTab() {
    final totalTabs = 1 + _openTabs.length;
    if (totalTabs <= 1) return;
    _vimCommandTimer?.cancel();
    setState(() {
      _vimCommand = '';
      _activeTabIndex = (_activeTabIndex + 1) % totalTabs;
      _recomputeSearchMatches();
    });
    _focusActiveTabContent();
  }

  void _selectPreviousSidebarTab() {
    final totalTabs = 1 + _openTabs.length;
    if (totalTabs <= 1) return;
    _vimCommandTimer?.cancel();
    setState(() {
      _vimCommand = '';
      _activeTabIndex = (_activeTabIndex - 1 + totalTabs) % totalTabs;
      _recomputeSearchMatches();
    });
    _focusActiveTabContent();
  }

  void _closeActiveSidebarTab() {
    if (_activeTabIndex > 0 && _activeTabIndex <= _openTabs.length) {
      _closeTab(_activeTabIndex - 1);
      _focusActiveTabContent();
    }
  }

  void _focusActiveTabContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_activeTabIndex == 0) {
        _sidebarFocusNode.requestFocus();
      } else {
        _docFocusNode.requestFocus();
      }
    });
  }

  void _openFileInTab(File file) {
    final filePath = file.path;
    final existingIdx = _openTabs.indexWhere((t) => t.filePath == filePath);
    if (existingIdx != -1) {
      setState(() {
        _activeTabIndex = existingIdx + 1;
        _recomputeSearchMatches();
      });
      _focusActiveTabContent();
      return;
    }

    final fileName = _extractFileName(filePath);
    final ext = _extractExtension(fileName);

    try {
      PlaybookDocument doc;
      if (ext == '.docx') {
        final bytes = file.readAsBytesSync();
        doc = PlaybookParser.parseDocx(filePath, bytes);
      } else if (ext == '.nxnb' || ext == '.md' || ext == '.markdown') {
        final content = file.readAsStringSync();
        doc = PlaybookParser.parseMarkdown(filePath, content);
      } else {
        final content = file.readAsStringSync();
        doc = PlaybookParser.parseScript(filePath, content);
      }

      setState(() {
        _openTabs.add(
          _OpenRunbookTab(
            filePath: filePath,
            fileName: fileName,
            document: doc,
          ),
        );
        _activeTabIndex = _openTabs.length;
        _recomputeSearchMatches();
      });
      _focusActiveTabContent();
    } catch (e) {
      setState(() {
        _openTabs.add(
          _OpenRunbookTab(
            filePath: filePath,
            fileName: fileName,
            errorMessage: 'Failed to load $fileName: $e',
          ),
        );
        _activeTabIndex = _openTabs.length;
      });
    }
  }

  void _closeTab(int openTabIndex) {
    if (openTabIndex < 0 || openTabIndex >= _openTabs.length) return;
    _vimCommandTimer?.cancel();
    setState(() {
      _vimCommand = '';
      _openTabs.removeAt(openTabIndex);
      if (_openTabs.isEmpty) {
        _activeTabIndex = 0;
      } else if (_activeTabIndex == openTabIndex + 1) {
        _activeTabIndex = 0;
      } else if (_activeTabIndex > openTabIndex + 1) {
        _activeTabIndex -= 1;
      }
      _recomputeSearchMatches();
    });
  }

  _OpenRunbookTab? get _activeOpenTab {
    if (_activeTabIndex <= 0 || _activeTabIndex > _openTabs.length) {
      return null;
    }
    return _openTabs[_activeTabIndex - 1];
  }

  void _openFindBar() {
    setState(() {
      _isFindBarOpen = true;
    });
    _recomputeSearchMatches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _findFocusNode.requestFocus();
      }
    });
  }

  void _closeFindBar() {
    setState(() {
      _isFindBarOpen = false;
      _searchQuery = '';
      _findController.clear();
      _searchMatches = [];
      _currentMatchIndex = 0;
    });
  }

  void _onFindQueryChanged() {
    final query = _findController.text;
    if (query == _searchQuery) return;
    setState(() {
      _searchQuery = query;
      _currentMatchIndex = 0;
      _recomputeSearchMatches();
    });
    _scrollToActiveMatch();
  }

  void _recomputeSearchMatches() {
    final tab = _activeOpenTab;
    final doc = tab?.document;
    final query = _searchQuery.trim();
    if (!_isFindBarOpen || doc == null || query.isEmpty) {
      _searchMatches = [];
      _currentMatchIndex = 0;
      return;
    }

    final lowerQuery = query.toLowerCase();
    final matches = <_SearchMatchLocation>[];

    for (int bIdx = 0; bIdx < doc.blocks.length; bIdx++) {
      final blockText = doc.blocks[bIdx].content.toLowerCase();
      int start = 0;
      int localMatchIdx = 0;
      while (true) {
        final found = blockText.indexOf(lowerQuery, start);
        if (found < 0) break;
        matches.add(
          _SearchMatchLocation(
            blockIndex: bIdx,
            matchIndexInBlock: localMatchIdx,
          ),
        );
        start = found + lowerQuery.length;
        localMatchIdx++;
      }
    }

    _searchMatches = matches;
    if (_searchMatches.isEmpty) {
      _currentMatchIndex = 0;
    } else if (_currentMatchIndex >= _searchMatches.length) {
      _currentMatchIndex = 0;
    }
  }

  void _nextSearchMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _searchMatches.length;
    });
    _scrollToActiveMatch();
  }

  void _prevSearchMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _searchMatches.length) %
          _searchMatches.length;
    });
    _scrollToActiveMatch();
  }

  void _scrollToActiveMatch() {
    if (_searchMatches.isEmpty) return;
    final tab = _activeOpenTab;
    final doc = tab?.document;
    if (doc == null) return;

    final match = _searchMatches[_currentMatchIndex];
    if (match.blockIndex < 0 || match.blockIndex >= doc.blocks.length) return;
    final block = doc.blocks[match.blockIndex];
    final key = _blockKeys['${doc.filePath}_${block.id}'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          alignment: 0.3,
        );
      }
    });
  }

  void _scrollToDocumentBlock(PlaybookDocument doc, PlaybookBlock block) {
    final key = _blockKeys['${doc.filePath}_${block.id}'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 150),
          alignment: 0.3,
        );
      }
    });
  }

  void _moveDocumentBlockSelection(PlaybookDocument doc, int delta) {
    if (doc.blocks.isEmpty) return;
    final currentId = _selectedBlockId ?? _lastSelectedBlockId;
    int currentIdx = currentId != null
        ? doc.blocks.indexWhere((b) => b.id == currentId)
        : -1;
    int targetIdx;
    if (currentIdx == -1) {
      if (delta > 0) {
        final firstScriptIdx = doc.blocks.indexWhere(
          (b) => b.type == PlaybookBlockType.scriptCell,
        );
        targetIdx = firstScriptIdx != -1 ? firstScriptIdx : 0;
      } else {
        targetIdx = doc.blocks.length - 1;
      }
    } else {
      targetIdx = (currentIdx + delta).clamp(0, doc.blocks.length - 1);
    }
    final targetBlock = doc.blocks[targetIdx];
    setState(() {
      _selectedBlockId = targetBlock.id;
      _lastSelectedBlockId = targetBlock.id;
    });
    _scrollToDocumentBlock(doc, targetBlock);
  }

  void _enterEditModeOnSelectedBlock(PlaybookDocument doc) {
    if (doc.blocks.isEmpty) return;
    final targetId = _selectedBlockId ?? _lastSelectedBlockId;
    PlaybookBlock targetBlock;
    if (targetId != null) {
      targetBlock = doc.blocks.firstWhere(
        (b) => b.id == targetId,
        orElse: () => doc.blocks.first,
      );
    } else {
      targetBlock = doc.blocks.firstWhere(
        (b) => b.type == PlaybookBlockType.scriptCell,
        orElse: () => doc.blocks.first,
      );
    }
    setState(() {
      _selectedBlockId = targetBlock.id;
      _lastSelectedBlockId = targetBlock.id;
    });
    _scrollToDocumentBlock(doc, targetBlock);
    final keyStr = '${doc.filePath}_${targetBlock.id}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (targetBlock.type == PlaybookBlockType.scriptCell) {
        _scriptCellKeys[keyStr]?.currentState?.requestEditorFocus();
      } else {
        _textBlockKeys[keyStr]?.currentState?.requestEditorFocus();
      }
    });
  }

  void _insertBlockRelativeToSelection(
    PlaybookDocument doc,
    PlaybookBlockType type, {
    required bool above,
    bool enterEditMode = false,
  }) {
    if (doc.blocks.isEmpty) {
      _addBlockToDocument(doc, type, atIndex: 0);
      if (enterEditMode && doc.blocks.isNotEmpty) {
        _enterEditModeOnSelectedBlock(doc);
      }
      return;
    }

    final currentId = _selectedBlockId ?? _lastSelectedBlockId;
    int currentIdx = currentId != null
        ? doc.blocks.indexWhere((b) => b.id == currentId)
        : -1;

    if (currentIdx == -1) {
      currentIdx = above ? 0 : doc.blocks.length - 1;
    }

    final insertIdx = above ? currentIdx : currentIdx + 1;
    _addBlockToDocument(doc, type, atIndex: insertIdx);

    final newBlock = doc.blocks[insertIdx];
    _scrollToDocumentBlock(doc, newBlock);

    if (enterEditMode) {
      _enterEditModeOnSelectedBlock(doc);
    }
  }

  void _executeActiveOrFirstScriptCell() {
    final tab = _activeOpenTab;
    final doc = tab?.document;
    if (doc == null || doc.blocks.isEmpty) return;

    PlaybookBlock? targetBlock;
    final candidateId = _selectedBlockId ?? _lastSelectedBlockId;
    if (candidateId != null) {
      final idx = doc.blocks.indexWhere((b) => b.id == candidateId);
      if (idx != -1) {
        if (doc.blocks[idx].type == PlaybookBlockType.scriptCell) {
          targetBlock = doc.blocks[idx];
        } else {
          for (int i = idx + 1; i < doc.blocks.length; i++) {
            if (doc.blocks[i].type == PlaybookBlockType.scriptCell) {
              targetBlock = doc.blocks[i];
              break;
            }
          }
        }
      }
    }

    targetBlock ??= doc.blocks
        .cast<PlaybookBlock?>()
        .firstWhere(
          (b) => b?.type == PlaybookBlockType.scriptCell,
          orElse: () => null,
        );

    if (targetBlock == null) return;

    setState(() {
      _selectedBlockId = targetBlock!.id;
      _lastSelectedBlockId = targetBlock.id;
    });

    final cellKey = _scriptCellKeys['${doc.filePath}_${targetBlock.id}'];
    if (cellKey?.currentState != null) {
      cellKey!.currentState!.executeScript();
    } else {
      final rawLines = targetBlock.content
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n');
      while (rawLines.isNotEmpty && rawLines.last.trim().isEmpty) {
        rawLines.removeLast();
      }
      if (rawLines.isEmpty) return;
      final availableTargets = _buildAvailableTargets();
      final defaultTarget = widget.syncedCommandPaneTarget.isNotEmpty
          ? widget.syncedCommandPaneTarget
          : availableTargets.first;
      final override = targetBlock.targetNodeOverride;
      final selectedTarget =
          (override == null ||
              override.startsWith('Synced with Command Pane') ||
              override == 'Synced')
          ? defaultTarget
          : override;
      widget.onExecuteScript(selectedTarget, rawLines).then((_) {
        if (mounted) {
          setState(() {
            targetBlock!.lastExecutedTime = DateTime.now();
            targetBlock.lastExecutedTarget = selectedTarget;
          });
        }
      });
    }
  }

  void _openTargetDropdownForActiveOrFirstScriptCell() {
    final tab = _activeOpenTab;
    final doc = tab?.document;
    if (doc == null || doc.blocks.isEmpty) return;

    PlaybookBlock? targetBlock;
    final candidateId = _selectedBlockId ?? _lastSelectedBlockId;
    if (candidateId != null) {
      final idx = doc.blocks.indexWhere((b) => b.id == candidateId);
      if (idx != -1) {
        if (doc.blocks[idx].type == PlaybookBlockType.scriptCell) {
          targetBlock = doc.blocks[idx];
        } else {
          for (int i = idx + 1; i < doc.blocks.length; i++) {
            if (doc.blocks[i].type == PlaybookBlockType.scriptCell) {
              targetBlock = doc.blocks[i];
              break;
            }
          }
        }
      }
    }

    targetBlock ??= doc.blocks
        .cast<PlaybookBlock?>()
        .firstWhere(
          (b) => b?.type == PlaybookBlockType.scriptCell,
          orElse: () => null,
        );

    if (targetBlock == null) return;

    if (_selectedBlockId != targetBlock.id) {
      setState(() {
        _selectedBlockId = targetBlock!.id;
        _lastSelectedBlockId = targetBlock.id;
      });
    }

    final cellKey = _scriptCellKeys['${doc.filePath}_${targetBlock.id}'];
    cellKey?.currentState?.showTargetDropdown();
  }

  KeyEventResult _handleDocumentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final tab = _activeOpenTab;
    if (tab == null) return KeyEventResult.ignored;
    final doc = tab.document;
    if (doc == null) return KeyEventResult.ignored;

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

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.physicalKey == PhysicalKeyboardKey.enter ||
        event.physicalKey == PhysicalKeyboardKey.numpadEnter;

    // Ctrl+Enter or Shift+Enter -> Execute active or first script cell
    if ((isCtrl || isShift) && !isAlt && isEnter) {
      _executeActiveOrFirstScriptCell();
      return KeyEventResult.handled;
    }

    final isKeyA = event.logicalKey == LogicalKeyboardKey.keyA ||
        event.physicalKey == PhysicalKeyboardKey.keyA;
    final isKeyB = event.logicalKey == LogicalKeyboardKey.keyB ||
        event.physicalKey == PhysicalKeyboardKey.keyB;
    final isKeyD = event.logicalKey == LogicalKeyboardKey.keyD ||
        event.physicalKey == PhysicalKeyboardKey.keyD;

    // Ctrl+Alt+A / Ctrl+Alt+B / Ctrl+Alt+D -> Insert or delete block
    // (Works even while editing inside a text field)
    if (isCtrl && isAlt) {
      if (!isShift && isKeyA) {
        _insertBlockRelativeToSelection(doc, PlaybookBlockType.scriptCell, above: true, enterEditMode: true);
        return KeyEventResult.handled;
      }
      if (!isShift && isKeyB) {
        _insertBlockRelativeToSelection(doc, PlaybookBlockType.scriptCell, above: false, enterEditMode: true);
        return KeyEventResult.handled;
      }
      if (!isShift && isKeyD) {
        _deleteSelectedBlock(doc);
        return KeyEventResult.handled;
      }
      if (isShift && isKeyA) {
        _insertBlockRelativeToSelection(doc, PlaybookBlockType.text, above: true, enterEditMode: true);
        return KeyEventResult.handled;
      }
      if (isShift && isKeyB) {
        _insertBlockRelativeToSelection(doc, PlaybookBlockType.text, above: false, enterEditMode: true);
        return KeyEventResult.handled;
      }
    }

    // Only handle single-key block navigation when not typing in a TextField
    if (!_docFocusNode.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }

    final isEscape = event.logicalKey == LogicalKeyboardKey.escape ||
        event.physicalKey == PhysicalKeyboardKey.escape;

    if (isEscape && !isCtrl && !isShift && !isAlt) {
      if (_vimCommand.isNotEmpty) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = '';
        });
        return KeyEventResult.handled;
      }
      if (_isFindBarOpen) {
        _closeFindBar();
      } else if (_selectedBlockId != null) {
        setState(() {
          _lastSelectedBlockId = _selectedBlockId;
          _selectedBlockId = null;
        });
      }
      return KeyEventResult.handled;
    }

    // Ctrl+D -> Duplicate selected block
    if (isCtrl && !isAlt && !isShift && isKeyD) {
      _duplicateSelectedBlock(doc);
      return KeyEventResult.handled;
    }

    // Ctrl+Z -> Undo delete block
    if (isCtrl && !isAlt && !isShift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _undoDeleteBlock(doc);
      return KeyEventResult.handled;
    }

    // Alt+Up / Alt+Down -> Move block up / down
    if (isAlt && !isCtrl && !isShift) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _moveSelectedBlock(doc, -1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _moveSelectedBlock(doc, 1);
        return KeyEventResult.handled;
      }
    }

    if (isCtrl || isAlt) return KeyEventResult.ignored;

    final isColon = event.character == ':' ||
        event.logicalKey == LogicalKeyboardKey.colon ||
        (isShift &&
            (event.logicalKey == LogicalKeyboardKey.semicolon ||
                event.physicalKey == PhysicalKeyboardKey.semicolon));

    final isKeyW = !isShift &&
        (event.logicalKey == LogicalKeyboardKey.keyW ||
            event.physicalKey == PhysicalKeyboardKey.keyW ||
            event.character == 'w' ||
            event.character == 'W');

    final isKeyQ = !isShift &&
        (event.logicalKey == LogicalKeyboardKey.keyQ ||
            event.physicalKey == PhysicalKeyboardKey.keyQ ||
            event.character == 'q' ||
            event.character == 'Q');

    final isModifierOnly = event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight ||
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight;

    // Vim modal command (:w to save document, :w {filename} to save as new file, :q to close document, :wq to save and close)
    if (_vimCommand.startsWith(':w ')) {
      if (isEnter) {
        _vimCommandTimer?.cancel();
        final rawFileName = _vimCommand.substring(3).trim();
        setState(() {
          _vimCommand = '';
        });
        if (rawFileName.isNotEmpty) {
          _saveToNewFile(tab, rawFileName);
        } else {
          _saveDocument(tab);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = _vimCommand.substring(0, _vimCommand.length - 1);
        });
        return KeyEventResult.handled;
      }
      if (!isCtrl && !isAlt && event.character != null && event.character!.length == 1) {
        final char = event.character!;
        if (char.codeUnitAt(0) >= 32 && !r'<>:"/\|?*'.contains(char)) {
          _vimCommandTimer?.cancel();
          setState(() {
            _vimCommand += char;
          });
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.handled;
    } else if (_vimCommand == ':w') {
      if (event.logicalKey == LogicalKeyboardKey.space || event.character == ' ') {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = ':w ';
        });
        return KeyEventResult.handled;
      } else if (isKeyQ) {
        _vimCommandTimer?.cancel();
        _saveDocument(tab);
        _lastTabClosedByVimTime = DateTime.now();
        setState(() {
          _vimCommand = '';
        });
        _closeActiveSidebarTab();
        return KeyEventResult.handled;
      } else if (isEnter) {
        _vimCommandTimer?.cancel();
        _saveDocument(tab);
        setState(() {
          _vimCommand = '';
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = ':';
        });
        return KeyEventResult.handled;
      } else if (!isModifierOnly) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = '';
        });
      }
    } else if (_vimCommand == ':') {
      if (isKeyW) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = ':w';
        });
        _saveDocument(tab);
        _vimCommandTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && _vimCommand.isNotEmpty) {
            setState(() {
              _vimCommand = '';
            });
          }
        });
        return KeyEventResult.handled;
      } else if (isKeyQ) {
        _vimCommandTimer?.cancel();
        _lastTabClosedByVimTime = DateTime.now();
        setState(() {
          _vimCommand = '';
        });
        _closeActiveSidebarTab();
        return KeyEventResult.handled;
      } else if (isEnter) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = '';
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = '';
        });
        return KeyEventResult.handled;
      } else if (!isModifierOnly) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = '';
        });
      }
    } else {
      if (isColon) {
        _vimCommandTimer?.cancel();
        setState(() {
          _vimCommand = ':';
        });
        _vimCommandTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && _vimCommand.isNotEmpty) {
            setState(() {
              _vimCommand = '';
            });
          }
        });
        return KeyEventResult.handled;
      }
    }

    // a -> Insert Script Cell Above
    if (!isShift && isKeyA) {
      _insertBlockRelativeToSelection(doc, PlaybookBlockType.scriptCell, above: true);
      return KeyEventResult.handled;
    }

    // b -> Insert Script Cell Below
    if (!isShift && isKeyB) {
      _insertBlockRelativeToSelection(doc, PlaybookBlockType.scriptCell, above: false);
      return KeyEventResult.handled;
    }

    final isKeyT = event.logicalKey == LogicalKeyboardKey.keyT ||
        event.physicalKey == PhysicalKeyboardKey.keyT ||
        event.character == 't';

    // t -> Open Target dropdown for selected script cell
    if (!isShift && isKeyT) {
      _openTargetDropdownForActiveOrFirstScriptCell();
      return KeyEventResult.handled;
    }

    final isKeyY = event.logicalKey == LogicalKeyboardKey.keyY ||
        event.physicalKey == PhysicalKeyboardKey.keyY;
    final isKeyP = event.logicalKey == LogicalKeyboardKey.keyP ||
        event.physicalKey == PhysicalKeyboardKey.keyP;
    final isKeyU = event.logicalKey == LogicalKeyboardKey.keyU ||
        event.physicalKey == PhysicalKeyboardKey.keyU;
    final isKeyG = event.logicalKey == LogicalKeyboardKey.keyG ||
        event.physicalKey == PhysicalKeyboardKey.keyG;
    final isKeyJ = event.logicalKey == LogicalKeyboardKey.keyJ ||
        event.physicalKey == PhysicalKeyboardKey.keyJ;
    final isKeyK = event.logicalKey == LogicalKeyboardKey.keyK ||
        event.physicalKey == PhysicalKeyboardKey.keyK;

    if (!isKeyG && _pendingG) {
      _pendingG = false;
      _pendingGTimer?.cancel();
    }

    // y -> Yank (copy) selected block
    if (!isShift && isKeyY) {
      _copySelectedBlock(doc);
      return KeyEventResult.handled;
    }

    // p -> Paste block below
    if (!isShift && isKeyP) {
      _pasteBlock(doc, above: false);
      return KeyEventResult.handled;
    }

    // Shift+P -> Paste block above
    if (isShift && isKeyP) {
      _pasteBlock(doc, above: true);
      return KeyEventResult.handled;
    }

    // u -> Undo delete block
    if (!isShift && isKeyU) {
      _undoDeleteBlock(doc);
      return KeyEventResult.handled;
    }

    // Shift+K -> Move selected block up
    if (isShift && isKeyK) {
      _moveSelectedBlock(doc, -1);
      return KeyEventResult.handled;
    }

    // Shift+J -> Move selected block down
    if (isShift && isKeyJ) {
      _moveSelectedBlock(doc, 1);
      return KeyEventResult.handled;
    }

    // G (Shift+G) -> Jump to last block
    if (isShift && isKeyG) {
      _selectBlockAtIndex(doc, doc.blocks.length - 1);
      return KeyEventResult.handled;
    }

    // gg -> Jump to first block
    if (!isShift && isKeyG) {
      if (_pendingG) {
        _pendingGTimer?.cancel();
        _pendingG = false;
        _selectBlockAtIndex(doc, 0);
        return KeyEventResult.handled;
      } else {
        _pendingG = true;
        _pendingGTimer?.cancel();
        _pendingGTimer = Timer(const Duration(milliseconds: 800), () {
          if (mounted) _pendingG = false;
        });
        return KeyEventResult.handled;
      }
    }

    // d -> Delete selected textbox or script cell (cuts to clipboard)
    if (!isShift && isKeyD) {
      _deleteSelectedBlock(doc);
      return KeyEventResult.handled;
    }

    // Shift+A -> Insert Text Box Above
    if (isShift && isKeyA) {
      _insertBlockRelativeToSelection(doc, PlaybookBlockType.text, above: true);
      return KeyEventResult.handled;
    }

    // Shift+B -> Insert Text Box Below
    if (isShift && isKeyB) {
      _insertBlockRelativeToSelection(doc, PlaybookBlockType.text, above: false);
      return KeyEventResult.handled;
    }

    // j / ArrowDown -> Move selection to next block
    if (!isShift &&
        (isKeyJ || event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      _moveDocumentBlockSelection(doc, 1);
      return KeyEventResult.handled;
    }

    // k / ArrowUp -> Move selection to previous block
    if (!isShift &&
        (isKeyK || event.logicalKey == LogicalKeyboardKey.arrowUp)) {
      _moveDocumentBlockSelection(doc, -1);
      return KeyEventResult.handled;
    }

    // Enter -> Enter edit mode on selected block
    if (!isShift && isEnter) {
      if (_lastTabClosedByVimTime != null &&
          DateTime.now().difference(_lastTabClosedByVimTime!).inMilliseconds < 500) {
        _lastTabClosedByVimTime = null;
        return KeyEventResult.handled;
      }
      _enterEditModeOnSelectedBlock(doc);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _handleGlobalHardwareKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final offstage = context.findAncestorWidgetOfExactType<Offstage>();
    if (offstage != null && offstage.offstage) return false;

    // Do not trigger hotkeys if another modal/dialog route is on top
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

    final isSidebarActive = isFocused;

    if (isSidebarActive) {
      final isTab = event.logicalKey == LogicalKeyboardKey.tab ||
          event.physicalKey == PhysicalKeyboardKey.tab;
      final isW = event.logicalKey == LogicalKeyboardKey.keyW ||
          event.physicalKey == PhysicalKeyboardKey.keyW;
      final isH = event.logicalKey == LogicalKeyboardKey.keyH ||
          event.physicalKey == PhysicalKeyboardKey.keyH;

      // Ctrl+Tab / Ctrl+PageDown -> Next sidebar tab
      if (isCtrl && !isShift && (isTab || event.logicalKey == LogicalKeyboardKey.pageDown)) {
        _selectNextSidebarTab();
        return true;
      }

      // Ctrl+Shift+Tab / Ctrl+PageUp -> Previous sidebar tab
      if (isCtrl && (isShift && isTab || event.logicalKey == LogicalKeyboardKey.pageUp)) {
        _selectPreviousSidebarTab();
        return true;
      }

      // Ctrl+W -> Close active document tab
      if (isCtrl && !isShift && isW) {
        _closeActiveSidebarTab();
        return true;
      }

      // Alt+H -> Focus Nexus terminal
      if (isAlt && !isCtrl && !isShift && isH) {
        _focusNexusTerminal();
        return true;
      }
    }

    // Ctrl+S / Cmd+S -> Save active document
    final isS = event.logicalKey == LogicalKeyboardKey.keyS ||
        event.physicalKey == PhysicalKeyboardKey.keyS;
    if (isCtrl && !isShift && isS) {
      final tab = _activeOpenTab;
      if (tab != null && tab.document != null) {
        _saveDocument(tab);
        return true;
      }
    }

    // Ctrl+F / Cmd+F -> Find in document
    final isF = event.logicalKey == LogicalKeyboardKey.keyF ||
        event.physicalKey == PhysicalKeyboardKey.keyF;
    if (isCtrl && !isShift && isF) {
      if (_activeTabIndex > 0) {
        _openFindBar();
        return true;
      }
    }

    // Escape -> Close find bar
    if (event.logicalKey == LogicalKeyboardKey.escape && _isFindBarOpen) {
      _closeFindBar();
      return true;
    }

    return false;
  }

  void _saveDocument(_OpenRunbookTab tab) {
    final doc = tab.document;
    if (doc == null) return;

    final ext = _extractExtension(doc.filePath);
    try {
      final file = File(doc.filePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      if (ext == '.nxnb' || ext == '.md' || ext == '.markdown') {
        file.writeAsStringSync(PlaybookParser.serializeToMarkdown(doc));
      } else if (ext == '.docx') {
        List<int>? existingBytes;
        if (file.existsSync()) {
          try {
            existingBytes = file.readAsBytesSync();
          } catch (_) {}
        }
        final docxBytes = PlaybookParser.serializeToDocx(
          doc,
          existingBytes: existingBytes,
        );
        file.writeAsBytesSync(docxBytes);
      } else {
        final content = doc.blocks.map((b) => b.content).join('\n\n');
        file.writeAsStringSync(content);
      }
      if (mounted) {
        setState(() {
          doc.isModified = false;
          tab.showSavedFeedback = true;
        });
        _saveFeedbackTimer?.cancel();
        _saveFeedbackTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && tab.showSavedFeedback) {
            setState(() {
              tab.showSavedFeedback = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error saving runbook document: $e');
    }
  }

  void _saveToNewFile(_OpenRunbookTab tab, String rawFileName) {
    final doc = tab.document;
    if (doc == null) return;

    var cleanName = rawFileName.trim();
    if (cleanName.isEmpty) return;

    if (cleanName.toLowerCase().endsWith('.nxnb')) {
      cleanName = cleanName.substring(0, cleanName.length - 5).trim();
    }
    for (final supportedExt in _supportedExtensions) {
      if (cleanName.toLowerCase().endsWith(supportedExt)) {
        cleanName = cleanName.substring(0, cleanName.length - supportedExt.length).trim();
        break;
      }
    }
    if (cleanName.isEmpty) return;

    final finalName = '$cleanName.nxnb';

    final currentFile = File(tab.filePath);
    final targetDir = currentFile.parent.existsSync() ? currentFile.parent.path : _resolvedDirPath;
    final newFilePath = '$targetDir${Platform.pathSeparator}$finalName';
    final newFile = File(newFilePath);

    try {
      if (!newFile.parent.existsSync()) {
        newFile.parent.createSync(recursive: true);
      }
      final serialized = PlaybookParser.serializeToMarkdown(doc);
      newFile.writeAsStringSync(serialized);

      _expandedFolders.add(_normalizePath(targetDir));
      _loadFiles();
      _openFileInTab(newFile);

      if (mounted) {
        setState(() {
          _activeOpenTab?.showSavedFeedback = true;
        });
        _saveFeedbackTimer?.cancel();
        _saveFeedbackTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && (_activeOpenTab?.showSavedFeedback ?? false)) {
            setState(() {
              _activeOpenTab?.showSavedFeedback = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error saving to new file: $e');
    }
  }

  void _addBlockToDocument(
    PlaybookDocument doc,
    PlaybookBlockType type, {
    int? atIndex,
  }) {
    setState(() {
      final newId =
          'block_${DateTime.now().microsecondsSinceEpoch}_${doc.blocks.length}';
      final newBlock = PlaybookBlock(
        id: newId,
        type: type,
        headingLevel: type == PlaybookBlockType.heading ? 2 : 1,
        content: '',
      );
      if (atIndex != null && atIndex >= 0 && atIndex <= doc.blocks.length) {
        doc.blocks.insert(atIndex, newBlock);
      } else {
        doc.blocks.add(newBlock);
      }
      _selectedBlockId = newId;
      _lastSelectedBlockId = newId;
      doc.isModified = true;
      _recomputeSearchMatches();
    });
  }

  void _flashVimStatus(String message) {
    if (!mounted) return;
    _vimStatusTimer?.cancel();
    setState(() {
      _vimStatusMessage = message;
    });
    _vimStatusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _vimStatusMessage.isNotEmpty) {
        setState(() {
          _vimStatusMessage = '';
        });
      }
    });
  }

  void _deleteBlock(PlaybookDocument doc, PlaybookBlock block) {
    final index = doc.blocks.indexWhere((b) => b.id == block.id);
    _clipboardBlock = block.copyWith();
    _deletedBlockHistory.add(
      _DeletedBlockHistory(
        block: _clipboardBlock!,
        originalIndex: index != -1 ? index : doc.blocks.length,
        docFilePath: doc.filePath,
      ),
    );
    _flashVimStatus('Deleted block (u to undo, p to paste)');

    setState(() {
      doc.blocks.removeWhere((b) => b.id == block.id);
      doc.isModified = true;
      if (_selectedBlockId == block.id || _lastSelectedBlockId == block.id) {
        if (doc.blocks.isEmpty) {
          _selectedBlockId = null;
          _lastSelectedBlockId = null;
        } else {
          final nextIndex = index.clamp(0, doc.blocks.length - 1);
          final nextBlock = doc.blocks[nextIndex];
          _selectedBlockId = nextBlock.id;
          _lastSelectedBlockId = nextBlock.id;
          _scrollToDocumentBlock(doc, nextBlock);
        }
      }
      _recomputeSearchMatches();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_docFocusNode.hasPrimaryFocus) {
        _docFocusNode.requestFocus();
      }
    });
  }

  void _deleteSelectedBlock(PlaybookDocument doc) {
    if (doc.blocks.isEmpty) return;
    final targetId = _selectedBlockId ?? _lastSelectedBlockId;
    final block = targetId != null
        ? doc.blocks.firstWhere((b) => b.id == targetId, orElse: () => doc.blocks.first)
        : doc.blocks.first;
    _deleteBlock(doc, block);
    _docFocusNode.requestFocus();
  }

  void _copySelectedBlock(PlaybookDocument doc) {
    if (doc.blocks.isEmpty) return;
    final targetId = _selectedBlockId ?? _lastSelectedBlockId;
    final block = targetId != null
        ? doc.blocks.firstWhere((b) => b.id == targetId, orElse: () => doc.blocks.first)
        : doc.blocks.first;
    _clipboardBlock = block.copyWith();
    _flashVimStatus('Yanked block (p to paste)');
  }

  void _pasteBlock(PlaybookDocument doc, {bool above = false}) {
    if (_clipboardBlock == null) {
      _flashVimStatus('Clipboard is empty');
      return;
    }
    final newId = 'block_${DateTime.now().microsecondsSinceEpoch}_${doc.blocks.length}';
    final pastedBlock = _clipboardBlock!.copyWith(id: newId);

    int insertIdx = doc.blocks.length;
    final targetId = _selectedBlockId ?? _lastSelectedBlockId;
    if (targetId != null) {
      final currentIdx = doc.blocks.indexWhere((b) => b.id == targetId);
      if (currentIdx != -1) {
        insertIdx = above ? currentIdx : currentIdx + 1;
      }
    } else if (doc.blocks.isNotEmpty) {
      insertIdx = above ? 0 : 1;
    }

    setState(() {
      doc.blocks.insert(insertIdx, pastedBlock);
      doc.isModified = true;
      _selectedBlockId = pastedBlock.id;
      _lastSelectedBlockId = pastedBlock.id;
      _recomputeSearchMatches();
    });
    _scrollToDocumentBlock(doc, pastedBlock);
    _flashVimStatus(above ? 'Pasted block above' : 'Pasted block below');
  }

  void _undoDeleteBlock(PlaybookDocument doc) {
    final docHistoryIndex = _deletedBlockHistory.lastIndexWhere(
      (h) => h.docFilePath == doc.filePath,
    );
    if (docHistoryIndex == -1) {
      _flashVimStatus('Nothing to undo');
      return;
    }

    final item = _deletedBlockHistory.removeAt(docHistoryIndex);
    final restoredBlock = item.block.copyWith();

    final insertIdx = item.originalIndex.clamp(0, doc.blocks.length);
    setState(() {
      doc.blocks.insert(insertIdx, restoredBlock);
      doc.isModified = true;
      _selectedBlockId = restoredBlock.id;
      _lastSelectedBlockId = restoredBlock.id;
      _recomputeSearchMatches();
    });
    _scrollToDocumentBlock(doc, restoredBlock);
    _flashVimStatus('Restored deleted block');
  }

  void _duplicateSelectedBlock(PlaybookDocument doc) {
    if (doc.blocks.isEmpty) return;
    final targetId = _selectedBlockId ?? _lastSelectedBlockId;
    int currentIdx = targetId != null
        ? doc.blocks.indexWhere((b) => b.id == targetId)
        : 0;
    if (currentIdx == -1) currentIdx = 0;
    final original = doc.blocks[currentIdx];

    final newId = 'block_${DateTime.now().microsecondsSinceEpoch}_${doc.blocks.length}';
    final duplicate = original.copyWith(id: newId);

    setState(() {
      doc.blocks.insert(currentIdx + 1, duplicate);
      doc.isModified = true;
      _selectedBlockId = duplicate.id;
      _lastSelectedBlockId = duplicate.id;
      _recomputeSearchMatches();
    });
    _scrollToDocumentBlock(doc, duplicate);
    _flashVimStatus('Duplicated block');
  }

  void _moveSelectedBlock(PlaybookDocument doc, int delta) {
    if (doc.blocks.length <= 1) return;
    final targetId = _selectedBlockId ?? _lastSelectedBlockId;
    int currentIdx = targetId != null
        ? doc.blocks.indexWhere((b) => b.id == targetId)
        : 0;
    if (currentIdx == -1) currentIdx = 0;

    final targetIdx = currentIdx + delta;
    if (targetIdx < 0 || targetIdx >= doc.blocks.length) return;

    setState(() {
      final block = doc.blocks.removeAt(currentIdx);
      doc.blocks.insert(targetIdx, block);
      doc.isModified = true;
      _selectedBlockId = block.id;
      _lastSelectedBlockId = block.id;
      _recomputeSearchMatches();
    });
    _scrollToDocumentBlock(doc, doc.blocks[targetIdx]);
    _flashVimStatus(delta < 0 ? 'Moved block up' : 'Moved block down');
  }

  void _selectBlockAtIndex(PlaybookDocument doc, int index) {
    if (doc.blocks.isEmpty) return;
    final clamped = index.clamp(0, doc.blocks.length - 1);
    final targetBlock = doc.blocks[clamped];
    setState(() {
      _selectedBlockId = targetBlock.id;
      _lastSelectedBlockId = targetBlock.id;
    });
    _scrollToDocumentBlock(doc, targetBlock);
  }

  List<String> _buildAvailableTargets() {
    final targets = <String>[];
    if (widget.syncedCommandPaneTarget.isNotEmpty) {
      targets.add(widget.syncedCommandPaneTarget);
    }
    for (final conn in widget.activeConnections) {
      if (conn.isNotEmpty && !targets.contains(conn)) {
        targets.add(conn);
      }
    }
    if (targets.isEmpty) {
      targets.add('Synced');
    }
    return targets;
  }

  IconData _iconForFile(String fileName) {
    final ext = _extractExtension(fileName);
    switch (ext) {
      case '.nxnb':
        return Icons.menu_book_rounded;
      case '.md':
      case '.markdown':
        return Icons.description_outlined;
      case '.docx':
        return Icons.article_outlined;
      case '.sh':
      case '.bash':
        return Icons.terminal;
      default:
        return Icons.insert_drive_file_outlined;
    }
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
                                          : palette.textColor.withValues(alpha: 0.5)),
                                      const SizedBox(height: 3),
                                      _buildSashDot((_isDraggingDivider || _isDividerHovered)
                                          ? palette.primaryColor
                                          : palette.textColor.withValues(alpha: 0.5)),
                                      const SizedBox(height: 3),
                                      _buildSashDot((_isDraggingDivider || _isDividerHovered)
                                          ? palette.primaryColor
                                          : palette.textColor.withValues(alpha: 0.5)),
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

  Widget _buildSashDot(Color color) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildTabBar(AppPalette palette) {
    return Material(
      color: palette.surfaceColor,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: palette.inputBorderColor, width: 1),
          ),
        ),
        child: Row(
          children: [
            // Scrollable tabs area
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Permanent Files tab
                    _buildTabItem(
                      palette: palette,
                      isActive: _activeTabIndex == 0,
                      onTap: () {
                        setState(() => _activeTabIndex = 0);
                        _sidebarFocusNode.requestFocus();
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            size: 15,
                            color: _activeTabIndex == 0
                                ? palette.primaryColor
                                : palette.textColor.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Files',
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 12,
                              fontWeight: _activeTabIndex == 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _activeTabIndex == 0
                                  ? palette.primaryColor
                                  : palette.textColor.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Opened document tabs
                    for (int i = 0; i < _openTabs.length; i++)
                      _buildDocumentTabHeader(palette, i, _openTabs[i]),
                  ],
                ),
              ),
            ),
            // Close sidebar button matching title bar window caption button styling
            _SidebarCaptionCloseButton(
              palette: palette,
              tooltip: 'Close sidebar',
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required AppPalette palette,
    required bool isActive,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Material(
      color: isActive ? palette.background : Colors.transparent,
      animationDuration: Duration.zero,
      child: InkWell(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: palette.inputBorderColor.withValues(alpha: 0.6),
                width: 1,
              ),
              bottom: BorderSide(
                color: isActive ? palette.primaryColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildDocumentTabHeader(
    AppPalette palette,
    int openTabIndex,
    _OpenRunbookTab tab,
  ) {
    final isActive = _activeTabIndex == openTabIndex + 1;
    final isModified = tab.document?.isModified ?? false;

    return _buildTabItem(
      palette: palette,
      isActive: isActive,
      onTap: () {
        setState(() {
          _activeTabIndex = openTabIndex + 1;
          _recomputeSearchMatches();
        });
        _docFocusNode.requestFocus();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isModified ? '${tab.fileName} *' : tab.fileName,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? palette.primaryColor : palette.textColor,
            ),
          ),
          const SizedBox(width: 4),
          _SidebarTabCloseButton(
            palette: palette,
            tooltip: 'Close tab',
            onPressed: () => _closeTab(openTabIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildExplorerActionButton({
    Key? key,
    required AppPalette palette,
    required String tooltip,
    required IconData icon,
    VoidCallback? onPressed,
    Color? iconColor,
    bool isDanger = false,
    double iconSize = 14.5,
  }) {
    return _SidebarToolbarButton(
      key: key,
      palette: palette,
      tooltip: tooltip,
      icon: icon,
      iconSize: iconSize,
      iconColor: iconColor,
      isDanger: isDanger,
      onPressed: onPressed,
    );
  }

  Widget _buildToolbarDivider(AppPalette palette) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: palette.inputBorderColor.withValues(alpha: 0.35),
    );
  }

  Widget _buildFilesTab(AppPalette palette) {
    final canDelete = _canDeleteSelection;
    final deleteTooltip = _selectedFilePath != null
        ? 'Delete File'
        : (canDelete ? 'Delete Folder' : 'Delete');

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
          if (_canOperateOnSelection) {
            _cutSelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () {
          if (_canOperateOnSelection) {
            _cutSelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          if (_canOperateOnSelection) {
            _copySelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
          if (_canOperateOnSelection) {
            _copySelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          if (_canPaste) {
            _pasteSelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
          if (_canPaste) {
            _pasteSelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (_canOperateOnSelection) {
            _promptRenameSelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (_canDeleteSelection) {
            _deleteCurrentSelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): _openSelectedFile,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _openSelectedFile,
      },
      child: Focus(
        focusNode: _sidebarFocusNode,
        autofocus: true,
        onKeyEvent: _handleFilesKey,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (!_sidebarFocusNode.hasFocus) {
              _sidebarFocusNode.requestFocus();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        // Directory path bar with New File, New Folder, Delete, Refresh, Collapse Folders icons
        Material(
          color: palette.surfaceColor.withValues(alpha: 0.5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: palette.inputBorderColor.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                InkWell(
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  onTap: () {
                    setState(() {
                      _selectedFolderPath = _resolvedDirPath;
                      _selectedFilePath = null;
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_rounded, size: 15, color: palette.accentColor),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFolderPath = _resolvedDirPath;
                        _selectedFilePath = null;
                      });
                    },
                    child: Text(
                      _resolvedDirPath,
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: palette.textColor.withValues(alpha: 0.85),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Explorer action buttons styled to match the desktop title bar theme
                _buildExplorerActionButton(
                  palette: palette,
                  tooltip: 'New File',
                  icon: Icons.note_add_outlined,
                  iconSize: 14.5,
                  onPressed: _promptCreateNewFile,
                ),
                _buildExplorerActionButton(
                  palette: palette,
                  tooltip: 'New Folder',
                  icon: Icons.create_new_folder_outlined,
                  iconSize: 14.5,
                  onPressed: _promptCreateNewFolder,
                ),
                _buildToolbarDivider(palette),
                _buildExplorerActionButton(
                  key: const Key('runbook_toolbar_cut_button'),
                  palette: palette,
                  tooltip: 'Cut (Ctrl+X)',
                  icon: Icons.content_cut_rounded,
                  iconSize: 14.0,
                  onPressed: _canOperateOnSelection ? _cutSelection : null,
                ),
                _buildExplorerActionButton(
                  key: const Key('runbook_toolbar_copy_button'),
                  palette: palette,
                  tooltip: 'Copy (Ctrl+C)',
                  icon: Icons.content_copy_rounded,
                  iconSize: 14.0,
                  onPressed: _canOperateOnSelection ? _copySelection : null,
                ),
                _buildExplorerActionButton(
                  key: const Key('runbook_toolbar_paste_button'),
                  palette: palette,
                  tooltip: 'Paste (Ctrl+V)',
                  icon: Icons.content_paste_rounded,
                  iconSize: 14.0,
                  onPressed: _canPaste ? _pasteSelection : null,
                ),
                _buildExplorerActionButton(
                  key: const Key('runbook_toolbar_rename_button'),
                  palette: palette,
                  tooltip: 'Rename (F2)',
                  icon: Icons.edit_outlined,
                  iconSize: 14.5,
                  onPressed: _canOperateOnSelection
                      ? _promptRenameSelection
                      : null,
                ),
                _buildExplorerActionButton(
                  key: const Key('runbook_toolbar_delete_button'),
                  palette: palette,
                  tooltip: deleteTooltip,
                  icon: Icons.delete_outline_rounded,
                  iconSize: 14.5,
                  isDanger: true,
                  onPressed: canDelete ? _deleteCurrentSelection : null,
                ),
                _buildToolbarDivider(palette),
                _buildExplorerActionButton(
                  palette: palette,
                  tooltip: 'Refresh',
                  icon: Icons.refresh_rounded,
                  iconSize: 15.0,
                  onPressed: _loadFiles,
                ),
                _buildExplorerActionButton(
                  palette: palette,
                  tooltip: 'Collapse Folders',
                  icon: Icons.unfold_less_rounded,
                  iconSize: 15.0,
                  onPressed: _collapseAllFolders,
                ),
              ],
            ),
          ),
        ),
        // Hierarchical folder & file tree with right-side Scrollbar
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (details) =>
                _showContextMenuForBackground(context, details),
            child: _treeNodes.isEmpty
                ? Center(
                    child: Text(
                      'No runbook documents found.',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 12,
                        color: palette.textColor.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _filesScrollController,
                    thumbVisibility: true,
                    interactive: true,
                    child: ListView.separated(
                      controller: _filesScrollController,
                      itemCount: _treeNodes.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: palette.inputBorderColor.withValues(alpha: 0.25),
                      ),
                      itemBuilder: (context, index) {
                        final node = _treeNodes[index];
                        final leftIndent = 10.0 + (node.depth * 16.0);
                        final isSelectedFolder =
                            node.isDirectory &&
                            _selectedFolderPath != null &&
                            _normalizePath(_selectedFolderPath!) ==
                                _normalizePath(node.path);
                        final isSelectedFile =
                            !node.isDirectory &&
                            _selectedFilePath != null &&
                            _normalizePath(_selectedFilePath!) ==
                                _normalizePath(node.path);
                        final isSelected = isSelectedFolder || isSelectedFile;
                        final isCutItem =
                            _isCutOperation &&
                            _clipboardPath != null &&
                            _normalizePath(node.path) ==
                                _normalizePath(_clipboardPath!);

                        return Material(
                          color: isSelected
                              ? palette.primaryColor.withValues(alpha: 0.15)
                              : Colors.transparent,
                          animationDuration: Duration.zero,
                          child: Opacity(
                            opacity: isCutItem ? 0.45 : 1.0,
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (_) {
                                _sidebarFocusNode.requestFocus();
                                setState(() {
                                  if (node.isDirectory) {
                                    _selectedFolderPath = node.path;
                                    _selectedFilePath = null;
                                  } else {
                                    _selectedFilePath = node.path;
                                    _selectedFolderPath = null;
                                  }
                                });
                              },
                              child: InkWell(
                                key: ValueKey(
                                  'file_tree_node_${node.name}',
                                ),
                                splashFactory: NoSplash.splashFactory,
                                highlightColor: Colors.transparent,
                                splashColor: Colors.transparent,
                                hoverColor: isSelected
                                    ? Colors.transparent
                                    : palette.primaryColor.withValues(
                                        alpha: 0.08,
                                      ),
                                onTap: () {
                                  if (node.isDirectory) {
                                    _toggleFolder(node);
                                  }
                                },
                                onDoubleTap: node.isDirectory
                                    ? null
                                    : () {
                                        if (node.entity is File) {
                                          _openFileInTab(
                                            node.entity as File,
                                          );
                                        }
                                      },
                                onSecondaryTapDown: (details) =>
                                    _showContextMenuForNode(
                                      context,
                                      details,
                                      node,
                                    ),
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: leftIndent,
                                    right: 6,
                                    top: 6,
                                    bottom: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      if (node.isDirectory) ...[
                                        Icon(
                                          node.isExpanded
                                              ? Icons.keyboard_arrow_down
                                              : Icons.keyboard_arrow_right,
                                          size: 16,
                                          color: palette.textColor
                                              .withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          node.isExpanded
                                              ? Icons.folder_open
                                              : Icons.folder,
                                          size: 16,
                                          color: palette.accentColor,
                                        ),
                                      ] else ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          _iconForFile(node.name),
                                          size: 16,
                                          color: isSelected
                                              ? palette.primaryColor
                                              : palette.textColor
                                                    .withValues(
                                                      alpha: 0.8,
                                                    ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          node.name,
                                          style: TextStyle(
                                            fontFamily: 'Courier',
                                            fontSize: 13,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : (node.isDirectory
                                                      ? FontWeight.bold
                                                      : FontWeight
                                                            .normal),
                                            color: isSelected
                                                ? palette.primaryColor
                                                : palette.textColor,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentTab(AppPalette palette, _OpenRunbookTab tab) {
    if (tab.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 36, color: palette.errorColor),
              const SizedBox(height: 12),
              Text(
                tab.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 13,
                  color: palette.errorColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final doc = tab.document;
    if (doc == null) {
      return const SizedBox.shrink();
    }

    final availableTargets = _buildAvailableTargets();
    final defaultTarget = widget.syncedCommandPaneTarget.isNotEmpty
        ? widget.syncedCommandPaneTarget
        : availableTargets.first;

    final activeMatch =
        (_searchMatches.isNotEmpty &&
            _currentMatchIndex < _searchMatches.length)
        ? _searchMatches[_currentMatchIndex]
        : null;

    return Focus(
      focusNode: _docFocusNode,
      autofocus: true,
      onKeyEvent: _handleDocumentKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!isFocused) {
            _docFocusNode.requestFocus();
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Document toolbar
            _buildDocumentToolbar(palette, tab, doc),
            // Find word bar (when toggled via button or Ctrl+F)
            if (_isFindBarOpen) _buildFindBar(palette),
            // Top action bar (shown only when there are no text blocks or script cells in the document)
            if (!doc.blocks.any(
              (b) =>
                  b.type == PlaybookBlockType.scriptCell ||
                  b.type == PlaybookBlockType.text,
            ))
              _buildTopActionBar(palette, tab, doc),
            // Scrollable document content with right-side Scrollbar
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_selectedBlockId != null) {
                    setState(() {
                      _lastSelectedBlockId = _selectedBlockId;
                      _selectedBlockId = null;
                    });
                  }
                  _docFocusNode.requestFocus();
                },
                child: Scrollbar(
                  controller: _docScrollController,
                  thumbVisibility: true,
                  interactive: true,
                  child: ListView.builder(
                    controller: _docScrollController,
                    padding: const EdgeInsets.fromLTRB(14, 10, 18, 20),
                    itemCount: doc.blocks.length,
                    itemBuilder: (context, index) {
                      final block = doc.blocks[index];
                      final blockKey = _blockKeys.putIfAbsent(
                        '${doc.filePath}_${block.id}',
                        () => GlobalKey(),
                      );
                      final activeMatchInThisBlock =
                          (activeMatch != null &&
                              activeMatch.blockIndex == index)
                          ? activeMatch.matchIndexInBlock
                          : null;

                      switch (block.type) {
                        case PlaybookBlockType.heading:
                          return Container(
                            key: blockKey,
                            child: _buildHeadingBlock(
                              palette,
                              doc,
                              block,
                              activeMatchInThisBlock,
                            ),
                          );
                        case PlaybookBlockType.text:
                          final isFollowedByScriptCell =
                              (index + 1 < doc.blocks.length) &&
                              doc.blocks[index + 1].type ==
                                  PlaybookBlockType.scriptCell;
                          return Container(
                            key: blockKey,
                            child: _buildTextBlock(
                              palette,
                              doc,
                              block,
                              activeMatchInThisBlock,
                              index,
                              isFollowedByScriptCell: isFollowedByScriptCell,
                            ),
                          );
                        case PlaybookBlockType.scriptCell:
                          final isPrecededByTextBlock =
                              (index > 0) &&
                              doc.blocks[index - 1].type ==
                                  PlaybookBlockType.text;
                          final override = block.targetNodeOverride;
                          final selectedTarget =
                              (override == null ||
                                  override.startsWith(
                                    'Synced with Command Pane',
                                  ) ||
                                  override == 'Synced')
                              ? defaultTarget
                              : override;
                          final scriptCellKey = _scriptCellKeys.putIfAbsent(
                            '${doc.filePath}_${block.id}',
                            () => GlobalKey<ScriptCellWidgetState>(),
                          );
                          return Container(
                            key: blockKey,
                            child: ScriptCellWidget(
                              key: scriptCellKey,
                              block: block,
                              availableTargets: availableTargets,
                              selectedTarget: selectedTarget,
                              isSelected: _selectedBlockId == block.id,
                              isPrecededByTextBlock: isPrecededByTextBlock,
                              onSelect: () {
                                _lastSelectedBlockId = block.id;
                                if (_selectedBlockId != block.id) {
                                  setState(() {
                                    _selectedBlockId = block.id;
                                  });
                                }
                              },
                              onExitEdit: () {
                                setState(() {
                                  _lastSelectedBlockId = block.id;
                                  _selectedBlockId = null;
                                });
                                _docFocusNode.requestFocus();
                              },
                              onInsertAbove: (type) =>
                                  _addBlockToDocument(doc, type, atIndex: index),
                              onInsertBelow: (type) => _addBlockToDocument(
                                doc,
                                type,
                                atIndex: index + 1,
                              ),
                              searchQuery: _isFindBarOpen
                                  ? _searchQuery.trim()
                                  : '',
                              activeMatchIndexInBlock: activeMatchInThisBlock,
                              onTargetChanged: (newTarget) {
                                setState(() {
                                  block.targetNodeOverride = newTarget;
                                });
                              },
                              onSend: (linesToRun, targetNode) =>
                                  widget.onExecuteScript(targetNode, linesToRun),
                              onDelete: () => _deleteBlock(doc, block),
                              onContentChanged: () {
                                setState(() {
                                  doc.isModified = true;
                                  _recomputeSearchMatches();
                                });
                              },
                            ),
                          );
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentToolbar(
    AppPalette palette,
    _OpenRunbookTab tab,
    PlaybookDocument doc,
  ) {
    return Material(
      color: palette.surfaceColor.withValues(alpha: 0.6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: palette.inputBorderColor, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _iconForFile(tab.fileName),
              size: 14,
              color: palette.primaryColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tab.showSavedFeedback
                    ? '${tab.fileName} (Saved)'
                    : doc.isModified
                    ? '${tab.fileName} (Modified)'
                    : tab.fileName,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  color: tab.showSavedFeedback
                      ? palette.primaryColor
                      : doc.isModified
                      ? palette.accentColor
                      : palette.textColor.withValues(alpha: 0.8),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_vimCommand.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                key: const Key('vim_command_indicator'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: palette.primaryColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  _vimCommand,
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: palette.primaryColor,
                  ),
                ),
              ),
            ],
            if (_vimStatusMessage.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                key: const Key('vim_status_indicator'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: palette.accentColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  _vimStatusMessage,
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: palette.accentColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionBar(
    AppPalette palette,
    _OpenRunbookTab tab,
    PlaybookDocument doc,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Container(
          height: 26,
          decoration: BoxDecoration(
            color: palette.surfaceColor,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: palette.inputBorderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Tooltip(
                message: 'Add Script Cell',
                child: InkWell(
                  key: const Key('runbook_top_add_script_button'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    final insertIndex = doc.blocks.isEmpty ? 0 : 1;
                    _addBlockToDocument(
                      doc,
                      PlaybookBlockType.scriptCell,
                      atIndex: insertIndex,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Icon(
                      Icons.terminal,
                      size: 15,
                      color: palette.primaryColor,
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: palette.inputBorderColor,
              ),
              Tooltip(
                message: 'Add Text Block',
                child: InkWell(
                  key: const Key('runbook_top_add_text_button'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    final insertIndex = doc.blocks.isEmpty ? 0 : 1;
                    _addBlockToDocument(
                      doc,
                      PlaybookBlockType.text,
                      atIndex: insertIndex,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Icon(
                      Icons.notes_outlined,
                      size: 15,
                      color: palette.accentColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFindBar(AppPalette palette) {
    final total = _searchMatches.length;
    final current = total == 0 ? 0 : _currentMatchIndex + 1;

    return Material(
      color: palette.surfaceColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: palette.inputBorderColor, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 15,
              color: palette.textColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                key: const Key('runbook_find_input'),
                controller: _findController,
                focusNode: _findFocusNode,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  color: palette.textColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Find in file...',
                  hintStyle: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    color: palette.textColor.withValues(alpha: 0.4),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: palette.inputBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: palette.inputBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: palette.primaryColor),
                  ),
                ),
                onSubmitted: (_) => _nextSearchMatch(),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$current/$total',
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 11,
                color: total > 0
                    ? palette.primaryColor
                    : palette.textColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Previous match',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              splashRadius: 14,
              icon: Icon(
                Icons.keyboard_arrow_up,
                size: 16,
                color: palette.textColor,
              ),
              onPressed: total > 0 ? _prevSearchMatch : null,
            ),
            IconButton(
              tooltip: 'Next match',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              splashRadius: 14,
              icon: Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: palette.textColor,
              ),
              onPressed: total > 0 ? _nextSearchMatch : null,
            ),
            IconButton(
              tooltip: 'Close find',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              splashRadius: 14,
              icon: Icon(Icons.close, size: 15, color: palette.textColor),
              onPressed: _closeFindBar,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadingBlock(
    AppPalette palette,
    PlaybookDocument doc,
    PlaybookBlock block,
    int? activeMatchInBlock,
  ) {
    double fontSize;
    Color color;
    switch (block.headingLevel) {
      case 1:
        fontSize = 18;
        color = palette.primaryColor;
        break;
      case 2:
        fontSize = 15;
        color = palette.accentColor;
        break;
      default:
        fontSize = 14;
        color = palette.textColor;
        break;
    }

    final textBlockKey = _textBlockKeys.putIfAbsent(
      '${doc.filePath}_${block.id}',
      () => GlobalKey<_EditablePlaybookTextBlockState>(),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _lastSelectedBlockId = block.id;
          if (_selectedBlockId != block.id) {
            setState(() {
              _selectedBlockId = block.id;
            });
          }
        },
        child: _EditablePlaybookTextBlock(
          key: textBlockKey,
          block: block,
          isSelected: _selectedBlockId == block.id,
          onSelect: () {
            _lastSelectedBlockId = block.id;
            if (_selectedBlockId != block.id) {
              setState(() {
                _selectedBlockId = block.id;
              });
            }
          },
          onExitEdit: () {
            setState(() {
              _lastSelectedBlockId = block.id;
              _selectedBlockId = null;
            });
            _docFocusNode.requestFocus();
          },
          onExecuteShortcut: _executeActiveOrFirstScriptCell,
          searchQuery: _isFindBarOpen ? _searchQuery.trim() : '',
          activeMatchIndexInBlock: activeMatchInBlock,
          style: TextStyle(
            fontFamily: 'Courier',
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          onChanged: () {
            setState(() {
              doc.isModified = true;
              _recomputeSearchMatches();
            });
          },
        ),
      ),
    );
  }

  Widget _buildTextBlock(
    AppPalette palette,
    PlaybookDocument doc,
    PlaybookBlock block,
    int? activeMatchInBlock,
    int index, {
    bool isFollowedByScriptCell = false,
  }) {
    final isSelected = _selectedBlockId == block.id;
    final textBlockKey = _textBlockKeys.putIfAbsent(
      '${doc.filePath}_${block.id}',
      () => GlobalKey<_EditablePlaybookTextBlockState>(),
    );
    return _HoverablePlaybookBlockContainer(
      blockId: block.id,
      containerKey: ValueKey('text_block_container_${block.id}'),
      showBorderOnHover: true,
      isSelected: isSelected,
      isFollowedByScriptCell: isFollowedByScriptCell,
      deleteKey: ValueKey('delete_text_${block.id}'),
      tooltip: 'Delete Text Block',
      onDelete: () => _deleteBlock(doc, block),
      onSelect: () {
        _lastSelectedBlockId = block.id;
        if (_selectedBlockId != block.id) {
          setState(() {
            _selectedBlockId = block.id;
          });
        }
      },
      onInsertAbove: (type) => _addBlockToDocument(doc, type, atIndex: index),
      onInsertBelow: (type) => _addBlockToDocument(doc, type, atIndex: index + 1),
      child: _EditablePlaybookTextBlock(
        key: textBlockKey,
        block: block,
        isSelected: isSelected,
        onSelect: () {
          _lastSelectedBlockId = block.id;
          if (_selectedBlockId != block.id) {
            setState(() {
              _selectedBlockId = block.id;
            });
          }
        },
        onExitEdit: () {
          setState(() {
            _lastSelectedBlockId = block.id;
            _selectedBlockId = null;
          });
          _docFocusNode.requestFocus();
        },
        onExecuteShortcut: _executeActiveOrFirstScriptCell,
        searchQuery: _isFindBarOpen ? _searchQuery.trim() : '',
        activeMatchIndexInBlock: activeMatchInBlock,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: 13,
          height: 1.4,
          color: palette.textColor,
        ),
        onChanged: () {
          setState(() {
            doc.isModified = true;
            _recomputeSearchMatches();
          });
        },
      ),
    );
  }
}

class _HoverablePlaybookBlockContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;
  final String tooltip;
  final Key? deleteKey;
  final bool showBorderOnHover;
  final bool isSelected;
  final Key? containerKey;
  final String? blockId;
  final VoidCallback? onSelect;
  final void Function(PlaybookBlockType type)? onInsertAbove;
  final void Function(PlaybookBlockType type)? onInsertBelow;
  final bool isFollowedByScriptCell;

  const _HoverablePlaybookBlockContainer({
    required this.child,
    required this.onDelete,
    this.tooltip = 'Delete block',
    this.deleteKey,
    this.showBorderOnHover = false,
    this.isSelected = false,
    this.containerKey,
    this.blockId,
    this.onSelect,
    this.onInsertAbove,
    this.onInsertBelow,
    this.isFollowedByScriptCell = false,
  });

  @override
  State<_HoverablePlaybookBlockContainer> createState() =>
      _HoverablePlaybookBlockContainerState();
}

class _HoverablePlaybookBlockContainerState
    extends State<_HoverablePlaybookBlockContainer> {
  bool _isHovered = false;
  bool _isTopHovered = false;
  bool _isBottomHovered = false;

  Widget _buildInsertionPill({
    required AppPalette palette,
    required bool isTop,
    required String blockId,
    required void Function(PlaybookBlockType type) onInsert,
  }) {
    final direction = isTop ? 'above' : 'below';
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: palette.inputBorderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Add Script Cell $direction',
            child: InkWell(
              key: ValueKey('add_script_${direction}_$blockId'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => onInsert(PlaybookBlockType.scriptCell),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.terminal,
                      size: 13,
                      color: palette.primaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Script',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: palette.textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: palette.inputBorderColor,
          ),
          Tooltip(
            message: 'Add Text Box $direction',
            child: InkWell(
              key: ValueKey('add_text_${direction}_$blockId'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => onInsert(PlaybookBlockType.text),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 13,
                      color: palette.accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Text',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: palette.textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.activePalette;
    final isSelected = widget.isSelected;
    final showBorder = widget.showBorderOnHover && (isSelected || _isHovered);
    final borderColor = isSelected
        ? palette.primaryColor
        : (_isHovered ? palette.inputBorderColor : Colors.transparent);

    final blockId = widget.blockId ?? '';
    final bottomMargin = widget.isFollowedByScriptCell ? 2.0 : 14.0;
    final innerBottomPadding = widget.isFollowedByScriptCell ? 5.0 : 9.0;
    final showBottomPill = _isBottomHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isTopHovered = false;
        _isBottomHovered = false;
      }),
      onHover: (event) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final size = box.size;
        final pos = event.localPosition;
        final centerX = size.width / 2;
        final inCenterZone = (pos.dx >= centerX - 120) && (pos.dx <= centerX + 120);
        final inTopZone = inCenterZone && (pos.dy <= 28);
        final inBottomZone = inCenterZone && (pos.dy >= size.height - 28);

        if (inTopZone != _isTopHovered || inBottomZone != _isBottomHovered) {
          setState(() {
            _isTopHovered = inTopZone;
            _isBottomHovered = inBottomZone;
          });
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Main text box
              Padding(
                padding: EdgeInsets.fromLTRB(48, 14, 0, bottomMargin),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onSelect,
                  child: AnimatedContainer(
                    key: widget.containerKey,
                    duration: const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(minHeight: 38),
                    padding: EdgeInsets.fromLTRB(10, 9, 8, innerBottomPadding),
                    decoration: BoxDecoration(
                      color: (isSelected || _isHovered)
                          ? palette.surfaceColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: showBorder ? borderColor : Colors.transparent,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: widget.child),
                        if (_isHovered) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            key: widget.deleteKey,
                            tooltip: widget.tooltip,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 22,
                              minHeight: 22,
                            ),
                            splashRadius: 12,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 15,
                              color: palette.errorColor.withValues(alpha: 0.85),
                            ),
                            onPressed: widget.onDelete,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Center-Top hover action pill (Add Script Cell / Add Text Box above)
              if (widget.onInsertAbove != null)
                Positioned(
                  top: 0,
                  left: 68,
                  right: 20,
                  height: 28,
                  child: IgnorePointer(
                    ignoring: !_isTopHovered,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _isTopHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: _buildInsertionPill(
                          palette: palette,
                          isTop: true,
                          blockId: blockId,
                          onInsert: widget.onInsertAbove!,
                        ),
                      ),
                    ),
                  ),
                ),
              // Center-Bottom hover action pill (Add Script Cell / Add Text Box below)
              if (widget.onInsertBelow != null)
                Positioned(
                  bottom: 0,
                  left: 68,
                  right: 20,
                  height: 28,
                  child: IgnorePointer(
                    ignoring: !showBottomPill,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: showBottomPill ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: _buildInsertionPill(
                          palette: palette,
                          isTop: false,
                          blockId: blockId,
                          onInsert: widget.onInsertBelow!,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditablePlaybookTextBlock extends StatefulWidget {
  final PlaybookBlock block;
  final TextStyle style;
  final String searchQuery;
  final int? activeMatchIndexInBlock;
  final VoidCallback onChanged;
  final bool isSelected;
  final VoidCallback? onSelect;
  final VoidCallback? onExitEdit;
  final VoidCallback? onExecuteShortcut;

  const _EditablePlaybookTextBlock({
    super.key,
    required this.block,
    required this.style,
    required this.searchQuery,
    this.activeMatchIndexInBlock,
    required this.onChanged,
    this.isSelected = false,
    this.onSelect,
    this.onExitEdit,
    this.onExecuteShortcut,
  });

  @override
  State<_EditablePlaybookTextBlock> createState() =>
      _EditablePlaybookTextBlockState();
}

class _EditablePlaybookTextBlockState
    extends State<_EditablePlaybookTextBlock> {
  late HighlightingTextEditingController _controller;
  late FocusNode _focusNode;

  void requestEditorFocus() {
    _focusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _controller = HighlightingTextEditingController(
      text: widget.block.content,
      searchQuery: widget.searchQuery,
      activeMatchIndex: widget.activeMatchIndexInBlock,
    );
    _focusNode = FocusNode(onKeyEvent: _handleEditorKeyEvent);
    _focusNode.addListener(_onFocusChanged);
    _controller.addListener(_onTextChanged);
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _focusNode.unfocus();
      widget.onExitEdit?.call();
      return KeyEventResult.handled;
    }

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (isEnter && widget.onExecuteShortcut != null) {
      final isCtrl = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.controlLeft,
          ) ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.controlRight,
          );
      final isShift = HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftLeft,
          ) ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftRight,
          );
      if (isCtrl || isShift) {
        widget.onExecuteShortcut!();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      widget.onSelect?.call();
    }
  }

  @override
  void didUpdateWidget(_EditablePlaybookTextBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected == false && oldWidget.isSelected == true && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
    if (widget.block.content != _controller.text) {
      final prevSelection = _controller.selection;
      _controller.text = widget.block.content;
      if (prevSelection.end <= widget.block.content.length) {
        _controller.selection = prevSelection;
      }
    }
    _controller.updateSearchHighlight(
      widget.searchQuery,
      widget.activeMatchIndexInBlock,
    );
  }

  void _onTextChanged() {
    if (widget.block.content != _controller.text) {
      widget.block.content = _controller.text;
      widget.onChanged();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: widget.style,
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
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
class _SidebarToolbarButton extends StatefulWidget {
  final AppPalette palette;
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final bool isDanger;

  const _SidebarToolbarButton({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.icon,
    this.iconSize = 14.5,
    this.onPressed,
    this.iconColor,
    this.isDanger = false,
  });

  @override
  State<_SidebarToolbarButton> createState() => _SidebarToolbarButtonState();
}

class _SidebarToolbarButtonState extends State<_SidebarToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    final Color effectiveIdleColor = widget.iconColor ??
        (widget.isDanger && enabled
            ? widget.palette.textColor.withValues(alpha: 0.72)
            : widget.palette.textColor.withValues(alpha: enabled ? 0.72 : 0.28));

    final Color hoverColor = widget.isDanger
        ? widget.palette.errorColor
        : Colors.white;

    final Color hoverBgColor = widget.isDanger
        ? widget.palette.errorColor.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.1);

    final displayIconColor = enabled
        ? (_isHovered ? hoverColor : effectiveIdleColor)
        : effectiveIdleColor;

    return IconButton(
      tooltip: widget.tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      visualDensity: VisualDensity.compact,
      splashRadius: 13,
      hoverColor: hoverBgColor,
      highlightColor: Colors.transparent,
      style: IconButton.styleFrom(
        minimumSize: const Size(22, 22),
        fixedSize: const Size(24, 24),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      icon: MouseRegion(
        onEnter: (_) {
          if (enabled) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (enabled) setState(() => _isHovered = false);
        },
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: displayIconColor,
        ),
      ),
      onPressed: widget.onPressed,
    );
  }
}

/// A desktop window-style close button for the sidebar title bar,
/// matching [WindowCaptionButtons] styling and hover behavior.
class _SidebarCaptionCloseButton extends StatefulWidget {
  final AppPalette palette;
  final String tooltip;
  final VoidCallback? onPressed;

  const _SidebarCaptionCloseButton({
    required this.palette,
    required this.tooltip,
    this.onPressed,
  });

  @override
  State<_SidebarCaptionCloseButton> createState() =>
      _SidebarCaptionCloseButtonState();
}

class _SidebarCaptionCloseButtonState
    extends State<_SidebarCaptionCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        splashRadius: 14,
        hoverColor: const Color(0xFFC42B1C),
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        icon: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Icon(
            Icons.close,
            size: 14,
            color: _isHovered
                ? Colors.white
                : widget.palette.textColor.withValues(alpha: 0.7),
          ),
        ),
        onPressed: widget.onPressed,
      ),
    );
  }
}

/// A compact close button for document tab headers with subtle hover effect.
class _SidebarTabCloseButton extends StatefulWidget {
  final AppPalette palette;
  final String tooltip;
  final VoidCallback? onPressed;

  const _SidebarTabCloseButton({
    required this.palette,
    required this.tooltip,
    this.onPressed,
  });

  @override
  State<_SidebarTabCloseButton> createState() => _SidebarTabCloseButtonState();
}

class _SidebarTabCloseButtonState extends State<_SidebarTabCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      splashRadius: 12,
      hoverColor: Colors.white.withValues(alpha: 0.12),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      icon: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Icon(
          Icons.close,
          size: 13,
          color: _isHovered
              ? Colors.white
              : widget.palette.textColor.withValues(alpha: 0.7),
        ),
      ),
      onPressed: widget.onPressed,
    );
  }
}
