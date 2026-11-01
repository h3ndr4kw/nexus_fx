import 'dart:io';
import 'dart:math' as math;
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
import '../widgets/floating_send_progress_dialog.dart';
import 'sessions_screen.dart';

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

enum BroadcastTarget {
  all,
  left,
  right,
  custom,
}

class NexusScreenState extends State<NexusScreen> {
  final SshService _sshService = SshService.instance;
  final List<SshConnection> _tabs = [];
  final ScrollController _tabScrollController = ScrollController();
  int _activeTab = 0;

  bool _isSplitView = false;
  final List<SshConnection> _rightTabs = [];
  final ScrollController _rightTabScrollController = ScrollController();
  int _activeRightTab = 0;
  bool _isDraggingTab = false;
  bool _lastActivePaneIsRight = false;

  @visibleForTesting
  int get activeTabIndex => _activeTab;

  @visibleForTesting
  int get activeRightTabIndex => _activeRightTab;

  @visibleForTesting
  bool get lastActivePaneIsRight => _lastActivePaneIsRight;

  @visibleForTesting
  List<String> get tabLabels => _tabs.map((c) => c.currentLabel).toList();

  @visibleForTesting
  List<String> get rightTabLabels => _rightTabs.map((c) => c.currentLabel).toList();

  @visibleForTesting
  List<SshConnection> get tabs => List.unmodifiable(_tabs);

  @visibleForTesting
  List<SshConnection> get rightTabs => List.unmodifiable(_rightTabs);

