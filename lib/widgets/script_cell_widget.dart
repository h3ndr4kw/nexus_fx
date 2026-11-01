import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexus_fx/models/playbook_models.dart';
import 'package:nexus_fx/theme/app_theme.dart';

/// A [TextEditingController] that highlights case-insensitive occurrences of [searchQuery].
class HighlightingTextEditingController extends TextEditingController {
  String searchQuery;
  int? activeMatchIndex;

  HighlightingTextEditingController({
    super.text,
    this.searchQuery = '',
    this.activeMatchIndex,
  });

  void updateSearchHighlight(String query, int? newActiveMatchIndex) {
    if (searchQuery != query || activeMatchIndex != newActiveMatchIndex) {
      searchQuery = query;
      activeMatchIndex = newActiveMatchIndex;
      notifyListeners();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final rawText = text;
    final query = searchQuery;
    if (query.isEmpty || rawText.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final lowerText = rawText.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int matchIdx = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        if (start < rawText.length) {
          spans.add(TextSpan(text: rawText.substring(start), style: style));
        }
        break;
      }

      if (index > start) {
        spans.add(
          TextSpan(text: rawText.substring(start, index), style: style),
        );
      }

      final isCurrentActive =
          activeMatchIndex != null && matchIdx == activeMatchIndex;
      final matchText = rawText.substring(index, index + query.length);
      spans.add(
        TextSpan(
          text: matchText,
          style: (style ?? const TextStyle()).copyWith(
            backgroundColor: isCurrentActive
                ? Colors.orange.withValues(alpha: 0.85)
                : Colors.amber.withValues(alpha: 0.45),
            color: isCurrentActive ? Colors.black : style?.color,
            fontWeight: isCurrentActive ? FontWeight.bold : style?.fontWeight,
          ),
        ),
      );

      start = index + query.length;
      matchIdx++;
    }

    return TextSpan(style: style, children: spans);
  }
}

/// Interactive script cell widget with line numbers gutter, toolbar (copy, target node, send),
/// and selection-aware line extraction.
class ScriptCellWidget extends StatefulWidget {
  final PlaybookBlock block;
  final List<String> availableTargets;
  final String selectedTarget;
  final ValueChanged<String>? onTargetChanged;
  final FutureOr<void> Function(List<String> linesToRun, String targetNode)
  onSend;
  final VoidCallback? onContentChanged;
  final VoidCallback? onDelete;
  final String searchQuery;
  final int? activeMatchIndexInBlock;
  final bool? isSelected;
  final VoidCallback? onSelect;
  final VoidCallback? onExitEdit;
  final void Function(PlaybookBlockType type)? onInsertAbove;
  final void Function(PlaybookBlockType type)? onInsertBelow;
  final bool isPrecededByTextBlock;

  const ScriptCellWidget({
    super.key,
    required this.block,
    required this.availableTargets,
    required this.selectedTarget,
    this.onTargetChanged,
    required this.onSend,
    this.onContentChanged,
    this.onDelete,
    this.searchQuery = '',
    this.activeMatchIndexInBlock,
    this.isSelected,
    this.onSelect,
    this.onExitEdit,
    this.onInsertAbove,
    this.onInsertBelow,
    this.isPrecededByTextBlock = false,
  });

  @override
  State<ScriptCellWidget> createState() => ScriptCellWidgetState();
}

class ScriptCellWidgetState extends State<ScriptCellWidget> {
  late HighlightingTextEditingController _controller;
  late FocusNode _focusNode;
  late String _currentTarget;
  final GlobalKey<PopupMenuButtonState<String>> _leftTargetDropdownKey =
      GlobalKey<PopupMenuButtonState<String>>();
  bool _isTopHovered = false;
  bool _isBottomHovered = false;
  bool _isBoxHovered = false;
  bool _isFloatingBarHovered = false;
  bool _isSending = false;
  bool _isTargetDropdownOpen = false;

  bool get _showFloatingActions => _isBoxHovered || _isFloatingBarHovered;

  bool get hasEditorFocus => _focusNode.hasFocus;

