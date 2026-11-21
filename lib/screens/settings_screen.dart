import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import '../services/session_manager_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/fuzzy_searchable_dropdown.dart';
import '../widgets/radar_pulse_indicator.dart';

/// The Settings page: theme and fonts, terminal behaviour, file explorer
/// options, and session import/export.
class SettingsScreen extends StatefulWidget {
  final SessionManagerService sessionManager;
  final VoidCallback onShowKeyboardShortcuts;

  /// The product name, as shown in the title bar.
  final String appTitle;

  const SettingsScreen({
    super.key,
    required this.sessionManager,
    required this.onShowKeyboardShortcuts,
    required this.appTitle,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final availableFontSizes = const [
      9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 18.0, 20.0, 22.0, 24.0, 28.0, 32.0,
    ];
    final fontSizes = availableFontSizes.contains(settings.nexusTerminalFontSize)
        ? availableFontSizes
        : ([...availableFontSizes, settings.nexusTerminalFontSize]..sort());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Application & Terminal Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 16),
          _buildSettingsSection('Theme & Font'),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: Text('App Theme:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 280,
                child: FuzzySearchableDropdown<AppThemeType>(
                  items: AppThemeType.values,
                  selectedItem: settings.appTheme,
                  itemLabel: (t) => AppTheme.getPalette(t).name,
                  onChanged: (val) {
                    if (val != null) settings.setAppTheme(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: Text('Terminal Theme:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 280,
                child: FuzzySearchableDropdown<NexusTerminalThemeMode>(
                  items: NexusTerminalThemeMode.values,
                  selectedItem: settings.nexusTerminalThemeMode,
                  itemLabel: (t) => t.label,
                  onChanged: (val) {
                    if (val != null) {
                      settings.setNexusTerminalThemeMode(val);
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 140,
                child: Text('Terminal Font:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 280,
                child: FuzzySearchableDropdown<NexusTerminalFontFamily>(
                  items: NexusTerminalFontFamily.values,
                  selectedItem: settings.nexusTerminalFontFamily,
                  itemLabel: (f) => f.label,
                  onChanged: (val) {
                    if (val != null) {
                      settings.setNexusTerminalFontFamily(val);
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: Text('Terminal Font Size:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 280,
                child: FuzzySearchableDropdown<double>(
                  items: fontSizes,
                  selectedItem: settings.nexusTerminalFontSize,
                  itemLabel: (s) => '${s.toInt()} pt',
                  onChanged: (val) {
                    if (val != null) {
                      settings.setNexusTerminalFontSize(val);
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Decrease font size (1 pt)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: settings.nexusTerminalFontSize > 8.0
                      ? () {
                          final newSize = (settings.nexusTerminalFontSize - 1.0).clamp(8.0, 36.0);
                          settings.setNexusTerminalFontSize(newSize);
                          setState(() {});
                        }
                      : null,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.inputBorderColor),
                    ),
                    child: Icon(Icons.remove, size: 14, color: AppTheme.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Increase font size (1 pt)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: settings.nexusTerminalFontSize < 36.0
                      ? () {
                          final newSize = (settings.nexusTerminalFontSize + 1.0).clamp(8.0, 36.0);
                          settings.setNexusTerminalFontSize(newSize);
                          setState(() {});
                        }
                      : null,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.inputBorderColor),
                    ),
                    child: Icon(Icons.add, size: 14, color: AppTheme.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.inputBorderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.terminal, size: 15, color: AppTheme.accentPrimary),
                    const SizedBox(width: 8),
                    Text(
                      'nexus@terminal:~ \$',
                      style: TextStyle(
                        fontFamily: settings.nexusTerminalFontFamily.fontFamily,
                        fontSize: settings.nexusTerminalFontSize.clamp(10.0, 18.0),
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${settings.nexusTerminalFontSize.toInt()} pt)',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey('settings_reduce_motion'),
            title: Text('Reduce motion',
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
            subtitle: Text(
              'Stop looping animations (tab beacons, animated borders, loading shimmer). '
              'Also on automatically when animation effects are turned off in Windows.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            value: settings.reduceMotion,
            onChanged: (val) {
              settings.setReduceMotion(val ?? false);
              setState(() {});
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 24),
          _buildSettingsSection('SSH Session Tabs'),
          const SizedBox(height: 8),
          Text(
            switch (settings.nexusTabStyle) {
              NexusTabStyle.pill => 'Tab aktif memakai pill terangkat. '
                  'Tombol tutup (×) pada tab tidak aktif hanya muncul saat hover agar bar tetap bersih.',
              NexusTabStyle.classic => 'Tab datar dengan garis bawah berwarna pada tab aktif '
                  'dan tombol tutup (×) di setiap tab.',
              NexusTabStyle.attached => 'Tab aktif menyatu langsung dengan area terminal di bawahnya, '
                  'sedangkan tombol Close All dibuat netral agar tidak tertekan tidak sengaja.',
            },
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: Text('Tab Style:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 280,
                child: FuzzySearchableDropdown<NexusTabStyle>(
                  key: const ValueKey('settings_nexus_tab_style'),
                  items: NexusTabStyle.values,
                  selectedItem: settings.nexusTabStyle,
                  itemLabel: (s) => s.label,
                  onChanged: (val) {
                    if (val != null) {
                      settings.setNexusTabStyle(val);
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSettingsSection('SSH Session Tab Beacon Indicator'),
          const SizedBox(height: 8),
          Text(
            'Indikator denyut pada tab sesi SSH aktif (Nexus workspace) menandakan sesi terhubung dan terfokus.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: Text('Pulse Style:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 280,
                child: FuzzySearchableDropdown<NexusPulseStyle>(
                  items: NexusPulseStyle.values,
                  selectedItem: settings.nexusPulseStyle,
                  itemLabel: (s) => s.label,
                  onChanged: (val) {
                    if (val != null) {
                      settings.setNexusPulseStyle(val);
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.inputBorderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadarPulseIndicator(
                      style: settings.nexusPulseStyle,
                      pulseColor: settings.nexusPulseColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Preview: ${settings.nexusPulseStyle.label}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: Text('Pulse Color:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 280,
                child: FuzzySearchableDropdown<NexusPulseColor>(
                  items: NexusPulseColor.values,
                  selectedItem: settings.nexusPulseColor,
                  itemLabel: (c) => c.label,
                  onChanged: (val) {
                    if (val != null) {
                      settings.setNexusPulseColor(val);
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final pc in NexusPulseColor.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Tooltip(
                        message: pc.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            settings.setNexusPulseColor(pc);
                            setState(() {});
                          },
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [pc.primary, pc.secondary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: settings.nexusPulseColor == pc
                                    ? AppTheme.ink
                                    : AppTheme.ink.withValues(alpha: 0.25),
                                width: settings.nexusPulseColor == pc ? 2.5 : 1,
                              ),
                              boxShadow: settings.nexusPulseColor == pc
                                  ? [
                                      BoxShadow(
                                        color: pc.primary.withValues(alpha: 0.6),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: settings.nexusPulseColor == pc
                                ? const Center(
                                    child: Icon(Icons.check, size: 12, color: Colors.white),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSettingsSection('Startup & Sessions'),
          CheckboxListTile(
            title: Text('Show Sessions Manager dialog at startup', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
            value: settings.showSessionDialogAtStartup,
            onChanged: (val) {
              settings.setShowSessionDialogAtStartup(val ?? true);
              setState(() {});
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 24),
          _buildSettingsSection('File Transfers'),
          CheckboxListTile(
            key: const ValueKey('settings_transfer_notifications'),
            title: Text('Desktop notifications for file transfers',
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
            subtitle: Text(
              'Only while ${widget.appTitle} is in the background: when a copy/move longer than 10 s finishes, any transfer fails, or a name conflict needs your decision.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            value: settings.transferNotifications,
            onChanged: (val) {
              settings.setTransferNotifications(val ?? true);
              setState(() {});
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 24),
          _buildSettingsSection('Keyboard Shortcuts & Assistance'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('View All Keyboard Shortcuts', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
            subtitle: Text('See shortcuts for navigation, terminal workspace, sessions, and explorer', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            trailing: OutlinedButton.icon(
              icon: const Icon(Icons.keyboard_outlined, size: 14),
              label: const Text('View Shortcuts (F1)', style: TextStyle(fontSize: 11)),
              onPressed: widget.onShowKeyboardShortcuts,
            ),
          ),
          const SizedBox(height: 24),
          _buildSettingsSection('Export / Import Sessions'),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Export Sessions to JSON'),
                onPressed: () async {
                  final loc = await getSaveLocation(
                    suggestedName: 'nexus_fx_sessions.json',
                    acceptedTypeGroups: const [
                      XTypeGroup(label: 'JSON Files', extensions: ['json']),
                    ],
                  );
                  if (loc != null) {
                    await widget.sessionManager.exportToFile(File(loc.path));
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('Exported to ${loc.path}'), backgroundColor: AppTheme.statusSuccess),
                      );
                    }
                  }
                },
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentPrimary,
                  side: BorderSide(color: AppTheme.accentPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Import Sessions from JSON'),
                onPressed: () async {
                  final file = await openFile(
                    acceptedTypeGroups: const [
                      XTypeGroup(label: 'JSON Files', extensions: ['json']),
                    ],
                  );
                  if (file != null) {
                    await widget.sessionManager.importFromFile(File(file.path));
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('Imported sessions from ${file.path}'), backgroundColor: AppTheme.statusSuccess),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accentPrimary),
        ),
        const SizedBox(height: 4),
        Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
      ],
    );
  }
}
