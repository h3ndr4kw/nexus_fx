import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../models/file_explorer_models.dart';
import '../models/nexus_tool.dart';
import '../models/session_models.dart';
import '../services/app_log.dart';
import '../services/crypto_vault_service.dart';
import '../services/nexus_tool_registry.dart';
import '../services/session_manager_service.dart';
import '../services/settings_service.dart';
import '../services/transfer_manager.dart';
import '../services/transfer_notifier.dart';
import '../services/transfer_taskbar_progress.dart';
import '../services/window_state_service.dart';
import '../theme/app_theme.dart';
import '../widgets/command_palette.dart';
import '../widgets/file_explorer_dialogs.dart';
import '../widgets/file_explorer_view.dart';
import '../widgets/keyboard_shortcuts_dialog.dart';
import '../widgets/sidebar_icon.dart';
import '../widgets/transfer_status_bar.dart';
import '../widgets/window_caption_buttons.dart';
import '../widgets/window_drag_area.dart';
import '../controllers/file_explorer_tabs_controller.dart';
import '../controllers/session_fullscreen_controller.dart';
import 'nexus_screen.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';

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

class _MainScreenState extends State<MainScreen> with WindowListener {
  late final SessionManagerService _sessionManager;
  late final NexusToolRegistry _toolRegistry;
  AppTab _selectedTab = AppTab.nexus;
  AppTab _previousTab = AppTab.nexus;
  String? _selectedCustomToolId;
  String? _previousCustomToolId;
  bool _isSidebarVisible = true;
  bool _isSessionFullscreen = false;
  bool _isRightSidebarVisible = false;
  final GlobalKey<NexusScreenState> _nexusKey = GlobalKey<NexusScreenState>();
  final FocusNode _sidebarFocusNode = FocusNode();
  int _sidebarIndex = 0;
  bool _isCommandPaletteOpen = false;

  List<NexusTool> get _customTools => _toolRegistry.tools;
  final Map<String, Widget> _toolViewCache = {};
  bool get _isNexusActive => _selectedCustomToolId == null && _selectedTab == AppTab.nexus;
  bool get _isFileExplorerActive => _selectedCustomToolId == null && _selectedTab == AppTab.fileExplorer;

  // Sessions is no longer a sidebar item: it is reached through the Session
  // Manager dialog (top bar button / Alt+1 / startup).
  static const List<AppTab> _sidebarTabs = [
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

  final FileExplorerTabsController _explorerTabs = FileExplorerTabsController();
  final ScrollController _fileExplorerTabScrollController = ScrollController();

  void _onExplorerTabsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _explorerTabs.addListener(_onExplorerTabsChanged);
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
    windowManager.addListener(this);
    TransferManager.instance.addListener(_syncPreventCloseForTransfers);
    _taskbarProgress = TransferTaskbarProgress(TransferManager.instance);
    _transferNotifier = TransferNotifier(
      TransferManager.instance,
      isEnabled: () => SettingsService.instance.transferNotifications,
      appName: widget.appTitle,
    );

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
      _toolViewCache.clear();
      if (_selectedCustomToolId != null &&
          _toolRegistry.getToolById(_selectedCustomToolId!) == null) {
        _selectedCustomToolId = null;
        _selectedTab = AppTab.nexus;
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
        _selectTab(AppTab.nexus, 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.connectSessionProfile(profile, toRightPane: toRightPane);
        });
      },
      openSessionInFileExplorer: _openSessionInFileExplorer,
      navigateToTerminal: () => _selectTab(AppTab.nexus, 0),
      navigateToSessions: _openStartupSessionsDialog,
      navigateToFileExplorer: () => _selectTab(AppTab.fileExplorer, 1),
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
    windowManager.removeListener(this);
    TransferManager.instance.removeListener(_syncPreventCloseForTransfers);
    _taskbarProgress?.dispose();
    _transferNotifier?.dispose();
    _sidebarFocusNode.dispose();
    _fileExplorerTabScrollController.dispose();
    _explorerTabs.removeListener(_onExplorerTabsChanged);
    _explorerTabs.dispose();
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

