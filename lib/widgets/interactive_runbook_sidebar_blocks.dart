part of 'interactive_runbook_sidebar.dart';

// Document block widgets: hover container with insert pills, and the inline text editor.

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
