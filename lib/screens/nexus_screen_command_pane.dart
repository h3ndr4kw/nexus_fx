// Private members of NexusScreenState live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'nexus_screen.dart';

/// Command pane: broadcast input, history, snippets, node picker and the destructive-command guard.
extension _NexusCommandPane on NexusScreenState {
  Widget _buildCommandPaneToggleButton() {
    final palette = AppTheme.activePalette;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.inputBorderColor),
        ),
      ),
      child: Tooltip(
        message: _showCommandPane ? 'Hide command pane (Ctrl+Shift+Space)' : 'Show command pane (Ctrl+Shift+Space)',
        child: InkWell(
          key: const ValueKey('nexus_command_pane_toggle_button'),
          onTap: toggleCommandPane,
          child: Container(
            color: _showCommandPane
                ? palette.primaryColor.withValues(alpha: 0.15)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Icon(
              Icons.terminal,
              size: 16,
              color: _showCommandPane
                  ? palette.primaryColor
                  : palette.dimText(0.7),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleCommandInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isControl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
    final isShift = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
    final isSpace = event.logicalKey == LogicalKeyboardKey.space ||
        event.physicalKey == PhysicalKeyboardKey.space;

    if (isControl && isShift && isSpace) {
      return KeyEventResult.handled;
    }

    if (isControl && !isShift && event.logicalKey == LogicalKeyboardKey.keyK) {
      _openSnippetPicker();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (isShift) {
        // Shift+Enter allows newline insertion in multiline TextField
        return KeyEventResult.ignored;
      } else {
        // Enter sends command
        if (!_isSendingCommands) {
          _sendBroadcastCommand();
        }
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      final isControl = HardwareKeyboard.instance.isControlPressed;
      final isAlt = HardwareKeyboard.instance.isAltPressed;
      final isMeta = HardwareKeyboard.instance.isMetaPressed;
      if (!isShift && !isControl && !isAlt && !isMeta) {
        if (_navigateCommandHistory(up: true)) {
          return KeyEventResult.handled;
        }
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      final isControl = HardwareKeyboard.instance.isControlPressed;
      final isAlt = HardwareKeyboard.instance.isAltPressed;
      final isMeta = HardwareKeyboard.instance.isMetaPressed;
      if (!isShift && !isControl && !isAlt && !isMeta) {
        if (_navigateCommandHistory(up: false)) {
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  bool _navigateCommandHistory({required bool up}) {
    if (_commandHistory.isEmpty) return false;

    final text = _commandInputController.text;
    final selection = _commandInputController.selection;

    if (up) {
      if (text.contains('\n') && selection.baseOffset > text.indexOf('\n')) {
        return false;
      }

      final cmd = _broadcastCoordinator.navigateHistoryUp(text);
      if (cmd != null) {
        _commandInputController.value = TextEditingValue(
          text: cmd,
          selection: TextSelection.collapsed(offset: cmd.length),
        );
        return true;
      }
      return false;
    } else {
      if (text.contains('\n') && selection.baseOffset <= text.lastIndexOf('\n')) {
        return false;
      }

      final cmd = _broadcastCoordinator.navigateHistoryDown();
      if (cmd != null) {
        _commandInputController.value = TextEditingValue(
          text: cmd,
          selection: TextSelection.collapsed(offset: cmd.length),
        );
        return true;
      }
      return false;
    }
  }

  String _shortcutLabel(String key) => Platform.isMacOS ? '⌘$key' : 'Ctrl+$key';

  void _toggleConnectionSelection(String id) {
    setState(() {
      _broadcastCoordinator.toggleSelection(id);
      _broadcastCoordinator.updateBroadcastTargetFromSelection(
        leftTabs: _tabs,
        rightTabs: _rightTabs,
      );
    });
  }

  void _updateBroadcastTargetFromSelection() {
    _broadcastCoordinator.updateBroadcastTargetFromSelection(
      leftTabs: _tabs,
      rightTabs: _rightTabs,
    );
  }

  Future<void> _sendBroadcastCommand() async {
    final rawText = _commandInputController.text;

    final targetConnections = _broadcastCoordinator.resolveTargetConnections(
      leftTabs: _tabs,
      rightTabs: _rightTabs,
      isSplitView: _isSplitView,
    );

    if (targetConnections.isEmpty) {
      final targetName = _broadcastTarget == BroadcastTarget.left
          ? 'left pane'
          : (_broadcastTarget == BroadcastTarget.right
              ? 'right pane'
              : (_broadcastTarget == BroadcastTarget.custom
                  ? 'selected targets'
                  : 'active'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('No connected SSH sessions in $targetName to send command.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (rawText.trim().isEmpty) return;

    final dangerous = _findDestructiveLines(rawText);
    if (dangerous.isNotEmpty) {
      final confirmed = await _confirmDestructiveCommand(
        lines: dangerous,
        nodeCount: targetConnections.length,
      );
      if (confirmed != true || !mounted) return;
    }

    await _broadcastCoordinator.executeBroadcast(
      targetConnections: targetConnections,
      rawText: rawText,
    );

    if (mounted) {
      _commandInputController.clear();
    }
  }

  List<String> _findDestructiveLines(String rawText) {
    return rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => NexusScreenState._destructivePatterns.any((p) => p.hasMatch(l)))
        .toList();
  }

  Future<bool?> _confirmDestructiveCommand({
    required List<String> lines,
    required int nodeCount,
  }) {
    final palette = AppTheme.activePalette;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surfaceColor,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Run potentially destructive command?',
                style: TextStyle(color: palette.textColor, fontSize: 15),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following line(s) match destructive patterns and will be executed on $nodeCount node${nodeCount == 1 ? '' : 's'}:',
              style: TextStyle(
                color: palette.textColor.withValues(alpha: 0.8),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines
                    .map((l) => Text(
                          l,
                          style: const TextStyle(
                            fontFamily: 'Courier New',
                            fontSize: 12,
                            color: Colors.amber,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Proceed & Execute'),
          ),
        ],
      ),
    );
  }

  // Snippets and history actions
  Future<void> _openSnippetPicker() async {
    final selected = await SnippetPickerModal.show(context);
    if (selected != null && mounted) {
      _commandInputController.value = TextEditingValue(
        text: selected.fullScript,
        selection: TextSelection.collapsed(offset: selected.fullScript.length),
      );
      _commandFocusNode.requestFocus();
    }
  }

  Widget _buildSnippetsButton() {
    final palette = AppTheme.activePalette;
    return Tooltip(
      message: 'Snippets (${_shortcutLabel('K')})',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openSnippetPicker,
          borderRadius: BorderRadius.circular(6),
          hoverColor: palette.primaryColor.withValues(alpha: 0.12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
            decoration: BoxDecoration(
              color: palette.background.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.inputBorderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 13,
                  color: palette.textColor.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryButton() {
    final palette = AppTheme.activePalette;
    return PopupMenuButton<String>(
      tooltip: 'Command History',
      color: palette.surfaceColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.inputBorderColor),
      ),
      padding: EdgeInsets.zero,
      onSelected: (cmd) {
        _commandInputController.value = TextEditingValue(
          text: cmd,
          selection: TextSelection.collapsed(offset: cmd.length),
        );
        _commandFocusNode.requestFocus();
      },
      itemBuilder: (context) {
        if (_commandHistory.isEmpty) {
          return [
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                'No history yet',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Courier New',
                  color: palette.dimText(0.5),
                ),
              ),
            ),
          ];
        }
        return _commandHistory.reversed.take(15).map((cmd) {
          final lines = cmd
              .split('\n')
              .map((l) => l.trimRight())
              .where((l) => l.isNotEmpty)
              .toList();
          final isMulti = lines.length > 1;
          final firstLine = lines.isNotEmpty ? lines.first : cmd;

          return PopupMenuItem<String>(
            value: cmd,
            child: SizedBox(
              width: 320,
              child: Row(
                children: [
                  Icon(
                    isMulti ? Icons.article_outlined : Icons.terminal_rounded,
                    size: 13,
                    color: isMulti
                        ? palette.primaryColor
                        : palette.dimText(0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      firstLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 11.5,
                        color: palette.textColor,
                      ),
                    ),
                  ),
                  if (isMulti) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: palette.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: palette.primaryColor.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${lines.length} lines',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'Courier New',
                          fontWeight: FontWeight.bold,
                          color: palette.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList();
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: palette.background.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: palette.inputBorderColor),
          ),
          child: Icon(
            Icons.history_rounded,
            size: 14,
            color: palette.dimText(0.7),
          ),
        ),
      ),
    );
  }

  // Target node picker
  Widget _buildNodePicker() {
    final palette = AppTheme.activePalette;
    final allConns = [..._tabs, ..._rightTabs];
    final selectedCount = _selectedConnectionIds.length;

    return Tooltip(
      message: 'Select target nodes ($selectedCount active)',
      child: FuzzySearchableDropdown<SshConnection>(
        openUpward: true,
        popupWidth: 280,
        items: allConns,
        selectedItem: null,
        hintText: 'Search & toggle node...',
        searchPlaceholder: 'Search node by name or host...',
        itemLabel: (c) =>
            c.currentLabel.isNotEmpty ? c.currentLabel : c.currentHost,
        itemSubtitle: (c) =>
            '${c.currentHost} • ${c.isConnected ? 'online' : 'offline'}',
        searchTerms: (c) => [c.currentLabel, c.currentHost],
        itemBadge: (c) => _selectedConnectionIds.contains(c.id)
            ? Icon(Icons.check_circle_rounded,
                size: 14, color: palette.primaryColor)
            : const SizedBox.shrink(),
        onChanged: (c) {
          if (c != null) _toggleConnectionSelection(c.id);
        },
        customTrigger: (context, isOpen) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6.5),
            decoration: BoxDecoration(
              color: isOpen
                  ? palette.primaryColor.withValues(alpha: 0.18)
                  : palette.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isOpen
                    ? palette.primaryColor
                    : (selectedCount > 0
                        ? palette.primaryColor.withValues(alpha: 0.5)
                        : palette.inputBorderColor),
                width: isOpen ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 15,
                  color: selectedCount > 0
                      ? palette.primaryColor
                      : palette.dimText(0.6),
                ),
                if (selectedCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$selectedCount',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: palette.primaryColor,
                    ),
                  ),
                ],
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 13,
                  color: palette.dimText(0.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int get _targetNodeCount {
    return _broadcastCoordinator.resolveTargetConnections(
      leftTabs: _tabs,
      rightTabs: _rightTabs,
      isSplitView: _isSplitView,
    ).length;
  }

  Widget _buildRunButton() {
    final palette = AppTheme.activePalette;
    final activeColor = palette.primaryColor;

    return ListenableBuilder(
      listenable: _commandInputController,
      builder: (context, _) {
        final nodeCount = _targetNodeCount;
        final hasText = _commandInputController.text.trim().isNotEmpty;
        final canRun = !_isSendingCommands && hasText && nodeCount > 0;
        final isActive = canRun || _isSendingCommands;

        final tooltipMessage = _isSendingCommands
            ? 'Executing...'
            : (nodeCount == 0
                ? 'No target node selected'
                : (!hasText
                    ? 'Enter command'
                    : 'Run on $nodeCount node${nodeCount == 1 ? '' : 's'} (Enter)'));

        return Tooltip(
          message: tooltipMessage,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canRun ? _sendBroadcastCommand : null,
              borderRadius: BorderRadius.circular(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: isActive
                      ? activeColor
                      : palette.textColor.withValues(alpha: 0.08),
                  border: Border.all(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.25)
                        : palette.textColor.withValues(alpha: 0.06),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: _isSendingCommands
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        Icons.play_arrow_rounded,
                        size: 19,
                        color: isActive
                            ? Colors.black
                            : palette.dimText(0.3),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Command toolbar
  Widget _buildDevopsToolbarCommandPane() {
    final palette = AppTheme.activePalette;
    return Container(
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isSendingCommands
              ? palette.primaryColor.withValues(alpha: 0.4)
              : palette.textColor.withValues(alpha: 0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 26,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3.5),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isSendingCommands
                ? palette.primaryColor
                : palette.textColor.withValues(alpha: 0.22),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            if (_isSendingCommands)
              BoxShadow(
                color: palette.primaryColor.withValues(alpha: 0.3),
                blurRadius: 14,
                spreadRadius: 1,
              ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Node Picker on the left
            _buildNodePicker(),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: palette.textColor.withValues(alpha: 0.12),
            ),
            // Command Input Box
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): () {
                    if (!_isSendingCommands) {
                      _sendBroadcastCommand();
                    }
                  },
                  const SingleActivator(
                    LogicalKeyboardKey.numpadEnter,
                  ): () {
                    if (!_isSendingCommands) {
                      _sendBroadcastCommand();
                    }
                  },
                },
                child: TextField(
                  controller: _commandInputController,
                  focusNode: _commandFocusNode,
                  minLines: 1,
                  maxLines: 4,
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12.5,
                    color: palette.textColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    hintText: 'Enter command to broadcast...',
                    hintStyle: TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 12,
                      color: palette.dimText(0.35),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Quick Actions (Snippets & History)
            _buildSnippetsButton(),
            const SizedBox(width: 4),
            _buildHistoryButton(),
            const SizedBox(width: 8),
            // Run Button
            _buildRunButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingCommandPane() {
    return _buildDevopsToolbarCommandPane();
  }

  Widget _buildFullscreenButton() {
    final palette = AppTheme.activePalette;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.inputBorderColor),
        ),
      ),
      child: Tooltip(
        message: 'Fullscreen session (Ctrl+Shift+Enter)',
        child: InkWell(
          key: const ValueKey('nexus_fullscreen_button'),
          onTap: _activeConnection == null ? null : toggleSessionFullscreen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Icon(
              Icons.fullscreen,
              size: 18,
              color: palette.dimText(0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitButton() {
    final palette = AppTheme.activePalette;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.inputBorderColor),
        ),
      ),
      child: Tooltip(
        message: _isSplitView ? 'Close split view' : 'Split view',
        child: InkWell(
          key: const ValueKey('nexus_split_button'),
          onTap: _toggleSplitView,
          child: Container(
            color: _isSplitView
                ? palette.primaryColor.withValues(alpha: 0.15)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: SplitScreenIcon(
              size: 16,
              color: _isSplitView
                  ? palette.primaryColor
                  : palette.dimText(0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCloseAllButton() {
    final palette = AppTheme.activePalette;
    return Container(
      height: 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.inputBorderColor),
        ),
      ),
      child: Tooltip(
        message: 'Close all tabs',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: _confirmAndCloseAll,
            borderRadius: BorderRadius.circular(4),
            hoverColor: palette.errorColor.withValues(alpha: 0.15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: palette.errorColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: palette.errorColor.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 14,
                    color: palette.errorColor,
                  ),
                  const SizedBox(width: 4.5),
                  Text(
                    'Close All',
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.errorColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
