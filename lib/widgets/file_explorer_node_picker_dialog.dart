part of 'file_explorer_dialogs.dart';

// Picker for the node/session a new explorer tab opens on.

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
                    borderSide: const BorderSide(color: Color(0xFF6B7280)),
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
                          borderSide: BorderSide(color: Color(0xFF6B7280)),
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
                        borderSide: BorderSide(color: Color(0xFF6B7280)),
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
                        borderSide: BorderSide(color: Color(0xFF6B7280)),
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