    // Ctrl+Space: Quick Connect Sessions.
    // Skipped on File Explorer: there Ctrl+Space belongs to the view's own
    // node/local target picker, so let the event reach the focus tree.
    if (isCtrl && !isShift && !isAlt && isSpace && !_isFileExplorerActive) {
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
      _openStartupSessionsDialog();
      return true;
    }
    if (isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.digit2) {
      _selectTab(AppTab.nexus, 0);
      return true;
    }
    if (isAlt && !isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.digit3) {
      _selectTab(AppTab.fileExplorer, 1);
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
        _selectTab(AppTab.nexus, 0);
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
        _closeFileExplorerTab(_explorerTabs.activeIndex);
        return true;
      }
      if (isCtrl && !isAlt && event.logicalKey == LogicalKeyboardKey.tab) {
        _switchFileExplorerTab(isShift ? -1 : 1);
        return true;
      }
    }

    // Ctrl+Shift+Enter: fullscreen the active SSH session
    if (_isNexusActive &&
        isSessionFullscreenShortcut(event.logicalKey,
            ctrl: isCtrl, shift: isShift, alt: isAlt)) {
      _nexusKey.currentState?.toggleSessionFullscreen();
      return true;
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
        final next = isDown
            ? (_sidebarIndex + 1) % totalSidebarItems
            : (_sidebarIndex - 1 + totalSidebarItems) % totalSidebarItems;
        // Moving the selection opens the page right away; focus stays in the
        // sidebar so j/k / arrows can keep navigating.
        _activateSidebarIndex(next, moveFocusToContent: false);
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.keyL) {
        _activateSidebarIndex(_sidebarIndex);
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

  /// Opens the sidebar item at [index] (built-in tab or custom tool).
  void _activateSidebarIndex(int index, {bool moveFocusToContent = true}) {
    if (index < _sidebarTabs.length) {
      _selectTab(
        _sidebarTabs[index],
        index,
        moveFocusToContent: moveFocusToContent,
      );
    } else {
      final toolIdx = index - _sidebarTabs.length;
      if (toolIdx >= 0 && toolIdx < _customTools.length) {
        _selectCustomTool(_customTools[toolIdx], index);
      }
    }
  }

  void _exitSessionFullscreen() {
    if (_isSessionFullscreen) {
      _nexusKey.currentState?.exitSessionFullscreen();
    }
  }

  void _selectTab(AppTab tab, int index, {bool moveFocusToContent = true}) {
    if (tab != AppTab.nexus) _exitSessionFullscreen();
    setState(() {
      _selectedCustomToolId = null;
      _previousCustomToolId = null;
      _selectedTab = tab;
      _previousTab = tab;
      _sidebarIndex = index;
    });
    if (moveFocusToContent && tab == AppTab.fileExplorer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusActiveFileExplorer();
      });
    }
  }

  void _selectCustomTool(NexusTool tool, int sidebarIndex) {
    _exitSessionFullscreen();
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
    _exitSessionFullscreen();
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

  // Quit guard while file transfers are running

  bool _preventCloseForTransfers = false;
  TransferTaskbarProgress? _taskbarProgress;
  TransferNotifier? _transferNotifier;

  /// Intercepts the window close button only while transfers are active, so
  /// normal closing is unaffected.
  void _syncPreventCloseForTransfers() {
    final want = TransferManager.instance.hasActiveJobs;
    if (want == _preventCloseForTransfers) return;
    _preventCloseForTransfers = want;
    _setWindowPreventClose(want);
  }

  Future<void> _setWindowPreventClose(bool value) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    try {
      await windowManager.setPreventClose(value);
    } catch (e, st) {
      AppLog.warningUnlessPluginMissing('Window: set prevent-close', e, st);
      // Not available in tests / before window_manager is initialised.
    }
  }

  @override
  void onWindowClose() async {
    if (!_preventCloseForTransfers || !mounted) return;
    if (await _confirmQuitWithTransfers()) {
      TransferManager.instance.cancelAll();
      await _setWindowPreventClose(false);
      try {
        await windowManager.destroy();
      } catch (e, st) {
        AppLog.warningUnlessPluginMissing('Window: destroy', e, st);
      }
    }
  }

  Future<bool> _confirmQuitWithTransfers() async {
    final count = TransferManager.instance.activeJobs.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: const Text('File transfers still running'),
        content: Text(
          '$count file transfer(s) are still running. Quitting cancels them and '
          'may leave incomplete files at the destination.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            key: const ValueKey('quit_keep_transfers'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep running'),
          ),
          ElevatedButton(
            key: const ValueKey('quit_cancel_transfers'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel transfers & quit',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<void> _confirmAndExit() async {
    final activeTransfers = TransferManager.instance.activeJobs.length;
    final transferNote = activeTransfers > 0
        ? ' $activeTransfers file transfer(s) still running will be cancelled.'
        : '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: Text('Exit ${widget.appTitle}?'),
        content: Text(
          'Are you sure you want to exit ${widget.appTitle}? Any running terminal sessions will be terminated.$transferNote',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
          _selectTab(AppTab.nexus, 0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _nexusKey.currentState?.connectSessionProfile(item.session!);
          });
        }
        break;
      case CommandAction.openSessionsManager:
        _openStartupSessionsDialog();
        break;
      case CommandAction.toggleSplitView:
        _selectTab(AppTab.nexus, 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.toggleSplitView();
        });
        break;
      case CommandAction.toggleSessionFullscreen:
        _selectTab(AppTab.nexus, 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.toggleSessionFullscreen();
        });
        break;
      case CommandAction.toggleCommandPane:
        _selectTab(AppTab.nexus, 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.toggleCommandPane();
        });
        break;
      case CommandAction.toggleRunbookSidebar:
        _selectTab(AppTab.nexus, 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _nexusKey.currentState?.toggleRightSidebar();
        });
        break;
      case CommandAction.setTheme:
        if (item.appTheme != null) {
          SettingsService.instance.setAppTheme(item.appTheme!);
        }
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
    _exitSessionFullscreen();
    SessionsDialog.show(
      context,
      sessionManager: _sessionManager,
      initialShowAtStartup: SettingsService.instance.showSessionDialogAtStartup,
      onToggleShowAtStartup: (val) {
        SettingsService.instance.setShowSessionDialogAtStartup(val);
      },
      onConnectSessions: (sessions, {openInRightSplit = false}) {
        _selectTab(AppTab.nexus, 0);
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
    });
    _explorerTabs.open(target);

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
    if (_explorerTabs.length <= 1) return;
    _explorerTabs.switchBy(delta);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusActiveFileExplorer();
    });
  }

  void _focusActiveFileExplorer() {
    if (!mounted || _selectedTab != AppTab.fileExplorer) return;
    final node = _explorerTabs.activeTab.focusNode;
    if (node.canRequestFocus) {
      node.requestFocus();
    }
  }

  void _closeFileExplorerTab(int index) {
    if (index < 0 || index >= _explorerTabs.length) return;
    _explorerTabs.close(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusActiveFileExplorer();
    });
  }

  void _closeOtherFileExplorerTabs(FileExplorerTab keepTab) {
    _explorerTabs.closeOthers(keepTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusActiveFileExplorer();
    });
  }

  void _closeAllFileExplorerTabs() {
    _explorerTabs.closeAll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusActiveFileExplorer();
    });
  }

  Future<void> _showFileExplorerTabContextMenu(
    Offset globalPosition,
    FileExplorerTab tab,
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

    final canCloseOthers = _explorerTabs.length > 1;

    final selected = await showMenu<String>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: position,
      color: AppTheme.surfaceColor,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppTheme.inputBorderColor),
      ),
      items: [
        PopupMenuItem<String>(
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
        PopupMenuItem<String>(
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
        PopupMenuItem<String>(
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
        final idx = _explorerTabs.tabs.indexWhere((t) => t.id == tab.id);
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
    final fullscreen = _isSessionFullscreen;
    final isNexusWithRightSidebar =
        _isNexusActive && (_isRightSidebarVisible || fullscreen);

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
            if (!fullscreen) _buildTitleBar(),
            Expanded(
              child: Row(
                children: [
                  if (_isSidebarVisible && !fullscreen) ...[
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
            // Global, non-modal copy/move progress; visible on every page.
            const TransferStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 38,
      color: AppTheme.activePalette.background,
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        children: [
          // Drag-to-move area: icon, title and the empty space up to the
          // buttons, like a native caption bar.
          Expanded(
            child: WindowDragArea(
              child: SizedBox(
                height: 38,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 12),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, size: 18, color: AppTheme.accentPrimary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.appTitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Session Manager: opens the sessions dialog from any tab.
          _SessionManagerTopBarButton(
            onTap: _openStartupSessionsDialog,
          ),
          const SizedBox(width: 4),
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
                  _buildSidebarNavItem(AppTab.nexus, 'Nexus', Icons.terminal, 0, isCompact),
                  _buildSidebarNavItem(AppTab.fileExplorer, 'File Explorer', Icons.folder_open, 1, isCompact),
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

    final Widget itemContainer = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
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

    // Activate on pointer-down (desktop-style, feels instant) and skip the
    // slow Material ripple; selection feedback comes from the 120ms
    // AnimatedContainer above instead.
    return InkWell(
      onTapDown: (_) => onTap(),
      onTap: () {},
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: AppTheme.bgSurface.withValues(alpha: 0.4),
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
            _selectTab(AppTab.nexus, 0);
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
          onSessionFullscreenChanged: (active) {
            if (mounted && _isSessionFullscreen != active) {
              setState(() => _isSessionFullscreen = active);
            }
          },
        ),
        _buildFileExplorerPage(),
        SettingsScreen(
          sessionManager: _sessionManager,
          onShowKeyboardShortcuts: _showKeyboardShortcutsDialog,
          appTitle: widget.appTitle,
        ),
        for (final tool in tools) _cachedToolView(tool),
      ].map((page) => RepaintBoundary(child: page)).toList(),
    );
  }

  /// Returns the same widget instance for a tool across rebuilds so that
  /// sidebar navigation (which calls setState on this screen) does not force
  /// every tool view to rebuild. Invalidated in [_onToolsChanged].
  Widget _cachedToolView(NexusTool tool) {
    return _toolViewCache.putIfAbsent(
      tool.id,
      () => KeyedSubtree(
        key: ValueKey('nexus_custom_tool_${tool.id}'),
        child: Builder(
          builder: (ctx) => tool.buildView(ctx, _buildToolContext()),
        ),
      ),
    );
  }

  Widget _buildFileExplorerPage() {
    final safeActiveIdx = _explorerTabs.activeIndex.clamp(
      0,
      _explorerTabs.tabs.isNotEmpty ? _explorerTabs.length - 1 : 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceSecondary,
            border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: ListView.builder(
                  controller: _fileExplorerTabScrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: _explorerTabs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _explorerTabs.length) {
                      return _buildFileExplorerAddTabButton();
                    }
                    final tab = _explorerTabs.tabs[index];
                    final isActive = index == safeActiveIdx;
                    return _buildFileExplorerTabItem(tab, index, isActive);
                  },
                ),
              ),
              if (_explorerTabs.length > 1)
                _buildFileExplorerCloseAllButton(),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: safeActiveIdx,
            children: _explorerTabs.tabs.asMap().entries.map((entry) {
              final index = entry.key;
              final tab = entry.value;
              final isTabActive = (_selectedTab == AppTab.fileExplorer) && (index == safeActiveIdx);
              return FileExplorerView(
                key: GlobalObjectKey(tab),
                transferOwnerId: tab.id,
                focusNode: tab.focusNode,
                isActive: isTabActive,
                initialLeftTarget: tab.leftTarget,
                initialRightTarget: tab.rightTarget,
                initialActivePane: tab.initialActivePane,
                onTargetChanged: (newTarget) {
                  if (!mounted) return;
                  _explorerTabs.retarget(tab, right: newTarget);
                },
                onNewTab: _promptNewFileExplorerTab,
                onCloseTab: () => _closeFileExplorerTab(_explorerTabs.activeIndex),
                onSwitchTab: _switchFileExplorerTab,
                onExit: () {
                  final idx = _explorerTabs.tabs.indexOf(tab);
                  if (_explorerTabs.length > 1 && idx != -1) {
                    _closeFileExplorerTab(idx);
                  } else {
                    setState(() {
                      _selectedTab = AppTab.nexus;
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
    FileExplorerTab tab,
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
          _explorerTabs.activate(index);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusActiveFileExplorer();
          });
        },
        // Active tab: a rounded outlined pill; inactive tabs sit flat on the strip.
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.accentPrimary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? AppTheme.accentPrimary.withValues(alpha: 0.4)
                  : Colors.transparent,
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
                    fontSize: 12.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive ? AppTheme.ink : AppTheme.textSecondary,
                  ),
                ),
              ),
              _FileExplorerTabTransferBadge(tabId: tab.id),
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
                          ? AppTheme.ink.withValues(alpha: 0.7)
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
          alignment: Alignment.center,
          child: Icon(
            Icons.add,
            size: 18,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildFileExplorerCloseAllButton() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
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
        ? AppTheme.ink
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
                  : (_isHovered ? AppTheme.ink.withValues(alpha: 0.1) : Colors.transparent),
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

class _SessionManagerTopBarButton extends StatefulWidget {
  final VoidCallback onTap;

  const _SessionManagerTopBarButton({required this.onTap});

  @override
  State<_SessionManagerTopBarButton> createState() =>
      _SessionManagerTopBarButtonState();
}

class _SessionManagerTopBarButtonState extends State<_SessionManagerTopBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = _isHovered ? AppTheme.ink : AppTheme.textSecondary;

    return Tooltip(
      message: 'Session Manager',
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
                  ? AppTheme.ink.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(
                Icons.dns_outlined,
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
    final iconColor = _isHovered ? AppTheme.ink : AppTheme.textSecondary;

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
                  ? AppTheme.ink.withValues(alpha: 0.1)
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

/// Small indicator on an explorer tab while transfers it started are running:
/// a spinner, or an amber warning when one is waiting on a name conflict.
class _FileExplorerTabTransferBadge extends StatelessWidget {
  const _FileExplorerTabTransferBadge({required this.tabId});

  final String tabId;

  @override
  Widget build(BuildContext context) {
    final manager = TransferManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final jobs = manager.activeJobs.where((j) => j.owner == tabId).toList();
        if (jobs.isEmpty) return const SizedBox.shrink();
        final needsAttention = jobs.any((j) => j.needsAttention);
        final tooltip = needsAttention
            ? 'A transfer from this tab needs your decision (see transfer bar)'
            : '${jobs.length} transfer(s) running from this tab';
        return Padding(
          key: ValueKey('file_explorer_tab_transfer_badge_$tabId'),
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: tooltip,
            child: needsAttention
                ? Icon(Icons.warning_amber_rounded,
                    size: 13, color: AppTheme.statusWarning)
                : SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppTheme.adaptive(const Color(0xFF56B6C2)),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
