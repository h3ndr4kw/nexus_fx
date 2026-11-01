import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import '../theme/app_theme.dart';
import '../models/file_explorer_models.dart';

enum NodeViewMode {
  cards,
  tree,
  table,
  map,
}

typedef FirestoreHttpHandler = Future<Map<String, dynamic>> Function(
  Uri uri,
  String method,
  Map<String, dynamic>? body,
);

enum ToolsViewMode {
  grid,
  list,
}

enum NexusPulseStyle {
  neonSonarWave('Neon Sonar Wave'),
  breathingGlowCore('Breathing Glow Core'),
  telemetryHeartbeat('Telemetry Heartbeat'),
  classicRadar('Classic Radar');

  final String label;
  const NexusPulseStyle(this.label);
}

enum NexusPulseColor {
  emerald(
    label: 'Emerald (Cyber Green)',
    primary: Color(0xFF10B981),
    secondary: Color(0xFF22D3EE),
    accent: Color(0xFFA3E635),
    dark: Color(0xFF059669),
  ),
  ruby(
    label: 'Ruby (Crimson Rose)',
    primary: Color(0xFFEF4444),
    secondary: Color(0xFFFB7185),
    accent: Color(0xFFFDA4AF),
    dark: Color(0xFFBE123C),
  ),
  sapphire(
    label: 'Sapphire (Electric Azure)',
    primary: Color(0xFF3B82F6),
    secondary: Color(0xFF38BDF8),
    accent: Color(0xFF93C5FD),
    dark: Color(0xFF1D4ED8),
  ),
  amethyst(
    label: 'Amethyst (Neon Violet)',
    primary: Color(0xFF8B5CF6),
    secondary: Color(0xFFEC4899),
    accent: Color(0xFFF472B6),
    dark: Color(0xFF6D28D9),
  ),
  diamond(
    label: 'Diamond (Frost White)',
    primary: Color(0xFFF8FAFC),
    secondary: Color(0xFF38BDF8),
    accent: Color(0xFFFFFFFF),
    dark: Color(0xFF64748B),
  ),
  amber(
    label: 'Amber (Solar Gold)',
    primary: Color(0xFFF59E0B),
    secondary: Color(0xFFFBBF24),
    accent: Color(0xFFFEF08A),
    dark: Color(0xFFB45309),
  );

  final String label;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color dark;

  const NexusPulseColor({
    required this.label,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.dark,
  });
}

enum NexusTerminalFontFamily {
  courierNew('Courier New', 'Courier New'),
  consolas('Consolas', 'Consolas'),
  cascadiaMono('Cascadia Mono', 'Cascadia Mono'),
  jetbrainsMono('JetBrains Mono', 'JetBrains Mono'),
  lucidaConsole('Lucida Console', 'Lucida Console'),
  monospace('System Monospace', 'monospace');

  final String label;
  final String fontFamily;
  const NexusTerminalFontFamily(this.label, this.fontFamily);
}

enum NexusTerminalThemeMode {
  followAppTheme('Follow App Theme'),
  classicDark('Classic Dark'),
  highContrast('High Contrast'),
  matrixGreen('Matrix Green');

  final String label;
  const NexusTerminalThemeMode(this.label);
}

