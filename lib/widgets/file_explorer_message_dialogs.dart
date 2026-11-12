part of 'file_explorer_dialogs.dart';

// Confirm, drop-action, notification and prompt dialogs.

/// 3. Confirmation Dialog (Delete, Copy, Move, Exit)
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
    this.borderColor = const Color(0xFF98C379),
    this.confirmText = 'Yes',
    this.cancelText = 'No',
    this.defaultYes = true,
  });

  @override
  State<FileExplorerConfirmDialog> createState() => _FileExplorerConfirmDialogState();
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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.tab) {
              setState(() => _selectedYes = !_selectedYes);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              Navigator.pop(context, _selectedYes);
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
        child: Container(
          width: 480,
          decoration: BoxDecoration(
            color: const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: widget.borderColor, width: 1.8),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title on border
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: widget.borderColor,
                        thickness: 1.5,
                        indent: 14,
                        endIndent: 8,
                      ),
                    ),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: widget.borderColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: widget.borderColor,
                        thickness: 1.5,
                        indent: 8,
                        endIndent: 14,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  children: [
                    Text(
                      widget.message1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD8DEE9),
                      ),
                    ),
                    if (widget.message2 != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.message2!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFF5C6370),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TerminalButton(
                      label: '[  ${widget.confirmText}  ]',
                      isSelected: _selectedYes,
                      highlightColor: const Color(0xFF56B6C2),
                      onTap: () => Navigator.pop(context, true),
                    ),
                    const SizedBox(width: 24),
                    _TerminalButton(
                      label: '[  ${widget.cancelText}  ]',
                      isSelected: !_selectedYes,
                      highlightColor: const Color(0xFF56B6C2),
                      onTap: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color highlightColor;
  final VoidCallback onTap;

  const _TerminalButton({
    required this.label,
    required this.isSelected,
    required this.highlightColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? highlightColor : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.black : const Color(0xFFABB2BF),
          ),
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
  State<FileExplorerDropActionDialog> createState() => _FileExplorerDropActionDialogState();
}

class _FileExplorerDropActionDialogState extends State<FileExplorerDropActionDialog> {
  int _selectedIndex = 0; // 0: Copy, 1: Move, 2: Cancel

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              setState(() => _selectedIndex = (_selectedIndex - 1 + 3) % 3);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.tab) {
              setState(() => _selectedIndex = (_selectedIndex + 1) % 3);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (_selectedIndex == 0) {
                Navigator.pop(context, FileDropAction.copy);
              } else if (_selectedIndex == 1) {
                Navigator.pop(context, FileDropAction.move);
              } else {
                Navigator.pop(context, null);
              }
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
        child: Container(
          width: 520,
          decoration: BoxDecoration(
            color: const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF56B6C2), width: 1.8),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Divider(
                        color: Color(0xFF56B6C2),
                        thickness: 1.5,
                        indent: 14,
                        endIndent: 8,
                      ),
                    ),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF56B6C2),
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Expanded(
                      child: Divider(
                        color: Color(0xFF56B6C2),
                        thickness: 1.5,
                        indent: 8,
                        endIndent: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Color(0xFFD8DEE9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.destPath != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Target: ${widget.destPath}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFF5C6370),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildOptionButton(
                      index: 0,
                      label: '[c] Copy',
                      action: FileDropAction.copy,
                      color: const Color(0xFF98C379),
                    ),
                    const SizedBox(width: 14),
                    _buildOptionButton(
                      index: 1,
                      label: '[m] Move',
                      action: FileDropAction.move,
                      color: const Color(0xFF56B6C2),
                    ),
                    const SizedBox(width: 14),
                    _buildOptionButton(
                      index: 2,
                      label: '[Esc] Cancel',
                      action: null,
                      color: const Color(0xFF5C6370),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required int index,
    required String label,
    required FileDropAction? action,
    required Color color,
  }) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => Navigator.pop(context, action),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.25) : const Color(0xFF181A20),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF2C313C),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : const Color(0xFFABB2BF),
          ),
        ),
      ),
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
    this.borderColor = const Color(0xFF56B6C2),
    this.icon,
    this.buttonText = 'OK',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(context, true);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 500,
          decoration: BoxDecoration(
            color: const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 1.8),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title on border
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: borderColor,
                        thickness: 1.5,
                        indent: 14,
                        endIndent: 8,
                      ),
                    ),
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: borderColor),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: borderColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: borderColor,
                        thickness: 1.5,
                        indent: 8,
                        endIndent: 14,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Column(
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD8DEE9),
                      ),
                    ),
                    if (subMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFFABB2BF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Button
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TerminalButton(
                      label: '[  $buttonText  ]',
                      isSelected: true,
                      highlightColor: borderColor,
                      onTap: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 4. Prompt Input Dialog (Create File, Create Folder, Rename, Merge)
class FileExplorerPromptDialog extends StatefulWidget {
  final String title;
  final String promptLabel;
  final String initialValue;

  const FileExplorerPromptDialog({
    super.key,
    required this.title,
    required this.promptLabel,
    this.initialValue = '',
  });

  @override
  State<FileExplorerPromptDialog> createState() => _FileExplorerPromptDialogState();
}

class _FileExplorerPromptDialogState extends State<FileExplorerPromptDialog> {
  late TextEditingController _controller;

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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 460,
        decoration: BoxDecoration(
          color: const Color(0xFF1E222B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF98C379), width: 1.8),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Divider(
                      color: Color(0xFF98C379),
                      thickness: 1.5,
                      indent: 14,
                      endIndent: 8,
                    ),
                  ),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF98C379),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Expanded(
                    child: Divider(
                      color: Color(0xFF98C379),
                      thickness: 1.5,
                      indent: 8,
                      endIndent: 14,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.promptLabel,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFABB2BF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0xFFD8DEE9),
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF181A20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF2C313C)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF56B6C2)),
                      ),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        Navigator.pop(context, val.trim());
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF56B6C2),
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () {
                      final val = _controller.text.trim();
                      if (val.isNotEmpty) {
                        Navigator.pop(context, val);
                      }
                    },
                    child: const Text('  OK  '),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF5C6370))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
