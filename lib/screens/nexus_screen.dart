import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/session_models.dart';
import '../theme/app_theme.dart';
import '../services/session_manager_service.dart';
import '../services/ssh_service.dart';
import '../services/settings_service.dart';
import '../widgets/ssh_tab_view.dart';
import '../widgets/command_palette.dart';
import '../widgets/interactive_runbook_sidebar.dart';
import '../controllers/terminal_tab_controller.dart';
import '../controllers/broadcast_coordinator.dart';
import '../widgets/floating_send_progress_dialog.dart';
import '../widgets/radar_pulse_indicator.dart';
import 'sessions_screen.dart';
import '../widgets/fuzzy_searchable_dropdown.dart';
import '../widgets/snippet_dialogs.dart';

export '../controllers/broadcast_coordinator.dart' show BroadcastTarget;
export '../widgets/radar_pulse_indicator.dart';

class SshConnectionConfig {
  final String host;
  final String label;
  final String? fallbackHost;
  final String? fallbackLabel;
  final String? targetUsername;
  final String? targetPassword;
  final String? jumpClusterHost;
  final String? jumpClusterFallback;
  final String? jumpClusterUsername;
  final String? jumpClusterPassword;
  final String? feHostname;
  final String? clusterName;
  final bool? isOam;

  const SshConnectionConfig({
    required this.host,
    required this.label,
    this.fallbackHost,
    this.fallbackLabel,
    this.targetUsername,
    this.targetPassword,
    this.jumpClusterHost,
    this.jumpClusterFallback,
    this.jumpClusterUsername,
    this.jumpClusterPassword,
    this.feHostname,
    this.clusterName,
    this.isOam,
  });
}

class NexusScreen extends StatefulWidget {
  final String? initialHost;
  final String? initialLabel;
  final ValueChanged<bool>? onRightSidebarChanged;

  const NexusScreen({
    super.key,
    this.initialHost,
    this.initialLabel,
    this.onRightSidebarChanged,
  });

  @override
  State<NexusScreen> createState() => NexusScreenState();
}

class NexusScreenState extends State<NexusScreen> {
  final SshService _sshService = SshService.instance;
  late final TerminalTabController _tabController = TerminalTabController();
  late final BroadcastCoordinator _broadcastCoordinator = BroadcastCoordinator();

  TerminalTabController get tabController => _tabController;
  BroadcastCoordinator get broadcastCoordinator => _broadcastCoordinator;

  final ScrollController _tabScrollController = ScrollController();
  final ScrollController _rightTabScrollController = ScrollController();
  bool _isDraggingTab = false;

  List<SshConnection> get _tabs => _tabController.tabs;
  List<SshConnection> get _rightTabs => _tabController.rightTabs;
  int get _activeTab => _tabController.activeTab;
  set _activeTab(int val) => _tabController.setActiveTab(val);
  int get _activeRightTab => _tabController.activeRightTab;
  set _activeRightTab(int val) => _tabController.setActiveRightTab(val);
  bool get _isSplitView => _tabController.isSplitView;
  set _isSplitView(bool val) => _tabController.setSplitView(val);
  bool get _lastActivePaneIsRight => _tabController.lastActivePaneIsRight;
  set _lastActivePaneIsRight(bool val) => _tabController.setLastActivePaneIsRight(val);

  BroadcastTarget get _broadcastTarget => _broadcastCoordinator.target;
  set _broadcastTarget(BroadcastTarget val) => _broadcastCoordinator.setTarget(val, leftTabs: _tabs, rightTabs: _rightTabs);
  Set<String> get _selectedConnectionIds => _broadcastCoordinator.selectedConnectionIds;
  bool get _isSendingCommands => _broadcastCoordinator.isSending;
  bool get _isParallelMode => _broadcastCoordinator.isParallelMode;
  List<String> get _commandHistory => _broadcastCoordinator.commandHistory;

  @visibleForTesting
  int get activeTabIndex => _tabController.activeTab;

  @visibleForTesting
  SshConnection? get activeConnection => _activeConnection;

  SshConnection? get _activeConnection {
    if (_isSplitView && _lastActivePaneIsRight) {
      if (_activeRightTab >= 0 && _activeRightTab < _rightTabs.length) {
        return _rightTabs[_activeRightTab];
      }
    }
    if (_activeTab >= 0 && _activeTab < _tabs.length) {
      return _tabs[_activeTab];
    }
    return null;
  }

  @visibleForTesting
  int get activeRightTabIndex => _tabController.activeRightTab;

  @visibleForTesting
  bool get lastActivePaneIsRight => _tabController.lastActivePaneIsRight;

  @visibleForTesting
  List<String> get tabLabels => _tabController.tabLabels;

  @visibleForTesting
  List<String> get rightTabLabels => _tabController.rightTabLabels;

  @visibleForTesting
  List<SshConnection> get tabs => _tabController.tabs;

  @visibleForTesting
  List<SshConnection> get rightTabs => _tabController.rightTabs;

  bool _showCommandPane = false;
  bool _isRightSidebarVisible = false;
  final GlobalKey<InteractiveRunbookSidebarState> _sidebarKey =
      GlobalKey<InteractiveRunbookSidebarState>();
  final TextEditingController _commandInputController = TextEditingController();
  final FocusNode _commandFocusNode = FocusNode();

  bool _isRunbookSending = false;
  bool _isRunbookCancelled = false;
  bool _isRunbookCompleted = false;
  String? _runbookErrorMessage;
  String _runbookTargetNode = '';
  int _runbookCurrentLineIndex = 0;
  int _runbookTotalLines = 0;
  String _runbookCurrentCommand = '';

  bool get isRightSidebarVisible => _isRightSidebarVisible;

