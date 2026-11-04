import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../models/file_explorer_models.dart';
import '../models/nexus_tool.dart';
import '../models/session_models.dart';
import '../services/crypto_vault_service.dart';
import '../services/nexus_tool_registry.dart';
import '../services/session_manager_service.dart';
import '../services/settings_service.dart';
import '../services/window_state_service.dart';
import '../theme/app_theme.dart';
import '../widgets/command_palette.dart';
import '../widgets/file_explorer_dialogs.dart';
import '../widgets/file_explorer_view.dart';
import '../widgets/fuzzy_searchable_dropdown.dart';
import '../widgets/keyboard_shortcuts_dialog.dart';
import '../widgets/sidebar_icon.dart';
import '../widgets/window_caption_buttons.dart';
import 'nexus_screen.dart';
import 'sessions_screen.dart';

enum AppTab {
  sessions,
  nexus,
  fileExplorer,
  settings,
}

class MainScreen extends StatefulWidget {
  final SessionManagerService? sessionManager;
  final NexusToolRegistry? toolRegistry;
  final List<NexusTool>? customTools;
  final String appTitle;
  final bool suppressStartupDialog;

  const MainScreen({
    super.key,
    this.sessionManager,
    this.toolRegistry,
    this.customTools,
    this.appTitle = 'NexusFX',
    this.suppressStartupDialog = false,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final SessionManagerService _sessionManager;
  late final NexusToolRegistry _toolRegistry;
  AppTab _selectedTab = AppTab.sessions;
  AppTab _previousTab = AppTab.sessions;
  String? _selectedCustomToolId;
  String? _previousCustomToolId;
  bool _isSidebarVisible = true;
  bool _isRightSidebarVisible = false;
  final GlobalKey<NexusScreenState> _nexusKey = GlobalKey<NexusScreenState>();
  final FocusNode _sidebarFocusNode = FocusNode();
  int _sidebarIndex = 0;
  bool _isCommandPaletteOpen = false;

  List<NexusTool> get _customTools => _toolRegistry.tools;
  bool get _isNexusActive => _selectedCustomToolId == null && _selectedTab == AppTab.nexus;
  bool get _isFileExplorerActive => _selectedCustomToolId == null && _selectedTab == AppTab.fileExplorer;

  static const List<AppTab> _sidebarTabs = [
    AppTab.sessions,
    AppTab.nexus,
    AppTab.fileExplorer,
  ];

  static const double _minCompactSidebarWidth = 50.0;
  static const double _minExpandedSidebarWidth = 110.0;
  static const double _maxSidebarWidth = 350.0;
  static const double _defaultSidebarWidth = 170.0;

  double _sidebarWidth = 170.0;
  bool _isDraggingDivider = false;
  bool _isDividerHovered = false;
  double _dragStartWidth = 170.0;
  double _dragAccumulatedDelta = 0.0;
  bool _showSashDots = false;
  bool _isMainWidgetSelected = false;
  Timer? _sashIdleTimer;

  void _showDotsWithAutoFade() {
    _sashIdleTimer?.cancel();
    if (!_showSashDots && mounted) {
      setState(() => _showSashDots = true);
    }
    _sashIdleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isDividerHovered && !_isDraggingDivider) {
        setState(() => _showSashDots = false);
      }
    });
  }

  void _onSidebarOrSashPointer() {
    if (_isMainWidgetSelected && mounted) {
      setState(() => _isMainWidgetSelected = false);
    }
    _showDotsWithAutoFade();
  }

  void _onSelectMainWidget() {
    _sashIdleTimer?.cancel();
    if (mounted && (_showSashDots || !_isMainWidgetSelected)) {
      setState(() {
        _isMainWidgetSelected = true;
        _showSashDots = false;
      });
    }
  }

  int _nextFileExplorerTabId = 1;
  late final List<_FileExplorerTab> _fileExplorerTabs = [
    _createDefaultFileExplorerTab(),
  ];
  int _activeFileExplorerTab = 0;
  final ScrollController _fileExplorerTabScrollController = ScrollController();

  _FileExplorerTab _createDefaultFileExplorerTab() {
    return _FileExplorerTab(
      id: 'fe_tab_${_nextFileExplorerTabId++}',
      label: 'Local Explorer',
      leftTarget: ExplorerNodeTarget.local,
      rightTarget: ExplorerNodeTarget.local,
      initialActivePane: PaneSide.left,
    );
  }

  String _formatExplorerTabLabel(ExplorerNodeTarget target) {
    if (target.isLocal) return 'Local Explorer';
    return 'SFTP: ${target.label}';
  }

  @override
  void initState() {
    super.initState();
    _sessionManager = widget.sessionManager ?? SessionManagerService.instance;
    _toolRegistry = widget.toolRegistry ?? NexusToolRegistry.instance;
    if (widget.customTools != null && widget.customTools!.isNotEmpty) {
      _toolRegistry.registerAll(widget.customTools!);
    }
    _toolRegistry.addListener(_onToolsChanged);
    final savedLeftWidth = SettingsService.instance.leftSidebarWidth;
    if (savedLeftWidth >= _minCompactSidebarWidth && savedLeftWidth <= _maxSidebarWidth) {
      _sidebarWidth = savedLeftWidth;
    }
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    if (!widget.suppressStartupDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (SettingsService.instance.showSessionDialogAtStartup && mounted) {
          _openStartupSessionsDialog();
        }
      });
    }
  }

  void _onToolsChanged() {
    if (!mounted) return;
    setState(() {
      if (_selectedCustomToolId != null &&
          _toolRegistry.getToolById(_selectedCustomToolId!) == null) {
        _selectedCustomToolId = null;
        _selectedTab = AppTab.sessions;
      }
    });
  }

  NexusToolContext _buildToolContext() {
    return NexusToolContext(
      sessionManager: _sessionManager,
      settings: SettingsService.instance,
      cryptoVault: CryptoVaultService.instance,
      tabController: _nexusKey.currentState?.tabController,
      broadcastCoordinator: _nexusKey.currentState?.broadcastCoordinator,
      connectSessionInTerminal: (profile, {toRightPane = false}) {
        _selectTab(AppTab.nexus, 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.connectSessionProfile(profile, toRightPane: toRightPane);
        });
      },
      openSessionInFileExplorer: _openSessionInFileExplorer,
      navigateToTerminal: () => _selectTab(AppTab.nexus, 1),
      navigateToSessions: () => _selectTab(AppTab.sessions, 0),
      navigateToFileExplorer: () => _selectTab(AppTab.fileExplorer, 2),
      navigateToTool: (toolId) {
        final idx = _customTools.indexWhere((t) => t.id == toolId);
        if (idx != -1) {
          _selectCustomTool(_customTools[idx], _sidebarTabs.length + idx);
        }
      },
    );
  }

  @override
  void dispose() {
    _toolRegistry.removeListener(_onToolsChanged);
    _sashIdleTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _sidebarFocusNode.dispose();
    _fileExplorerTabScrollController.dispose();
    for (final tab in _fileExplorerTabs) {
      tab.dispose();
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    // Do not intercept if a modal route (like dialog or command palette) is active on top
    final route = ModalRoute.of(context);
    final isCurrentRoute = route == null || route.isCurrent;
    if (!isCurrentRoute) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
    final isShift = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
    final isAlt = HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.altRight);
    final isSpace = event.logicalKey == LogicalKeyboardKey.space ||
        event.physicalKey == PhysicalKeyboardKey.space;

    // Ctrl+B: Toggle Left Sidebar
    if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyB) {
      _toggleSidebar();
      return true;
    }

    // Ctrl+Shift+B: Toggle Right Sidebar (Nexus Runbook)
    if (isCtrl && isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyB) {
      if (_isNexusActive) {
        _toggleRightSidebar();
        return true;
      }
    }

    // Ctrl+Space: Quick Connect Sessions
    if (isCtrl && !isShift && !isAlt && isSpace) {
      if (!_isCommandPaletteOpen) {
        _showCommandPalette(sessionsOnly: true);
        return true;
      }
    }

    // Ctrl+Shift+P: Full Command Palette
    if (isCtrl && isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyP) {
      if (!_isCommandPaletteOpen) {
        _showCommandPalette(sessionsOnly: false);
        return true;
      }
    }

    // Alt+S or Ctrl+0: Focus Sidebar / Switch to Sessions
    if (isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyS) {
      _focusSidebar();
      return true;
    }
    final isDigit0 = event.logicalKey == LogicalKeyboardKey.digit0 ||
        event.logicalKey == LogicalKeyboardKey.numpad0;
    if (isCtrl && !isShift && !isAlt && isDigit0) {
      _focusSidebar();
      return true;
    }

    // Alt+1 .. Alt+4: Direct Tab Switching
    if (isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.digit1) {
      _selectTab(AppTab.sessions, 0);
      return true;
    }
    if (isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.digit2) {
      _selectTab(AppTab.nexus, 1);
      return true;
    }
    if (isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.digit3) {
      _selectTab(AppTab.fileExplorer, 2);
      return true;
    }
    if (isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.digit4) {
      _toggleSettings();
      return true;
    }

    // Resize Left Sidebar shortcuts:
    // Alt + LeftArrow -> Shrink left sidebar (step by step to 50px icon-only)
    // Alt + RightArrow -> Enlarge left sidebar (step by step up to 350px)
    final isArrowLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.physicalKey == PhysicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.bracketLeft ||
        event.physicalKey == PhysicalKeyboardKey.bracketLeft;
    final isArrowRight = event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.physicalKey == PhysicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.bracketRight ||
        event.physicalKey == PhysicalKeyboardKey.bracketRight;

    if (isAlt && !isCtrl && !isShift && (isArrowLeft || isArrowRight)) {
      if (!_isSidebarVisible) {
        setState(() => _isSidebarVisible = true);
      }
      setState(() {
        const double step = 30.0;
        if (isArrowLeft) {
          // Shrink sidebar towards left
          if (_sidebarWidth <= _minExpandedSidebarWidth) {
            _sidebarWidth = _minCompactSidebarWidth; // 50.0
          } else {
            final next = _sidebarWidth - step;
            _sidebarWidth = next < _minExpandedSidebarWidth
                ? _minCompactSidebarWidth
                : next;
          }
        } else {
          // Enlarge sidebar towards right
          if (_sidebarWidth < _minExpandedSidebarWidth) {
            _sidebarWidth = _minExpandedSidebarWidth; // 110.0
          } else {
            _sidebarWidth = (_sidebarWidth + step).clamp(_minExpandedSidebarWidth, _maxSidebarWidth);
          }
        }
      });
      SettingsService.instance.setLeftSidebarWidth(_sidebarWidth);
      return true;
    }

    // Ctrl+Shift+Space: Toggle Command Pane in Nexus
    if (isCtrl && isShift && !isAlt && isSpace) {
      if (!_isNexusActive) {
        _selectTab(AppTab.nexus, 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.showCommandPane();
        });
      } else {
        _nexusKey.currentState?.toggleCommandPane();
      }
      return true;
    }

    // File Explorer Tab shortcuts: Ctrl+T (New Tab), Ctrl+W (Close Tab), Ctrl+Tab (Next/Prev Tab)
    if (_isFileExplorerActive) {
      if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyT) {
        _promptNewFileExplorerTab();
        return true;
      }
      if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyW) {
        _closeFileExplorerTab(_activeFileExplorerTab);
        return true;
      }
      if (isCtrl && !isAlt && event.logicalKey == LogicalKeyboardKey.tab) {
        _switchFileExplorerTab(isShift ? -1 : 1);
        return true;
      }
    }

    // F11: Full Screen
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullScreen();
      return true;
    }

    // Ctrl+Q: Exit
    if (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.keyQ) {
      _confirmAndExit();
      return true;
    }

    // F1 or Ctrl+/: Shortcuts Help
    if (event.logicalKey == LogicalKeyboardKey.f1 ||
        (isCtrl && !isShift && !isAlt && event.logicalKey == LogicalKeyboardKey.slash)) {
      _showKeyboardShortcutsDialog();
      return true;
    }

    // Sidebar navigation when focused
    if (_sidebarFocusNode.hasFocus) {
      final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.keyK;
      final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.keyJ;
      final totalSidebarItems = _sidebarTabs.length + _customTools.length;

      if (!isCtrl && !isShift && !isAlt && (isUp || isDown) && totalSidebarItems > 0) {
        setState(() {
          if (isDown) {
            _sidebarIndex = (_sidebarIndex + 1) % totalSidebarItems;
          } else {
            _sidebarIndex = (_sidebarIndex - 1 + totalSidebarItems) % totalSidebarItems;
          }
        });
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.keyL) {
        if (_sidebarIndex < _sidebarTabs.length) {
          _selectTab(_sidebarTabs[_sidebarIndex], _sidebarIndex);
        } else {
          final toolIdx = _sidebarIndex - _sidebarTabs.length;
          if (toolIdx >= 0 && toolIdx < _customTools.length) {
            _selectCustomTool(_customTools[toolIdx], _sidebarIndex);
          }
        }
        _sidebarFocusNode.unfocus();
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _sidebarFocusNode.unfocus();
        return true;
      }
    }

    return false;
  }

  void _selectTab(AppTab tab, int index) {
    setState(() {
      _selectedCustomToolId = null;
      _previousCustomToolId = null;
      _selectedTab = tab;
      _previousTab = tab;
      _sidebarIndex = index;
    });
    if (tab == AppTab.fileExplorer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusActiveFileExplorer();
      });
    }
  }

  void _selectCustomTool(NexusTool tool, int sidebarIndex) {
    setState(() {
      _selectedCustomToolId = tool.id;
      _previousCustomToolId = tool.id;
      if (_selectedTab == AppTab.settings) {
        _selectedTab = _previousTab;
      }
      _sidebarIndex = sidebarIndex;
    });
  }

  void _toggleSettings() {
    setState(() {
      if (_selectedTab == AppTab.settings) {
        _selectedTab = _previousTab;
        _selectedCustomToolId = _previousCustomToolId;
      } else {
        _previousTab = _selectedTab;
        _previousCustomToolId = _selectedCustomToolId;
        _selectedCustomToolId = null;
        _selectedTab = AppTab.settings;
      }
    });
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarVisible = !_isSidebarVisible;
      if (!_isSidebarVisible && _sidebarFocusNode.hasFocus) {
        _sidebarFocusNode.unfocus();
      }
    });
  }

  void _toggleRightSidebar() {
    if (_isNexusActive) {
      _nexusKey.currentState?.toggleRightSidebar();
    }
  }

  void _focusSidebar() {
    setState(() {
      _isSidebarVisible = true;
      if (_selectedCustomToolId != null) {
        final toolIdx = _customTools.indexWhere((t) => t.id == _selectedCustomToolId);
        _sidebarIndex = toolIdx >= 0 ? _sidebarTabs.length + toolIdx : 0;
      } else {
        final idx = _sidebarTabs.indexOf(_selectedTab);
        _sidebarIndex = idx >= 0 ? idx : 0;
      }
    });
    _sidebarFocusNode.requestFocus();
  }

  Future<void> _toggleFullScreen() async {
    await WindowStateService.instance.toggleFullScreen();
  }

  Future<void> _confirmAndExit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: Text('Exit ${widget.appTitle}?'),
        content: Text(
          'Are you sure you want to exit ${widget.appTitle}? Any running terminal sessions will be terminated.',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      exit(0);
    }
  }

  void _showKeyboardShortcutsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const KeyboardShortcutsDialog(),
    );
  }

  void _showCommandPalette({bool sessionsOnly = false}) {
    if (_isCommandPaletteOpen) return;
    _isCommandPaletteOpen = true;
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => CommandPalette(
        sessionsOnly: sessionsOnly,
        sessionManager: _sessionManager,
        customTools: _customTools,
        toolContext: _buildToolContext(),
        onSelect: _handleCommandAction,
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isCommandPaletteOpen = false);
      } else {
        _isCommandPaletteOpen = false;
      }
    });
  }

  void _handleCommandAction(CommandItem item) {
    switch (item.action) {
      case CommandAction.connectSession:
        if (item.session != null) {
          _selectTab(AppTab.nexus, 1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _nexusKey.currentState?.connectSessionProfile(item.session!);
          });
        }
        break;
      case CommandAction.openSessionsManager:
        _openStartupSessionsDialog();
        break;
      case CommandAction.toggleSplitView:
        _selectTab(AppTab.nexus, 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.toggleSplitView();
        });
        break;
      case CommandAction.toggleCommandPane:
        _selectTab(AppTab.nexus, 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.toggleCommandPane();
        });
        break;
      case CommandAction.toggleRunbookSidebar:
        _selectTab(AppTab.nexus, 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.toggleRightSidebar();
        });
        break;
      case CommandAction.setTheme:
        break;
      case CommandAction.setFontSize:
        break;
      case CommandAction.openCustomTool:
        if (item.customToolId != null) {
          final idx = _customTools.indexWhere((t) => t.id == item.customToolId);
          if (idx != -1) {
            _selectCustomTool(_customTools[idx], _sidebarTabs.length + idx);
          }
        }
        break;
      case CommandAction.executeCustomToolCommand:
        item.onCustomExecute?.call();
        break;
    }
  }

  void _openStartupSessionsDialog() {
    SessionsDialog.show(
      context,
      sessionManager: _sessionManager,
      initialShowAtStartup: SettingsService.instance.showSessionDialogAtStartup,
      onToggleShowAtStartup: (val) {
        SettingsService.instance.setShowSessionDialogAtStartup(val);
      },
      onConnectSessions: (sessions, {openInRightSplit = false}) {
        _selectTab(AppTab.nexus, 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final s in sessions) {
            _nexusKey.currentState?.connectSessionProfile(s, toRightPane: openInRightSplit);
          }
        });
      },
      onOpenInFileExplorer: (session) {
        _openSessionInFileExplorer(session);
      },
    );
  }

  void _openSessionInFileExplorer(SessionProfile session) {
    if (session.protocol != SessionProtocol.ssh) return;
    final route = _sessionManager.resolveSshRoute(session);
    final target = ExplorerNodeTarget.fromSessionProfile(session, route);
    _openSftpTab(target);
  }

  Future<void> _promptNewFileExplorerTab() async {
    final selected = await showDialog<ExplorerNodeTarget>(
      context: context,
      builder: (ctx) => FileExplorerNodePickerDialog(
        currentTarget: ExplorerNodeTarget.local,
      ),
    );
    if (selected != null && mounted) {
      _openSftpTab(selected);
    }
  }

  void _openSftpTab(ExplorerNodeTarget target) {
    setState(() {
      _selectedCustomToolId = null;
      _selectedTab = AppTab.fileExplorer;
      final newTab = _FileExplorerTab(
        id: 'fe_tab_${_nextFileExplorerTabId++}',
        label: _formatExplorerTabLabel(target),
        leftTarget: ExplorerNodeTarget.local,
        rightTarget: target,
        initialActivePane: target.isLocal ? PaneSide.left : PaneSide.right,
      );
      _fileExplorerTabs.add(newTab);
      _activeFileExplorerTab = _fileExplorerTabs.length - 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_fileExplorerTabScrollController.hasClients) {
        _fileExplorerTabScrollController.animateTo(
          _fileExplorerTabScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      _focusActiveFileExplorer();
    });
  }

  void _switchFileExplorerTab(int delta) {
    if (_fileExplorerTabs.length <= 1) return;
    setState(() {
      _activeFileExplorerTab =
          (_activeFileExplorerTab + delta) % _fileExplorerTabs.length;
      if (_activeFileExplorerTab < 0) {
        _activeFileExplorerTab += _fileExplorerTabs.length;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusActiveFileExplorer();
    });
  }

  void _focusActiveFileExplorer() {
    if (!mounted || _selectedTab != AppTab.fileExplorer) return;
    final safeIdx = _activeFileExplorerTab.clamp(
      0,
      _fileExplorerTabs.isNotEmpty ? _fileExplorerTabs.length - 1 : 0,
    );
    if (_fileExplorerTabs.isNotEmpty && safeIdx < _fileExplorerTabs.length) {
      final node = _fileExplorerTabs[safeIdx].focusNode;
      if (node.canRequestFocus) {
        node.requestFocus();
      }
    }
  }

  void _closeFileExplorerTab(int index) {
    if (index < 0 || index >= _fileExplorerTabs.length) return;
    final toRemove = _fileExplorerTabs[index];
    setState(() {
      if (_fileExplorerTabs.length <= 1) {
        _fileExplorerTabs
          ..clear()
          ..add(_createDefaultFileExplorerTab());
        _activeFileExplorerTab = 0;
      } else {
        _fileExplorerTabs.removeAt(index);
        if (_activeFileExplorerTab >= _fileExplorerTabs.length) {
          _activeFileExplorerTab = _fileExplorerTabs.length - 1;
        } else if (_activeFileExplorerTab > index) {
          _activeFileExplorerTab--;
        }
      }
    });
    toRemove.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusActiveFileExplorer();
    });
  }

  void _closeOtherFileExplorerTabs(_FileExplorerTab keepTab) {
    final toRemove = _fileExplorerTabs.where((t) => t.id != keepTab.id).toList();
    setState(() {
      _fileExplorerTabs.removeWhere((t) => t.id != keepTab.id);
      _activeFileExplorerTab = 0;
    });
    for (final t in toRemove) {
      t.dispose();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusActiveFileExplorer();
    });
  }

  void _closeAllFileExplorerTabs() {
    final toRemove = List<_FileExplorerTab>.from(_fileExplorerTabs);
    setState(() {
      _fileExplorerTabs
        ..clear()
        ..add(_createDefaultFileExplorerTab());
      _activeFileExplorerTab = 0;
    });
    for (final t in toRemove) {
      t.dispose();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusActiveFileExplorer();
    });
  }

  Future<void> _showFileExplorerTabContextMenu(
    Offset globalPosition,
    _FileExplorerTab tab,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final overlayRect = overlay != null
        ? Offset.zero & overlay.size
        : Offset.zero & MediaQuery.of(context).size;

    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      overlayRect,
    );

    final canCloseOthers = _fileExplorerTabs.length > 1;

    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: AppTheme.surfaceColor,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppTheme.inputBorderColor),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'new_tab',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.add, size: 14, color: AppTheme.accentPrimary),
              SizedBox(width: 8),
              Expanded(
                child: Text('New Tab', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
              ),
              Text('Ctrl+T', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'close',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.close, size: 14, color: AppTheme.textPrimary),
              SizedBox(width: 8),
              Expanded(
                child: Text('Close Tab', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
              ),
              Text('Ctrl+W', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'close_others',
          enabled: canCloseOthers,
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.tab_unselected,
                size: 14,
                color: canCloseOthers ? AppTheme.textPrimary : Colors.grey,
              ),
              SizedBox(width: 8),
              Text(
                'Close Other Tabs',
                style: TextStyle(
                  fontSize: 12,
                  color: canCloseOthers ? AppTheme.textPrimary : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'close_all',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.clear_all, size: 14, color: AppTheme.statusError),
              SizedBox(width: 8),
              Text('Close All Tabs', style: TextStyle(fontSize: 12, color: AppTheme.statusError)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;

    switch (selected) {
      case 'new_tab':
        _promptNewFileExplorerTab();
        break;
      case 'close':
        final idx = _fileExplorerTabs.indexWhere((t) => t.id == tab.id);
        if (idx != -1) _closeFileExplorerTab(idx);
        break;
      case 'close_others':
        _closeOtherFileExplorerTabs(tab);
        break;
      case 'close_all':
        _closeAllFileExplorerTabs();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNexusWithRightSidebar = _isNexusActive && _isRightSidebarVisible;

    return Scaffold(
      backgroundColor: AppTheme.activePalette.background,
      body: MouseRegion(
        onHover: (_) {
          if (!_isMainWidgetSelected) {
            _showDotsWithAutoFade();
          }
        },
        child: Column(
          children: [
            _buildTitleBar(),
            Expanded(
              child: Row(
                children: [
                  if (_isSidebarVisible) ...[
                    _buildSidebar(),
                    _buildResizeHandle(),
                  ],
                  Expanded(
                    child: isNexusWithRightSidebar
                        ? _buildBodyContent()
                        : Container(
                            margin: EdgeInsets.only(
                              left: _isSidebarVisible ? 0 : 3,
                              right: 3,
                              top: 3,
                              bottom: 3,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _isMainWidgetSelected
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.accentPrimary.withValues(alpha: 0.08),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (_) => _onSelectMainWidget(),
                              child: Material(
                                color: AppTheme.bgSurface,
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: _isMainWidgetSelected
                                        ? AppTheme.accentPrimary.withValues(alpha: 0.45)
                                        : AppTheme.borderSubtle.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                child: _buildBodyContent(),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 38,
      color: AppTheme.activePalette.background,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 18, color: AppTheme.accentPrimary),
          const SizedBox(width: 6),
          Text(
            widget.appTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          // Window drag-to-move area across middle of top bar
          Expanded(
            child: DragToMoveArea(
              child: Container(
                height: 38,
                color: Colors.transparent,
              ),
            ),
          ),
          // Settings Button (placed to the left of the left sidebar toggle button)
          _SettingsTopBarButton(
            isSelected: _selectedTab == AppTab.settings,
            onTap: _toggleSettings,
          ),
          Container(
            height: 16,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: AppTheme.borderSubtle,
          ),
          // Layout Controls: Left Sidebar, Right Sidebar (Nexus page only), Fullscreen
          SidebarToggleButton(
            isSidebarVisible: _isSidebarVisible,
            onTap: _toggleSidebar,
          ),
          if (_isNexusActive) ...[
            const SizedBox(width: 4),
            RightSidebarToggleButton(
              isSidebarVisible: _isRightSidebarVisible,
              onTap: _toggleRightSidebar,
            ),
          ],
          const SizedBox(width: 4),
          _KeyboardShortcutsTopBarButton(
            onTap: _showKeyboardShortcutsDialog,
          ),
          const SizedBox(width: 8),
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            const WindowCaptionButtons(showFullScreen: true),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final isCompact = _sidebarWidth <= 70;
    final tools = _customTools;
    return MouseRegion(
      onHover: (_) => _onSidebarOrSashPointer(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _onSidebarOrSashPointer(),
        child: Container(
          width: _sidebarWidth,
          margin: const EdgeInsets.only(left: 3, top: 3, bottom: 3),
          child: Material(
            color: AppTheme.bgSurfaceSecondary,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: AppTheme.borderSubtle.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Focus(
              focusNode: _sidebarFocusNode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _buildSidebarNavItem(AppTab.sessions, 'Sessions', Icons.dns_outlined, 0, isCompact),
                  _buildSidebarNavItem(AppTab.nexus, 'Nexus', Icons.terminal, 1, isCompact),
                  _buildSidebarNavItem(AppTab.fileExplorer, 'File Explorer', Icons.folder_open, 2, isCompact),
                  if (tools.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 8 : 12,
                        vertical: 6,
                      ),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: AppTheme.borderSubtle.withValues(alpha: 0.6),
                      ),
                    ),
                    for (int i = 0; i < tools.length; i++)
                      _buildCustomToolSidebarItem(
                        tools[i],
                        _sidebarTabs.length + i,
                        isCompact,
                      ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarNavItem(
    AppTab tab,
    String label,
    IconData icon,
    int index,
    bool isCompact,
  ) {
    final isSelected = _selectedCustomToolId == null && _selectedTab == tab;
    return _buildSidebarItemTile(
      label: label,
      icon: icon,
      index: index,
      isCompact: isCompact,
      isSelected: isSelected,
      onTap: () => _selectTab(tab, index),
    );
  }

  Widget _buildCustomToolSidebarItem(
    NexusTool tool,
    int index,
    bool isCompact,
  ) {
    final isSelected = _selectedTab != AppTab.settings && _selectedCustomToolId == tool.id;
    return _buildSidebarItemTile(
      label: tool.title,
      icon: tool.icon,
      index: index,
      isCompact: isCompact,
      isSelected: isSelected,
      onTap: () => _selectCustomTool(tool, index),
    );
  }

  Widget _buildSidebarItemTile({
    required String label,
    required IconData icon,
    required int index,
    required bool isCompact,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isFocused = _sidebarFocusNode.hasFocus && _sidebarIndex == index;

    final Widget content = isCompact
        ? Center(
            child: Icon(
              icon,
              size: 18,
              color: isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary,
            ),
          )
        : Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? AppTheme.accentPrimary : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          );

    final Widget itemContainer = Container(
      height: 36,
      margin: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 8,
        vertical: 2,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 0 : 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.accentPrimary.withValues(alpha: 0.15)
            : (isFocused ? AppTheme.bgSurface.withValues(alpha: 0.4) : Colors.transparent),
        borderRadius: BorderRadius.circular(4),
        border: isSelected
            ? Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.4))
            : (isFocused ? Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.2)) : null),
      ),
      child: content,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: isCompact
          ? Tooltip(
              message: label,
              waitDuration: const Duration(milliseconds: 300),
              child: itemContainer,
            )
          : itemContainer,
    );
  }

  Widget _buildResizeHandle() {
    final isInteracting = _isDraggingDivider || _isDividerHovered;
    final dotColor = isInteracting
        ? AppTheme.accentPrimary
        : AppTheme.textMuted.withValues(alpha: 0.6);
    final shouldShowDots = isInteracting || (_showSashDots && !_isMainWidgetSelected);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) {
        setState(() {
          _isDividerHovered = true;
          _isMainWidgetSelected = false;
        });
      },
      onExit: (_) => setState(() => _isDividerHovered = false),
      onHover: (_) => _onSidebarOrSashPointer(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) {
          setState(() {
            _isDraggingDivider = true;
            _isMainWidgetSelected = false;
            _dragStartWidth = _sidebarWidth;
            _dragAccumulatedDelta = 0.0;
          });
        },
        onHorizontalDragUpdate: (details) {
          setState(() {
            _dragAccumulatedDelta += details.delta.dx;
            final candidate = _dragStartWidth + _dragAccumulatedDelta;
            if (candidate < 85) {
              _sidebarWidth = _minCompactSidebarWidth;
            } else {
              _sidebarWidth = candidate.clamp(_minExpandedSidebarWidth, _maxSidebarWidth);
            }
          });
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isDraggingDivider = false);
          SettingsService.instance.setLeftSidebarWidth(_sidebarWidth);
          _showDotsWithAutoFade();
        },
        onDoubleTap: () {
          setState(() {
            if (_sidebarWidth <= _minCompactSidebarWidth + 10) {
              _sidebarWidth = _defaultSidebarWidth;
            } else {
              _sidebarWidth = _minCompactSidebarWidth;
            }
          });
          SettingsService.instance.setLeftSidebarWidth(_sidebarWidth);
        },
        child: Container(
          width: 5,
          color: Colors.transparent,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isInteracting)
                  Container(
                    width: 1,
                    height: double.infinity,
                    color: AppTheme.accentPrimary.withValues(alpha: 0.5),
                  ),
                AnimatedOpacity(
                  opacity: shouldShowDots ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSashDot(dotColor),
                      const SizedBox(height: 3),
                      _buildSashDot(dotColor),
                      const SizedBox(height: 3),
                      _buildSashDot(dotColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSashDot(Color color) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildBodyContent() {
    final tools = _customTools;
    int stackIndex = _selectedTab.index;
    if (_selectedTab != AppTab.settings && _selectedCustomToolId != null) {
      final toolIdx = tools.indexWhere((t) => t.id == _selectedCustomToolId);
      if (toolIdx != -1) {
        stackIndex = 4 + toolIdx;
      }
    }

    return IndexedStack(
      index: stackIndex,
      children: [
        SessionsScreen(
          sessionManager: _sessionManager,
          isActive: _selectedCustomToolId == null && _selectedTab == AppTab.sessions,
          onConnectSessions: (sessions, {openInRightSplit = false}) {
            _selectTab(AppTab.nexus, 1);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              for (final s in sessions) {
                _nexusKey.currentState?.connectSessionProfile(s, toRightPane: openInRightSplit);
              }
            });
          },
          onOpenInFileExplorer: _openSessionInFileExplorer,
        ),
        NexusScreen(
          key: _nexusKey,
          onRightSidebarChanged: (visible) {
            if (mounted && _isRightSidebarVisible != visible) {
              setState(() => _isRightSidebarVisible = visible);
            }
          },
        ),
        _buildFileExplorerPage(),
        _buildSettingsScreen(),
        for (final tool in tools)
          KeyedSubtree(
            key: ValueKey('nexus_custom_tool_${tool.id}'),
            child: Builder(
              builder: (ctx) => tool.buildView(ctx, _buildToolContext()),
            ),
          ),
      ],
    );
  }

  Widget _buildFileExplorerPage() {
    final safeActiveIdx = _activeFileExplorerTab.clamp(
      0,
      _fileExplorerTabs.isNotEmpty ? _fileExplorerTabs.length - 1 : 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 38,
          decoration: const BoxDecoration(
            color: AppTheme.bgSurfaceSecondary,
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.folder_outlined, color: AppTheme.accentPrimary, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'FILE EXPLORER',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 22, color: AppTheme.borderSubtle),
              Expanded(
                child: ListView.builder(
                  controller: _fileExplorerTabScrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: _fileExplorerTabs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _fileExplorerTabs.length) {
                      return _buildFileExplorerAddTabButton();
                    }
                    final tab = _fileExplorerTabs[index];
                    final isActive = index == safeActiveIdx;
                    return _buildFileExplorerTabItem(tab, index, isActive);
                  },
                ),
              ),
              if (_fileExplorerTabs.length > 1)
                _buildFileExplorerCloseAllButton(),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: safeActiveIdx,
            children: _fileExplorerTabs.asMap().entries.map((entry) {
              final index = entry.key;
              final tab = entry.value;
              final isTabActive = (_selectedTab == AppTab.fileExplorer) && (index == safeActiveIdx);
              return FileExplorerView(
                key: GlobalObjectKey(tab),
                focusNode: tab.focusNode,
                isActive: isTabActive,
                initialLeftTarget: tab.leftTarget,
                initialRightTarget: tab.rightTarget,
                initialActivePane: tab.initialActivePane,
                onTargetChanged: (newTarget) {
                  if (!mounted) return;
                  setState(() {
                    tab.rightTarget = newTarget;
                    tab.label = _formatExplorerTabLabel(newTarget);
                  });
                },
                onNewTab: _promptNewFileExplorerTab,
                onCloseTab: () => _closeFileExplorerTab(_activeFileExplorerTab),
                onSwitchTab: _switchFileExplorerTab,
                onExit: () {
                  final idx = _fileExplorerTabs.indexOf(tab);
                  if (_fileExplorerTabs.length > 1 && idx != -1) {
                    _closeFileExplorerTab(idx);
                  } else {
                    setState(() {
                      _selectedTab = AppTab.sessions;
                    });
                  }
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFileExplorerTabItem(
    _FileExplorerTab tab,
    int index,
    bool isActive,
  ) {
    final isRemote = !tab.rightTarget.isLocal;
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showFileExplorerTabContextMenu(details.globalPosition, tab);
      },
      child: InkWell(
        key: ValueKey('file_explorer_tab_${tab.id}'),
        onTap: () {
          setState(() {
            _activeFileExplorerTab = index;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusActiveFileExplorer();
          });
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.accentPrimary.withValues(alpha: 0.14)
                : Colors.transparent,
            border: Border(
              right: const BorderSide(color: AppTheme.borderSubtle),
              bottom: BorderSide(
                color: isActive ? AppTheme.accentPrimary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRemote ? Icons.cloud_outlined : Icons.computer_rounded,
                size: 13,
                color: isActive
                    ? (isRemote ? AppTheme.statusWarning : AppTheme.accentPrimary)
                    : AppTheme.textSecondary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Close Tab (Ctrl+W)',
                child: InkWell(
                  key: ValueKey('file_explorer_close_tab_${tab.id}'),
                  onTap: () => _closeFileExplorerTab(index),
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 13,
                      color: isActive
                          ? Colors.white70
                          : AppTheme.textSecondary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileExplorerAddTabButton() {
    return Tooltip(
      message: 'New File Explorer Tab (Ctrl+T)',
      child: InkWell(
        key: const ValueKey('file_explorer_new_tab_button'),
        onTap: _promptNewFileExplorerTab,
        child: Container(
          width: 34,
          height: 38,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: AppTheme.borderSubtle),
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.add,
            size: 16,
            color: AppTheme.accentPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildFileExplorerCloseAllButton() {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppTheme.borderSubtle),
        ),
      ),
      child: Tooltip(
        message: 'Close all File Explorer tabs',
        child: InkWell(
          key: const ValueKey('file_explorer_close_all_button'),
          onTap: _closeAllFileExplorerTabs,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.clear_all,
                  size: 15,
                  color: AppTheme.statusError.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 4),
                Text(
                  'Close All',
                  style: TextStyle(
                    color: AppTheme.statusError.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsScreen() {
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
          const Text(
            'Application & Terminal Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 16),
          _buildSettingsSection('Theme & Font'),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
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
              const SizedBox(
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
              const SizedBox(
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
                    child: const Icon(Icons.remove, size: 14, color: AppTheme.textSecondary),
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
                    child: const Icon(Icons.add, size: 14, color: AppTheme.textSecondary),
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
                    const Icon(Icons.terminal, size: 15, color: AppTheme.accentPrimary),
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSettingsSection('SSH Session Tab Beacon Indicator'),
          const SizedBox(height: 8),
          const Text(
            'Indikator denyut pada tab sesi SSH aktif (Nexus workspace) menandakan sesi terhubung dan terfokus.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
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
                      setState(() => settings.setNexusPulseStyle(val));
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
                      style: const TextStyle(
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
              const SizedBox(
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
                      setState(() => settings.setNexusPulseColor(val));
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
                            setState(() => settings.setNexusPulseColor(pc));
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
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.25),
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
            title: const Text('Show Sessions Manager dialog at startup', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
            value: settings.showSessionDialogAtStartup,
            onChanged: (val) {
              setState(() => settings.setShowSessionDialogAtStartup(val ?? true));
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 24),
          _buildSettingsSection('Keyboard Shortcuts & Assistance'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('View All Keyboard Shortcuts', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
            subtitle: const Text('See shortcuts for navigation, terminal workspace, sessions, and explorer', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            trailing: OutlinedButton.icon(
              icon: const Icon(Icons.keyboard_outlined, size: 14),
              label: const Text('View Shortcuts (F1)', style: TextStyle(fontSize: 11)),
              onPressed: _showKeyboardShortcutsDialog,
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
                    await _sessionManager.exportToFile(File(loc.path));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
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
                  side: const BorderSide(color: AppTheme.accentPrimary),
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
                    await _sessionManager.importFromFile(File(file.path));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
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
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accentPrimary),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
      ],
    );
  }
}

class _SettingsTopBarButton extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingsTopBarButton({
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SettingsTopBarButton> createState() => _SettingsTopBarButtonState();
}

class _SettingsTopBarButtonState extends State<_SettingsTopBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = _isHovered
        ? Colors.white
        : (widget.isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary);

    return Tooltip(
      message: 'Settings',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 30.0,
            height: 28.0,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppTheme.accentPrimary.withValues(alpha: 0.15)
                  : (_isHovered ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
              borderRadius: BorderRadius.circular(4),
              border: widget.isSelected
                  ? Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.4))
                  : null,
            ),
            child: Center(
              child: Icon(
                Icons.settings_outlined,
                size: 16.0,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyboardShortcutsTopBarButton extends StatefulWidget {
  final VoidCallback onTap;

  const _KeyboardShortcutsTopBarButton({
    required this.onTap,
  });

  @override
  State<_KeyboardShortcutsTopBarButton> createState() =>
      _KeyboardShortcutsTopBarButtonState();
}

class _KeyboardShortcutsTopBarButtonState
    extends State<_KeyboardShortcutsTopBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = _isHovered ? Colors.white : AppTheme.textSecondary;

    return Tooltip(
      message: 'Keyboard Shortcuts (F1 / Ctrl+/)',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 30.0,
            height: 28.0,
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(
                Icons.keyboard_outlined,
                size: 16.0,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileExplorerTab {
  final String id;
  String label;
  ExplorerNodeTarget leftTarget;
  ExplorerNodeTarget rightTarget;
  final PaneSide initialActivePane;
  final FocusNode focusNode = FocusNode();

  _FileExplorerTab({
    required this.id,
    required this.label,
    required this.leftTarget,
    required this.rightTarget,
    required this.initialActivePane,
  });

  void dispose() {
    focusNode.dispose();
  }
}
