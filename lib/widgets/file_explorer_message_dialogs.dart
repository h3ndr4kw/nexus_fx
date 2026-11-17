part of 'file_explorer_dialogs.dart';

// Confirm, drop-action, notification and prompt dialogs.

/// Body text for the message dialogs: a primary line and an optional muted one.
class _DialogMessage extends StatelessWidget {
  final String message;
  final String? detail;

  const _DialogMessage({required this.message, this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: _Dlg.textPrimary,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              style: const TextStyle(fontSize: 12, color: _Dlg.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Yes/No confirmation for copy, move and delete. The default button is focused;
/// y, n and Esc answer without moving focus.
class FileExplorerConfirmDialog extends StatefulWidget {
  final String title;
  final String message1;
  final String? message2;
  final Color borderColor;
  final String confirmText;
  final String cancelText;
  final bool defaultYes;

  const FileExplorerConfirmDialog({
    super.key,
    required this.title,
    required this.message1,
    this.message2,
    this.borderColor = _Dlg.accent,
    this.confirmText = 'Yes',
    this.cancelText = 'No',
    this.defaultYes = true,
  });

  @override
  State<FileExplorerConfirmDialog> createState() =>
      _FileExplorerConfirmDialogState();
}

class _FileExplorerConfirmDialogState extends State<FileExplorerConfirmDialog> {
  late bool _selectedYes;

  @override
  void initState() {
    super.initState();
    _selectedYes = widget.defaultYes;
  }

  @override
  Widget build(BuildContext context) {
    final isDanger = widget.borderColor == _Dlg.danger;
    return Focus(
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            FocusManager.instance.primaryFocus?.previousFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            FocusManager.instance.primaryFocus?.nextFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyY) {
            Navigator.pop(context, true);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyN ||
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context, false);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: _DialogShell(
        title: widget.title,
        icon: isDanger ? Icons.delete_outline : Icons.help_outline,
        accent: widget.borderColor,
        width: 480,
        onClose: () => Navigator.pop(context, false),
        actions: [
          _TerminalButton(
            label: widget.confirmText,
            shortcut: 'Y',
            isSelected: _selectedYes,
            highlightColor: widget.borderColor,
            autofocus: widget.defaultYes,
            onFocusChange: (f) {
              if (f && !_selectedYes) {
                setState(() => _selectedYes = true);
              }
            },
            onTap: () => Navigator.pop(context, true),
          ),
          _TerminalButton(
            label: widget.cancelText,
            shortcut: 'N',
            isSelected: !_selectedYes,
            highlightColor: _Dlg.accent,
            autofocus: !widget.defaultYes,
            onFocusChange: (f) {
              if (f && _selectedYes) {
                setState(() => _selectedYes = false);
              }
            },
            onTap: () => Navigator.pop(context, false),
          ),
        ],
        child: _DialogMessage(message: widget.message1, detail: widget.message2),
      ),
    );
  }
}

/// Shared dialog button. A real tab stop: Enter/Space activate it, a white ring
/// shows keyboard focus, hover tints it, and it reports as a button to screen
/// readers. `isSelected` marks the default/chosen action. A label written as
/// `[c] Copy` renders `c` as a keycap; `[  Yes  ]` renders as plain `Yes`.
class _TerminalButton extends StatefulWidget {
  final String label;
  final String? shortcut;
  final bool isSelected;
  final Color highlightColor;
  final VoidCallback onTap;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  const _TerminalButton({
    required this.label,
    required this.isSelected,
    required this.highlightColor,
    required this.onTap,
    this.shortcut,
    this.autofocus = false,
    this.onFocusChange,
  });

  @override
  State<_TerminalButton> createState() => _TerminalButtonState();
}

class _TerminalButtonState extends State<_TerminalButton> {
  static final _bracketLabel = RegExp(r'^\[\s*([^\]]*?)\s*\]\s*(.*)$');

  bool _hovered = false;
  bool _focused = false;

  (String?, String) _split() {
    final m = _bracketLabel.firstMatch(widget.label);
    if (m == null) return (widget.shortcut, widget.label);
    final rest = m[2]!.trim();
    if (rest.isEmpty) return (widget.shortcut, m[1]!);
    return (widget.shortcut ?? m[1]!, rest);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.highlightColor;
    final selected = widget.isSelected;
    final (shortcut, text) = _split();

    final background = selected
        ? color.withValues(alpha: 0.15)
        : _hovered
        ? _Dlg.divider
        : _Dlg.field;
    final foreground = selected ? color : _Dlg.textPrimary;
    final border = _focused
        ? Colors.white
        : selected
        ? color.withValues(alpha: 0.7)
        : _Dlg.outline;

    return Semantics(
      button: true,
      selected: selected,
      focusable: true,
      focused: _focused,
      label: text,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onFocusChange: widget.onFocusChange,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border, width: _focused ? 2 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                ),
                if (shortcut != null) ...[
                  const SizedBox(width: 8),
                  _Keycap(shortcut),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small key label in the style of the palette's ESC keycap.
class _Keycap extends StatelessWidget {
  final String keyLabel;

  const _Keycap(this.keyLabel);

  @override
  Widget build(BuildContext context) {
    final label = keyLabel.length <= 3 ? keyLabel.toUpperCase() : keyLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _Dlg.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _Dlg.outline),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: _Dlg.textSecondary,
        ),
      ),
    );
  }
}

enum FileDropAction { copy, move }

/// Dialog shown when dragging and dropping files across panes to choose Copy or Move
class FileExplorerDropActionDialog extends StatefulWidget {
  final String title;
  final String message;
  final String? destPath;

  const FileExplorerDropActionDialog({
    super.key,
    required this.title,
    required this.message,
    this.destPath,
  });

  @override
  State<FileExplorerDropActionDialog> createState() =>
      _FileExplorerDropActionDialogState();
}

class _FileExplorerDropActionDialogState
    extends State<FileExplorerDropActionDialog> {
  int _selectedIndex = 0; // 0: Copy, 1: Move, 2: Cancel

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            FocusManager.instance.primaryFocus?.previousFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            FocusManager.instance.primaryFocus?.nextFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
            Navigator.pop(context, FileDropAction.copy);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
            Navigator.pop(context, FileDropAction.move);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.keyQ) {
            Navigator.pop(context, null);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: _DialogShell(
        title: widget.title,
        icon: Icons.swap_horiz,
        width: 520,
        onClose: () => Navigator.pop(context, null),
        actions: [
          _buildOptionButton(
            index: 0,
            label: 'Copy',
            shortcut: 'C',
            action: FileDropAction.copy,
          ),
          _buildOptionButton(
            index: 1,
            label: 'Move',
            shortcut: 'M',
            action: FileDropAction.move,
          ),
          _buildOptionButton(
            index: 2,
            label: 'Cancel',
            action: null,
          ),
        ],
        child: _DialogMessage(
          message: widget.message,
          detail: widget.destPath == null ? null : 'Target: ${widget.destPath}',
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required int index,
    required String label,
    String? shortcut,
    required FileDropAction? action,
  }) {
    return _TerminalButton(
      label: label,
      shortcut: shortcut,
      isSelected: _selectedIndex == index,
      highlightColor: _Dlg.accent,
      autofocus: index == 0,
      onFocusChange: (f) {
        if (f && _selectedIndex != index) {
          setState(() => _selectedIndex = index);
        }
      },
      onTap: () => Navigator.pop(context, action),
    );
  }
}

/// Notification Alert Dialog (e.g. Wireshark launch/not installed, alert messages)
class FileExplorerNotificationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? subMessage;
  final Color borderColor;
  final IconData? icon;
  final String buttonText;

  const FileExplorerNotificationDialog({
    super.key,
    required this.title,
    required this.message,
    this.subMessage,
    this.borderColor = _Dlg.accent,
    this.icon,
    this.buttonText = 'OK',
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context, true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _DialogShell(
        title: title,
        icon: icon ?? Icons.info_outline,
        accent: borderColor,
        width: 500,
        onClose: () => Navigator.pop(context, true),
        actions: [
          _TerminalButton(
            label: buttonText,
            isSelected: true,
            autofocus: true,
            highlightColor: borderColor,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
        child: _DialogMessage(message: message, detail: subMessage),
      ),
    );
  }
}

/// One-line text prompt (change directory, create, rename, merge). Stays open
/// with an inline message when the value is empty or rejected by [validator].
class FileExplorerPromptDialog extends StatefulWidget {
  final String title;
  final String promptLabel;
  final String initialValue;

  /// Returns an error message to keep the dialog open with, or null when the
  /// trimmed value is acceptable. An empty value is always rejected.
  final String? Function(String value)? validator;

  const FileExplorerPromptDialog({
    super.key,
    required this.title,
    required this.promptLabel,
    this.initialValue = '',
    this.validator,
  });

  @override
  State<FileExplorerPromptDialog> createState() =>
      _FileExplorerPromptDialogState();
}

class _FileExplorerPromptDialogState extends State<FileExplorerPromptDialog> {
  late TextEditingController _controller;
  String? _error;

  void _submit() {
    final val = _controller.text.trim();
    final error = val.isEmpty
        ? 'This field cannot be empty.'
        : widget.validator?.call(val);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, val);
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: widget.title,
      icon: Icons.edit_outlined,
      width: 460,
      onClose: () => Navigator.pop(context),
      actions: [
        _TerminalButton(
          label: 'Cancel',
          isSelected: false,
          highlightColor: _Dlg.accent,
          onTap: () => Navigator.pop(context),
        ),
        _TerminalButton(
          label: 'OK',
          shortcut: 'Enter',
          isSelected: true,
          highlightColor: _Dlg.accent,
          onTap: _submit,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.promptLabel,
              style: const TextStyle(fontSize: 12, color: _Dlg.textSecondary),
            ),
            const SizedBox(height: 8),
            MergeSemantics(
              child: Semantics(
                label: widget.promptLabel,
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _Dlg.textPrimary,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _Dlg.field,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: _Dlg.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: _Dlg.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: _Dlg.accent, width: 1.5),
                    ),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: _Dlg.danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _Dlg.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