class SettingsService extends ChangeNotifier {
  static SettingsService? _instance;
  Set<NodeViewMode> _enabledViewModes = {
    NodeViewMode.cards,
    NodeViewMode.tree,
    NodeViewMode.table,
    NodeViewMode.map,
  };
  NodeViewMode _nodeViewMode = NodeViewMode.cards;
  ToolsViewMode _toolsViewMode = ToolsViewMode.grid;
  NexusPulseStyle _nexusPulseStyle = NexusPulseStyle.neonSonarWave;
  NexusPulseColor _nexusPulseColor = NexusPulseColor.emerald;
  String _gilanDashboardUrl = 'https://10.52.10.180:31343/';
  String _gilanDashboardUsername = 'hendra_kusuma_x';
  String _gilanDashboardPassword = 'H3ndr4kw@12a';
  bool _nexusOnlyWhenActive = false;
  bool _nexusAutoCloseTabOnDisconnect = false;
  bool _nexusAutoSessionLogging = true;
  bool _nexusCascadeExit = false;
  bool _nexusRunbookShowProgress = true;
  bool _nexusRunbookAutoClose = true;
  int _nexusRunbookAutoCloseDelay = 2;
  bool _showNodesTab = false;
  double _floatingCommandWidth = 50.0;
  double _rightSidebarWidth = 440.0;
  double _leftSidebarWidth = 170.0;
  AppThemeType _appTheme = AppThemeType.antigravity;
  AppFontSize _appFontSize = AppFontSize.medium;
  double _borderAnimationDuration = 8.0;
  bool _rememberMe = true;
  String _rememberedUsername = 'admin';
  String _rememberedPassword = '';
  bool _autoCheckUpdates = true;
  bool _autoDownloadUpdates = false;
  String _updateRemotePath = '/home/vmridwan/smart_e_he_updates';
  String? _customConfigPath;
  FileExplorerDensity _fileExplorerDensity = FileExplorerDensity.standard;
  FileExplorerFontFamily _fileExplorerFontFamily = FileExplorerFontFamily.monospace;
  FileExplorerIconTheme _fileExplorerIconTheme = FileExplorerIconTheme.smart;
  NexusTerminalFontFamily _nexusTerminalFontFamily = NexusTerminalFontFamily.courierNew;
  double _nexusTerminalFontSize = 14.0;
  double _nexusTerminalLineHeight = 1.0;
  NexusTerminalThemeMode _nexusTerminalThemeMode = NexusTerminalThemeMode.followAppTheme;
  Set<String> _pinnedTools = {'cluster_deployment'};
  bool _showSessionDialogAtStartup = true;

  static const String firestoreBaseUrl =
      'https://firestore.googleapis.com/v1/projects/nexus-fx/databases/(default)/documents';

  FirestoreHttpHandler? customFirestoreHttpHandler;

  SettingsService._();

  static SettingsService get instance {
    _instance ??= SettingsService._();
    return _instance!;
  }

  bool get showSessionDialogAtStartup => _showSessionDialogAtStartup;

  void setShowSessionDialogAtStartup(bool show) {
    if (_showSessionDialogAtStartup != show) {
      _showSessionDialogAtStartup = show;
      notifyListeners();
      saveSettings();
    }
  }

  Set<NodeViewMode> get enabledViewModes => Set.unmodifiable(_enabledViewModes);
  NodeViewMode get nodeViewMode => _nodeViewMode;
  ToolsViewMode get toolsViewMode => _toolsViewMode;
  String get gilanDashboardUrl => _gilanDashboardUrl;
  String get gilanDashboardUsername => _gilanDashboardUsername;
  String get gilanDashboardPassword => _gilanDashboardPassword;
  bool get nexusOnlyWhenActive => _nexusOnlyWhenActive;
  bool get nexusAutoCloseTabOnDisconnect => _nexusAutoCloseTabOnDisconnect;
  bool get nexusAutoSessionLogging => _nexusAutoSessionLogging;
  bool get nexusCascadeExit => _nexusCascadeExit;
  bool get nexusRunbookShowProgress => _nexusRunbookShowProgress;
  bool get nexusRunbookAutoClose => _nexusRunbookAutoClose;
  int get nexusRunbookAutoCloseDelay => _nexusRunbookAutoCloseDelay;
  Duration get nexusRunbookAutoCloseDuration =>
      Duration(seconds: _nexusRunbookAutoCloseDelay);
  bool get showNodesTab => _showNodesTab;
  double get floatingCommandWidth => _floatingCommandWidth;
  double get rightSidebarWidth => _rightSidebarWidth;
  double get leftSidebarWidth => _leftSidebarWidth;
  AppThemeType get appTheme => _appTheme;
  AppFontSize get appFontSize => _appFontSize;
  NexusPulseStyle get nexusPulseStyle => _nexusPulseStyle;
  NexusPulseColor get nexusPulseColor => _nexusPulseColor;
  double get borderAnimationDuration => _borderAnimationDuration;
  Duration get borderAnimationDurationObj =>
      Duration(milliseconds: (_borderAnimationDuration * 1000).round());
  bool get rememberMe => _rememberMe;
  String get rememberedUsername => _rememberedUsername;
  String get rememberedPassword => _rememberedPassword;
  bool get autoCheckUpdates => _autoCheckUpdates;
  bool get autoDownloadUpdates => _autoDownloadUpdates;
  String get updateRemotePath => _updateRemotePath;
  FileExplorerDensity get fileExplorerDensity => _fileExplorerDensity;
  FileExplorerFontFamily get fileExplorerFontFamily => _fileExplorerFontFamily;
  FileExplorerIconTheme get fileExplorerIconTheme => _fileExplorerIconTheme;
  NexusTerminalFontFamily get nexusTerminalFontFamily => _nexusTerminalFontFamily;
  double get nexusTerminalFontSize => _nexusTerminalFontSize;
  double get nexusTerminalLineHeight => _nexusTerminalLineHeight;
  NexusTerminalThemeMode get nexusTerminalThemeMode => _nexusTerminalThemeMode;
  Set<String> get pinnedTools => Set.unmodifiable(_pinnedTools);
  bool isToolPinned(String toolId) => _pinnedTools.contains(toolId);

