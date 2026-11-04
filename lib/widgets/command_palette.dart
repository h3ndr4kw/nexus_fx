import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nexus_tool.dart';
import '../models/session_models.dart';
import '../theme/app_theme.dart';
import '../services/session_manager_service.dart';

enum CommandAction {
  connectSession,
  openSessionsManager,
  toggleCommandPane,
  toggleRunbookSidebar,
  toggleSplitView,
  setTheme,
  setFontSize,
  openCustomTool,
  executeCustomToolCommand,
}

class CommandItem {
  final String label;
  final String subtitle;
  final IconData icon;
  final CommandAction action;
  final String? badge;
  final Color? badgeColor;
  final SessionProfile? session;
  final String? customToolId;
  final VoidCallback? onCustomExecute;

  const CommandItem({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.action,
    this.badge,
    this.badgeColor,
    this.session,
    this.customToolId,
    this.onCustomExecute,
  });
}

class CommandPalette extends StatefulWidget {
  final void Function(CommandItem item) onSelect;
  final bool sessionsOnly;
  final List<NexusTool> customTools;
  final NexusToolContext? toolContext;
  final SessionManagerService? sessionManager;

  const CommandPalette({
    super.key,
    required this.onSelect,
    this.sessionsOnly = false,
    this.customTools = const [],
    this.toolContext,
    this.sessionManager,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocusNode = FocusNode();
  int _selectedIndex = 0;
  List<CommandItem> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _updateFilteredItems('');
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  List<CommandItem> _buildAllCommands() {
    final list = <CommandItem>[];

    // Sessions from SessionManagerService
    final sessions = (widget.sessionManager ?? SessionManagerService.instance).sessions;
    for (final s in sessions) {
      final isLocal = s.protocol == SessionProtocol.local;
      list.add(CommandItem(
        label: s.name,
        subtitle: isLocal ? 'Local System Shell' : 'Connect SSH to ${s.host}:${s.port}',
        icon: isLocal ? Icons.terminal : Icons.cloud_queue,
        action: CommandAction.connectSession,
        badge: isLocal ? 'LOCAL' : 'SSH',
        badgeColor: isLocal ? const Color(0xFF64B5F6) : const Color(0xFFFF7043),
        session: s,
      ));
    }

    if (!widget.sessionsOnly) {
      list.add(const CommandItem(
        label: 'Open Sessions Manager',
        subtitle: 'Manage sessions, folders, and connection properties',
        icon: Icons.folder_special_outlined,
        action: CommandAction.openSessionsManager,
      ));
      list.add(const CommandItem(
        label: 'Toggle Split View',
        subtitle: 'Toggle dual terminal panes (Left & Right)',
        icon: Icons.vertical_split_outlined,
        action: CommandAction.toggleSplitView,
      ));
      list.add(const CommandItem(
        label: 'Toggle Broadcast Bar',
        subtitle: 'Show/hide multi-terminal broadcast input bar',
        icon: Icons.podcasts,
        action: CommandAction.toggleCommandPane,
      ));
      list.add(const CommandItem(
        label: 'Toggle Runbook Sidebar',
        subtitle: 'Show/hide Interactive Runbook & Notebook panel',
        icon: Icons.menu_book_outlined,
        action: CommandAction.toggleRunbookSidebar,
      ));

      // Custom Tools & Plugin Commands
      for (final tool in widget.customTools) {
        list.add(CommandItem(
          label: 'Open Tool: ${tool.title}',
          subtitle: tool.subtitle ?? 'Switch to ${tool.title} workspace',
          icon: tool.icon,
          action: CommandAction.openCustomTool,
          badge: 'TOOL',
          badgeColor: AppTheme.accentPrimary,
          customToolId: tool.id,
        ));

        if (widget.toolContext != null) {
          for (final cmd in tool.buildCommands(widget.toolContext!)) {
            list.add(CommandItem(
              label: cmd.label,
              subtitle: cmd.subtitle,
              icon: cmd.icon,
              action: CommandAction.executeCustomToolCommand,
              badge: cmd.badge ?? tool.title.toUpperCase(),
              badgeColor: cmd.badgeColor ?? AppTheme.accentPrimary,
              customToolId: tool.id,
              onCustomExecute: () => cmd.onExecute(widget.toolContext!),
            ));
          }
        }
      }

      // Theme commands
      for (final theme in AppThemeType.values) {
        list.add(CommandItem(
          label: 'Set Theme: ${theme.name}',
          subtitle: 'Switch application color theme',
          icon: Icons.palette_outlined,
          action: CommandAction.setTheme,
        ));
      }
    }

    return list;
  }

  void _updateFilteredItems(String query) {
    final all = _buildAllCommands();
    if (query.trim().isEmpty) {
      setState(() {
        _filteredItems = all;
        _selectedIndex = 0;
      });
      return;
    }

    final q = query.toLowerCase().trim();
    setState(() {
      _filteredItems = all.where((item) {
        return item.label.toLowerCase().contains(q) ||
            item.subtitle.toLowerCase().contains(q);
      }).toList();
      _selectedIndex = 0;
    });
  }

  void _onEnter() {
    if (_filteredItems.isNotEmpty && _selectedIndex < _filteredItems.length) {
      final selected = _filteredItems[_selectedIndex];
      Navigator.of(context).pop();
      widget.onSelect(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      alignment: Alignment.topCenter,
      child: Container(
        width: 620,
        margin: const EdgeInsets.only(top: 60),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20, color: AppTheme.accentPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            if (_selectedIndex < _filteredItems.length - 1) {
                              setState(() => _selectedIndex++);
                            }
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            if (_selectedIndex > 0) {
                              setState(() => _selectedIndex--);
                            }
                          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                            _onEnter();
                          }
                        }
                      },
                      child: TextField(
                        controller: _queryController,
                        focusNode: _queryFocusNode,
                        autofocus: true,
                        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Type a command or search sessions...',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: _updateFilteredItems,
                        onSubmitted: (_) => _onEnter(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: _filteredItems.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No matching commands or sessions', style: TextStyle(color: AppTheme.textMuted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _filteredItems.length,
                      itemBuilder: (ctx, idx) {
                        final item = _filteredItems[idx];
                        final isSelected = idx == _selectedIndex;
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onSelect(item);
                          },
                          child: Container(
                            color: isSelected ? AppTheme.accentPrimary.withValues(alpha: 0.15) : Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Icon(item.icon, size: 18, color: isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                          color: isSelected ? AppTheme.accentPrimary : AppTheme.textPrimary,
                                        ),
                                      ),
                                      Text(item.subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                    ],
                                  ),
                                ),
                                if (item.badge != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (item.badgeColor ?? AppTheme.accentPrimary).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.badge!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: item.badgeColor ?? AppTheme.accentPrimary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
