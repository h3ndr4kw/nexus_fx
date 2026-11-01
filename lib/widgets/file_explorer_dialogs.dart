import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/file_explorer_models.dart';
import '../models/session_models.dart';
import '../services/file_explorer_service.dart';
import '../services/session_manager_service.dart';
import '../services/settings_service.dart';

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

/// 2. Node Picker Dialog (Network Manager, OAM, FE, Local, Custom SSH)
class FileExplorerNodePickerDialog extends StatefulWidget {
  final ExplorerNodeTarget currentTarget;

  const FileExplorerNodePickerDialog({super.key, required this.currentTarget});

  @override
  State<FileExplorerNodePickerDialog> createState() => _FileExplorerNodePickerDialogState();
}

class _FileExplorerNodePickerDialogState extends State<FileExplorerNodePickerDialog> {
  String _searchFilter = '';
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _searchFocusNode = FocusNode(onKeyEvent: (node, event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_lastFilteredNodes.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1).clamp(0, _lastFilteredNodes.length - 1);
        });
        _scrollToIndex(_selectedIndex);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_lastFilteredNodes.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1).clamp(0, _lastFilteredNodes.length - 1);
        });
        _scrollToIndex(_selectedIndex);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_lastFilteredNodes.isNotEmpty &&
          _selectedIndex >= 0 &&
          _selectedIndex < _lastFilteredNodes.length) {
        _selectNode(_lastFilteredNodes[_selectedIndex]);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });

  List<ExplorerNodeTarget> _lastFilteredNodes = [];

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 54.0;
    final targetOffset = index * itemHeight;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final viewport = _scrollController.position.viewportDimension;
    if (targetOffset < _scrollController.offset) {
      _scrollController.jumpTo(targetOffset.clamp(0.0, maxScroll));
    } else if (targetOffset + itemHeight > _scrollController.offset + viewport) {
      _scrollController.jumpTo((targetOffset + itemHeight - viewport).clamp(0.0, maxScroll));
    }
  }

  Future<void> _selectNode(ExplorerNodeTarget node) async {
    if (node.type == ExplorerTargetType.networkManager && node.host.isEmpty) {
      final edited = await _showEditNodeCredentialsDialog(context, node);
      if (edited != null && mounted) {
        Navigator.pop(context, edited);
      }
    } else {
      if (mounted) {
        Navigator.pop(context, node);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = SessionManagerService.instance.sessions;

    final filter = _searchFilter.trim().toLowerCase();

    // Build list of node options
    final List<ExplorerNodeTarget> nodeOptions = [
      ExplorerNodeTarget.local,
      ...sessions
          .where((s) => s.protocol == SessionProtocol.ssh)
          .map((s) => ExplorerNodeTarget.fromSessionProfile(s)),
    ];

    // Filter
    final filtered = filter.isEmpty
        ? nodeOptions
        : nodeOptions.where((n) {
            return n.label.toLowerCase().contains(filter) ||
                n.host.toLowerCase().contains(filter);
          }).toList();
    _lastFilteredNodes = filtered;
    final safeIndex = filtered.isEmpty ? 0 : _selectedIndex.clamp(0, filtered.length - 1);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 600,
        height: 520,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2C313C))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_sync_outlined, color: Color(0xFF56B6C2), size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'SELECT BROWSE TARGET',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF56B6C2),
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF5C6370)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search filter
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                onChanged: (val) {
                  setState(() {
                    _searchFilter = val;
                    _selectedIndex = 0;
                  });
                },
                onSubmitted: (_) {
                  if (filtered.isNotEmpty && safeIndex >= 0 && safeIndex < filtered.length) {
                    _selectNode(filtered[safeIndex]);
                  }
                },
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Color(0xFFD8DEE9),
                ),
                decoration: InputDecoration(
                  hintText: 'Filter nodes... [↑/↓] Navigate  [Enter] Select',
                  hintStyle: const TextStyle(fontFamily: 'monospace', color: Color(0xFF5C6370)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF5C6370)),
                  filled: true,
                  fillColor: const Color(0xFF181A20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF2C313C)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF2C313C)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: Color(0xFF56B6C2)),
                  ),
                ),
              ),
            ),

            // Nodes List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: filtered.length,
                itemBuilder: (context, idx) {
                  final node = filtered[idx];
                  final isSelected = idx == safeIndex;
                  final isCurrent = widget.currentTarget.type == node.type &&
                      widget.currentTarget.host == node.host;

                  IconData icon;
                  Color iconColor;
                  String typeTag;

                  switch (node.type) {
                    case ExplorerTargetType.local:
                      icon = Icons.computer;
                      iconColor = const Color(0xFF98C379);
                      typeTag = 'LOCAL';
                      break;
                    case ExplorerTargetType.networkManager:
                      icon = Icons.hub_outlined;
                      iconColor = const Color(0xFFE5C07B);
                      typeTag = 'NM JUMP';
                      break;
                    case ExplorerTargetType.oam:
                      icon = Icons.dns_outlined;
                      iconColor = const Color(0xFF61AFEF);
                      typeTag = 'OAM';
                      break;
                    case ExplorerTargetType.fe:
                      icon = Icons.developer_board;
                      iconColor = const Color(0xFFC678DD);
                      typeTag = 'FE';
                      break;
                    case ExplorerTargetType.customSsh:
                      icon = Icons.terminal;
                      iconColor = const Color(0xFFE06C75);
                      typeTag = 'SSH';
                      break;
                    case ExplorerTargetType.sessionSsh:
                      icon = Icons.lan;
                      iconColor = const Color(0xFF56B6C2);
                      typeTag = 'SESSION';
                      break;
                  }

                  Color cardBg;
                  Color cardBorder;
                  if (isSelected) {
                    cardBg = const Color(0xFF2B3A4A);
                    cardBorder = const Color(0xFF56B6C2);
                  } else if (isCurrent) {
                    cardBg = const Color(0xFF222834);
                    cardBorder = const Color(0xFF3E4451);
                  } else {
                    cardBg = const Color(0xFF181A20);
                    cardBorder = const Color(0xFF2C313C);
                  }

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: BorderSide(
                          color: cardBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(icon, color: iconColor, size: 20),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                node.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: (isSelected || isCurrent) ? FontWeight.bold : FontWeight.normal,
                                  color: (isSelected || isCurrent) ? Colors.white : const Color(0xFFD8DEE9),
                                ),
                              ),
                            ),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF56B6C2).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: const Color(0xFF56B6C2).withValues(alpha: 0.5),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF56B6C2),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: node.isLocal
                            ? null
                            : node.type == ExplorerTargetType.fe
                                ? Text(
                                    'Host: ${node.host} | OAM Hop (Passwordless)',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Color(0xFF5C6370),
                                    ),
                                  )
                                : Text(
                                    'Host: ${node.host} | User: ${node.username}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Color(0xFF5C6370),
                                    ),
                                  ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!node.isLocal && node.type != ExplorerTargetType.fe)
                              IconButton(
                                icon: const Icon(Icons.key, size: 14, color: Color(0xFF5C6370)),
                                tooltip: 'Edit Credentials for ${node.label}',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () async {
                                  final edited = await _showEditNodeCredentialsDialog(context, node);
                                  if (edited != null && context.mounted) {
                                    Navigator.pop(context, edited);
                                  }
                                },
                              ),
                            if (!node.isLocal && node.type != ExplorerTargetType.fe) const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                typeTag,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: iconColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _selectNode(node),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom action: Custom SSH connection
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF2C313C))),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_link, size: 16),
                    label: const Text(
                      'Connect Custom SSH Node...',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF56B6C2),
                      side: const BorderSide(color: Color(0xFF56B6C2)),
                    ),
                    onPressed: () async {
                      final custom = await _showCustomSshDialog(context);
                      if (custom != null && context.mounted) {
                        Navigator.pop(context, custom);
                      }
                    },
                  ),
                  const Spacer(),
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

  Future<ExplorerNodeTarget?> _showEditNodeCredentialsDialog(
    BuildContext context,
    ExplorerNodeTarget node,
  ) async {
    final hostCtrl = TextEditingController(text: node.host);
    final userCtrl = TextEditingController(text: node.username);
    final passCtrl = TextEditingController(text: node.password);
    bool obscure = true;

    return showDialog<ExplorerNodeTarget>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E222B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: Color(0xFF56B6C2), width: 1.5),
            ),
            title: Row(
              children: [
                const Icon(Icons.key, color: Color(0xFF56B6C2), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CREDENTIALS: ${node.label}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (node.host.isEmpty) ...[
                    TextField(
                      controller: hostCtrl,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Host IP / Hostname',
                        labelStyle: TextStyle(color: Color(0xFF5C6370)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF2C313C)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF56B6C2)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: Color(0xFF5C6370)),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2C313C)),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF56B6C2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Color(0xFF5C6370)),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2C313C)),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF56B6C2)),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: const Color(0xFF5C6370),
                        ),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF5C6370))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF56B6C2),
                  foregroundColor: const Color(0xFF1E222B),
                ),
                onPressed: () {
                  final newHost = hostCtrl.text.trim().isEmpty ? node.host : hostCtrl.text.trim();
                  final updated = node.copyWith(
                    host: newHost,
                    label: node.type == ExplorerTargetType.networkManager && newHost.isNotEmpty
                        ? 'Network Manager ($newHost)'
                        : node.label,
                    username: userCtrl.text.trim(),
                    password: passCtrl.text,
                  );
                  Navigator.pop(ctx, updated);
                },
                child: const Text('Save & Select', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<ExplorerNodeTarget?> _showCustomSshDialog(BuildContext context) async {
    final hostCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '22');
    final userCtrl = TextEditingController(text: 'root');
    final passCtrl = TextEditingController();

    return showDialog<ExplorerNodeTarget>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: Color(0xFF56B6C2), width: 1.5),
        ),
        title: const Text(
          'CONNECT CUSTOM SSH',
          style: TextStyle(fontFamily: 'monospace', color: Color(0xFF56B6C2), fontSize: 14),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hostCtrl,
                autofocus: true,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Host / IP',
                  labelStyle: TextStyle(fontFamily: 'monospace', color: Color(0xFF5C6370)),
                ),
              ),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Port',
                  labelStyle: TextStyle(fontFamily: 'monospace', color: Color(0xFF5C6370)),
                ),
              ),
              TextField(
                controller: userCtrl,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Username',
                  labelStyle: TextStyle(fontFamily: 'monospace', color: Color(0xFF5C6370)),
                ),
              ),
              TextField(
                controller: passCtrl,
                obscureText: true,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(fontFamily: 'monospace', color: Color(0xFF5C6370)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF5C6370))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF56B6C2),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final host = hostCtrl.text.trim();
              if (host.isEmpty) return;
              final port = int.tryParse(portCtrl.text.trim()) ?? 22;
              final user = userCtrl.text.trim();
              final pass = passCtrl.text;
              Navigator.pop(
                ctx,
                ExplorerNodeTarget(
                  type: ExplorerTargetType.customSsh,
                  label: 'SSH ($host)',
                  host: host,
                  port: port,
                  username: user,
                  password: pass,
                ),
              );
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

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