  double get fontScaleFactor {
    switch (_appFontSize) {
      case AppFontSize.small:
        return 0.85;
      case AppFontSize.medium:
        return 1.0;
      case AppFontSize.large:
        return 1.15;
      case AppFontSize.extraLarge:
        return 1.30;
    }
  }

  bool isViewModeEnabled(NodeViewMode mode) => _enabledViewModes.contains(mode);

  @visibleForTesting
  void setConfigPathForTesting(String? path) {
    _customConfigPath = path;
  }

  String _getConfigPath() {
    return _customConfigPath ?? 'config/settings.yaml';
  }

  Future<void> loadSettings() async {
    try {
      final file = File(_getConfigPath());
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final yaml = loadYaml(content);
        if (yaml is Map) {
          if (yaml['nexus_only_when_active'] != null) {
            _nexusOnlyWhenActive = yaml['nexus_only_when_active'] == true;
          }

          if (yaml['nexus_auto_close_tab_on_disconnect'] != null) {
            _nexusAutoCloseTabOnDisconnect =
                yaml['nexus_auto_close_tab_on_disconnect'] == true;
          }

          if (yaml['nexus_auto_session_logging'] != null) {
            _nexusAutoSessionLogging = yaml['nexus_auto_session_logging'] == true;
          }

          if (yaml['nexus_cascade_exit'] != null) {
            _nexusCascadeExit = yaml['nexus_cascade_exit'] == true;
          }

          if (yaml['nexus_runbook_show_progress'] != null) {
            _nexusRunbookShowProgress = yaml['nexus_runbook_show_progress'] == true;
          }

          if (yaml['nexus_runbook_auto_close'] != null) {
            _nexusRunbookAutoClose = yaml['nexus_runbook_auto_close'] == true;
          }

          if (yaml['nexus_runbook_auto_close_delay'] != null) {
            final d = int.tryParse(yaml['nexus_runbook_auto_close_delay'].toString());
            if (d != null && d >= 1 && d <= 30) {
              _nexusRunbookAutoCloseDelay = d;
            }
          }

          if (yaml['show_nodes_tab'] != null) {
            _showNodesTab = yaml['show_nodes_tab'] == true;
          }

          if (yaml['floating_command_width'] != null) {
            final w = double.tryParse(yaml['floating_command_width'].toString());
            if (w != null && w >= 20.0 && w <= 100.0) {
              _floatingCommandWidth = w;
            }
          }

          if (yaml['right_sidebar_width'] != null) {
            final w = double.tryParse(yaml['right_sidebar_width'].toString());
            if (w != null && w >= 320.0 && w <= 1200.0) {
              _rightSidebarWidth = w;
            }
          }

          if (yaml['left_sidebar_width'] != null) {
            final w = double.tryParse(yaml['left_sidebar_width'].toString());
            if (w != null && w >= 50.0 && w <= 480.0) {
              _leftSidebarWidth = w;
            }
          }

          if (yaml['tools_page_view'] != null) {
            final toolsMode = _parseToolsViewMode(yaml['tools_page_view'].toString());
            if (toolsMode != null) {
              _toolsViewMode = toolsMode;
            }
          }

          if (yaml['gilan_dashboard'] != null) {
            final gilanVal = yaml['gilan_dashboard'];
            if (gilanVal is Map) {
              if (gilanVal['url'] != null) {
                _gilanDashboardUrl = gilanVal['url'].toString();
              }
              if (gilanVal['username'] != null) {
                _gilanDashboardUsername = gilanVal['username'].toString();
              }
              if (gilanVal['password'] != null) {
                _gilanDashboardPassword = gilanVal['password'].toString();
              }
            }
          }

          if (yaml['app_theme'] != null) {
            final theme = _parseAppTheme(yaml['app_theme'].toString());
            if (theme != null) {
              _appTheme = theme;
              AppTheme.currentTheme = theme;
            }
          }

          if (yaml['app_font_size'] != null) {
            final fontSize = _parseAppFontSize(yaml['app_font_size'].toString());
            if (fontSize != null) {
              _appFontSize = fontSize;
            }
          }

          if (yaml['nexus_pulse_style'] != null) {
            final pulseStyle = _parseNexusPulseStyle(yaml['nexus_pulse_style'].toString());
            if (pulseStyle != null) {
              _nexusPulseStyle = pulseStyle;
            }
          }

          if (yaml['nexus_pulse_color'] != null) {
            final pulseColor = _parseNexusPulseColor(yaml['nexus_pulse_color'].toString());
            if (pulseColor != null) {
              _nexusPulseColor = pulseColor;
            }
          }

          if (yaml['border_animation_duration'] != null) {
            final d = double.tryParse(yaml['border_animation_duration'].toString());
            if (d != null && d >= 1.0 && d <= 30.0) {
              _borderAnimationDuration = d;
            }
          }

          if (yaml['remember_me'] != null) {
            _rememberMe = yaml['remember_me'] == true;
          }

          if (_rememberMe) {
            if (yaml['remembered_username'] != null) {
              _rememberedUsername = yaml['remembered_username'].toString();
            }
            if (yaml['remembered_password'] != null) {
              _rememberedPassword = yaml['remembered_password'].toString();
            }
          } else {
            _rememberedUsername = '';
            _rememberedPassword = '';
          }

          if (yaml['nodes_page_view'] != null) {
            final nodesViewVal = yaml['nodes_page_view'];

            if (nodesViewVal is Map) {
              // New multi-select format
              final enabledList = nodesViewVal['enabled'];
              if (enabledList is List && enabledList.isNotEmpty) {
                final parsed = <NodeViewMode>{};
                for (final item in enabledList) {
                  final mode = _parseMode(item.toString());
                  if (mode != null) parsed.add(mode);
                }
                if (parsed.isNotEmpty) {
                  _enabledViewModes = parsed;
                }
              }

              final currentVal = nodesViewVal['current'];
              if (currentVal != null) {
                final mode = _parseMode(currentVal.toString());
                if (mode != null && _enabledViewModes.contains(mode)) {
                  _nodeViewMode = mode;
                } else if (_enabledViewModes.isNotEmpty) {
                  _nodeViewMode = _enabledViewModes.first;
                }
              }
            } else {
              // Legacy single string format
              final mode = _parseMode(nodesViewVal.toString());
              if (mode != null) {
                _nodeViewMode = mode;
                _enabledViewModes = {mode};
              }
            }
          }

          if (yaml['auto_check_updates'] != null) {
            _autoCheckUpdates = yaml['auto_check_updates'] == true;
          }

          if (yaml['auto_download_updates'] != null) {
            _autoDownloadUpdates = yaml['auto_download_updates'] == true;
          }

          if (yaml['update_remote_path'] != null) {
            final remotePath = yaml['update_remote_path'].toString().trim();
            if (remotePath.isNotEmpty) {
              _updateRemotePath = remotePath;
            }
          }

          if (yaml['file_explorer_density'] != null) {
            final density = _parseFileExplorerDensity(yaml['file_explorer_density'].toString());
            if (density != null) {
              _fileExplorerDensity = density;
            }
          }

          if (yaml['file_explorer_font_family'] != null) {
            final fontFamily = _parseFileExplorerFontFamily(yaml['file_explorer_font_family'].toString());
            if (fontFamily != null) {
              _fileExplorerFontFamily = fontFamily;
            }
          }

          if (yaml['file_explorer_icon_theme'] != null) {
            final iconTheme = _parseFileExplorerIconTheme(yaml['file_explorer_icon_theme'].toString());
            if (iconTheme != null) {
              _fileExplorerIconTheme = iconTheme;
            }
          }

          if (yaml['nexus_terminal_font_family'] != null) {
            final ff = _parseNexusTerminalFontFamily(yaml['nexus_terminal_font_family'].toString());
            if (ff != null) {
              _nexusTerminalFontFamily = ff;
            }
          }

          if (yaml['nexus_terminal_font_size'] != null) {
            final fs = double.tryParse(yaml['nexus_terminal_font_size'].toString());
            if (fs != null && fs >= 8.0 && fs <= 36.0) {
              _nexusTerminalFontSize = fs;
            }
          }

          if (yaml['nexus_terminal_line_height'] != null) {
            final lh = double.tryParse(yaml['nexus_terminal_line_height'].toString());
            if (lh != null && lh >= 0.8 && lh <= 2.0) {
              _nexusTerminalLineHeight = lh;
            }
          }

          if (yaml['nexus_terminal_theme_mode'] != null) {
            final tm = _parseNexusTerminalThemeMode(yaml['nexus_terminal_theme_mode'].toString());
            if (tm != null) {
              _nexusTerminalThemeMode = tm;
            }
          }

          if (yaml['pinned_tools'] != null) {
            final pinned = yaml['pinned_tools'];
            if (pinned is List) {
              _pinnedTools = pinned.map((e) => e.toString()).toSet();
            }
          } else {
            _pinnedTools = {'cluster_deployment'};
          }

          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    }
  }

  FileExplorerDensity? _parseFileExplorerDensity(String value) {
    for (final d in FileExplorerDensity.values) {
      if (d.name.toLowerCase() == value.trim().toLowerCase()) return d;
    }
    return null;
  }

  FileExplorerFontFamily? _parseFileExplorerFontFamily(String value) {
    for (final f in FileExplorerFontFamily.values) {
      if (f.name.toLowerCase() == value.trim().toLowerCase()) return f;
    }
    return null;
  }

  FileExplorerIconTheme? _parseFileExplorerIconTheme(String value) {
    for (final t in FileExplorerIconTheme.values) {
      if (t.name.toLowerCase() == value.trim().toLowerCase()) return t;
    }
    return null;
  }

  NexusTerminalFontFamily? _parseNexusTerminalFontFamily(String value) {
    final v = value.trim().toLowerCase();
    for (final f in NexusTerminalFontFamily.values) {
      if (f.name.toLowerCase() == v ||
          f.label.toLowerCase() == v ||
          f.fontFamily.toLowerCase() == v) {
        return f;
      }
    }
    return null;
  }

  NexusTerminalThemeMode? _parseNexusTerminalThemeMode(String value) {
    final v = value.trim().toLowerCase();
    for (final t in NexusTerminalThemeMode.values) {
      if (t.name.toLowerCase() == v || t.label.toLowerCase() == v) {
        return t;
      }
    }
    return null;
  }

  ToolsViewMode? _parseToolsViewMode(String value) {
    switch (value.trim().toLowerCase()) {
      case 'list':
        return ToolsViewMode.list;
      case 'grid':
        return ToolsViewMode.grid;
      case 'carousel':
        return ToolsViewMode.grid;
      default:
        return null;
    }
  }

  NodeViewMode? _parseMode(String value) {
    switch (value.trim().toLowerCase()) {
      case 'tree':
        return NodeViewMode.tree;
      case 'table':
        return NodeViewMode.table;
      case 'cards':
        return NodeViewMode.cards;
      case 'map':
        return NodeViewMode.map;
      default:
        return null;
    }
  }

  AppThemeType? _parseAppTheme(String value) {
    final v = value.trim().toLowerCase().replaceAll('-', '_');
    for (final theme in AppThemeType.values) {
      final nameSnake = theme.name.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (match) => '_${match.group(0)!.toLowerCase()}',
      );
      if (theme.name.toLowerCase() == v || nameSnake == v) {
        return theme;
      }
    }
    return null;
  }

