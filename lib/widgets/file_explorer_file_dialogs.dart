part of 'file_explorer_dialogs.dart';

// View-file and open-with dialogs.

/// Edits (or only shows, when read-only) a file's text and saves through [onSave].
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
  State<FileExplorerViewFileDialog> createState() =>
      _FileExplorerViewFileDialogState();
}

class _FileExplorerViewFileDialogState
    extends State<FileExplorerViewFileDialog> {
  late TextEditingController _controller;
  bool _isSaving = false;
  String? _saveError;

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
    return _DialogShell(
      title: widget.fileName,
      rawTitle: true,
      icon: Icons.description_outlined,
      width: 860,
      height: 600,
      insetPadding: const EdgeInsets.all(24),
      onClose: () => Navigator.pop(context),
      child: Column(
        children: [
          if (!widget.readOnly && widget.onSave != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.save, size: 16),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _Dlg.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    onPressed: _isSaving ? null : _save,
                  ),
                ],
              ),
            ),
          if (_saveError != null)
            Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: const Color(0xFF2B1D20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: _Dlg.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _saveError!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _Dlg.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Container(
              color: _Dlg.editor,
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                readOnly: widget.readOnly,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _Dlg.textPrimary,
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
    );
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      await widget.onSave!(_controller.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _saveError = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

/// Picks the editor for a .log or .txt file; keys 1-5, j/k and Enter work without the mouse.
class FileExplorerOpenWithDialog extends StatefulWidget {
  final String fileName;
  final ExternalEditor defaultEditor;

  const FileExplorerOpenWithDialog({
    super.key,
    required this.fileName,
    this.defaultEditor = ExternalEditor.notepadPlusPlus,
  });

  @override
  State<FileExplorerOpenWithDialog> createState() =>
      _FileExplorerOpenWithDialogState();
}

class _FileExplorerOpenWithDialogState
    extends State<FileExplorerOpenWithDialog> {
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
    return Focus(
      autofocus: true,
      skipTraversal: true,
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
              _selectedIndex =
                  (_selectedIndex - 1 + _options.length) % _options.length;
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
      child: _DialogShell(
        title: 'OPEN WITH',
        icon: Icons.open_in_new,
        width: 520,
        onClose: () => Navigator.of(context).pop(null),
        footerLeading: const Text(
          '↑/↓ or j/k to move  ·  1-5 to choose  ·  Enter to open',
          style: TextStyle(fontSize: 11, color: _Dlg.textMuted),
        ),
        actions: [
          _TerminalButton(
            label: 'Cancel',
            shortcut: 'Esc',
            isSelected: false,
            highlightColor: _Dlg.accent,
            onTap: () => Navigator.of(context).pop(null),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 14,
                    color: _Dlg.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _Dlg.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: _Dlg.divider),
            for (var idx = 0; idx < _options.length; idx++)
              _buildOption(idx),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(int idx) {
    final opt = _options[idx];
    final isDefault = opt == widget.defaultEditor;
    final icon = switch (opt) {
      ExternalEditor.notepadPlusPlus => Icons.edit_note,
      ExternalEditor.nvim => Icons.terminal,
      ExternalEditor.vscode => Icons.code,
      ExternalEditor.zed => Icons.bolt,
      ExternalEditor.internalViewer => Icons.visibility,
    };

    return Semantics(
      button: true,
      selected: idx == _selectedIndex,
      label: '${idx + 1}. ${opt.label}${isDefault ? ', default' : ''}',
      onTap: () => _submit(opt),
      excludeSemantics: true,
      child: SizedBox(
        height: PaletteRow.extent,
        child: PaletteRow(
          icon: icon,
          label: opt.label,
          isSelected: idx == _selectedIndex,
          onTap: () => _submit(opt),
          trailing: [
            if (isDefault)
              const PaletteBadge(text: 'DEFAULT', color: _Dlg.accent),
            _Keycap('${idx + 1}'),
          ],
        ),
      ),
    );
  }
}
