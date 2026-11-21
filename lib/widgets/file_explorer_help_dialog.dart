part of 'file_explorer_dialogs.dart';

// Keyboard shortcut help.

/// Keyboard shortcut reference for the File Explorer.
class FileExplorerHelpDialog extends StatelessWidget {
  const FileExplorerHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.keyQ) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: _DialogShell(
        title: 'Keyboard Shortcuts',
        icon: Icons.keyboard_outlined,
        width: 620,
        onClose: () => Navigator.of(context).pop(),
        footerLeading: const Text(
          'Press Enter or Esc to close',
          style: TextStyle(fontSize: 11, color: _Dlg.textMuted),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShortcutRow('Tab', 'Switch Pane'),
                    _ShortcutRow('Ctrl+h/l', 'Focus Left/Right'),
                    _ShortcutRow('Ctrl+t', 'New Tab'),
                    _ShortcutRow('Ctrl+w', 'Close Tab'),
                    _ShortcutRow('Ctrl+Tab', 'Next Tab'),
                    _ShortcutRow('j/k', 'Move Down/Up'),
                    _ShortcutRow('Space', 'Select/Unselect'),
                    _ShortcutRow('c', 'Copy Selected'),
                    _ShortcutRow('d/Del', 'Delete Selected'),
                    _ShortcutRow('r', 'Rename Active'),
                    _ShortcutRow('Ctrl+j', 'Merge Selected'),
                    _ShortcutRow('=', 'Compare Selected'),
                  ],
                ),
              ),
              SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShortcutRow('Ctrl+d', 'Dual Pane'),
                    _ShortcutRow('Ctrl+Shift+S', 'Appearance/Font'),
                    _ShortcutRow('Ctrl +/-', 'Zoom In / Out'),
                    _ShortcutRow('/', 'Filter List'),
                    _ShortcutRow('Ctrl+Space', 'Browse Dest/Target'),
                    _ShortcutRow('m', 'Move Selected'),
                    _ShortcutRow('n/N', 'New File/Dir'),
                    _ShortcutRow('o/v', 'Edit File'),
                    _ShortcutRow('z', 'Compress Selected'),
                    _ShortcutRow('x', 'Extract Archive'),
                    _ShortcutRow('Esc/q', 'Exit Explorer'),
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

class _ShortcutRow extends StatelessWidget {
  final String keyLabel;
  final String description;

  const _ShortcutRow(this.keyLabel, this.description);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _Dlg.field,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _Dlg.outline),
                ),
                child: Text(
                  keyLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _Dlg.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 12.5, color: _Dlg.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
