import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nexus_tool.dart';
import '../models/session_models.dart';
import '../theme/app_theme.dart';
import '../services/session_manager_service.dart';
import '../services/web_launcher.dart';
import 'palette_widgets.dart';

enum CommandAction {
  connectSession,
  openSessionsManager,
  toggleCommandPane,
  toggleRunbookSidebar,
  toggleSplitView,
  toggleSessionFullscreen,
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

  /// Opens a session's web UI. Defaults to the system browser.
  final Future<bool> Function(String url) openUrl;

  const CommandPalette({
    super.key,
    required this.onSelect,
    this.sessionsOnly = false,
    this.customTools = const [],
    this.toolContext,
    this.sessionManager,
    this.openUrl = WebLauncher.open,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _queryFocusNode = FocusNode(onKeyEvent: _handleKey);
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
    _scrollController.dispose();
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
        badgeColor: isLocal ? PaletteColors.local : PaletteColors.ssh,
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
        label: 'Toggle Session Fullscreen',
        subtitle: 'Fill the screen with the active SSH session',
        icon: Icons.fullscreen,
        action: CommandAction.toggleSessionFullscreen,
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

  void _openWeb(SessionProfile session) {
    final url = session.resolvedWebUrl;
    if (url == null || !session.canOpenWeb) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    widget.openUrl(url).then((ok) {
      if (!ok) {
        messenger?.showSnackBar(SnackBar(content: Text('Could not open $url in the browser.')));
      }
    });
  }

  void _onCtrlEnter() {
    if (_selectedIndex >= _filteredItems.length) return;
    final session = _filteredItems[_selectedIndex].session;
    if (session != null) _openWeb(session);
  }

  List<Widget> _sessionBadges(CommandItem item, SessionProfile session) {
    return [
      PaletteBadge(
        text: item.badge!,
        color: item.badgeColor ?? AppTheme.accentPrimary,
        onTap: () {
          Navigator.of(context).pop();
          widget.onSelect(item);
        },
      ),
      if (session.resolvedWebUrl != null)
        PaletteBadge(
          text: 'WEB',
          color: PaletteColors.web,
          enabled: session.canOpenWeb,
          tooltip: session.canOpenWeb
              ? 'Open ${session.resolvedWebUrl} (Ctrl+Enter)'
              : 'Reachable only through a jump host. Set a Web URL in Properties.',
          onTap: () => _openWeb(session),
        ),
    ];
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      if (_filteredItems.isNotEmpty) {
        final delta = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
        setState(() {
          _selectedIndex = (_selectedIndex + delta).clamp(0, _filteredItems.length - 1);
        });
        ensurePaletteRowVisible(_scrollController, _selectedIndex);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isControlPressed) {
        _onCtrlEnter();
      } else {
        _onEnter();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PaletteFrame(
      header: PaletteSearchHeader(
        controller: _queryController,
        focusNode: _queryFocusNode,
        hintText: 'Type a command or search sessions...',
        onChanged: _updateFilteredItems,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: _filteredItems.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No matching commands or sessions', style: TextStyle(color: AppTheme.textMuted)),
            )
          : ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemExtent: PaletteRow.extent,
              itemCount: _filteredItems.length,
              itemBuilder: (ctx, idx) {
                final item = _filteredItems[idx];
                return PaletteRow(
                  icon: item.icon,
                  label: item.label,
                  subtitle: item.subtitle,
                  isSelected: idx == _selectedIndex,
                  trailing: [
                    if (item.session != null && item.badge != null)
                      ..._sessionBadges(item, item.session!)
                    else if (item.badge != null)
                      PaletteBadge(
                        text: item.badge!,
                        color: item.badgeColor ?? AppTheme.accentPrimary,
                      ),
                  ],
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onSelect(item);
                  },
                );
              },
            ),
    );
  }
}
