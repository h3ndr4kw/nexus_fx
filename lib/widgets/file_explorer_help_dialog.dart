part of 'file_explorer_dialogs.dart';

// Keyboard shortcut help.

/// 1. HELP (Shortcuts) dialog matching image 3 exactly
class FileExplorerHelpDialog extends StatelessWidget {
  const FileExplorerHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Focus(
        autofocus: true,
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
        child: Container(
          width: 580,
          decoration: BoxDecoration(
            color: const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF98C379), // Light green border
              width: 1.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title bar with horizontal lines
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
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
                    const Text(
                      'HELP (Shortcuts)',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF56B6C2), // Cyan title
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

              // Two-column shortcuts matching screenshot 3 and vim/dest navigation
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _ShortcutRow('[Tab]', 'Switch Pane'),
                          _ShortcutRow('[Ctrl+h/l]', 'Focus Left/Right'),
                          _ShortcutRow('[Ctrl+t]', 'New Tab'),
                          _ShortcutRow('[Ctrl+w]', 'Close Tab'),
                          _ShortcutRow('[Ctrl+Tab]', 'Next Tab'),
                          _ShortcutRow('[j/k]', 'Move Down/Up'),
                          _ShortcutRow('[Space]', 'Select/Unselect'),
                          _ShortcutRow('[c]', 'Copy Selected'),
                          _ShortcutRow('[d/Del]', 'Delete Selected'),
                          _ShortcutRow('[r]', 'Rename Active'),
                          _ShortcutRow('[Ctrl+j]', 'Merge Selected'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _ShortcutRow('[Ctrl+d]', 'Dual Pane'),
                          _ShortcutRow('[Ctrl+Shift+S]', 'Appearance/Font'),
                          _ShortcutRow('[Ctrl +/-]', 'Zoom In / Out'),
                          _ShortcutRow('[/]', 'Filter List'),
                          _ShortcutRow('[Ctrl+Space]', 'Browse Dest/Target'),
                          _ShortcutRow('[m]', 'Move Selected'),
                          _ShortcutRow('[n/N]', 'New File/Dir'),
                          _ShortcutRow('[o/v]', 'Edit File'),
                          _ShortcutRow('[Esc/q]', 'Exit Explorer'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Close hint
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF2C313C), width: 1),
                  ),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Press Enter or Esc to close',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF5C6370),
                  ),
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
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              keyLabel,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFABB2BF),
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFD8DEE9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