  AppFontSize? _parseAppFontSize(String value) {
    final v = value.trim().toLowerCase();
    for (final size in AppFontSize.values) {
      if (size.name.toLowerCase() == v) {
        return size;
      }
    }
    return null;
  }

  NexusPulseStyle? _parseNexusPulseStyle(String value) {
    final v = value.trim().toLowerCase();
    for (final style in NexusPulseStyle.values) {
      if (style.name.toLowerCase() == v || style.label.toLowerCase() == v) {
        return style;
      }
    }
    return null;
  }

  NexusPulseColor? _parseNexusPulseColor(String value) {
    final v = value.trim().toLowerCase();
    for (final color in NexusPulseColor.values) {
      if (color.name.toLowerCase() == v || color.label.toLowerCase() == v) {
        return color;
      }
    }
    return null;
  }

  Future<void> setNexusPulseStyle(NexusPulseStyle style) async {
    if (_nexusPulseStyle == style) return;
    _nexusPulseStyle = style;
    notifyListeners();
    await _saveSettings();
  }

  Future<NexusPulseStyle> cycleNexusPulseStyle() async {
    final nextIndex = (_nexusPulseStyle.index + 1) % NexusPulseStyle.values.length;
    final nextStyle = NexusPulseStyle.values[nextIndex];
    await setNexusPulseStyle(nextStyle);
    return nextStyle;
  }