  void toggleRightSidebar() {
    setState(() {
      _isRightSidebarVisible = !_isRightSidebarVisible;
    });
    if (!_isRightSidebarVisible) {
      _focusActiveTerminal();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isRightSidebarVisible) {
          _sidebarKey.currentState?.focusSidebar();
        }
      });
    }
    widget.onRightSidebarChanged?.call(_isRightSidebarVisible);
  }

  void _addTab(SshConnection conn, {bool isRightPane = false}) {
    conn.onClosed = () {
      if (mounted) {
        if (SettingsService.instance.nexusAutoCloseTabOnDisconnect) {
          _closeTabForConnection(conn.id);
        }
      }
    };
    setState(() {
      _tabController.addTab(conn, isRightPane: isRightPane);
      _broadcastCoordinator.handleNewConnection(conn, isRightPane: isRightPane);
    });
  }

  void _addTabToRight(SshConnection conn) => _addTab(conn, isRightPane: true);

  @visibleForTesting
  void addConnectionForTesting(SshConnection conn, {bool isRightPane = false}) =>
      _addTab(conn, isRightPane: isRightPane);

  Future<void> connectSessionProfile(SessionProfile profile, {bool toRightPane = false}) async {
    final route = SessionManagerService.instance.resolveSshRoute(profile);
    final conn = SshConnection.fromSessionProfile(profile, route: route);
    if (toRightPane) {
      if (!_isSplitView) {
        setState(() => _isSplitView = true);
      }
      _addTabToRight(conn);
    } else {
      _addTab(conn);
    }
    await conn.connect();
  }

  void _openSessionsDialog() {
    SessionsDialog.show(
      context,
      onConnectSessions: (sessions, {openInRightSplit = false}) {
        for (final s in sessions) {
          connectSessionProfile(s, toRightPane: openInRightSplit);
        }
      },
      onOpenInFileExplorer: (_) {},
    );
  }

  @visibleForTesting
  List<String> get commandHistory => _broadcastCoordinator.commandHistory;

  @visibleForTesting
  BroadcastTarget get broadcastTarget => _broadcastCoordinator.target;

  @visibleForTesting
  Set<String> get selectedConnectionIds => _broadcastCoordinator.selectedConnectionIds;

  @visibleForTesting
  void setBroadcastTargetForTesting(BroadcastTarget target) {
    setState(() {
      _broadcastCoordinator.setTarget(
        target,
        leftTabs: _tabs,
        rightTabs: _rightTabs,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_onControllersChanged);
    _broadcastCoordinator.addListener(_onControllersChanged);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _commandFocusNode.onKeyEvent = _handleCommandInputKey;
    if (widget.initialHost != null) {
      _openSshTab(widget.initialHost!, widget.initialLabel ?? widget.initialHost!);
    }
  }

  void _onControllersChanged() {
    if (mounted) setState(() {});
  }

  void toggleCommandPane() {
    setState(() {
      _showCommandPane = !_showCommandPane;
      if (_showCommandPane) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _commandFocusNode.requestFocus();
        });
      } else {
        _commandFocusNode.unfocus();
      }
    });
  }

  void showCommandPane() {
    if (!_showCommandPane) {
      setState(() {
        _showCommandPane = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _commandFocusNode.requestFocus();
        });
      });
    } else {
      _commandFocusNode.requestFocus();
    }
  }

  void hideCommandPane() {
    if (_showCommandPane) {
      setState(() {
        _showCommandPane = false;
        _commandFocusNode.unfocus();
      });
    }
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final route = ModalRoute.of(context);
    final isCurrentRoute = route == null || route.isCurrent;
    if (!isCurrentRoute) return false;

    if (!TickerMode.valuesOf(context).enabled) return false;

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

    if (widget.onRightSidebarChanged == null && isCtrl && isShift && isSpace) {
      toggleCommandPane();
      return true;
    }

    if (isCtrl &&
        isShift &&
        event.logicalKey == LogicalKeyboardKey.keyB &&
        widget.onRightSidebarChanged == null) {
      toggleRightSidebar();
      return true;
    }

    // Switch pane shortcuts between terminal and sidebar:
    // Alt+L -> Focus sidebar (and open it if hidden)
    final isL = event.logicalKey == LogicalKeyboardKey.keyL ||
        event.physicalKey == PhysicalKeyboardKey.keyL;
    if (isAlt && !isCtrl && !isShift && isL) {
      if (!_isRightSidebarVisible) {
        toggleRightSidebar();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _sidebarKey.currentState?.focusSidebar();
          }
        });
      } else {
        _sidebarKey.currentState?.focusSidebar();
      }
      return true;
    }

    // Alt+H -> Focus active terminal
    final isH = event.logicalKey == LogicalKeyboardKey.keyH ||
        event.physicalKey == PhysicalKeyboardKey.keyH;
    if (isAlt && !isCtrl && !isShift && isH) {
      _focusActiveTerminal();
      return true;
    }

    // Resize Right Sidebar shortcuts:
    // Alt+Shift+Left / Alt+Shift+H -> Enlarge right sidebar (drag divider to the left)
    // Alt+Shift+Right / Alt+Shift+L -> Shrink right sidebar (drag divider to the right)
    final isArrowLeft = event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.physicalKey == PhysicalKeyboardKey.arrowLeft;
    final isArrowRight = event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.physicalKey == PhysicalKeyboardKey.arrowRight;
    final isLeft = isArrowLeft || isH;
    final isRight = isArrowRight || isL;
    if (isAlt && isShift && !isCtrl && (isLeft || isRight)) {
      if (_isRightSidebarVisible) {
        const double resizeStep = 40.0;
        final currentWidth = SettingsService.instance.rightSidebarWidth;
        final newWidth = isLeft
            ? (currentWidth + resizeStep).clamp(320.0, 1200.0)
            : (currentWidth - resizeStep).clamp(320.0, 1200.0);
        SettingsService.instance.setRightSidebarWidth(newWidth, persist: true);
        return true;
      }
    }

    // Reset Right Sidebar Width:
    // Alt+= -> Reset to default width (440.0)
    final isEqual = event.logicalKey == LogicalKeyboardKey.equal ||
        event.physicalKey == PhysicalKeyboardKey.equal;
    if (isAlt && !isCtrl && !isShift && isEqual) {
      if (_isRightSidebarVisible) {
        SettingsService.instance.setRightSidebarWidth(440.0, persist: true);
        return true;
      }
    }

    // Tab Navigation Shortcuts
    final isSidebarActive = _isRightSidebarVisible && (_sidebarKey.currentState?.isFocused ?? false);
    final isTab = event.logicalKey == LogicalKeyboardKey.tab ||
        event.physicalKey == PhysicalKeyboardKey.tab;
    final isT = event.logicalKey == LogicalKeyboardKey.keyT ||
        event.physicalKey == PhysicalKeyboardKey.keyT;
    final isW = event.logicalKey == LogicalKeyboardKey.keyW ||
        event.physicalKey == PhysicalKeyboardKey.keyW;

    // If sidebar is active, let sidebar handle Tab switching, W (close tab), etc.
    if (isSidebarActive && isCtrl && (isTab || isT || isW || event.logicalKey == LogicalKeyboardKey.pageDown || event.logicalKey == LogicalKeyboardKey.pageUp)) {
      return false;
    }

    // 1. Next Tab: Ctrl + Tab OR Ctrl + T OR Ctrl + PageDown

    if (isCtrl && !isAlt && !isShift &&
        (isTab || isT || event.logicalKey == LogicalKeyboardKey.pageDown)) {
      _selectNextTab();
      return true;
    }

    // 2. Previous Tab: Ctrl + Shift + Tab OR Ctrl + Shift + T OR Ctrl + PageUp
    if (isCtrl && !isAlt && isShift && (isTab || isT)) {
      _selectPreviousTab();
      return true;
    }
    if (isCtrl && !isAlt && event.logicalKey == LogicalKeyboardKey.pageUp) {
      _selectPreviousTab();
      return true;
    }

    // 3. Close Active Tab: Ctrl + W
    if (isCtrl && !isAlt && !isShift && isW) {
      _closeActiveTab();
      return true;
    }

    // 4. Jump to Tab: Alt + 1..9
    if (isAlt && !isCtrl) {
      final digitIndex = _getDigitIndex(event.logicalKey);
      if (digitIndex != null) {
        _selectTabAtIndex(digitIndex);
        return true;
      }
    }

    return false;
  }

  void selectNextTab({bool? isRightPane}) => _selectNextTab(isRightPane: isRightPane);
  void selectPreviousTab({bool? isRightPane}) => _selectPreviousTab(isRightPane: isRightPane);
  void selectTabAtIndex(int targetIndex, {bool? isRightPane}) =>
      _selectTabAtIndex(targetIndex, isRightPane: isRightPane);
  void closeActiveTab({bool? isRightPane}) => _closeActiveTab(isRightPane: isRightPane);

  void _focusActiveTerminal() {
    _sidebarKey.currentState?.unfocusSidebar();
    void doFocus() {
      if (!mounted) return;
      final targetConn = _isSplitView && _lastActivePaneIsRight && _rightTabs.isNotEmpty
          ? (_activeRightTab >= 0 && _activeRightTab < _rightTabs.length ? _rightTabs[_activeRightTab] : null)
          : (_tabs.isNotEmpty && _activeTab >= 0 && _activeTab < _tabs.length ? _tabs[_activeTab] : null);
      if (targetConn != null) {
        final state = GlobalObjectKey(targetConn).currentState;
        if (state is SshTabViewState) {
          state.requestFocus();
        }
      }
    }

    doFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => doFocus());
  }

  void _selectNextTab({bool? isRightPane}) {
    final useRight = isRightPane ?? (_isSplitView && _lastActivePaneIsRight && _rightTabs.isNotEmpty);
    final targetList = useRight ? _rightTabs : _tabs;
    if (targetList.isEmpty) return;

    setState(() {
      if (useRight) {
        _activeRightTab = (_activeRightTab + 1) % targetList.length;
      } else {
        _activeTab = (_activeTab + 1) % targetList.length;
      }
    });
    _focusActiveTerminal();
  }

  void _selectPreviousTab({bool? isRightPane}) {
    final useRight = isRightPane ?? (_isSplitView && _lastActivePaneIsRight && _rightTabs.isNotEmpty);
    final targetList = useRight ? _rightTabs : _tabs;
    if (targetList.isEmpty) return;

    setState(() {
      if (useRight) {
        _activeRightTab = (_activeRightTab - 1 + targetList.length) % targetList.length;
      } else {
        _activeTab = (_activeTab - 1 + targetList.length) % targetList.length;
      }
    });
    _focusActiveTerminal();
  }

  void _selectTabAtIndex(int targetIndex, {bool? isRightPane}) {
    final useRight = isRightPane ?? (_isSplitView && _lastActivePaneIsRight && _rightTabs.isNotEmpty);
    final targetList = useRight ? _rightTabs : _tabs;
    if (targetList.isEmpty) return;

    if (targetIndex >= 0 && targetIndex < targetList.length) {
      setState(() {
        if (useRight) {
          _activeRightTab = targetIndex;
        } else {
          _activeTab = targetIndex;
        }
      });
      _focusActiveTerminal();
    }
  }

  void _closeActiveTab({bool? isRightPane}) {
    final useRight = isRightPane ?? (_isSplitView && _lastActivePaneIsRight && _rightTabs.isNotEmpty);
    if (useRight) {
      if (_activeRightTab >= 0 && _activeRightTab < _rightTabs.length) {
        _closeTab(_activeRightTab, isRightPane: true);
      }
    } else {
      if (_activeTab >= 0 && _activeTab < _tabs.length) {
        _closeTab(_activeTab, isRightPane: false);
      } else if (_rightTabs.isNotEmpty && _activeRightTab >= 0 && _activeRightTab < _rightTabs.length) {
        _closeTab(_activeRightTab, isRightPane: true);
      }
    }
  }

  int? _getDigitIndex(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) return 0;
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) return 1;
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) return 2;
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) return 3;
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) return 4;
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) return 5;
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) return 6;
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) return 7;
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) return 8;
    return null;
  }

  List<SshConnection> openMultipleSshConnections(List<SshConnectionConfig> configs, {bool? isRightPane}) {
    if (configs.isEmpty) return [];
    final isTargetRight = isRightPane ?? _isSplitView;
    final targetList = isTargetRight ? _rightTabs : _tabs;
    final initialTabCount = targetList.length;
    final newConnections = <SshConnection>[];

    for (final cfg in configs) {
      final conn = _sshService.createConnection(
        host: cfg.host,
        label: cfg.label,
        fallbackHost: cfg.fallbackHost,
        fallbackLabel: cfg.fallbackLabel,
        targetUsername: cfg.targetUsername,
        targetPassword: cfg.targetPassword,
        jumpClusterHost: cfg.jumpClusterHost,
        jumpClusterFallback: cfg.jumpClusterFallback,
        jumpClusterUsername: cfg.jumpClusterUsername,
        jumpClusterPassword: cfg.jumpClusterPassword,
        feHostname: cfg.feHostname,
        clusterName: cfg.clusterName,
        isOam: cfg.isOam,
      );

      conn.onClosed = () {
        if (mounted) {
          if (SettingsService.instance.nexusAutoCloseTabOnDisconnect) {
            _closeTabForConnection(conn.id);
          }
        }
      };
      newConnections.add(conn);
    }

    setState(() {
      targetList.addAll(newConnections);
      if (isTargetRight) {
        _activeRightTab = initialTabCount;
      } else {
        _activeTab = initialTabCount;
      }
      if (_broadcastTarget == BroadcastTarget.all ||
          (_broadcastTarget == BroadcastTarget.left && !isTargetRight) ||
          (_broadcastTarget == BroadcastTarget.right && isTargetRight)) {
        _selectedConnectionIds.addAll(newConnections.map((c) => c.id));
      }
    });
    return newConnections;
  }

  SshConnection openSshConnection(
    String host,
    String label, {
    String? fallbackHost,
    String? fallbackLabel,
    String? targetUsername,
    String? targetPassword,
    String? jumpClusterHost,
    String? jumpClusterFallback,
    String? jumpClusterUsername,
    String? jumpClusterPassword,
    String? feHostname,
    String? clusterName,
    bool? isOam,
    bool? isRightPane,
  }) {
    return _openSshTab(
      host,
      label,
      fallbackHost: fallbackHost,
      fallbackLabel: fallbackLabel,
      targetUsername: targetUsername,
      targetPassword: targetPassword,
      jumpClusterHost: jumpClusterHost,
      jumpClusterFallback: jumpClusterFallback,
      jumpClusterUsername: jumpClusterUsername,
      jumpClusterPassword: jumpClusterPassword,
      feHostname: feHostname,
      clusterName: clusterName,
      isOam: isOam,
      isRightPane: isRightPane,
    );
  }

  SshConnection _openSshTab(
    String host,
    String label, {
    String? fallbackHost,
    String? fallbackLabel,
    String? targetUsername,
    String? targetPassword,
    String? jumpClusterHost,
    String? jumpClusterFallback,
    String? jumpClusterUsername,
    String? jumpClusterPassword,
    String? feHostname,
    String? clusterName,
    bool? isOam,
    bool? isRightPane,
  }) {
    final conn = _sshService.createConnection(
      host: host,
      label: label,
      fallbackHost: fallbackHost,
      fallbackLabel: fallbackLabel,
      targetUsername: targetUsername,
      targetPassword: targetPassword,
      jumpClusterHost: jumpClusterHost,
      jumpClusterFallback: jumpClusterFallback,
      jumpClusterUsername: jumpClusterUsername,
      jumpClusterPassword: jumpClusterPassword,
      feHostname: feHostname,
      clusterName: clusterName,
      isOam: isOam,
    );

    conn.onClosed = () {
      if (mounted) {
        if (SettingsService.instance.nexusAutoCloseTabOnDisconnect) {
          _closeTabForConnection(conn.id);
        }
      }
    };

    final isTargetRight = isRightPane ?? _isSplitView;
    _addTab(conn, isRightPane: isTargetRight);
    return conn;
  }

  void _closeTabForConnection(String id) {
    final leftIndex = _tabs.indexWhere((c) => c.id == id);
    if (leftIndex != -1) {
      _closeTab(leftIndex, isRightPane: false);
      return;
    }
    final rightIndex = _rightTabs.indexWhere((c) => c.id == id);
    if (rightIndex != -1) {
      _closeTab(rightIndex, isRightPane: true);
    }
  }

  void _closeTab(int index, {bool isRightPane = false}) {
    final targetList = isRightPane ? _rightTabs : _tabs;
    if (index < 0 || index >= targetList.length) return;
    final conn = targetList[index];
    _sshService.removeConnection(conn.id, graceful: true);

    setState(() {
      _tabController.closeTabAt(index, isRightPane: isRightPane);
      _broadcastCoordinator.removeConnection(conn.id);
      _updateBroadcastTargetFromSelection();

      if (_tabs.isEmpty && _rightTabs.isEmpty) {
        _isSplitView = false;
        _showCommandPane = false;
      }
    });
    _focusActiveTerminal();
  }

  void _closeAllTabs() {
    for (final conn in List.of(_tabs)) {
      _sshService.removeConnection(conn.id, graceful: true);
    }
    for (final conn in List.of(_rightTabs)) {
      _sshService.removeConnection(conn.id, graceful: true);
    }
    setState(() {
      _tabController.closeAllTabs();
      _broadcastCoordinator.clearSelection();
      _broadcastCoordinator.setTarget(BroadcastTarget.all, leftTabs: [], rightTabs: []);
      _showCommandPane = false;
    });
  }

  void _closeOtherTabs(SshConnection keepConn, {bool isRightPane = false}) {
    final targetList = isRightPane ? _rightTabs : _tabs;
    for (final conn in List.of(targetList)) {
      if (conn.id != keepConn.id) {
        conn.onClosed = null;
        _sshService.removeConnection(conn.id, graceful: true);
      }
    }
    setState(() {
      targetList.removeWhere((c) => c.id != keepConn.id);
      if (isRightPane) {
        _activeRightTab = 0;
      } else {
        _activeTab = 0;
      }
    });
  }

  void toggleSplitView() => _toggleSplitView();

  void _toggleSplitView() {
    setState(() {
      if (_isSplitView) {
        // Merge right pane tabs into left pane tabs
        _tabs.addAll(_rightTabs);
        _rightTabs.clear();
        _isSplitView = false;
        _lastActivePaneIsRight = false;
        _broadcastTarget = BroadcastTarget.all;
      } else {
        _isSplitView = true;
      }
    });
  }

  void _moveTabToRightPane(SshConnection conn) {
    final index = _tabs.indexWhere((c) => c.id == conn.id);
    if (index == -1) return;
    setState(() {
      _tabController.moveTabBetweenPanes(index, fromRightPane: false);
    });
  }

  void _moveTabToLeftPane(SshConnection conn) {
    final index = _rightTabs.indexWhere((c) => c.id == conn.id);
    if (index == -1) return;
    setState(() {
      _tabController.moveTabBetweenPanes(index, fromRightPane: true);
      if (_rightTabs.isEmpty) {
        _broadcastCoordinator.setTarget(BroadcastTarget.all, leftTabs: _tabs, rightTabs: _rightTabs);
      }
    });
  }


  Future<void> _confirmAndCloseAll() async {
    final totalCount = _tabs.length + _rightTabs.length;
    if (totalCount == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppTheme.inputBorderColor),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 20),
            SizedBox(width: 8),
            Text(
              'Close All Tabs',
              style: TextStyle(
                color: AppTheme.titleColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to close all $totalCount active SSH connections?',
          style: const TextStyle(
            color: AppTheme.textColor,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Close All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _closeAllTabs();
    }
  }

  void _showTabContextMenu(Offset globalPosition, SshConnection conn, {bool isRightPane = false}) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final overlayRect = overlay != null
        ? Offset.zero & overlay.size
        : Offset.zero & MediaQuery.of(context).size;

    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      overlayRect,
    );

    final targetList = isRightPane ? _rightTabs : _tabs;
    final canCloseOthers = targetList.length > 1;

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
          value: 'close',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.close, size: 14, color: AppTheme.textColor),
              SizedBox(width: 8),
              Text('Close Tab', style: TextStyle(fontSize: 12, color: AppTheme.textColor)),
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
                color: canCloseOthers ? AppTheme.textColor : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                'Close Other Tabs',
                style: TextStyle(
                  fontSize: 12,
                  color: canCloseOthers ? AppTheme.textColor : Colors.grey,
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
              Icon(Icons.clear_all, size: 14, color: AppTheme.errorColor),
              SizedBox(width: 8),
              Text('Close All Tabs', style: TextStyle(fontSize: 12, color: AppTheme.errorColor)),
            ],
          ),
        ),
        if (conn.logFile != null) ...[
          const PopupMenuDivider(height: 1),
          const PopupMenuItem<String>(
            value: 'copy_log_path',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 14, color: AppTheme.accentPrimary),
                SizedBox(width: 8),
                Text('Copy Session Log Path', style: TextStyle(fontSize: 12, color: AppTheme.textColor)),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          enabled: false,
          height: 26,
          child: Text(
            'ACTIVE PULSE STYLE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Colors.grey,
            ),
          ),
        ),
        for (final style in NexusPulseStyle.values)
          PopupMenuItem<String>(
            value: 'pulse_style_${style.name}',
            height: 32,
            child: Row(
              children: [
                Icon(
                  SettingsService.instance.nexusPulseStyle == style
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 13,
                  color: SettingsService.instance.nexusPulseStyle == style
                      ? AppTheme.activePalette.primaryColor
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  style.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: SettingsService.instance.nexusPulseStyle == style
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: SettingsService.instance.nexusPulseStyle == style
                        ? AppTheme.textColor
                        : AppTheme.textColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          enabled: false,
          height: 26,
          child: Text(
            'ACTIVE PULSE COLOR',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Colors.grey,
            ),
          ),
        ),
        for (final pColor in NexusPulseColor.values)
          PopupMenuItem<String>(
            value: 'pulse_color_${pColor.name}',
            height: 32,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: pColor.primary,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    pColor.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: SettingsService.instance.nexusPulseColor == pColor
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: SettingsService.instance.nexusPulseColor == pColor
                          ? AppTheme.textColor
                          : AppTheme.textColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                if (SettingsService.instance.nexusPulseColor == pColor)
                  Icon(
                    Icons.check,
                    size: 13,
                    color: AppTheme.activePalette.primaryColor,
                  ),
              ],
            ),
          ),
      ],
    );

    if (!mounted || selected == null) return;

    if (selected.startsWith('pulse_style_')) {
      final styleName = selected.substring('pulse_style_'.length);
      final style = NexusPulseStyle.values.firstWhere(
        (s) => s.name == styleName,
        orElse: () => NexusPulseStyle.neonSonarWave,
      );
      await SettingsService.instance.setNexusPulseStyle(style);
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (selected.startsWith('pulse_color_')) {
      final colorName = selected.substring('pulse_color_'.length);
      final pColor = NexusPulseColor.values.firstWhere(
        (c) => c.name == colorName,
        orElse: () => NexusPulseColor.emerald,
      );
      await SettingsService.instance.setNexusPulseColor(pColor);
      if (mounted) {
        setState(() {});
      }
      return;
    }

    switch (selected) {
      case 'close':
        _closeTabForConnection(conn.id);
        break;
      case 'close_others':
        _closeOtherTabs(conn, isRightPane: isRightPane);
        break;
      case 'close_all':
        _confirmAndCloseAll();
        break;
      case 'copy_log_path':
        final logFile = conn.logFile;
        if (logFile != null) {
          await Clipboard.setData(ClipboardData(text: logFile.path));
          if (Platform.isWindows && logFile.existsSync()) {
            Process.run('explorer.exe', ['/select,', logFile.path]);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Log path copied & opened: ${logFile.path}'),
                backgroundColor: AppTheme.successColor,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        break;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _tabController.removeListener(_onControllersChanged);
    _broadcastCoordinator.removeListener(_onControllersChanged);
    _tabScrollController.dispose();
    _rightTabScrollController.dispose();
    _commandInputController.dispose();
    _commandFocusNode.dispose();
    _tabController.dispose();
    _broadcastCoordinator.dispose();
    super.dispose();
  }

  Widget _buildCommandPaneToggleButton() {
    final palette = AppTheme.activePalette;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.inputBorderColor),
        ),
      ),
      child: Tooltip(
        message: _showCommandPane ? 'Hide command pane (Ctrl+Shift+Space)' : 'Show command pane (Ctrl+Shift+Space)',
        child: InkWell(
          key: const ValueKey('nexus_command_pane_toggle_button'),
          onTap: toggleCommandPane,
          child: Container(
            color: _showCommandPane
                ? palette.primaryColor.withValues(alpha: 0.15)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Icon(
              Icons.terminal,
              size: 16,
              color: _showCommandPane
                  ? palette.primaryColor
                  : palette.textColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleCommandInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isControl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
    final isShift = HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
    final isSpace = event.logicalKey == LogicalKeyboardKey.space ||
        event.physicalKey == PhysicalKeyboardKey.space;

    if (isControl && isShift && isSpace) {
      return KeyEventResult.handled;
    }

    if (isControl && !isShift && event.logicalKey == LogicalKeyboardKey.keyK) {
      _openSnippetPicker();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (isShift) {
        // Shift+Enter allows newline insertion in multiline TextField
        return KeyEventResult.ignored;
      } else {
        // Enter sends command
        if (!_isSendingCommands) {
          _sendBroadcastCommand();
        }
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      final isControl = HardwareKeyboard.instance.isControlPressed;
      final isAlt = HardwareKeyboard.instance.isAltPressed;
      final isMeta = HardwareKeyboard.instance.isMetaPressed;
      if (!isShift && !isControl && !isAlt && !isMeta) {
        if (_navigateCommandHistory(up: true)) {
          return KeyEventResult.handled;
        }
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      final isControl = HardwareKeyboard.instance.isControlPressed;
      final isAlt = HardwareKeyboard.instance.isAltPressed;
      final isMeta = HardwareKeyboard.instance.isMetaPressed;
      if (!isShift && !isControl && !isAlt && !isMeta) {
        if (_navigateCommandHistory(up: false)) {
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  bool _navigateCommandHistory({required bool up}) {
    if (_commandHistory.isEmpty) return false;

    final text = _commandInputController.text;
    final selection = _commandInputController.selection;

    if (up) {
      if (text.contains('\n') && selection.baseOffset > text.indexOf('\n')) {
        return false;
      }

      final cmd = _broadcastCoordinator.navigateHistoryUp(text);
      if (cmd != null) {
        _commandInputController.value = TextEditingValue(
          text: cmd,
          selection: TextSelection.collapsed(offset: cmd.length),
        );
        return true;
      }
      return false;
    } else {
      if (text.contains('\n') && selection.baseOffset <= text.lastIndexOf('\n')) {
        return false;
      }

      final cmd = _broadcastCoordinator.navigateHistoryDown();
      if (cmd != null) {
        _commandInputController.value = TextEditingValue(
          text: cmd,
          selection: TextSelection.collapsed(offset: cmd.length),
        );
        return true;
      }
      return false;
    }
  }

  String _shortcutLabel(String key) => Platform.isMacOS ? '⌘$key' : 'Ctrl+$key';

  void _toggleConnectionSelection(String id) {
    setState(() {
      _broadcastCoordinator.toggleSelection(id);
      _broadcastCoordinator.updateBroadcastTargetFromSelection(
        leftTabs: _tabs,
        rightTabs: _rightTabs,
      );
    });
  }

  void _updateBroadcastTargetFromSelection() {
    _broadcastCoordinator.updateBroadcastTargetFromSelection(
      leftTabs: _tabs,
      rightTabs: _rightTabs,
    );
  }


  Future<void> _sendBroadcastCommand() async {
    final rawText = _commandInputController.text;

    final targetConnections = _broadcastCoordinator.resolveTargetConnections(
      leftTabs: _tabs,
      rightTabs: _rightTabs,
      isSplitView: _isSplitView,
    );

    if (targetConnections.isEmpty) {
      final targetName = _broadcastTarget == BroadcastTarget.left
          ? 'left pane'
          : (_broadcastTarget == BroadcastTarget.right
              ? 'right pane'
              : (_broadcastTarget == BroadcastTarget.custom
                  ? 'selected targets'
                  : 'active'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('No connected SSH sessions in $targetName to send command.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (rawText.trim().isEmpty) return;

    final dangerous = _findDestructiveLines(rawText);
    if (dangerous.isNotEmpty) {
      final confirmed = await _confirmDestructiveCommand(
        lines: dangerous,
        nodeCount: targetConnections.length,
      );
      if (confirmed != true || !mounted) return;
    }

    await _broadcastCoordinator.executeBroadcast(
      targetConnections: targetConnections,
      rawText: rawText,
    );

    if (mounted) {
      _commandInputController.clear();
    }
  }


  // --- Destructive Command Guardrails ---
  static final List<RegExp> _destructivePatterns = [
    RegExp(r'\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*)'),
    RegExp(r'\b(reboot|shutdown|poweroff|halt)\b'),
    RegExp(r'\binit\s+[06]\b'),
    RegExp(r'\bmkfs(\.\w+)?\b'),
    RegExp(r'\bdd\s+.*\bof=/dev/'),
    RegExp(r'\bsystemctl\s+(stop|disable|mask|poweroff|reboot)\b'),
    RegExp(r'\bkillall\b|\bpkill\b|\bkill\s+-9\b'),
    RegExp(r'>\s*/dev/sd'),
    RegExp(r':\(\)\s*\{'),
  ];

  List<String> _findDestructiveLines(String rawText) {
    return rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where((l) => _destructivePatterns.any((p) => p.hasMatch(l)))
        .toList();
  }

  Future<bool?> _confirmDestructiveCommand({
    required List<String> lines,
    required int nodeCount,
  }) {
    final palette = AppTheme.activePalette;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surfaceColor,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Run potentially destructive command?',
                style: TextStyle(color: palette.textColor, fontSize: 15),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following line(s) match destructive patterns and will be executed on $nodeCount node${nodeCount == 1 ? '' : 's'}:',
              style: TextStyle(
                color: palette.textColor.withValues(alpha: 0.8),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines
                    .map((l) => Text(
                          l,
                          style: const TextStyle(
                            fontFamily: 'Courier New',
                            fontSize: 12,
                            color: Colors.amber,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Proceed & Execute'),
          ),
        ],
      ),
    );
  }

  // --- Snippets & History Actions ---
  Future<void> _openSnippetPicker() async {
    final selected = await SnippetPickerModal.show(context);
    if (selected != null && mounted) {
      _commandInputController.value = TextEditingValue(
        text: selected.fullScript,
        selection: TextSelection.collapsed(offset: selected.fullScript.length),
      );
      _commandFocusNode.requestFocus();
    }
  }

  Widget _buildSnippetsButton() {
    final palette = AppTheme.activePalette;
    return Tooltip(
      message: 'Snippets (${_shortcutLabel('K')})',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openSnippetPicker,
          borderRadius: BorderRadius.circular(6),
          hoverColor: palette.primaryColor.withValues(alpha: 0.12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
            decoration: BoxDecoration(
              color: palette.background.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.inputBorderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 13,
                  color: palette.textColor.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryButton() {
    final palette = AppTheme.activePalette;
    return PopupMenuButton<String>(
      tooltip: 'Command History',
      color: palette.surfaceColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.inputBorderColor),
      ),
      padding: EdgeInsets.zero,
      onSelected: (cmd) {
        _commandInputController.value = TextEditingValue(
          text: cmd,
          selection: TextSelection.collapsed(offset: cmd.length),
        );
        _commandFocusNode.requestFocus();
      },
      itemBuilder: (context) {
        if (_commandHistory.isEmpty) {
          return [
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                'No history yet',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Courier New',
                  color: palette.textColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ];
        }
        return _commandHistory.reversed.take(15).map((cmd) {
          final lines = cmd
              .split('\n')
              .map((l) => l.trimRight())
              .where((l) => l.isNotEmpty)
              .toList();
          final isMulti = lines.length > 1;
          final firstLine = lines.isNotEmpty ? lines.first : cmd;

          return PopupMenuItem<String>(
            value: cmd,
            child: SizedBox(
              width: 320,
              child: Row(
                children: [
                  Icon(
                    isMulti ? Icons.article_outlined : Icons.terminal_rounded,
                    size: 13,
                    color: isMulti
                        ? palette.primaryColor
                        : palette.textColor.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      firstLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 11.5,
                        color: palette.textColor,
                      ),
                    ),
                  ),
                  if (isMulti) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: palette.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: palette.primaryColor.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${lines.length} lines',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'Courier New',
                          fontWeight: FontWeight.bold,
                          color: palette.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList();
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: palette.background.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: palette.inputBorderColor),
          ),
          child: Icon(
            Icons.history_rounded,
            size: 14,
            color: palette.textColor.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  // --- Node Picker with FuzzySearchableDropdown ---
  Widget _buildNodePicker() {
    final palette = AppTheme.activePalette;
    final allConns = [..._tabs, ..._rightTabs];
    final selectedCount = _selectedConnectionIds.length;

    return Tooltip(
      message: 'Select target nodes ($selectedCount active)',
      child: FuzzySearchableDropdown<SshConnection>(
        openUpward: true,
        popupWidth: 280,
        items: allConns,
        selectedItem: null,
        hintText: 'Search & toggle node...',
        searchPlaceholder: 'Search node by name or host...',
        itemLabel: (c) =>
            c.currentLabel.isNotEmpty ? c.currentLabel : c.currentHost,
        itemSubtitle: (c) =>
            '${c.currentHost} • ${c.isConnected ? 'online' : 'offline'}',
        searchTerms: (c) => [c.currentLabel, c.currentHost],
        itemBadge: (c) => _selectedConnectionIds.contains(c.id)
            ? Icon(Icons.check_circle_rounded,
                size: 14, color: palette.primaryColor)
            : const SizedBox.shrink(),
        onChanged: (c) {
          if (c != null) _toggleConnectionSelection(c.id);
        },
        customTrigger: (context, isOpen) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6.5),
            decoration: BoxDecoration(
              color: isOpen
                  ? palette.primaryColor.withValues(alpha: 0.18)
                  : palette.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isOpen
                    ? palette.primaryColor
                    : (selectedCount > 0
                        ? palette.primaryColor.withValues(alpha: 0.5)
                        : palette.inputBorderColor),
                width: isOpen ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 15,
                  color: selectedCount > 0
                      ? palette.primaryColor
                      : palette.textColor.withValues(alpha: 0.6),
                ),
                if (selectedCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$selectedCount',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: palette.primaryColor,
                    ),
                  ),
                ],
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 13,
                  color: palette.textColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  int get _targetNodeCount {
    return _broadcastCoordinator.resolveTargetConnections(
      leftTabs: _tabs,
      rightTabs: _rightTabs,
      isSplitView: _isSplitView,
    ).length;
  }

  // --- Run Button (Vibrant Circular Arrow Button) ---
  Widget _buildRunButton() {
    final palette = AppTheme.activePalette;
    const activeBlue = Color(0xFF2563EB);

    return ListenableBuilder(
      listenable: _commandInputController,
      builder: (context, _) {
        final nodeCount = _targetNodeCount;
        final hasText = _commandInputController.text.trim().isNotEmpty;
        final canRun = !_isSendingCommands && hasText && nodeCount > 0;
        final isActive = canRun || _isSendingCommands;

        final tooltipMessage = _isSendingCommands
            ? 'Executing...'
            : (nodeCount == 0
                ? 'No target node selected'
                : (!hasText
                    ? 'Enter command'
                    : 'Run on $nodeCount node${nodeCount == 1 ? '' : 's'} (Enter)'));

        return Tooltip(
          message: tooltipMessage,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canRun ? _sendBroadcastCommand : null,
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? activeBlue
                      : palette.textColor.withValues(alpha: 0.08),
                  border: Border.all(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.25)
                        : palette.textColor.withValues(alpha: 0.06),
                    width: 1,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: activeBlue.withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: _isSendingCommands
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: isActive
                            ? Colors.white
                            : palette.textColor.withValues(alpha: 0.3),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- DevOps Single-Row Command Pane (Double-Border Layered Inset Capsule) ---
  Widget _buildDevopsToolbarCommandPane() {
    final palette = AppTheme.activePalette;
    return Container(
      // LAPISAN 1: OUTER RING (Tipis & redup sebagai trench kedalaman)
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isSendingCommands
              ? palette.primaryColor.withValues(alpha: 0.4)
              : palette.textColor.withValues(alpha: 0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 26,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3.5), // Celah 3.5px antara border luar dan dalam
      child: Container(
        // LAPISAN 2: INNER SURFACE CAPSULE (Lebih tebal & lebih terang, efek mengambang)
        decoration: BoxDecoration(
          color: palette.surfaceColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isSendingCommands
                ? palette.primaryColor
                : palette.textColor.withValues(alpha: 0.22),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            if (_isSendingCommands)
              BoxShadow(
                color: palette.primaryColor.withValues(alpha: 0.3),
                blurRadius: 14,
                spreadRadius: 1,
              ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Node Picker on the left
            _buildNodePicker(),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: palette.textColor.withValues(alpha: 0.12),
            ),
            // Command Input Box
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): () {
                    if (!_isSendingCommands) {
                      _sendBroadcastCommand();
                    }
                  },
                  const SingleActivator(
                    LogicalKeyboardKey.numpadEnter,
                  ): () {
                    if (!_isSendingCommands) {
                      _sendBroadcastCommand();
                    }
                  },
                },
                child: TextField(
                  controller: _commandInputController,
                  focusNode: _commandFocusNode,
                  minLines: 1,
                  maxLines: 4,
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12.5,
                    color: palette.textColor,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    hintText: 'Enter command to broadcast...',
                    hintStyle: TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 12,
                      color: palette.textColor.withValues(alpha: 0.35),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Quick Actions (Snippets & History)
            _buildSnippetsButton(),
            const SizedBox(width: 4),
            _buildHistoryButton(),
            const SizedBox(width: 8),
            // Run Button
            _buildRunButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingCommandPane() {
    return _buildDevopsToolbarCommandPane();
  }

  Widget _buildSplitButton() {
    final palette = AppTheme.activePalette;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.inputBorderColor),
        ),
      ),
      child: Tooltip(
        message: _isSplitView ? 'Close split view' : 'Split view',
        child: InkWell(
          key: const ValueKey('nexus_split_button'),
          onTap: _toggleSplitView,
          child: Container(
            color: _isSplitView
                ? palette.primaryColor.withValues(alpha: 0.15)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: SplitScreenIcon(
              size: 16,
              color: _isSplitView
                  ? palette.primaryColor
                  : palette.textColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCloseAllButton() {
    final palette = AppTheme.activePalette;
    return Container(
      height: 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: palette.inputBorderColor),
        ),
      ),
      child: Tooltip(
        message: 'Close all tabs',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: _confirmAndCloseAll,
            borderRadius: BorderRadius.circular(4),
            hoverColor: palette.errorColor.withValues(alpha: 0.15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: palette.errorColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: palette.errorColor.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 14,
                    color: palette.errorColor,
                  ),
                  const SizedBox(width: 4.5),
                  Text(
                    'Close All',
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.errorColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens an SSH-only command palette (OAM + FE hostnames). The selected
  /// target is opened as a new tab in the pane that owns the "+" button.
  void _showNewSessionPalette({required bool isRightPane}) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => CommandPalette(
        sessionsOnly: true,
        onSelect: (item) {
          if (item.action == CommandAction.connectSession && item.session != null) {
            connectSessionProfile(item.session!, toRightPane: isRightPane);
          } else if (item.action == CommandAction.openSessionsManager) {
            _openSessionsDialog();
          }
        },
      ),
    );
  }

  /// Seamless "+" button: no background/border, blends with the tab bar so
  /// only the icon is visible.
  Widget _buildNewTabButton({required bool isRightPane}) {
    return Tooltip(
      message: 'New SSH session',
      child: InkWell(
        canRequestFocus: false,
        key: ValueKey(
            isRightPane ? 'nexus_new_tab_button_right' : 'nexus_new_tab_button'),
        onTap: () => _showNewSessionPalette(isRightPane: isRightPane),
        hoverColor: AppTheme.textColor.withValues(alpha: 0.06),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Icon(
            Icons.add,
            size: 16,
            color: AppTheme.textColor.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }

  Widget _buildTabListWidget({
    required List<SshConnection> tabs,
    required int activeIndex,
    required ScrollController controller,
    required bool isRightPane,
  }) {
    if (tabs.isEmpty) {
      return Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              isRightPane ? 'Split Pane (Empty)' : 'Left Pane (Empty)',
              style: TextStyle(
                color: AppTheme.textColor.withValues(alpha: 0.5),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          _buildNewTabButton(isRightPane: isRightPane),
        ],
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        controller: controller,
        primary: false,
        scrollDirection: Axis.horizontal,
        children: [
          for (int index = 0; index < tabs.length; index++)
            _buildTabItem(tabs[index], index, index == activeIndex, isRightPane),
          _buildNewTabButton(isRightPane: isRightPane),
        ],
      ),
    );
  }

  Widget _buildEnvironmentBadge(SessionEnvironment env) {
    return Container(
      key: ValueKey('tab_env_badge_${env.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: env.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: env.color.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Text(
        env.label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: env.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTabItem(
    SshConnection conn,
    int index,
    bool isActive,
    bool isRightPane,
  ) {
    final palette = AppTheme.activePalette;
    final tabItemWidget = InkWell(
      canRequestFocus: false,
      key: ValueKey(conn.id),
      onTap: () {
        setState(() {
          _lastActivePaneIsRight = isRightPane;
          if (isRightPane) {
            _activeRightTab = index;
          } else {
            _activeTab = index;
          }
        });
        _focusActiveTerminal();
      },
      onSecondaryTapDown: (details) {
        _lastActivePaneIsRight = isRightPane;
        _showTabContextMenu(details.globalPosition, conn, isRightPane: isRightPane);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? palette.background : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? palette.primaryColor : Colors.transparent,
              width: 2,
            ),
            right: BorderSide(
              color: palette.inputBorderColor,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<bool>(
              stream: conn.connectionState,
              initialData: conn.isConnected,
              builder: (context, snapshot) {
                final connected = snapshot.data ?? false;
                if (connected && isActive) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final next = await SettingsService.instance.cycleNexusPulseStyle();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Pulse Style: ${next.label}'),
                            duration: const Duration(milliseconds: 1400),
                            behavior: SnackBarBehavior.floating,
                            width: 280,
                          ),
                        );
                      }
                    },
                    child: Tooltip(
                      message: 'Pulse: ${SettingsService.instance.nexusPulseStyle.label} • ${SettingsService.instance.nexusPulseColor.label}\nClick to cycle style',
                      child: ListenableBuilder(
                        listenable: SettingsService.instance,
                        builder: (context, _) => RadarPulseIndicator(
                          color: SettingsService.instance.nexusPulseColor.primary,
                          size: 7.5,
                          style: SettingsService.instance.nexusPulseStyle,
                          pulseColor: SettingsService.instance.nexusPulseColor,
                        ),
                      ),
                    ),
                  );
                }
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected
                        ? palette.successColor
                        : palette.errorColor,
                  ),
                );
              },
            ),
            StreamBuilder<String>(
              stream: conn.labelStream,
              initialData: conn.currentLabel,
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? conn.currentLabel,
                  style: TextStyle(
                    color: isActive ? palette.textColor : palette.textColor.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              },
            ),
            const SizedBox(width: 6),
            _buildEnvironmentBadge(conn.environment),
            const SizedBox(width: 8),
            InkWell(
              canRequestFocus: false,
              onTap: () => _closeTab(index, isRightPane: isRightPane),
              child: Icon(
                Icons.close,
                size: 14,
                color: isActive
                    ? palette.textColor
                    : palette.textColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );

    return Draggable<_TabDragData>(
      data: _TabDragData(connection: conn, fromRightPane: isRightPane),
      onDragStarted: () {
        setState(() => _isDraggingTab = true);
      },
      onDragEnd: (_) {
        setState(() => _isDraggingTab = false);
      },
      onDraggableCanceled: (velocity, offset) {
        setState(() => _isDraggingTab = false);
      },
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.primaryColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.successColor,
                ),
              ),
              Text(
                conn.currentLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: tabItemWidget,
      ),
      child: tabItemWidget,
    );
  }

  Widget _buildEmptyPaneState(String message) {
    return Container(
      color: AppTheme.background,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.splitscreen_outlined,
            size: 40,
            color: AppTheme.titleColor.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropZoneOverlay({String message = 'Drop here to split'}) {
    return Container(
      color: AppTheme.primaryColor.withValues(alpha: 0.12),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.splitscreen_outlined,
              size: 36,
              color: AppTheme.primaryColor.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: AppTheme.primaryColor.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<SshConnection> _getCommandPaneResolvedConnections({bool connectedOnly = true}) {
    final allConns = [..._tabs, ..._rightTabs];
    bool filterConn(SshConnection c) => !connectedOnly || c.isConnected;

    if (_broadcastTarget == BroadcastTarget.custom) {
      return allConns
          .where((c) => filterConn(c) && _selectedConnectionIds.contains(c.id))
          .toList();
    } else if (!_isSplitView) {
      return _tabs.where(filterConn).toList();
    } else {
      switch (_broadcastTarget) {
        case BroadcastTarget.left:
          return _tabs.where(filterConn).toList();
        case BroadcastTarget.right:
          return _rightTabs.where(filterConn).toList();
        case BroadcastTarget.all:
          return allConns.where(filterConn).toList();
        case BroadcastTarget.custom:
          return [];
      }
    }
  }

  String get _syncedCommandPaneTargetLabel {
    var resolved = _getCommandPaneResolvedConnections(connectedOnly: true);
    if (resolved.isEmpty) {
      resolved = _getCommandPaneResolvedConnections(connectedOnly: false);
    }
    if (resolved.isEmpty) {
      return 'Synced with Command Pane';
    }
    final names = resolved
        .map((c) => c.currentLabel.isNotEmpty ? c.currentLabel : c.currentHost)
        .join(', ');
    return 'Synced with Command Pane ($names)';
  }

  @visibleForTesting
  String get syncedCommandPaneTargetLabel => _syncedCommandPaneTargetLabel;

  List<String> get _activeConnectionLabels {
    final labels = <String>['Active Tab'];
    for (final conn in [..._tabs, ..._rightTabs]) {
      final label = conn.currentLabel.isNotEmpty ? conn.currentLabel : conn.currentHost;
      if (label.isNotEmpty && !labels.contains(label)) {
        labels.add(label);
      }
    }
    return labels;
  }

  List<SshConnection> _resolveRunbookTargetConnections(String targetNode) {
    final allConns = [..._tabs, ..._rightTabs];
    if (targetNode == 'Synced with Command Pane' ||
        targetNode == 'Synced' ||
        targetNode == _syncedCommandPaneTargetLabel ||
        targetNode.startsWith('Synced with Command Pane')) {
      return _getCommandPaneResolvedConnections(connectedOnly: true);
    }

    if (targetNode == 'Active Tab') {
      if (_tabs.isNotEmpty && _activeTab >= 0 && _activeTab < _tabs.length) {
        final active = _tabs[_activeTab];
        if (active.isConnected) return [active];
      }
      if (_isSplitView &&
          _rightTabs.isNotEmpty &&
          _activeRightTab >= 0 &&
          _activeRightTab < _rightTabs.length) {
        final activeRight = _rightTabs[_activeRightTab];
        if (activeRight.isConnected) return [activeRight];
      }
      return [];
    }

    // Match specific connection label or host
    final matched = allConns.where((c) {
      if (!c.isConnected) return false;
      return c.currentLabel == targetNode ||
          c.currentHost == targetNode ||
          c.label == targetNode ||
          c.host == targetNode;
    }).toList();
    return matched;
  }

  Future<List<SshConnection>?> _showQuickNodePickerDialog(String requestedTarget) async {
    List<SshConnection>? resultConnections;
    await SessionsDialog.show(
      context,
      onConnectSessions: (sessions, {openInRightSplit = false}) {
        final opened = <SshConnection>[];
        for (final s in sessions) {
          final route = SessionManagerService.instance.resolveSshRoute(s);
          final conn = SshConnection.fromSessionProfile(s, route: route);
          _addTab(conn);
          conn.connect();
          opened.add(conn);
        }
        resultConnections = opened;
      },
      onOpenInFileExplorer: (_) {},
    );
    return resultConnections;
  }

  @visibleForTesting
  Future<void> executeRunbookScript(String targetNode, List<String> lines) =>
      _executeRunbookScript(targetNode, lines);

  Future<void> _executeRunbookScript(String targetNode, List<String> lines) async {
    final cleanLines = lines.where((l) => l.trim().isNotEmpty).toList();
    if (cleanLines.isEmpty) return;

    var targetConnections = _resolveRunbookTargetConnections(targetNode);
    if (targetConnections.isEmpty) {
      if (!mounted) return;
      final picked = await _showQuickNodePickerDialog(targetNode);
      if (picked == null || picked.isEmpty || !mounted) return;
      targetConnections = picked;
    }

    for (final conn in targetConnections) {
      if (!conn.isConnected) {
        try {
          await conn.connectionState
              .firstWhere((connected) => connected)
              .timeout(const Duration(seconds: 15));
        } catch (_) {}
      }
    }

    final showProgress = SettingsService.instance.nexusRunbookShowProgress;
    final resolvedTargetDisplay = targetConnections.length == 1
        ? (targetConnections.first.currentLabel.isNotEmpty
            ? targetConnections.first.currentLabel
            : targetConnections.first.currentHost)
        : (targetNode == 'Active Tab' || targetNode.startsWith('Synced')
            ? '${targetConnections.length} hosts'
            : '$targetNode (${targetConnections.length} hosts)');

    setState(() {
      _isRunbookSending = true;
      _isRunbookCancelled = false;
      _isRunbookCompleted = false;
      _runbookErrorMessage = null;
      _runbookTargetNode = resolvedTargetDisplay;
      _runbookTotalLines = cleanLines.length;
      _runbookCurrentLineIndex = 1;
      _runbookCurrentCommand = cleanLines.first;
    });

    try {
      for (int i = 0; i < cleanLines.length; i++) {
        if (_isRunbookCancelled || !mounted) break;

        final disconnectedBefore = targetConnections
            .cast<SshConnection?>()
            .firstWhere((c) => c != null && !c.isConnected, orElse: () => null);
        if (disconnectedBefore != null) {
          final label = disconnectedBefore.currentLabel.isNotEmpty
              ? disconnectedBefore.currentLabel
              : disconnectedBefore.currentHost;
          if (mounted) {
            setState(() {
              _runbookErrorMessage =
                  'Target SSH session disconnected ($label)';
              if (!showProgress) {
                _isRunbookSending = false;
              }
            });
            if (!showProgress) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Target SSH session disconnected ($label)'),
                  backgroundColor: AppTheme.activePalette.errorColor,
                ),
              );
            }
          }
          return;
        }

        final cmd = cleanLines[i];
        if (showProgress) {
          setState(() {
            _runbookCurrentLineIndex = i + 1;
            _runbookCurrentCommand = cmd;
          });
        }

        if (_isParallelMode) {
          await Future.wait(
            targetConnections.map(
              (conn) => conn.sendCommandAndWaitForPrompt(command: cmd),
            ),
          );
        } else {
          for (final conn in targetConnections) {
            if (_isRunbookCancelled || !mounted) break;
            await conn.sendCommandAndWaitForPrompt(command: cmd);
          }
        }

        if (_isRunbookCancelled || !mounted) break;

        final disconnectedAfter = targetConnections
            .cast<SshConnection?>()
            .firstWhere((c) => c != null && !c.isConnected, orElse: () => null);
        if (disconnectedAfter != null) {
          final label = disconnectedAfter.currentLabel.isNotEmpty
              ? disconnectedAfter.currentLabel
              : disconnectedAfter.currentHost;
          if (mounted) {
            setState(() {
              _runbookErrorMessage =
                  'Target SSH session disconnected ($label)';
              if (!showProgress) {
                _isRunbookSending = false;
              }
            });
            if (!showProgress) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Target SSH session disconnected ($label)'),
                  backgroundColor: AppTheme.activePalette.errorColor,
                ),
              );
            }
          }
          return;
        }
      }

      if (mounted && !_isRunbookCancelled && _runbookErrorMessage == null) {
        if (showProgress) {
          setState(() {
            _isRunbookCompleted = true;
          });
        } else {
          setState(() {
            _isRunbookSending = false;
            _isRunbookCompleted = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _runbookErrorMessage = e.toString();
          if (!showProgress) {
            _isRunbookSending = false;
          }
        });
        if (!showProgress) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: AppTheme.activePalette.errorColor,
            ),
          );
        }
      }
    }
  }

  void _cancelRunbookExecution() {
    setState(() {
      _isRunbookCancelled = true;
      _isRunbookSending = false;
      _isRunbookCompleted = false;
      _runbookErrorMessage = null;
    });
    if (_isRightSidebarVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sidebarKey.currentState?.focusSidebar();
        }
      });
    }
  }

  void _closeRunbookProgressDialog() {
    setState(() {
      _isRunbookSending = false;
      _isRunbookCompleted = false;
      _runbookErrorMessage = null;
    });
    if (_isRightSidebarVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sidebarKey.currentState?.focusSidebar();
        }
      });
    }
  }

  Widget _buildRightSidebarWidget() {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        // Keep at least 400px for the main content so left/right sidebars never squeeze it into overflow.
          final s = SettingsService.instance;
          final maxRight = MediaQuery.of(context).size.width - s.leftSidebarWidth - 400;
          return SizedBox(
          width: s.rightSidebarWidth.clamp(0.0, maxRight < 240 ? 240.0 : maxRight),
          child: InteractiveRunbookSidebar(
            key: _sidebarKey,
            onClose: () {
              if (_isRightSidebarVisible) {
                toggleRightSidebar();
              }
            },
            activeConnections: _activeConnectionLabels,
            syncedCommandPaneTarget: _syncedCommandPaneTargetLabel,
            onExecuteScript: _executeRunbookScript,
            onFocusNexusTerminal: _focusActiveTerminal,
          ),
        );
      },
    );
  }

  Widget _buildTerminalMainArea() {
    if (_tabs.isEmpty && _rightTabs.isEmpty) {
      return Stack(
        children: [
          Positioned.fill(
            child: _buildEmptyState(),
          ),
          if (_showCommandPane)
            ListenableBuilder(
              listenable: SettingsService.instance,
              builder: (context, _) {
                final widthFactor =
                    (SettingsService.instance.floatingCommandWidth / 100.0)
                        .clamp(0.2, 1.0);
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: widthFactor,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16.0),
                        child: _buildFloatingCommandPane(),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      );
    }

    return Column(
      children: [
        // Tab bar
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.activePalette.surfaceColor,
            border: Border(
              bottom: BorderSide(color: AppTheme.activePalette.inputBorderColor),
            ),
          ),
          child: _isSplitView
              ? Row(
                  children: [
                    // Left Pane Tab Bar
                    Expanded(
                      flex: 1,
                      child: _buildTabListWidget(
                        tabs: _tabs,
                        activeIndex: _activeTab,
                        controller: _tabScrollController,
                        isRightPane: false,
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppTheme.activePalette.inputBorderColor,
                    ),
                    // Right Pane Tab Bar with Split and Close All buttons
                    Expanded(
                      flex: 1,
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTabListWidget(
                              tabs: _rightTabs,
                              activeIndex: _activeRightTab,
                              controller: _rightTabScrollController,
                              isRightPane: true,
                            ),
                          ),
                          _buildCommandPaneToggleButton(),
                          _buildSplitButton(),
                          if (_tabs.length + _rightTabs.length > 1)
                            _buildCloseAllButton(),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _buildTabListWidget(
                        tabs: _tabs,
                        activeIndex: _activeTab,
                        controller: _tabScrollController,
                        isRightPane: false,
                      ),
                    ),
                    _buildCommandPaneToggleButton(),
                    _buildSplitButton(),
                    if (_tabs.length + _rightTabs.length > 1)
                      _buildCloseAllButton(),
                  ],
                ),
        ),

        // Production Guardrail Warning Banner
        if (_activeConnection?.environment.isProduction == true)
          Container(
            key: const ValueKey('prod_guardrail_banner'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFEF4444).withValues(alpha: 0.2),
                  const Color(0xFFEF4444).withValues(alpha: 0.05),
                ],
              ),
              border: const Border(
                bottom: BorderSide(
                  color: Color(0xFFEF4444),
                  width: 1.5,
                ),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFEF4444)),
                SizedBox(width: 6),
                Text(
                  'PRODUCTION ENVIRONMENT — EXECUTE COMMANDS WITH CAUTION',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          ),

        // Terminal view
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _isSplitView
                    ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Terminal Pane — accepts drops from right pane
                    Expanded(
                      flex: 1,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) => _lastActivePaneIsRight = false,
                        child: DragTarget<_TabDragData>(
                          onWillAcceptWithDetails: (details) =>
                              details.data.fromRightPane,
                          onAcceptWithDetails: (details) {
                            _moveTabToLeftPane(details.data.connection);
                          },
                          builder: (context, candidateData, rejectedData) {
                            final content = _tabs.isEmpty
                                ? _buildEmptyPaneState('Primary pane empty')
                                : IndexedStack(
                                    index: _activeTab.clamp(
                                        0, _tabs.length - 1),
                                    children: [
                                      for (int i = 0; i < _tabs.length; i++)
                                        SshTabView(
                                          key: GlobalObjectKey(_tabs[i]),
                                          connection: _tabs[i],
                                          isActive: !_lastActivePaneIsRight && i == _activeTab,
                                          onFocus: () => _lastActivePaneIsRight = false,
                                          onClose: () => _closeTab(i, isRightPane: false),
                                          bottomInset: _showCommandPane ? 68.0 : 0.0,
                                        ),
                                    ],
                                  );
                            if (candidateData.isNotEmpty) {
                              return Stack(
                                children: [
                                  content,
                                  Positioned.fill(
                                    child: _buildDropZoneOverlay(
                                        message: 'Move to left pane'),
                                  ),
                                ],
                              );
                            }
                            return content;
                          },
                        ),
                      ),
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: AppTheme.inputBorderColor,
                    ),
                    // Right Terminal Pane — accepts drops from left pane
                    Expanded(
                      flex: 1,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: (_) => _lastActivePaneIsRight = true,
                        child: DragTarget<_TabDragData>(
                          onWillAcceptWithDetails: (details) =>
                              !details.data.fromRightPane,
                          onAcceptWithDetails: (details) {
                            _moveTabToRightPane(details.data.connection);
                          },
                          builder: (context, candidateData, rejectedData) {
                            final content = _rightTabs.isEmpty
                                ? _buildEmptyPaneState(
                                    'Split view active. Open an SSH client to display here.')
                                : IndexedStack(
                                    index: _activeRightTab.clamp(
                                        0, _rightTabs.length - 1),
                                    children: [
                                      for (int i = 0; i < _rightTabs.length; i++)
                                        SshTabView(
                                          key: GlobalObjectKey(_rightTabs[i]),
                                          connection: _rightTabs[i],
                                          isActive: _lastActivePaneIsRight && i == _activeRightTab,
                                          onFocus: () => _lastActivePaneIsRight = true,
                                          onClose: () => _closeTab(i, isRightPane: true),
                                          bottomInset: _showCommandPane ? 68.0 : 0.0,
                                        ),
                                    ],
                                  );
                            if (candidateData.isNotEmpty) {
                              return Stack(
                                children: [
                                  content,
                                  Positioned.fill(
                                    child: _buildDropZoneOverlay(
                                        message: 'Move to right pane'),
                                  ),
                                ],
                              );
                            }
                            return content;
                          },
                        ),
                      ),
                    ),
                  ],
                )
              // Single pane mode — show drop target on right half when dragging
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final terminalContent = IndexedStack(
                      index: _activeTab.clamp(
                          0, _tabs.isNotEmpty ? _tabs.length - 1 : 0),
                      children: [
                        for (int i = 0; i < _tabs.length; i++)
                          SshTabView(
                            key: GlobalObjectKey(_tabs[i]),
                            connection: _tabs[i],
                            isActive: i == _activeTab,
                            onFocus: () => _lastActivePaneIsRight = false,
                            onClose: () => _closeTab(i, isRightPane: false),
                            bottomInset: _showCommandPane ? 68.0 : 0.0,
                          ),
                      ],
                    );

                    final halfWidth = constraints.maxWidth / 2;
                    return Stack(
                      children: [
                        terminalContent,
                        if (_isDraggingTab)
                          // Drop target covers the right half
                          Positioned(
                            left: halfWidth,
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: DragTarget<_TabDragData>(
                              onWillAcceptWithDetails: (details) =>
                                  !details.data.fromRightPane,
                              onAcceptWithDetails: (details) {
                                _moveTabToRightPane(details.data.connection);
                              },
                              builder:
                                  (context, candidateData, rejectedData) {
                                if (candidateData.isNotEmpty) {
                                  return _buildDropZoneOverlay(
                                      message: 'Drop here to split');
                                }
                                return const SizedBox.expand();
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              if (_showCommandPane)
                ListenableBuilder(
                  listenable: SettingsService.instance,
                  builder: (context, _) {
                    final widthFactor =
                        (SettingsService.instance.floatingCommandWidth / 100.0)
                            .clamp(0.2, 1.0);
                    return Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(
                        child: FractionallySizedBox(
                          widthFactor: widthFactor,
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: _buildFloatingCommandPane(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: MouseRegion(
            onHover: (_) {
              if (_isRightSidebarVisible) {
                _sidebarKey.currentState?.onGlobalHover();
              }
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      if (_isRightSidebarVisible) {
                        _sidebarKey.currentState?.onSelectMainWidget();
                      }
                    },
                    child: _isRightSidebarVisible
                        ? Container(
                            margin: const EdgeInsets.only(top: 3, bottom: 3),
                            child: Material(
                              color: AppTheme.activePalette.surfaceColor,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: AppTheme.activePalette.inputBorderColor
                                      .withValues(alpha: 0.6),
                                  width: 1,
                                ),
                              ),
                              child: _buildTerminalMainArea(),
                            ),
                          )
                        : _buildTerminalMainArea(),
                  ),
                ),
                Offstage(
                  offstage: !_isRightSidebarVisible,
                  child: ExcludeFocus(
                    excluding: !_isRightSidebarVisible,
                    child: _buildRightSidebarWidget(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isRunbookSending &&
            SettingsService.instance.nexusRunbookShowProgress)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_isRunbookCompleted || _runbookErrorMessage != null) {
                  _closeRunbookProgressDialog();
                }
              },
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: FloatingSendProgressDialog(
                  targetNode: _runbookTargetNode,
                  currentLineIndex: _runbookCurrentLineIndex,
                  totalLines: _runbookTotalLines,
                  currentCommand: _runbookCurrentCommand,
                  isCompleted: _isRunbookCompleted,
                  errorMessage: _runbookErrorMessage,
                  autoClose: SettingsService.instance.nexusRunbookAutoClose,
                  autoCloseDuration: Duration(
                    seconds: SettingsService.instance.nexusRunbookAutoCloseDelay,
                  ),
                  onCancel: _cancelRunbookExecution,
                  onClose: _closeRunbookProgressDialog,
                ),
              ),
            ),
          ),
      ],
    );
  }


  Widget _buildEmptyState() {
    return Container(
      color: AppTheme.background,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.terminal,
              size: 64,
              color: AppTheme.titleColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            const Text(
              'NEXUS SSH TERMINAL',
              style: TextStyle(
                color: AppTheme.titleColor,
                fontSize: 24,
                fontWeight: FontWeight.w100,
                letterSpacing: 4.0,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Press Ctrl+Space to quick-connect to a node\nor select a node from the Nodes view',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom split icon matching the rounded rectangular split screen design
class SplitScreenIcon extends StatelessWidget {
  final Color? color;
  final double size;

  const SplitScreenIcon({
    super.key,
    this.color,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? IconTheme.of(context).color ?? AppTheme.textColor;
    return CustomPaint(
      size: Size(size, size * 0.9),
      painter: _SplitIconPainter(color: iconColor),
    );
  }
}

class _SplitIconPainter extends CustomPainter {
  final Color color;

  _SplitIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
      const Radius.circular(3.0),
    );
    canvas.drawRRect(rrect, paint);

    final centerX = size.width / 2;
    canvas.drawLine(
      Offset(centerX, 0.75),
      Offset(centerX, size.height - 0.75),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SplitIconPainter oldDelegate) =>
      oldDelegate.color != color;
}


class _TabDragData {
  final SshConnection connection;
  final bool fromRightPane;

  const _TabDragData({required this.connection, required this.fromRightPane});
}

