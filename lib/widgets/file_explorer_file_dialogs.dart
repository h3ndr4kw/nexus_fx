part of 'file_explorer_dialogs.dart';

// View-file and open-with dialogs.

/// 5. View/Edit File Modal Dialog
class FileExplorerViewFileDialog extends StatefulWidget {
  final String fileName;
  final String initialContent;
  final bool readOnly;
  final Future<void> Function(String newContent)? onSave;

  const FileExplorerViewFileDialog({
    super.key,
    required this.fileName,
    required this.initialContent,
    this.readOnly = false,
    this.onSave,
  });

  @override
  State<FileExplorerViewFileDialog> createState() => _FileExplorerViewFileDialogState();
}

class _FileExplorerViewFileDialogState extends State<FileExplorerViewFileDialog> {
  late TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
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
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 860,
        height: 600,
        decoration: BoxDecoration(
          color: const Color(0xFF1E222B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF56B6C2), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2C313C))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, color: Color(0xFF56B6C2), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF56B6C2),
                    ),
                  ),
                  const Spacer(),
                  if (!widget.readOnly && widget.onSave != null)
                    ElevatedButton.icon(
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.save, size: 16),
                      label: const Text('Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF98C379),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: _isSaving
                          ? null
                          : () async {
                              setState(() => _isSaving = true);
                              try {
                                await widget.onSave!(_controller.text);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('File saved successfully')),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _isSaving = false);
                              }
                            },
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF5C6370)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Container(
                color: const Color(0xFF14171E),
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  readOnly: widget.readOnly,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFFD8DEE9),
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 8. Open With Dialog for *.log and *.txt files
class FileExplorerOpenWithDialog extends StatefulWidget {
  final String fileName;
  final ExternalEditor defaultEditor;

  const FileExplorerOpenWithDialog({
    super.key,
    required this.fileName,
    this.defaultEditor = ExternalEditor.notepadPlusPlus,
  });

  @override
  State<FileExplorerOpenWithDialog> createState() => _FileExplorerOpenWithDialogState();
}

class _FileExplorerOpenWithDialogState extends State<FileExplorerOpenWithDialog> {
  static const List<ExternalEditor> _options = [
    ExternalEditor.notepadPlusPlus,
    ExternalEditor.nvim,
    ExternalEditor.vscode,
    ExternalEditor.zed,
    ExternalEditor.internalViewer,
  ];

  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    final idx = _options.indexOf(widget.defaultEditor);
    _selectedIndex = idx >= 0 ? idx : 0;
  }

  void _submit(ExternalEditor editor) {
    Navigator.of(context).pop(editor);
  }

  @override
  Widget build(BuildContext context) {
    const borderColor = Color(0xFF56B6C2); // Cyan border
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.keyJ) {
              setState(() {
                _selectedIndex = (_selectedIndex + 1) % _options.length;
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.keyK) {
              setState(() {
                _selectedIndex = (_selectedIndex - 1 + _options.length) % _options.length;
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              _submit(_options[_selectedIndex]);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.digit1 ||
                event.logicalKey == LogicalKeyboardKey.numpad1) {
              _submit(_options[0]);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.digit2 ||
                event.logicalKey == LogicalKeyboardKey.numpad2) {
              _submit(_options[1]);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.digit3 ||
                event.logicalKey == LogicalKeyboardKey.numpad3) {
              _submit(_options[2]);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.digit4 ||
                event.logicalKey == LogicalKeyboardKey.numpad4) {
              _submit(_options[3]);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.digit5 ||
                event.logicalKey == LogicalKeyboardKey.numpad5) {
              _submit(_options[4]);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.keyQ) {
              Navigator.of(context).pop(null);
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title bar
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Divider(
                        color: borderColor,
                        thickness: 1.5,
                        indent: 14,
                        endIndent: 8,
                      ),
                    ),
                    const Text(
                      'OPEN WITH',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: borderColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Expanded(
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

              // Target filename info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282C34),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 14, color: Color(0xFF98C379)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.fileName,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFFE5C07B),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Options list
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Column(
                  children: List.generate(_options.length, (idx) {
                    final opt = _options[idx];
                    final isSelected = idx == _selectedIndex;
                    final isDefault = opt == widget.defaultEditor;

                    IconData icon;
                    switch (opt) {
                      case ExternalEditor.notepadPlusPlus:
                        icon = Icons.edit_note;
                        break;
                      case ExternalEditor.nvim:
                        icon = Icons.terminal;
                        break;
                      case ExternalEditor.vscode:
                        icon = Icons.code;
                        break;
                      case ExternalEditor.zed:
                        icon = Icons.bolt;
                        break;
                      case ExternalEditor.internalViewer:
                        icon = Icons.visibility;
                        break;
                    }

                    return InkWell(
                      onTap: () => _submit(opt),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF3E4452) : Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: isSelected ? borderColor : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '[${idx + 1}]',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? const Color(0xFF61AFEF) : const Color(0xFF5C6370),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              icon,
                              size: 16,
                              color: isSelected ? borderColor : const Color(0xFFABB2BF),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                opt.label,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.white : const Color(0xFFDCDFE4),
                                ),
                              ),
                            ),
                            if (isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0x3398C379),
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: const Color(0xFF98C379), width: 0.8),
                                ),
                                child: const Text(
                                  '[Default]',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF98C379),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const Divider(color: Color(0xFF3E4452), thickness: 1, indent: 20, endIndent: 20),

              // Bottom footer hint & cancel button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '[↑/↓/j/k] Move  [1-5] Choose  [Enter] Open',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFF5C6370),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TerminalButton(
                      label: '[Esc] Cancel',
                      isSelected: false,
                      highlightColor: const Color(0xFFE06C75),
                      onTap: () => Navigator.of(context).pop(null),
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
