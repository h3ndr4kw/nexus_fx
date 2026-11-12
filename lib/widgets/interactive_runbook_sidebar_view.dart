// Private members of InteractiveRunbookSidebarState live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'interactive_runbook_sidebar.dart';

/// Widget builders for the sidebar: tab bar, files tab, document tab, toolbars, find bar, blocks.
extension _RunbookViewBuilders on InteractiveRunbookSidebarState {
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
                                : palette.dimText(0.75),
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
                        color: palette.dimText(0.6),
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
              color: palette.dimText(0.7),
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
                    color: palette.dimText(0.4),
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
                    : palette.dimText(0.6),
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