/// Appearance and font settings dialog for File Explorer
class FileExplorerSettingsDialog extends StatefulWidget {
  const FileExplorerSettingsDialog({super.key});

  @override
  State<FileExplorerSettingsDialog> createState() => _FileExplorerSettingsDialogState();
}

class _FileExplorerSettingsDialogState extends State<FileExplorerSettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;

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
                event.logicalKey == LogicalKeyboardKey.keyQ) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 600,
          decoration: BoxDecoration(
            color: const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF56B6C2),
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
                  children: const [
                    Expanded(
                      child: Divider(
                        color: Color(0xFF56B6C2),
                        thickness: 1.5,
                        indent: 14,
                        endIndent: 8,
                      ),
                    ),
                    Text(
                      'EXPLORER APPEARANCE & FONT SETTINGS',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF56B6C2),
                        letterSpacing: 1.1,
                      ),
                    ),
                    Expanded(
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Density & Size
                    _buildSectionHeader('DENSITY & SIZE', Icons.format_size_rounded),
                    const SizedBox(height: 6),
                    Row(
                      children: FileExplorerDensity.values.map((d) {
                        final isSelected = settings.fileExplorerDensity == d;
                        return Expanded(
                          child: _buildOptionTile(
                            label: d.label,
                            subtitle: '${d.rowHeight.toInt()}px · font ${d.fontSize} · icon ${d.iconSize.toInt()}px',
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                settings.setFileExplorerDensity(d);
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 14),

                    // Section 2: Font Family
                    _buildSectionHeader('FONT FAMILY', Icons.font_download_outlined),
                    const SizedBox(height: 6),
                    Row(
                      children: FileExplorerFontFamily.values.map((f) {
                        final isSelected = settings.fileExplorerFontFamily == f;
                        return Expanded(
                          child: _buildOptionTile(
                            label: f.label,
                            subtitle: f == FileExplorerFontFamily.monospace
                                ? 'Fixed-width terminal style'
                                : 'Modern clean system font',
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                settings.setFileExplorerFontFamily(f);
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 14),

                    // Section 3: Icon Theme
                    _buildSectionHeader('ICON THEME', Icons.palette_outlined),
                    const SizedBox(height: 6),
                    Row(
                      children: FileExplorerIconTheme.values.map((t) {
                        final isSelected = settings.fileExplorerIconTheme == t;
                        return Expanded(
                          child: _buildOptionTile(
                            label: t.label,
                            subtitle: t == FileExplorerIconTheme.smart
                                ? 'Color-coded by extension'
                                : 'Uniform folder & file icons',
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                settings.setFileExplorerIconTheme(t);
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 14),

                    // Section 4: Live Preview
                    _buildSectionHeader('LIVE PREVIEW', Icons.remove_red_eye_outlined),
                    const SizedBox(height: 6),
                    _buildPreviewBox(settings),
                  ],
                ),
              ),

              const Divider(color: Color(0xFF3E4452), thickness: 1, indent: 20, endIndent: 20),

              // Bottom footer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Shortcuts: [Ctrl +/-] Zoom  ·  Auto-saved to config',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Color(0xFF5C6370),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TerminalButton(
                      label: '[Esc] Close',
                      isSelected: true,
                      highlightColor: const Color(0xFF56B6C2),
                      onTap: () => Navigator.of(context).pop(),
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFE5C07B)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE5C07B),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2B3A4A) : const Color(0xFF181B20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFF56B6C2) : const Color(0xFF2C313C),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 14,
                  color: isSelected ? const Color(0xFF56B6C2) : const Color(0xFF5C6370),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFF61AFEF) : const Color(0xFFD8DEE9),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Color(0xFF828997),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBox(SettingsService settings) {
    final density = settings.fileExplorerDensity;
    final fontFamily = settings.fileExplorerFontFamily.fontFamily;
    final iconTheme = settings.fileExplorerIconTheme;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF13161C),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2C313C)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          // Sample Row 1: Folder
          Container(
            height: density.rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  child: Text('[ ]', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF5C6370))),
                ),
                Icon(
                  Icons.folder_rounded,
                  size: density.iconSize,
                  color: const Color(0xFFE5C07B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'my_project_folder',
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: density.fontSize,
                      color: const Color(0xFFE5C07B),
                    ),
                  ),
                ),
                Text(
                  '-',
                  style: TextStyle(fontFamily: fontFamily, fontSize: density.fontSize, color: const Color(0xFFABB2BF)),
                ),
                const SizedBox(width: 20),
                Text(
                  'Oct 21 00:04',
                  style: TextStyle(fontFamily: fontFamily, fontSize: density.fontSize, color: const Color(0xFFABB2BF)),
                ),
              ],
            ),
          ),
          // Sample Row 2: File
          Container(
            height: density.rowHeight,
            color: const Color(0xFF2B3A4A),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  child: Text('[*]', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF98C379), fontWeight: FontWeight.bold)),
                ),
                Icon(
                  iconTheme == FileExplorerIconTheme.smart ? Icons.tune_rounded : Icons.insert_drive_file_outlined,
                  size: density.iconSize,
                  color: iconTheme == FileExplorerIconTheme.smart ? const Color(0xFFE5C07B) : const Color(0xFFD8DEE9),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'server_config.yaml',
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: density.fontSize,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFD8DEE9),
                    ),
                  ),
                ),
                Text(
                  '4.2 KB',
                  style: TextStyle(fontFamily: fontFamily, fontSize: density.fontSize, color: const Color(0xFFABB2BF)),
                ),
                const SizedBox(width: 20),
                Text(
                  'Oct 21 00:04',
                  style: TextStyle(fontFamily: fontFamily, fontSize: density.fontSize, color: const Color(0xFFABB2BF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
