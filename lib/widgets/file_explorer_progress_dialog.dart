part of 'file_explorer_dialogs.dart';

// Transfer progress dialog.

/// Transfer Progress State
class FileTransferProgress {
  final String title;
  final String currentFile;
  final int completedItems;
  final int totalItems;
  final double progress; // 0.0 to 1.0
  final bool isIndeterminate;
  final int? currentBytes;
  final int? totalBytes;

  /// Set when the transfer failed. The dialog then shows this text instead of
  /// the progress bar and offers Close.
  final String? errorMessage;

  /// Extra state line under the counts, e.g. "Queued" or "Cancelling...".
  final String? note;

  const FileTransferProgress({
    required this.title,
    required this.currentFile,
    required this.completedItems,
    required this.totalItems,
    required this.progress,
    this.isIndeterminate = false,
    this.currentBytes,
    this.totalBytes,
    this.errorMessage,
    this.note,
  });
}

/// Modal progress dialog for a copy or move. The transfer itself runs in the
/// app-wide transfer queue, so closing the dialog never stops it:
/// [onBackground] (also Esc) hides the dialog and leaves progress to the
/// transfer bar, while [onCancel] stops the transfer. A failed transfer shows
/// its error with a single Close button (also [onBackground]).
class FileExplorerProgressDialog extends StatelessWidget {
  final ValueNotifier<FileTransferProgress> progressNotifier;
  final VoidCallback onBackground;
  final VoidCallback? onCancel;

  const FileExplorerProgressDialog({
    super.key,
    required this.progressNotifier,
    required this.onBackground,
    this.onCancel,
  });

  static final _detail = TextStyle(fontSize: 11.5, color: _Dlg.textSecondary);

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onBackground();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ValueListenableBuilder<FileTransferProgress>(
        valueListenable: progressNotifier,
        builder: (context, data, _) {
          final pct = (data.progress.clamp(0.0, 1.0) * 100).toInt();
          final failed = data.errorMessage != null;
          final status =
              data.currentBytes != null &&
                  data.totalBytes != null &&
                  data.totalBytes! > 0
              ? 'Progress: [${data.completedItems}/${data.totalItems}] items ($pct%) • ${FileExplorerItem.formatSize(data.currentBytes!)} / ${FileExplorerItem.formatSize(data.totalBytes!)}'
              : 'Progress: [${data.completedItems}/${data.totalItems}] items ($pct%)';

          return _DialogShell(
            title: failed ? '${data.title} failed' : data.title,
            rawTitle: true,
            icon: failed ? Icons.error_outline : Icons.sync_alt,
            accent: failed ? _Dlg.danger : _Dlg.accent,
            width: 480,
            onClose: onBackground,
            actions: [
              if (!failed && onCancel != null)
                _TerminalButton(
                  label: 'Cancel transfer',
                  isSelected: false,
                  highlightColor: _Dlg.danger,
                  onTap: onCancel!,
                ),
              _TerminalButton(
                label: failed ? 'Close' : 'Run in background',
                shortcut: failed ? null : 'Esc',
                isSelected: true,
                autofocus: true,
                highlightColor: _Dlg.accent,
                onTap: onBackground,
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (data.currentFile.isNotEmpty) ...[
                    Text(
                      'Item: ${data.currentFile}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _Dlg.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (failed)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        data.errorMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _Dlg.danger,
                        ),
                      ),
                    )
                  else ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(status, style: _detail),
                    ),
                    if (data.note != null) ...[
                      const SizedBox(height: 4),
                      Text(data.note!, style: _detail),
                    ],
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: data.isIndeterminate
                            ? null
                            : data.progress.clamp(0.0, 1.0),
                        backgroundColor: _Dlg.field,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _Dlg.accent,
                        ),
                        minHeight: 8,
                        semanticsLabel: data.title,
                        semanticsValue: '$pct%',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