  Future<void> setNexusPulseColor(NexusPulseColor color) async {
    if (_nexusPulseColor == color) return;
    _nexusPulseColor = color;
    notifyListeners();
    await _saveSettings();
  }

  Future<NexusPulseColor> cycleNexusPulseColor() async {
    final nextIndex = (_nexusPulseColor.index + 1) % NexusPulseColor.values.length;
    final nextColor = NexusPulseColor.values[nextIndex];
    await setNexusPulseColor(nextColor);
    return nextColor;
  }

  Future<void> setAppTheme(AppThemeType theme) async {
    if (_appTheme == theme) return;
    _appTheme = theme;
    AppTheme.currentTheme = theme;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setFileExplorerDensity(FileExplorerDensity density) async {
    if (_fileExplorerDensity == density) return;
    _fileExplorerDensity = density;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setFileExplorerFontFamily(FileExplorerFontFamily fontFamily) async {
    if (_fileExplorerFontFamily == fontFamily) return;
    _fileExplorerFontFamily = fontFamily;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setFileExplorerIconTheme(FileExplorerIconTheme iconTheme) async {
    if (_fileExplorerIconTheme == iconTheme) return;
    _fileExplorerIconTheme = iconTheme;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusTerminalFontFamily(NexusTerminalFontFamily fontFamily) async {
    if (_nexusTerminalFontFamily == fontFamily) return;
    _nexusTerminalFontFamily = fontFamily;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusTerminalFontSize(double fontSize) async {
    final clamped = fontSize.clamp(8.0, 36.0);
    if ((_nexusTerminalFontSize - clamped).abs() < 0.01) return;
    _nexusTerminalFontSize = clamped;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusTerminalLineHeight(double lineHeight) async {
    final clamped = lineHeight.clamp(0.8, 2.0);
    if ((_nexusTerminalLineHeight - clamped).abs() < 0.01) return;
    _nexusTerminalLineHeight = clamped;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusTerminalThemeMode(NexusTerminalThemeMode themeMode) async {
    if (_nexusTerminalThemeMode == themeMode) return;
    _nexusTerminalThemeMode = themeMode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAppFontSize(AppFontSize fontSize) async {
    if (_appFontSize == fontSize) return;
    _appFontSize = fontSize;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setBorderAnimationDuration(double seconds) async {
    final clamped = seconds.clamp(1.0, 30.0);
    if ((_borderAnimationDuration - clamped).abs() < 0.01) return;
    _borderAnimationDuration = clamped;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setToolsViewMode(ToolsViewMode mode) async {
    if (_toolsViewMode == mode) return;
    _toolsViewMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setToolPinned(String toolId, bool pinned) async {
    final changed = pinned ? _pinnedTools.add(toolId) : _pinnedTools.remove(toolId);
    if (!changed) return;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> toggleToolPinned(String toolId) async {
    await setToolPinned(toolId, !_pinnedTools.contains(toolId));
  }

  Future<void> setGilanDashboardConfig({
    required String url,
    required String username,
    required String password,
  }) async {
    if (_gilanDashboardUrl == url &&
        _gilanDashboardUsername == username &&
        _gilanDashboardPassword == password) {
      return;
    }
    _gilanDashboardUrl = url;
    _gilanDashboardUsername = username;
    _gilanDashboardPassword = password;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNodeViewMode(NodeViewMode mode) async {
    if (!_enabledViewModes.contains(mode)) {
      _enabledViewModes.add(mode);
    }
    if (_nodeViewMode == mode) return;
    _nodeViewMode = mode;
    notifyListeners();
    await _saveSettings();
  }

  Future<bool> toggleViewModeEnabled(NodeViewMode mode) async {
    if (_enabledViewModes.contains(mode)) {
      // Don't allow disabling the last remaining view
      if (_enabledViewModes.length <= 1) {
        return false;
      }
      _enabledViewModes.remove(mode);
      if (_nodeViewMode == mode) {
        _nodeViewMode = _enabledViewModes.first;
      }
    } else {
      _enabledViewModes.add(mode);
      _nodeViewMode = mode;
    }

    notifyListeners();
    await _saveSettings();
    return true;
  }

  Future<void> setNexusOnlyWhenActive(bool value) async {
    if (_nexusOnlyWhenActive == value) return;
    _nexusOnlyWhenActive = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusAutoCloseTabOnDisconnect(bool value) async {
    if (_nexusAutoCloseTabOnDisconnect == value) return;
    _nexusAutoCloseTabOnDisconnect = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusAutoSessionLogging(bool value) async {
    if (_nexusAutoSessionLogging == value) return;
    _nexusAutoSessionLogging = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusCascadeExit(bool value) async {
    if (_nexusCascadeExit == value) return;
    _nexusCascadeExit = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusRunbookShowProgress(bool value) async {
    if (_nexusRunbookShowProgress == value) return;
    _nexusRunbookShowProgress = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusRunbookAutoClose(bool value) async {
    if (_nexusRunbookAutoClose == value) return;
    _nexusRunbookAutoClose = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNexusRunbookAutoCloseDelay(int seconds) async {
    final clamped = seconds.clamp(1, 30);
    if (_nexusRunbookAutoCloseDelay == clamped) return;
    _nexusRunbookAutoCloseDelay = clamped;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setNodesTabVisibility(bool value) async {
    if (_showNodesTab == value) return;
    _showNodesTab = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setFloatingCommandWidth(double width) async {
    final clamped = width.clamp(20.0, 100.0);
    if ((_floatingCommandWidth - clamped).abs() < 0.01) return;
    _floatingCommandWidth = clamped;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setLeftSidebarWidth(double width, {bool persist = true}) async {
    final clamped = width.clamp(50.0, 480.0);
    if ((_leftSidebarWidth - clamped).abs() >= 0.01) {
      _leftSidebarWidth = clamped;
      notifyListeners();
    }
    if (persist) {
      await _saveSettings();
    }
  }

  Future<void> setRightSidebarWidth(double width, {bool persist = true}) async {
    final clamped = width.clamp(320.0, 1200.0);
    final changed = (_rightSidebarWidth - clamped).abs() >= 0.01;
    if (changed) {
      _rightSidebarWidth = clamped;
      notifyListeners();
    }
    if (persist) {
      await _saveSettings();
    }
  }

  Future<void> setRememberedLogin({
    required bool rememberMe,
    required String username,
    required String password,
  }) async {
    final nextUsername = rememberMe ? username : '';
    final nextPassword = rememberMe ? password : '';
    if (_rememberMe == rememberMe &&
        _rememberedUsername == nextUsername &&
        _rememberedPassword == nextPassword) {
      return;
    }
    _rememberMe = rememberMe;
    _rememberedUsername = nextUsername;
    _rememberedPassword = nextPassword;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAutoCheckUpdates(bool value) async {
    if (_autoCheckUpdates == value) return;
    _autoCheckUpdates = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setAutoDownloadUpdates(bool value) async {
    if (_autoDownloadUpdates == value) return;
    _autoDownloadUpdates = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setUpdateRemotePath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty || _updateRemotePath == trimmed) return;
    _updateRemotePath = trimmed;
    notifyListeners();
    await _saveSettings();
  }

  String _themeToYamlString(AppThemeType theme) {
    return theme.name.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
  }

  Future<void> _saveSettings() async {
    try {
      final file = File(_getConfigPath());
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final buffer = StringBuffer();
      buffer.writeln('# Smart-E HE Application Settings');
      buffer.writeln('nexus_only_when_active: $_nexusOnlyWhenActive');
      buffer.writeln(
          'nexus_auto_close_tab_on_disconnect: $_nexusAutoCloseTabOnDisconnect');
      buffer.writeln('nexus_auto_session_logging: $_nexusAutoSessionLogging');
      buffer.writeln('nexus_cascade_exit: $_nexusCascadeExit');
      buffer.writeln('nexus_runbook_show_progress: $_nexusRunbookShowProgress');
      buffer.writeln('nexus_runbook_auto_close: $_nexusRunbookAutoClose');
      buffer.writeln('nexus_runbook_auto_close_delay: $_nexusRunbookAutoCloseDelay');
      buffer.writeln('show_nodes_tab: $_showNodesTab');
      buffer.writeln('nexus_pulse_style: "${_nexusPulseStyle.name}"');
      buffer.writeln('nexus_pulse_color: "${_nexusPulseColor.name}"');
      buffer.writeln('floating_command_width: ${_floatingCommandWidth.round()}');
      buffer.writeln('right_sidebar_width: ${_rightSidebarWidth.round()}');
      buffer.writeln('left_sidebar_width: ${_leftSidebarWidth.round()}');
      buffer.writeln('app_theme: "${_themeToYamlString(_appTheme)}"');
      buffer.writeln('app_font_size: "${_appFontSize.name}"');
      buffer.writeln('border_animation_duration: $_borderAnimationDuration');
      buffer.writeln('remember_me: $_rememberMe');
      buffer.writeln('remembered_username: "$_rememberedUsername"');
      // Passwords are no longer saved in plaintext YAML files for security
      buffer.writeln('tools_page_view: "${_toolsViewMode.name}"');
      buffer.writeln('gilan_dashboard:');
      buffer.writeln('  url: "$_gilanDashboardUrl"');
      buffer.writeln('  username: "$_gilanDashboardUsername"');
      buffer.writeln('nodes_page_view:');
      buffer.writeln('  current: "${_nodeViewMode.name}"');
      buffer.writeln('  enabled:');
      for (final mode in _enabledViewModes) {
        buffer.writeln('    - "${mode.name}"');
      }
      buffer.writeln('auto_check_updates: $_autoCheckUpdates');
      buffer.writeln('auto_download_updates: $_autoDownloadUpdates');
      buffer.writeln('update_remote_path: "$_updateRemotePath"');
      buffer.writeln('file_explorer_density: "${_fileExplorerDensity.name}"');
      buffer.writeln('file_explorer_font_family: "${_fileExplorerFontFamily.name}"');
      buffer.writeln('file_explorer_icon_theme: "${_fileExplorerIconTheme.name}"');
      buffer.writeln('nexus_terminal_font_family: "${_nexusTerminalFontFamily.name}"');
      buffer.writeln('nexus_terminal_font_size: $_nexusTerminalFontSize');
      buffer.writeln('nexus_terminal_line_height: $_nexusTerminalLineHeight');
      buffer.writeln('nexus_terminal_theme_mode: "${_nexusTerminalThemeMode.name}"');
      buffer.writeln('pinned_tools:');
      for (final t in _pinnedTools) {
        buffer.writeln('  - "$t"');
      }
      file.writeAsStringSync(buffer.toString());
    } catch (e) {
      debugPrint('Failed to save settings: $e');
    }
  }

  Future<void> saveSettings() => _saveSettings();

  Future<void> fetchUserPreferencesFromFirestore(String email) async {
    return;
  }

  Future<void> saveUserPreferencesToFirestore(String email) async {
    return;
  }
}
