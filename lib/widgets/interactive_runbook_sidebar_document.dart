// Private members of InteractiveRunbookSidebarState live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'interactive_runbook_sidebar.dart';

/// Open runbook tabs: search, block selection and editing, Vim-style keys, saving.
extension _RunbookDocumentOps on InteractiveRunbookSidebarState {
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
    for (final supportedExt in InteractiveRunbookSidebarState._supportedExtensions) {
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
}
