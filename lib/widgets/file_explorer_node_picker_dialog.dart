part of 'file_explorer_dialogs.dart';

// Picker for the node/session a new explorer tab opens on.

/// Lists Local and the saved SSH sessions as nodes to browse, with a filter,
/// credential editing, and a custom SSH entry.
class FileExplorerNodePickerDialog extends StatefulWidget {
  final ExplorerNodeTarget currentTarget;

  const FileExplorerNodePickerDialog({super.key, required this.currentTarget});

  @override
  State<FileExplorerNodePickerDialog> createState() =>
      _FileExplorerNodePickerDialogState();
}

class _FileExplorerNodePickerDialogState
    extends State<FileExplorerNodePickerDialog> {
  String _searchFilter = '';
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _searchFocusNode = FocusNode(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_lastFilteredNodes.isNotEmpty) {
          setState(() {
            _selectedIndex = (_selectedIndex + 1).clamp(
              0,
              _lastFilteredNodes.length - 1,
            );
          });
          _scrollToIndex(_selectedIndex);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (_lastFilteredNodes.isNotEmpty) {
          setState(() {
            _selectedIndex = (_selectedIndex - 1).clamp(
              0,
              _lastFilteredNodes.length - 1,
            );
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
    },
  );

  List<ExplorerNodeTarget> _lastFilteredNodes = [];

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) =>
      ensurePaletteRowVisible(_scrollController, index);

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

    final List<ExplorerNodeTarget> nodeOptions = [
      ExplorerNodeTarget.local,
      ...sessions
          .where((s) => s.protocol == SessionProtocol.ssh)
          .map((s) => ExplorerNodeTarget.fromSessionProfile(s)),
    ];

    final filtered = filter.isEmpty
        ? nodeOptions
        : nodeOptions.where((n) {
            return n.label.toLowerCase().contains(filter) ||
                n.host.toLowerCase().contains(filter);
          }).toList();
    _lastFilteredNodes = filtered;
    final safeIndex = filtered.isEmpty
        ? 0
        : _selectedIndex.clamp(0, filtered.length - 1);

    return PaletteFrame(
      header: PaletteSearchHeader(
        controller: _searchController,
        focusNode: _searchFocusNode,
        hintText: 'Search nodes...',
        onChanged: (val) {
          setState(() {
            _searchFilter = val;
            _selectedIndex = 0;
          });
        },
        onClose: () => Navigator.pop(context),
      ),
      body: filtered.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "No node matches '${_searchFilter.trim()}'.\nClear the filter or connect a custom SSH node below.",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemExtent: PaletteRow.extent,
              itemCount: filtered.length,
              itemBuilder: (context, idx) =>
                  _buildNodeRow(filtered[idx], isSelected: idx == safeIndex),
            ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (filter.isEmpty && nodeOptions.length == 1)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'No saved SSH sessions yet. Add one in Sessions, or connect a custom node below.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text(
                    'Connect Custom SSH Node...',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentPrimary,
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
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeRow(ExplorerNodeTarget node, {required bool isSelected}) {
    final isCurrent = widget.currentTarget.type == node.type &&
        widget.currentTarget.host == node.host;

    final (IconData icon, String tag, Color tagColor) = switch (node.type) {
      ExplorerTargetType.local => (Icons.computer, 'LOCAL', PaletteColors.local),
      ExplorerTargetType.networkManager =>
        (Icons.hub_outlined, 'NM JUMP', AppTheme.warningColor),
      ExplorerTargetType.oam => (Icons.dns_outlined, 'OAM', AppTheme.accentColor),
      ExplorerTargetType.fe =>
        (Icons.developer_board, 'FE', const Color(0xFFA78BFA)),
      ExplorerTargetType.customSsh => (Icons.terminal, 'SSH', PaletteColors.ssh),
      ExplorerTargetType.sessionSsh => (Icons.cloud_queue, 'SSH', PaletteColors.ssh),
    };

    final String subtitle = switch (node.type) {
      ExplorerTargetType.local => 'Browse this computer',
      ExplorerTargetType.fe => 'Host: ${node.host} · OAM hop (passwordless)',
      _ => 'Host: ${node.host} · User: ${node.username}',
    };

    final canEditCredentials =
        !node.isLocal && node.type != ExplorerTargetType.fe;

    return PaletteRow(
      icon: icon,
      label: node.label,
      subtitle: subtitle,
      isSelected: isSelected,
      onTap: () => _selectNode(node),
      trailing: [
        if (canEditCredentials)
          IconButton(
            icon: const Icon(Icons.key, size: 14, color: AppTheme.textSecondary),
            tooltip: 'Edit Credentials for ${node.label}',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final edited = await _showEditNodeCredentialsDialog(context, node);
              if (edited != null && mounted) {
                Navigator.pop(context, edited);
              }
            },
          ),
        if (isCurrent)
          const PaletteBadge(text: 'ACTIVE', color: AppTheme.accentColor),
        PaletteBadge(text: tag, color: tagColor),
      ],
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
          void save() {
            final newHost = hostCtrl.text.trim().isEmpty
                ? node.host
                : hostCtrl.text.trim();
            final updated = node.copyWith(
              host: newHost,
              label:
                  node.type == ExplorerTargetType.networkManager &&
                      newHost.isNotEmpty
                  ? 'Network Manager ($newHost)'
                  : node.label,
              username: userCtrl.text.trim(),
              password: passCtrl.text,
            );
            Navigator.pop(ctx, updated);
          }

          return _DialogShell(
            title: 'Credentials: ${node.label}',
            rawTitle: true,
            icon: Icons.key,
            width: 420,
            onClose: () => Navigator.pop(ctx),
            actions: [
              _TerminalButton(
                label: 'Cancel',
                isSelected: false,
                highlightColor: _Dlg.accent,
                onTap: () => Navigator.pop(ctx),
              ),
              _TerminalButton(
                label: 'Save & Select',
                isSelected: true,
                highlightColor: _Dlg.accent,
                onTap: save,
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (node.host.isEmpty) ...[
                    TextField(
                      controller: hostCtrl,
                      style: const TextStyle(fontSize: 13, color: _Dlg.textPrimary),
                      decoration: _formFieldDecoration('Host IP / Hostname'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(fontSize: 13, color: _Dlg.textPrimary),
                    decoration: _formFieldDecoration('Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    style: const TextStyle(fontSize: 13, color: _Dlg.textPrimary),
                    onSubmitted: (_) => save(),
                    decoration: _formFieldDecoration(
                      'Password',
                      suffixIcon: IconButton(
                        tooltip: obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 16,
                          color: _Dlg.textSecondary,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

    String? hostError;

    return showDialog<ExplorerNodeTarget>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void connect() {
            final host = hostCtrl.text.trim();
            if (host.isEmpty) {
              setDialogState(() => hostError = 'Enter a host or IP address.');
              return;
            }
            final port = int.tryParse(portCtrl.text.trim()) ?? 22;
            Navigator.pop(
              ctx,
              ExplorerNodeTarget(
                type: ExplorerTargetType.customSsh,
                label: 'SSH ($host)',
                host: host,
                port: port,
                username: userCtrl.text.trim(),
                password: passCtrl.text,
              ),
            );
          }

          return _DialogShell(
            title: 'CONNECT CUSTOM SSH',
            icon: Icons.add_link,
            width: 420,
            onClose: () => Navigator.pop(ctx),
            actions: [
              _TerminalButton(
                label: 'Cancel',
                isSelected: false,
                highlightColor: _Dlg.accent,
                onTap: () => Navigator.pop(ctx),
              ),
              _TerminalButton(
                label: 'Connect',
                isSelected: true,
                highlightColor: _Dlg.accent,
                onTap: connect,
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hostCtrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 13, color: _Dlg.textPrimary),
                          onChanged: (_) {
                            if (hostError != null) {
                              setDialogState(() => hostError = null);
                            }
                          },
                          decoration: _formFieldDecoration(
                            'Host / IP',
                            errorText: hostError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: portCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13, color: _Dlg.textPrimary),
                          decoration: _formFieldDecoration('Port'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(fontSize: 13, color: _Dlg.textPrimary),
                    decoration: _formFieldDecoration('Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    style: const TextStyle(fontSize: 13, color: _Dlg.textPrimary),
                    onSubmitted: (_) => connect(),
                    decoration: _formFieldDecoration('Password'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