  bool _showCommandPane = false;
  bool _isRightSidebarVisible = false;
  final GlobalKey<InteractiveRunbookSidebarState> _sidebarKey =
      GlobalKey<InteractiveRunbookSidebarState>();
  BroadcastTarget _broadcastTarget = BroadcastTarget.all;
  final Set<String> _selectedConnectionIds = {};
  final TextEditingController _commandInputController = TextEditingController();
  final FocusNode _commandFocusNode = FocusNode();
  bool _isSendingCommands = false;
  final bool _isParallelMode = true;
  final List<String> _commandHistory = [];
  int _historyIndex = -1;
  String _commandDraft = '';

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
    final isTargetRight = isRightPane;
    final targetList = isTargetRight ? _rightTabs : _tabs;
    setState(() {
      targetList.add(conn);
      if (isTargetRight) {
        _activeRightTab = targetList.length - 1;
      } else {
        _activeTab = targetList.length - 1;
      }
      if (_broadcastTarget == BroadcastTarget.all ||
          (_broadcastTarget == BroadcastTarget.left && !isTargetRight) ||
          (_broadcastTarget == BroadcastTarget.right && isTargetRight)) {
        _selectedConnectionIds.add(conn.id);
      }
    });
  }

  void _addTabToRight(SshConnection conn) => _addTab(conn, isRightPane: true);

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
  List<String> get commandHistory => List.unmodifiable(_commandHistory);

  @visibleForTesting
  BroadcastTarget get broadcastTarget => _broadcastTarget;

  @visibleForTesting
  Set<String> get selectedConnectionIds => Set.unmodifiable(_selectedConnectionIds);

  @visibleForTesting
  void setBroadcastTargetForTesting(BroadcastTarget target) {
    setState(() {
      _broadcastTarget = target;
      if (target == BroadcastTarget.all) {
        _selectedConnectionIds.clear();
        _selectedConnectionIds.addAll(
          [..._tabs, ..._rightTabs].where((c) => c.isConnected).map((c) => c.id),
        );
      } else if (target == BroadcastTarget.left) {
        _selectedConnectionIds.clear();
        _selectedConnectionIds.addAll(
          _tabs.where((c) => c.isConnected).map((c) => c.id),
        );
      } else if (target == BroadcastTarget.right) {
        _selectedConnectionIds.clear();
        _selectedConnectionIds.addAll(
          _rightTabs.where((c) => c.isConnected).map((c) => c.id),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _commandFocusNode.onKeyEvent = _handleCommandInputKey;
    if (widget.initialHost != null) {
      _openSshTab(widget.initialHost!, widget.initialLabel ?? widget.initialHost!);
    }
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
    final targetList = isTargetRight ? _rightTabs : _tabs;

    setState(() {
      targetList.add(conn);
      if (isTargetRight) {
        _activeRightTab = targetList.length - 1;
      } else {
        _activeTab = targetList.length - 1;
      }
      if (_broadcastTarget == BroadcastTarget.all ||
          (_broadcastTarget == BroadcastTarget.left && !isTargetRight) ||
          (_broadcastTarget == BroadcastTarget.right && isTargetRight)) {
        _selectedConnectionIds.add(conn.id);
      }
    });
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
      targetList.removeAt(index);
      if (isRightPane) {
        if (_rightTabs.isEmpty) {
          _activeRightTab = 0;
        } else if (index < _activeRightTab) {
          _activeRightTab--;
        } else if (_activeRightTab >= _rightTabs.length) {
          _activeRightTab = _rightTabs.length - 1;
        }
      } else {
        if (_tabs.isEmpty) {
          _activeTab = 0;
        } else if (index < _activeTab) {
          _activeTab--;
        } else if (_activeTab >= _tabs.length) {
          _activeTab = _tabs.length - 1;
        }
      }

      _selectedConnectionIds.remove(conn.id);
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
      _tabs.clear();
      _rightTabs.clear();
      _selectedConnectionIds.clear();
      _broadcastTarget = BroadcastTarget.all;
      _activeTab = 0;
      _activeRightTab = 0;
      _isSplitView = false;
      _lastActivePaneIsRight = false;
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
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTab = 0;
      } else if (_activeTab >= _tabs.length) {
        _activeTab = _tabs.length - 1;
      }
      _rightTabs.add(conn);
      _activeRightTab = _rightTabs.length - 1;
      _isSplitView = true;
    });
  }

  void _moveTabToLeftPane(SshConnection conn) {
    final index = _rightTabs.indexWhere((c) => c.id == conn.id);
    if (index == -1) return;
    setState(() {
      _rightTabs.removeAt(index);
      if (_rightTabs.isEmpty) {
        _activeRightTab = 0;
        _isSplitView = false;
        _broadcastTarget = BroadcastTarget.all;
      } else if (_activeRightTab >= _rightTabs.length) {
        _activeRightTab = _rightTabs.length - 1;
      }
      _tabs.add(conn);
      _activeTab = _tabs.length - 1;
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
    _tabScrollController.dispose();
    _rightTabScrollController.dispose();
    _commandInputController.dispose();
    _commandFocusNode.dispose();
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
      // If multiline and cursor is not on the first line, allow normal cursor movement
      if (text.contains('\n') && selection.baseOffset > text.indexOf('\n')) {
        return false;
      }

      if (_historyIndex == -1) {
        _commandDraft = text;
      }

      if (_historyIndex + 1 < _commandHistory.length) {
        _historyIndex++;
        final cmd = _commandHistory[_commandHistory.length - 1 - _historyIndex];
        _commandInputController.value = TextEditingValue(
          text: cmd,
          selection: TextSelection.collapsed(offset: cmd.length),
        );
        return true;
      }
      return false;
    } else {
      // Down arrow
      if (_historyIndex == -1) {
        return false;
      }

      // If multiline and cursor is not on the last line, allow normal cursor movement
      if (text.contains('\n') && selection.baseOffset <= text.lastIndexOf('\n')) {
        return false;
      }

      _historyIndex--;
      if (_historyIndex >= 0) {
        final cmd = _commandHistory[_commandHistory.length - 1 - _historyIndex];
        _commandInputController.value = TextEditingValue(
          text: cmd,
          selection: TextSelection.collapsed(offset: cmd.length),
        );
      } else {
        _commandInputController.value = TextEditingValue(
          text: _commandDraft,
          selection: TextSelection.collapsed(offset: _commandDraft.length),
        );
      }
      return true;
    }
  }

  void _selectPresetTarget(BroadcastTarget target) {
    setState(() {
      _broadcastTarget = target;
      _selectedConnectionIds.clear();
      switch (target) {
        case BroadcastTarget.all:
          _selectedConnectionIds.addAll(
            [..._tabs, ..._rightTabs].map((c) => c.id),
          );
          break;
        case BroadcastTarget.left:
          _selectedConnectionIds.addAll(
            _tabs.map((c) => c.id),
          );
          break;
        case BroadcastTarget.right:
          _selectedConnectionIds.addAll(
            _rightTabs.map((c) => c.id),
          );
          break;
        case BroadcastTarget.custom:
          break;
      }
    });
  }

  void _toggleConnectionSelection(String id) {
    setState(() {
      if (_selectedConnectionIds.contains(id)) {
        _selectedConnectionIds.remove(id);
      } else {
        _selectedConnectionIds.add(id);
      }
      _updateBroadcastTargetFromSelection();
    });
  }

  void _updateBroadcastTargetFromSelection() {
    final allIds = [..._tabs, ..._rightTabs].map((c) => c.id).toSet();
    final leftIds = _tabs.map((c) => c.id).toSet();
    final rightIds = _rightTabs.map((c) => c.id).toSet();

    if (_selectedConnectionIds.isNotEmpty &&
        _selectedConnectionIds.length == allIds.length &&
        _selectedConnectionIds.containsAll(allIds)) {
      _broadcastTarget = BroadcastTarget.all;
    } else if (_selectedConnectionIds.isNotEmpty &&
        _selectedConnectionIds.length == leftIds.length &&
        _selectedConnectionIds.containsAll(leftIds)) {
      _broadcastTarget = BroadcastTarget.left;
    } else if (_selectedConnectionIds.isNotEmpty &&
        _selectedConnectionIds.length == rightIds.length &&
        _selectedConnectionIds.containsAll(rightIds)) {
      _broadcastTarget = BroadcastTarget.right;
    } else {
      _broadcastTarget = BroadcastTarget.custom;
    }
  }

  int get _allConnectedCount => [
        ..._tabs,
        ..._rightTabs,
      ].where((c) => c.isConnected).length;

  int get _leftConnectedCount => _tabs.where((c) => c.isConnected).length;

  int get _rightConnectedCount => _rightTabs.where((c) => c.isConnected).length;


  Future<void> _sendBroadcastCommand() async {
    final rawText = _commandInputController.text;

    final List<SshConnection> targetConnections;
    if (_broadcastTarget == BroadcastTarget.custom) {
      targetConnections = [..._tabs, ..._rightTabs]
          .where((c) => c.isConnected && _selectedConnectionIds.contains(c.id))
          .toList();
    } else if (!_isSplitView) {
      targetConnections = _tabs.where((c) => c.isConnected).toList();
    } else {
      switch (_broadcastTarget) {
        case BroadcastTarget.left:
          targetConnections = _tabs.where((c) => c.isConnected).toList();
          break;
        case BroadcastTarget.right:
          targetConnections = _rightTabs.where((c) => c.isConnected).toList();
          break;
        case BroadcastTarget.all:
          targetConnections = [
            ..._tabs,
            ..._rightTabs,
          ].where((c) => c.isConnected).toList();
          break;
        case BroadcastTarget.custom:
          targetConnections = [];
          break;
      }
    }

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

    final isBlank = rawText.trim().isEmpty;
    final lines = isBlank
        ? ['']
        : rawText
            .split(RegExp(r'\r?\n'))
            .where((line) => line.trim().isNotEmpty)
            .toList();

    if (lines.isEmpty) return;

    if (!isBlank) {
      if (_commandHistory.isEmpty || _commandHistory.last != rawText) {
        _commandHistory.add(rawText);
      }
    }
    _historyIndex = -1;
    _commandDraft = '';

    setState(() {
      _isSendingCommands = true;
    });

    try {
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Send line to all target connections and wait for each to complete
        if (_isParallelMode) {
          await Future.wait(
            targetConnections.map(
              (conn) => conn.sendCommandAndWaitForPrompt(command: line),
            ),
          );
        } else {
          for (final conn in targetConnections) {
            await conn.sendCommandAndWaitForPrompt(command: line);
          }
        }
      }

      if (mounted) {
        _commandInputController.clear();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingCommands = false;
        });
      }
    }
  }


  // --- DevOps Multi-Exec Toolbar (Redesign from user reference) ---
  Widget _buildDevopsToolbarCommandPane() {
    final palette = AppTheme.activePalette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isSendingCommands
              ? palette.primaryColor
              : palette.inputBorderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Target Modes (Broadcast All, Selective Node) + Warning Badge + Quick Actions (Snippets, History, sudo)
          Row(
            children: [
              // Segmented group: Broadcast All & Selective Node + Warning Badge
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: palette.background.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: palette.inputBorderColor,
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Broadcast ALL button
                            _buildBroadcastAllButton(),
                            if (_isSplitView) ...[
                              const SizedBox(width: 3),
                              _buildTargetChip(
                                label: 'LEFT ($_leftConnectedCount)',
                                target: BroadcastTarget.left,
                                count: _leftConnectedCount,
                              ),
                              const SizedBox(width: 3),
                              _buildTargetChip(
                                label: 'RIGHT ($_rightConnectedCount)',
                                target: BroadcastTarget.right,
                                count: _rightConnectedCount,
                              ),
                            ],
                            const SizedBox(width: 3),
                            // Selective Node dropdown
                            _buildSelectiveNodeButton(),
                          ],
                        ),
                      ),
                      if (_selectedConnectionIds.length > 1) ...[
                        const SizedBox(width: 8),
                        BreathingAmberBadge(count: _selectedConnectionIds.length),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Quick Actions on Right
              _buildSnippetsButton(),
              const SizedBox(width: 5),
              _buildHistoryButton(),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: Prompt >_, Command Input Box, Parallel Dropdown, Run Button
          Container(
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: palette.inputBorderColor,
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Primary color prompt
                Text(
                  '>_',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: palette.primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                // Input TextField
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () {
                        if (!_isSendingCommands) {
                          _sendBroadcastCommand();
                        }
                      },
                      const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
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
                        hintText: 'systemctl status nginx lines=50',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: palette.textColor.withValues(alpha: 0.4),
                          fontFamily: 'Courier New',
                        ),
                        isDense: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
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
                // Clear Button
                _buildClearButton(),
                const SizedBox(width: 8),
                // Parallel Mode Indicator
                _buildParallelBadge(),
                const SizedBox(width: 8),
                // Run Button
                _buildRunButton(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Row 3: Footer - TARGETS: chips
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TARGETS:',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'Courier New',
                          fontWeight: FontWeight.bold,
                          color: palette.textColor.withValues(alpha: 0.6),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildDynamicConnectionChips(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBroadcastAllButton() {
    final palette = AppTheme.activePalette;
    final isSelected = _broadcastTarget == BroadcastTarget.all;
    return InkWell(
      onTap: () => _selectPresetTarget(BroadcastTarget.all),
      borderRadius: BorderRadius.circular(5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.primaryColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: isSelected
              ? Border.all(color: palette.primaryColor, width: 1.2)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? palette.primaryColor
                    : palette.textColor.withValues(alpha: 0.4),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: palette.primaryColor.withValues(alpha: 0.6),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Broadcast ALL ($_allConnectedCount)',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Courier New',
                fontWeight: FontWeight.bold,
                color: isSelected ? palette.primaryColor : palette.textColor.withValues(alpha: 0.7),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectiveNodeButton() {
    final palette = AppTheme.activePalette;
    final isCustom = _broadcastTarget == BroadcastTarget.custom;
    final allConns = [..._tabs, ..._rightTabs];

    return PopupMenuButton<String>(
      tooltip: 'Selective Node',
      color: palette.surfaceColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.inputBorderColor),
      ),
      padding: EdgeInsets.zero,
      onSelected: (val) {
        if (val == '__all__') {
          _selectPresetTarget(BroadcastTarget.all);
        } else if (val == '__left__') {
          _selectPresetTarget(BroadcastTarget.left);
        } else if (val == '__right__') {
          _selectPresetTarget(BroadcastTarget.right);
        } else {
          _toggleConnectionSelection(val);
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: '__all__',
            child: Row(
              children: [
                Icon(
                  Icons.select_all_rounded,
                  size: 14,
                  color: _broadcastTarget == BroadcastTarget.all
                      ? palette.primaryColor
                      : palette.textColor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  'All Connected Nodes',
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 11,
                    color: palette.textColor,
                  ),
                ),
              ],
            ),
          ),
        ];

        if (_isSplitView) {
          items.add(
            PopupMenuItem<String>(
              value: '__left__',
              child: Text(
                'Left Pane Nodes',
                style: TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 11,
                  color: palette.textColor,
                ),
              ),
            ),
          );
          items.add(
            PopupMenuItem<String>(
              value: '__right__',
              child: Text(
                'Right Pane Nodes',
                style: TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 11,
                  color: palette.textColor,
                ),
              ),
            ),
          );
        }

        if (allConns.isNotEmpty) {
          items.add(const PopupMenuDivider());
          for (final conn in allConns) {
            final isChecked = _selectedConnectionIds.contains(conn.id);
            items.add(
              PopupMenuItem<String>(
                value: conn.id,
                child: Row(
                  children: [
                    Icon(
                      isChecked
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 14,
                      color: isChecked
                          ? palette.primaryColor
                          : palette.textColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      conn.currentLabel.isNotEmpty
                          ? conn.currentLabel
                          : conn.currentHost,
                      style: TextStyle(
                        fontFamily: 'Courier New',
                        fontSize: 11,
                        color: palette.textColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: isCustom
              ? palette.primaryColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: isCustom
              ? Border.all(color: palette.primaryColor.withValues(alpha: 0.5), width: 1)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Selective Node',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Courier New',
                fontWeight: isCustom ? FontWeight.bold : FontWeight.normal,
                color: isCustom ? palette.primaryColor : palette.textColor.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 13,
              color: isCustom ? palette.primaryColor : palette.textColor.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnippetsButton() {
    final palette = AppTheme.activePalette;
    return PopupMenuButton<String>(
      tooltip: 'Snippets (⌘K / Ctrl+K)',
      color: palette.surfaceColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: palette.inputBorderColor),
      ),
      padding: EdgeInsets.zero,
      onSelected: (snippet) {
        _commandInputController.value = TextEditingValue(
          text: snippet,
          selection: TextSelection.collapsed(offset: snippet.length),
        );
        _commandFocusNode.requestFocus();
      },
      itemBuilder: (context) {
        const snippets = [
          'systemctl status nginx lines=50',
          'systemctl restart nginx',
          'systemctl status radiusd',
          'tail -f /var/log/syslog',
          'docker ps',
          'df -h',
          'free -m',
          'uptime',
        ];
        return snippets.map((cmd) {
          return PopupMenuItem<String>(
            value: cmd,
            child: Text(
              cmd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Courier New',
                fontSize: 12,
                color: palette.textColor,
              ),
            ),
          );
        }).toList();
      },
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
              size: 12,
              color: palette.textColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              'Snippets',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Courier New',
                fontWeight: FontWeight.w600,
                color: palette.textColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '⌘K',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: palette.textColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryButton() {
    final palette = AppTheme.activePalette;
    return PopupMenuButton<String>(
      tooltip: 'History (^R / Ctrl+R)',
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
            PopupMenuItem(
              enabled: false,
              child: Text(
                'No recent commands',
                style: TextStyle(fontSize: 11, color: palette.textColor.withValues(alpha: 0.5)),
              ),
            ),
          ];
        }
        return _commandHistory.reversed.take(10).map((cmd) {
          return PopupMenuItem<String>(
            value: cmd,
            child: Text(
              cmd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Courier New',
                fontSize: 12,
                color: palette.textColor,
              ),
            ),
          );
        }).toList();
      },
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
              Icons.access_time_rounded,
              size: 12,
              color: palette.textColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              'History',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Courier New',
                fontWeight: FontWeight.w600,
                color: palette.textColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '^R',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: palette.textColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearButton() {
    final palette = AppTheme.activePalette;
    return Tooltip(
      message: 'Clear input',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('nexus_command_pane_clear_button'),
          onTap: () {
            _commandInputController.clear();
            _commandFocusNode.requestFocus();
          },
          borderRadius: BorderRadius.circular(6),
          hoverColor: palette.textColor.withValues(alpha: 0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: palette.background.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.inputBorderColor),
            ),
            alignment: Alignment.center,
            child: Text(
              'Clear',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Courier New',
                fontWeight: FontWeight.w600,
                color: palette.textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParallelBadge() {
    final palette = AppTheme.activePalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.inputBorderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CyanPulseDot(),
          Text(
            'Parallel',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Courier New',
              fontWeight: FontWeight.w600,
              color: palette.textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunButton() {
    final palette = AppTheme.activePalette;
    final runTextColor = palette.primaryColor.computeLuminance() > 0.35
        ? const Color(0xFF070B14)
        : Colors.white;

    return InkWell(
      key: const ValueKey('nexus_command_pane_send_button'),
      onTap: _isSendingCommands ? null : _sendBroadcastCommand,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6.5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.primaryColor,
              palette.primaryColor.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: palette.primaryColor.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isSendingCommands) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(runTextColor),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Running...',
                style: TextStyle(
                  color: runTextColor,
                  fontSize: 11.5,
                  fontFamily: 'Courier New',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ] else ...[
              Text(
                'Run',
                style: TextStyle(
                  color: runTextColor,
                  fontSize: 11.5,
                  fontFamily: 'Courier New',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTargetChip({
    required String label,
    required BroadcastTarget target,
    required int count,
  }) {
    final palette = AppTheme.activePalette;
    final isSelected = _broadcastTarget == target;
    return InkWell(
      onTap: () => _selectPresetTarget(target),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.primaryColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: isSelected
              ? Border.all(color: palette.primaryColor, width: 1.2)
              : Border.all(color: Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontFamily: 'Courier New',
            fontWeight: FontWeight.bold,
            color: isSelected ? palette.primaryColor : palette.textColor.withValues(alpha: 0.7),
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicConnectionChips() {
    final palette = AppTheme.activePalette;
    final allConns = [..._tabs, ..._rightTabs];
    if (allConns.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: allConns.map((conn) {
        final isSelected = _selectedConnectionIds.contains(conn.id);
        final isConnected = conn.isConnected;
        final isInRightPane = _rightTabs.any((c) => c.id == conn.id);

        return Padding(
          padding: const EdgeInsets.only(right: 6.0),
          child: Tooltip(
            message:
                '${conn.currentLabel} (${conn.currentHost})${isInRightPane ? ' • RIGHT' : ' • LEFT'}\nClick to toggle target selection',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              key: ValueKey('nexus_target_connection_chip_${conn.id}'),
              onTap: () => _toggleConnectionSelection(conn.id),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: palette.background.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? palette.primaryColor.withValues(alpha: 0.7)
                        : palette.inputBorderColor,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected
                            ? palette.successColor
                            : palette.errorColor,
                        boxShadow: isConnected
                            ? [
                                BoxShadow(
                                  color: palette.successColor.withValues(alpha: 0.6),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      conn.currentLabel.isNotEmpty
                          ? conn.currentLabel
                          : conn.currentHost,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontFamily: 'Courier New',
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? (isConnected ? palette.successColor : palette.primaryColor)
                            : palette.textColor.withValues(alpha: 0.7),
                      ),
                    ),
                    if (_isSplitView) ...[
                      const SizedBox(width: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: palette.textColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          isInRightPane ? 'R' : 'L',
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                            color: palette.textColor.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
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

/// Radar pulse expanding ripple beacon for active session tabs (ping-slow)
class RadarPulseIndicator extends StatefulWidget {
  final Color? color;
  final double size;
  final NexusPulseStyle? style;
  final NexusPulseColor? pulseColor;

  const RadarPulseIndicator({
    super.key,
    this.color,
    this.size = 7.5,
    this.style,
    this.pulseColor,
  });

  @override
  State<RadarPulseIndicator> createState() => _RadarPulseIndicatorState();
}

class _RadarPulseIndicatorState extends State<RadarPulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _controller.repeat();
    } else {
      _controller.value = 1.0;
    }
    _animation = CurvedAnimation(parent: _controller, curve: Curves.linear);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeStyle = widget.style ?? SettingsService.instance.nexusPulseStyle;
    final activeColor = widget.pulseColor ?? SettingsService.instance.nexusPulseColor;
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(right: 6),
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return CustomPaint(
            painter: _RadarPulsePainter(
              progress: _animation.value,
              color: widget.color ?? activeColor.primary,
              dotSize: widget.size,
              style: activeStyle,
              palette: activeColor,
            ),
            size: const Size(18, 18),
          );
        },
      ),
    );
  }
}

class _RadarPulsePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double dotSize;
  final NexusPulseStyle style;
  final NexusPulseColor palette;

  _RadarPulsePainter({
    required this.progress,
    required this.color,
    required this.dotSize,
    required this.style,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    switch (style) {
      case NexusPulseStyle.neonSonarWave:
        _paintNeonSonarWave(canvas, center, maxRadius);
        break;
      case NexusPulseStyle.breathingGlowCore:
        _paintBreathingGlowCore(canvas, center, maxRadius);
        break;
      case NexusPulseStyle.telemetryHeartbeat:
        _paintTelemetryHeartbeat(canvas, center, maxRadius);
        break;
      case NexusPulseStyle.classicRadar:
        _paintClassicRadar(canvas, center, maxRadius);
        break;
    }
  }

  void _paintNeonSonarWave(Canvas canvas, Offset center, double maxRadius) {
    final primary = palette.primary;
    final secondary = palette.secondary;
    final baseRadius = dotSize / 2;

    // Ring 1 (phase 0)
    final t1 = progress;
    final r1 = baseRadius + (t1 * (maxRadius - baseRadius));
    final op1 = ((1.0 - t1) * 0.85).clamp(0.0, 1.0);
    final color1 = Color.lerp(primary, secondary, t1)!;
    final ringPaint1 = Paint()
      ..color = color1.withValues(alpha: op1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, r1, ringPaint1);

    // Ring 2 (phase 0.5 offset)
    final t2 = (progress + 0.5) % 1.0;
    final r2 = baseRadius + (t2 * (maxRadius - baseRadius));
    final op2 = ((1.0 - t2) * 0.85).clamp(0.0, 1.0);
    final color2 = Color.lerp(primary, secondary, t2)!;
    final ringPaint2 = Paint()
      ..color = color2.withValues(alpha: op2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, r2, ringPaint2);

    // Center Core: primary with subtle secondary inner ring
    final corePaint = Paint()
      ..color = primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius, corePaint);

    final innerHighlight = Paint()
      ..color = secondary.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius * 0.45, innerHighlight);
  }

  void _paintBreathingGlowCore(Canvas canvas, Offset center, double maxRadius) {
    final darkColor = palette.dark;
    final accentColor = palette.accent;

    // Smooth sinusoidal breath (0.0 -> 1.0 -> 0.0)
    final breath = 0.5 + 0.5 * math.sin((progress * 2 * math.pi) - (math.pi / 2));
    final coreRadius = (dotSize / 2) * (0.85 + (0.35 * breath));
    final dynamicColor = Color.lerp(darkColor, accentColor, breath)!;

    // Outer soft aura / halo bloom
    final haloRadius = coreRadius + (breath * (maxRadius - coreRadius));
    final haloPaint = Paint()
      ..color = dynamicColor.withValues(alpha: 0.18 + (0.18 * breath))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, haloRadius, haloPaint);

    // Secondary subtle aura ring
    final auraRingPaint = Paint()
      ..color = dynamicColor.withValues(alpha: (0.45 * (1.0 - breath)).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, haloRadius * 0.9, auraRingPaint);

    // Glowing Core Dot
    final corePaint = Paint()
      ..color = dynamicColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, coreRadius, corePaint);
  }

  void _paintTelemetryHeartbeat(Canvas canvas, Offset center, double maxRadius) {
    final primary = palette.primary;
    final secondary = palette.secondary;
    final baseRadius = dotSize / 2;

    double coreRadius = baseRadius;
    Color coreColor = primary;

    if (progress < 0.22) {
      // Beat 1: First burst
      final t = progress / 0.22;
      coreRadius = baseRadius * (1.0 + (0.28 * math.sin(t * math.pi)));
      final waveRadius = baseRadius + (t * (maxRadius * 0.7 - baseRadius));
      final ringPaint = Paint()
        ..color = primary.withValues(alpha: (1.0 - t) * 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(center, waveRadius, ringPaint);
    } else if (progress >= 0.22 && progress < 0.58) {
      // Beat 2: Larger secondary burst with secondary shift
      final t = (progress - 0.22) / 0.36;
      coreRadius = baseRadius * (1.0 + (0.35 * math.sin(t * math.pi)));
      coreColor = Color.lerp(primary, secondary, t)!;
      final waveRadius = baseRadius + (t * (maxRadius - baseRadius));
      final ringPaint = Paint()
        ..color = secondary.withValues(alpha: (1.0 - t) * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(center, waveRadius, ringPaint);
    } else {
      // Rest period
      coreRadius = baseRadius;
      coreColor = primary;
    }

    final corePaint = Paint()
      ..color = coreColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, coreRadius, corePaint);
  }

  void _paintClassicRadar(Canvas canvas, Offset center, double maxRadius) {
    final ringRadius = (dotSize / 2) + (progress * (maxRadius - (dotSize / 2)));
    final ringOpacity = (1.0 - progress).clamp(0.0, 1.0) * 0.7;
    final ringPaint = Paint()
      ..color = color.withValues(alpha: ringOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, ringRadius, ringPaint);

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, dotSize / 2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPulsePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.dotSize != dotSize ||
        oldDelegate.style != style ||
        oldDelegate.palette != palette;
  }
}

/// Breathing amber glow on safety broadcast badge (warning-pulse)
class BreathingAmberBadge extends StatefulWidget {
  final int count;

  const BreathingAmberBadge({
    super.key,
    required this.count,
  });

  @override
  State<BreathingAmberBadge> createState() => _BreathingAmberBadgeState();
}

class _BreathingAmberBadgeState extends State<BreathingAmberBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1.0;
    }
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.activePalette;
    final warningColor = palette.warningColor;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final glowOpacity = 0.25 + (_animation.value * 0.55);
        final borderOpacity = 0.45 + (_animation.value * 0.45);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: warningColor.withValues(alpha: 0.12 + (_animation.value * 0.08)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: warningColor.withValues(alpha: borderOpacity),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: warningColor.withValues(alpha: glowOpacity * 0.4),
                blurRadius: 8 + (_animation.value * 4),
                spreadRadius: _animation.value * 1.5,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: warningColor,
                size: 13,
              ),
              const SizedBox(width: 4),
              Text(
                'Simultaneous execution: ${widget.count} hosts',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Courier New',
                  fontWeight: FontWeight.bold,
                  color: warningColor,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Cyan pulse dot indicator for parallel execution mode
class CyanPulseDot extends StatefulWidget {
  const CyanPulseDot({super.key});

  @override
  State<CyanPulseDot> createState() => _CyanPulseDotState();
}

class _CyanPulseDotState extends State<CyanPulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1.0;
    }
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final glow = 0.3 + (_animation.value * 0.6);
        return Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primaryColor.withValues(alpha: glow),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: glow * 0.6),
                blurRadius: 4,
                spreadRadius: _animation.value * 1.2,
              ),
            ],
          ),
        );
      },
    );
  }
}

