part of 'file_explorer_dialogs.dart';

// Explorer appearance settings.

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
