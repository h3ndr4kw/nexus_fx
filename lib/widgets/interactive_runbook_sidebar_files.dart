// Private members of InteractiveRunbookSidebarState live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'interactive_runbook_sidebar.dart';

/// Files tab: loading the runbook folder, create/rename/delete/move, clipboard and keyboard navigation of the tree.
extension _RunbookFileTreeOps on InteractiveRunbookSidebarState {
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
          if (InteractiveRunbookSidebarState._supportedExtensions.contains(ext)) {
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
                  color: palette.dimText(0.7),
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
                    color: palette.dimText(0.4),
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
                    borderSide: BorderSide(color: palette.inputOutlineColor),
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
    for (final supportedExt in InteractiveRunbookSidebarState._supportedExtensions) {
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
                  color: palette.dimText(0.7),
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
                    color: palette.dimText(0.4),
                  ),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.inputOutlineColor),
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
                  color: palette.dimText(0.7),
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
                    color: palette.dimText(0.4),
                  ),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: palette.inputOutlineColor),
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
      popUpAnimationStyle: AnimationStyle.noAnimation,
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
      popUpAnimationStyle: AnimationStyle.noAnimation,
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
}