  void requestEditorFocus() {
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  void showTargetDropdown() {
    if (_leftTargetDropdownKey.currentState != null) {
      _leftTargetDropdownKey.currentState!.showButtonMenu();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _leftTargetDropdownKey.currentState?.showButtonMenu();
        }
      });
    }
  }

  Future<void> executeScript() => _executeScript();

  bool get _isSelected {
    if (widget.isSelected != null) {
      return widget.isSelected!;
    }
    return _focusNode.hasFocus;
  }

  @override
  void initState() {
    super.initState();
    _currentTarget = widget.selectedTarget;
    final normalized = widget.block.content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    _controller = HighlightingTextEditingController(
      text: normalized,
      searchQuery: widget.searchQuery,
      activeMatchIndex: widget.activeMatchIndexInBlock,
    );
    _focusNode = FocusNode(onKeyEvent: _handleEditorKeyEvent);
    _focusNode.addListener(_onFocusChanged);
    _controller.addListener(_onControllerChanged);
    HardwareKeyboard.instance.addHandler(_handleDropdownKey);
  }

  bool _handleDropdownKey(KeyEvent event) {
    if (!_isTargetDropdownOpen) return false;
    if (event is! KeyDownEvent) return false;

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

    if (isCtrl || isShift || isAlt) return false;

    final isKeyJ = event.logicalKey == LogicalKeyboardKey.keyJ ||
        event.physicalKey == PhysicalKeyboardKey.keyJ ||
        event.character == 'j';
    final isKeyK = event.logicalKey == LogicalKeyboardKey.keyK ||
        event.physicalKey == PhysicalKeyboardKey.keyK ||
        event.character == 'k';

    if (isKeyJ) {
      FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.down);
      return true;
    }
    if (isKeyK) {
      FocusManager.instance.primaryFocus?.focusInDirection(TraversalDirection.up);
      return true;
    }
    return false;
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
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

    if ((isCtrl || isShift) && !isAlt && isEnter) {
      if (event is KeyDownEvent) {
        _executeScript();
      }
      return KeyEventResult.handled;
    }

    final isEscape = event.logicalKey == LogicalKeyboardKey.escape ||
        event.physicalKey == PhysicalKeyboardKey.escape;

    if (isEscape && !isCtrl && !isShift && !isAlt) {
      if (event is KeyDownEvent) {
        _focusNode.unfocus();
        widget.onExitEdit?.call();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      widget.onSelect?.call();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(ScriptCellWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected == false && oldWidget.isSelected == true && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
    if (widget.selectedTarget != oldWidget.selectedTarget) {
      _currentTarget = widget.selectedTarget;
    }
    if (widget.block.content != _controller.text) {
      final oldSelection = _controller.selection;
      final normalized = widget.block.content
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      _controller.text = normalized;
      if (oldSelection.end <= normalized.length) {
        _controller.selection = oldSelection;
      }
      widget.block.lastExecutedTime = null;
      widget.block.lastExecutedTarget = null;
    }
    _controller.updateSearchHighlight(
      widget.searchQuery,
      widget.activeMatchIndexInBlock,
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleDropdownKey);
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.block.content != _controller.text) {
      widget.block.content = _controller.text;
      widget.block.lastExecutedTime = null;
      widget.block.lastExecutedTarget = null;
      widget.onContentChanged?.call();
    }
    if (mounted) {
      setState(() {});
    }
  }

  List<String> _getAllLines() {
    final normalized = _controller.text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final rawLines = normalized.split('\n');
    while (rawLines.isNotEmpty && rawLines.last.trim().isEmpty) {
      rawLines.removeLast();
    }
    return rawLines;
  }

  List<String> _getSelectedLines() {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed || selection.start < 0) {
      return [];
    }

    final text = _controller.text;
    final selStart = math.min(selection.start, selection.end);
    final selEnd = math.max(selection.start, selection.end);
    if (selStart >= selEnd || selStart >= text.length) {
      return [];
    }

    final rawLines = text.split('\n');
    final selected = <String>[];
    var offset = 0;

    for (int i = 0; i < rawLines.length; i++) {
      final lineContent = rawLines[i];
      final lineStart = offset;
      final isLast = i == rawLines.length - 1;
      final lineEnd = isLast ? text.length : offset + lineContent.length + 1;

      final overlapStart = math.max(lineStart, selStart);
      final overlapEnd = math.min(lineEnd, selEnd);
      if (overlapStart < overlapEnd) {
        selected.add(lineContent);
      }

      offset = lineEnd;
    }

    while (selected.isNotEmpty && selected.last.trim().isEmpty) {
      selected.removeLast();
    }

    return selected;
  }

  Future<void> _executeScript() async {
    if (_isSending) return;
    final allLines = _getAllLines();
    final selectedLines = _getSelectedLines();
    final hasSelection = selectedLines.isNotEmpty;
    final linesToSend = hasSelection ? selectedLines : allLines;

    setState(() {
      _isSending = true;
    });
    try {
      await widget.onSend(linesToSend, _currentTarget);
      if (mounted) {
        setState(() {
          if (!hasSelection || selectedLines.length == allLines.length) {
            widget.block.lastExecutedTime = DateTime.now();
            widget.block.lastExecutedTarget = _currentTarget;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  String _lineCountSuffix(int count) {
    return count == 1 ? 'line' : 'lines';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.activePalette;
    final allLines = _getAllLines();
    final selectedLines = _getSelectedLines();
    final hasSelection = selectedLines.isNotEmpty;

    final count = hasSelection ? selectedLines.length : allLines.length;
    final defaultButtonLabel = hasSelection
        ? 'Send Selected ($count ${_lineCountSuffix(count)})'
        : 'Send All ($count ${_lineCountSuffix(count)})';

    final isSent = widget.block.lastExecutedTime != null;
    final String buttonLabel;
    if (_isSending) {
      buttonLabel = 'Sending to $_currentTarget...';
    } else if (hasSelection) {
      buttonLabel = defaultButtonLabel;
    } else if (isSent) {
      final t = widget.block.lastExecutedTime!;
      final timeStr =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
      final targetStr = widget.block.lastExecutedTarget ?? _currentTarget;
      buttonLabel = 'Sent to $targetStr at $timeStr (Click to re-run)';
    } else {
      buttonLabel = defaultButtonLabel;
    }

    final targets = widget.availableTargets.contains(_currentTarget)
        ? widget.availableTargets
        : [_currentTarget, ...widget.availableTargets];

    final selectedColor = palette.primaryColor;
    final isSelected = _isSelected;
    final lineCount = math.max(1, _controller.text.split('\n').length);

    final topPadding = widget.isPrecededByTextBlock ? 6.0 : 14.0;
    final showBottomPill = _isBottomHovered;

    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Stack(
        clipBehavior: Clip.none,
        children: [
          // Left indicator box (box tipis penanda script cell terseleksi)
          Positioned(
            left: 0,
            top: topPadding,
            bottom: 14,
            child: AnimatedContainer(
              key: const Key('script_cell_selected_indicator'),
              duration: const Duration(milliseconds: 150),
              width: 3.5,
              decoration: BoxDecoration(
                color: isSelected ? selectedColor : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Left gutter: Send button (▷ ˅) and [ ]
          Positioned(
            left: 6,
            top: topPadding,
            width: 38,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: buttonLabel,
                      child: InkWell(
                        key: const Key('script_cell_send_button'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: _isSending ? null : _executeScript,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: _isSending
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: Padding(
                                    padding: const EdgeInsets.all(1.5),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: palette.accentColor,
                                    ),
                                  ),
                                )
                              : (isSent && !hasSelection)
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Color(0xFF66BB6A),
                                )
                              : Icon(
                                  Icons.play_arrow_outlined,
                                  size: 16,
                                  color: palette.textColor.withValues(alpha: 0.9),
                                ),
                        ),
                      ),
                    ),
                    KeyedSubtree(
                      key: const Key('script_cell_left_target_dropdown'),
                      child: PopupMenuButton<String>(
                        key: _leftTargetDropdownKey,
                        tooltip: 'Target: $_currentTarget (t)',
                        initialValue: _currentTarget,
                        color: palette.surfaceColor,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onOpened: () {
                          if (mounted) {
                            setState(() {
                              _isTargetDropdownOpen = true;
                            });
                          }
                        },
                        onCanceled: () {
                          if (mounted) {
                            setState(() {
                              _isTargetDropdownOpen = false;
                            });
                          }
                        },
                        itemBuilder: (context) => targets
                            .map(
                              (target) => PopupMenuItem<String>(
                                value: target,
                                height: 34,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      target.startsWith('Synced')
                                          ? Icons.sync
                                          : Icons.dns_outlined,
                                      size: 14,
                                      color: palette.accentColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      target,
                                      style: TextStyle(
                                        fontFamily: 'Courier',
                                        fontSize: 12,
                                        fontWeight: target == _currentTarget
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: target == _currentTarget
                                            ? palette.primaryColor
                                            : palette.textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onSelected: (newTarget) {
                          setState(() {
                            _isTargetDropdownOpen = false;
                            _currentTarget = newTarget;
                            if (widget.block.lastExecutedTarget != null &&
                                widget.block.lastExecutedTarget != newTarget) {
                              widget.block.lastExecutedTime = null;
                              widget.block.lastExecutedTarget = null;
                            }
                          });
                          widget.onTargetChanged?.call(newTarget);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Icon(
                            Icons.arrow_drop_down,
                            size: 14,
                            color: palette.textColor.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Main Cell Box
          Padding(
            padding: EdgeInsets.fromLTRB(48, topPadding, 0, 14),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (!_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                }
                widget.onSelect?.call();
              },
              child: MouseRegion(
                onEnter: (_) => setState(() => _isBoxHovered = true),
                onExit: (_) => setState(() => _isBoxHovered = false),
                child: AnimatedContainer(
                  key: const Key('script_cell_container'),
                    duration: const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(minHeight: 41),
                    decoration: BoxDecoration(
                      color: palette.surfaceColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? selectedColor
                            : palette.inputBorderColor,
                        width: 1.0,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                    // Line numbers gutter
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: palette.background.withValues(alpha: 0.3),
                        border: Border(
                          right: BorderSide(
                            color: palette.inputBorderColor.withValues(
                              alpha: 0.5,
                            ),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(
                          lineCount,
                          (index) => Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 13,
                              height: 1.45,
                              color: palette.textColor.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Script content TextField
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 2,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 13,
                            height: 1.45,
                            color: palette.textColor,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
          child: MouseRegion(
            onEnter: (_) => setState(() => _isTopHovered = true),
            onExit: (_) => setState(() => _isTopHovered = false),
            child: Center(
              child: AnimatedOpacity(
                opacity: _isTopHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !_isTopHovered,
                  child: Container(
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
                          message: 'Add Script Cell above',
                          child: InkWell(
                            key: ValueKey('add_script_above_${widget.block.id}'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => widget.onInsertAbove!(
                              PlaybookBlockType.scriptCell,
                            ),
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
                          message: 'Add Text Box above',
                          child: InkWell(
                            key: ValueKey('add_text_above_${widget.block.id}'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => widget.onInsertAbove!(
                              PlaybookBlockType.text,
                            ),
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
                  ),
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
            child: MouseRegion(
              onEnter: (_) => setState(() => _isBottomHovered = true),
              onExit: (_) => setState(() => _isBottomHovered = false),
              child: Center(
                child: AnimatedOpacity(
                  opacity: showBottomPill ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: !showBottomPill,
                    child: Container(
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
                            message: 'Add Script Cell below',
                            child: InkWell(
                              key: ValueKey('add_script_below_${widget.block.id}'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => widget.onInsertBelow!(
                                PlaybookBlockType.scriptCell,
                              ),
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
                            message: 'Add Text Box below',
                            child: InkWell(
                              key: ValueKey('add_text_below_${widget.block.id}'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => widget.onInsertBelow!(
                                PlaybookBlockType.text,
                              ),
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Floating Action Box (Target dropdown, Divider, Copy, Delete)
        Positioned(
          top: 2,
          right: 12,
          child: AnimatedOpacity(
            opacity: _showFloatingActions ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: !_showFloatingActions,
              child: MouseRegion(
                onEnter: (_) => setState(() => _isFloatingBarHovered = true),
                onExit: (_) => setState(() => _isFloatingBarHovered = false),
                child: Container(
              decoration: BoxDecoration(
                color: palette.surfaceColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.inputBorderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Target selector (icon only popup menu)
                  Tooltip(
                    message: 'Target: $_currentTarget',
                    child: PopupMenuButton<String>(
                      key: const Key('script_cell_target_dropdown'),
                      tooltip: '',
                      initialValue: _currentTarget,
                      color: palette.surfaceColor,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onOpened: () {
                        if (mounted) {
                          setState(() {
                            _isTargetDropdownOpen = true;
                          });
                        }
                      },
                      onCanceled: () {
                        if (mounted) {
                          setState(() {
                            _isTargetDropdownOpen = false;
                          });
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _currentTarget.startsWith('Synced')
                                  ? Icons.sync
                                  : Icons.dns_outlined,
                              size: 14,
                              color: palette.accentColor,
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              color: palette.textColor.withValues(alpha: 0.7),
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (context) => targets
                          .map(
                            (target) => PopupMenuItem<String>(
                              value: target,
                              height: 34,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    target.startsWith('Synced')
                                        ? Icons.sync
                                        : Icons.dns_outlined,
                                    size: 14,
                                    color: palette.accentColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    target,
                                    style: TextStyle(
                                      fontFamily: 'Courier',
                                      fontSize: 12,
                                      fontWeight: target == _currentTarget
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: target == _currentTarget
                                          ? palette.primaryColor
                                          : palette.textColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onSelected: (newTarget) {
                        setState(() {
                          _isTargetDropdownOpen = false;
                          _currentTarget = newTarget;
                          if (widget.block.lastExecutedTarget != null &&
                              widget.block.lastExecutedTarget != newTarget) {
                            widget.block.lastExecutedTime = null;
                            widget.block.lastExecutedTarget = null;
                          }
                        });
                        widget.onTargetChanged?.call(newTarget);
                      },
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: palette.inputBorderColor,
                  ),
                  // Copy button
                  IconButton(
                    tooltip: 'Copy cell script',
                    icon: Icon(
                      Icons.copy,
                      size: 14,
                      color: palette.textColor.withValues(alpha: 0.85),
                    ),
                    splashRadius: 14,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _controller.text),
                      );
                    },
                  ),
                  if (widget.onDelete != null) ...[
                    Container(
                      width: 1,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: palette.inputBorderColor,
                    ),
                    IconButton(
                      key: ValueKey('delete_script_cell_${widget.block.id}'),
                      tooltip: 'Delete Cell',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 15,
                        color: palette.errorColor.withValues(alpha: 0.85),
                      ),
                      splashRadius: 14,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      onPressed: widget.onDelete,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    ],
  ),
],
);
}
}
