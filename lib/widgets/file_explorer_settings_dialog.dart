part of 'file_explorer_dialogs.dart';

// Explorer appearance settings.

/// Appearance and font settings dialog for File Explorer
class FileExplorerSettingsDialog extends StatefulWidget {
  const FileExplorerSettingsDialog({super.key});

  @override
  State<FileExplorerSettingsDialog> createState() =>
      _FileExplorerSettingsDialogState();
}

class _FileExplorerSettingsDialogState
    extends State<FileExplorerSettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;

    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.keyQ) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: _DialogShell(
        title: 'EXPLORER APPEARANCE & FONT SETTINGS',
        icon: Icons.tune,
        width: 600,
        onClose: () => Navigator.of(context).pop(),
        footerLeading: Text(
          'Ctrl +/- to zoom  ·  Changes are saved automatically',
          style: TextStyle(fontSize: 11, color: _Dlg.textMuted),
        ),
        actions: [
          _TerminalButton(
            label: 'Close',
            shortcut: 'Esc',
            isSelected: true,
            highlightColor: _Dlg.accent,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('DENSITY & SIZE', Icons.format_size_rounded),
              const SizedBox(height: 8),
              Row(
                children: FileExplorerDensity.values.map((d) {
                  final isSelected = settings.fileExplorerDensity == d;
                  return Expanded(
                    child: _buildOptionTile(
                      label: d.label,
                      subtitle:
                          '${d.rowHeight.toInt()}px · font ${d.fontSize} · icon ${d.iconSize.toInt()}px',
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

              const SizedBox(height: 16),

              _buildSectionHeader('FONT FAMILY', Icons.font_download_outlined),
              const SizedBox(height: 8),
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

              const SizedBox(height: 16),

              _buildSectionHeader('ICON THEME', Icons.palette_outlined),
              const SizedBox(height: 8),
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

              const SizedBox(height: 16),

              _buildSectionHeader('STATUS BAR', Icons.info_outline),
              const SizedBox(height: 8),
              Row(
                children: FileExplorerStatusBarStyle.values.map((s) {
                  final isSelected = settings.fileExplorerStatusBarStyle == s;
                  return Expanded(
                    child: _buildOptionTile(
                      label: s.label,
                      subtitle: s == FileExplorerStatusBarStyle.detailed
                          ? 'Pane summary and F1 help hint'
                          : 'Status dot and "Ready" only',
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          settings.setFileExplorerStatusBarStyle(s);
                        });
                      },
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              _buildSectionHeader('COMPRESS FORMAT', Icons.archive_outlined),
              const SizedBox(height: 8),
              Row(
                children: FileExplorerArchiveFormat.values.map((f) {
                  final isSelected = settings.fileExplorerArchiveFormat == f;
                  return Expanded(
                    child: _buildOptionTile(
                      label: f.label,
                      subtitle: f == FileExplorerArchiveFormat.tarGz
                          ? 'Built into every Linux server'
                          : 'Opens on any Windows; needs zip on servers',
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          settings.setFileExplorerArchiveFormat(f);
                        });
                      },
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              _buildSectionHeader('LIVE PREVIEW', Icons.remove_red_eye_outlined),
              const SizedBox(height: 8),
              _buildPreviewBox(settings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _Dlg.textMuted),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: _Dlg.textMuted,
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
    return _FocusableOptionTile(
      label: '$label, $subtitle',
      isSelected: isSelected,
      onTap: onTap,
      builder: (focused, hovered) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? _Dlg.selected
              : hovered
              ? _Dlg.divider
              : _Dlg.field,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: focused
                ? AppTheme.ink
                : isSelected
                ? _Dlg.accent
                : _Dlg.outline,
            width: focused ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 14,
                  color: isSelected ? _Dlg.accent : _Dlg.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: _Dlg.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10.5,
                color: isSelected ? _Dlg.accent : _Dlg.textMuted,
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
        color: _Dlg.editor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _Dlg.divider),
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
                SizedBox(
                  width: 20,
                  child: Text(
                    '[ ]',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: _Dlg.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  Icons.folder_rounded,
                  size: density.iconSize,
                  color: AppTheme.adaptive(const Color(0xFFE5C07B)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'my_project_folder',
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: density.fontSize,
                      color: AppTheme.adaptive(const Color(0xFFE5C07B)),
                    ),
                  ),
                ),
                Text(
                  '-',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: density.fontSize,
                    color: _Dlg.textSecondary,
                  ),
                ),
                const SizedBox(width: 20),
                Text(
                  'Oct 21 00:04',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: density.fontSize,
                    color: _Dlg.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Sample Row 2: File
          Container(
            height: density.rowHeight,
            color: _Dlg.selected,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '[*]',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppTheme.adaptive(const Color(0xFF98C379)),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  iconTheme == FileExplorerIconTheme.smart
                      ? Icons.tune_rounded
                      : Icons.insert_drive_file_outlined,
                  size: density.iconSize,
                  color: iconTheme == FileExplorerIconTheme.smart
                      ? AppTheme.adaptive(const Color(0xFFE5C07B))
                      : _Dlg.textPrimary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'server_config.yaml',
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: density.fontSize,
                      fontWeight: FontWeight.bold,
                      color: _Dlg.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '4.2 KB',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: density.fontSize,
                    color: _Dlg.textSecondary,
                  ),
                ),
                const SizedBox(width: 20),
                Text(
                  'Oct 21 00:04',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: density.fontSize,
                    color: _Dlg.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One choice in a settings radio group. A tab stop: Enter/Space select it, a
/// white ring marks keyboard focus, and it reports as a checked radio button.
class _FocusableOptionTile extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget Function(bool focused, bool hovered) builder;

  const _FocusableOptionTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.builder,
  });

  @override
  State<_FocusableOptionTile> createState() => _FocusableOptionTileState();
}

class _FocusableOptionTileState extends State<_FocusableOptionTile> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: widget.isSelected,
      focusable: true,
      focused: _focused,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(_focused, _hovered),
        ),
      ),
    );
  }
}
