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

  const FileTransferProgress({
    required this.title,
    required this.currentFile,
    required this.completedItems,
    required this.totalItems,
    required this.progress,
    this.isIndeterminate = false,
    this.currentBytes,
    this.totalBytes,
  });
}

/// Retro terminal modal progress dialog for file transfers (copy / move)
class FileExplorerProgressDialog extends StatelessWidget {
  final ValueNotifier<FileTransferProgress> progressNotifier;
  final VoidCallback? onCancel;

  const FileExplorerProgressDialog({
    super.key,
    required this.progressNotifier,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ValueListenableBuilder<FileTransferProgress>(
        valueListenable: progressNotifier,
        builder: (context, data, _) {
          final pct = (data.progress.clamp(0.0, 1.0) * 100).toInt();

          return Container(
            width: 480,
            padding: const EdgeInsets.all(20),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                Row(
                  children: [
                    const Icon(Icons.sync_alt, color: Color(0xFF56B6C2), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      data.title.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF56B6C2),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Current item info
                if (data.currentFile.isNotEmpty) ...[
                  Text(
                    'Item: ${data.currentFile}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFD8DEE9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data.currentBytes != null && data.totalBytes != null && data.totalBytes! > 0
                        ? 'Progress: [${data.completedItems}/${data.totalItems}] files ($pct%) • ${FileExplorerItem.formatSize(data.currentBytes!)} / ${FileExplorerItem.formatSize(data.totalBytes!)}'
                        : 'Progress: [${data.completedItems}/${data.totalItems}] files ($pct%)',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF5C6370),
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: data.isIndeterminate ? null : data.progress.clamp(0.0, 1.0),
                    backgroundColor: const Color(0xFF2C313C),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF56B6C2)),
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 16),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onCancel != null)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE06C75),
                          side: const BorderSide(color: Color(0xFFE06C75)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onPressed: onCancel,
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
