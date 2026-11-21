import 'dart:io';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../models/session_models.dart';
import '../theme/app_theme.dart';
import '../theme/terminal_theme_helper.dart';
import '../services/session_manager_service.dart';
import '../services/ssh_service.dart';
import '../services/settings_service.dart';
import '../widgets/ssh_tab_view.dart';
import '../widgets/command_palette.dart';
import '../widgets/interactive_runbook_sidebar.dart';
import '../controllers/terminal_tab_controller.dart';
import '../controllers/broadcast_coordinator.dart';
import '../controllers/session_fullscreen_controller.dart';
import '../widgets/floating_send_progress_dialog.dart';
import '../widgets/radar_pulse_indicator.dart';
import 'sessions_screen.dart';
import '../widgets/fuzzy_searchable_dropdown.dart';
import '../widgets/snippet_dialogs.dart';
import '../widgets/session_fullscreen_overlay.dart';

export '../controllers/broadcast_coordinator.dart' show BroadcastTarget;
export '../widgets/radar_pulse_indicator.dart';

part 'nexus_screen_tabs.dart';
part 'nexus_screen_command_pane.dart';
part 'nexus_screen_tab_strip.dart';
part 'nexus_screen_runbook.dart';
part 'nexus_screen_view.dart';

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
  final ValueChanged<bool>? onSessionFullscreenChanged;

  const NexusScreen({
    super.key,
    this.initialHost,
    this.initialLabel,
    this.onRightSidebarChanged,
    this.onSessionFullscreenChanged,
  });

  @override
  State<NexusScreen> createState() => NexusScreenState();
}

class NexusScreenState extends State<NexusScreen> {
  final SshService _sshService = SshService.instance;
  late final TerminalTabController _tabController = TerminalTabController();
  late final BroadcastCoordinator _broadcastCoordinator = BroadcastCoordinator();
  final SessionFullscreenController _fullscreen = SessionFullscreenController();
  bool _wasSessionFullscreen = false;

  TerminalTabController get tabController => _tabController;
  BroadcastCoordinator get broadcastCoordinator => _broadcastCoordinator;

  final ScrollController _tabScrollController = ScrollController();
  final ScrollController _rightTabScrollController = ScrollController();
  bool _isDraggingTab = false;

  /// Tab under the mouse; pill tabs show their close button on hover.
  String? _hoveredTabId;

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

  // Double-click on a tab is detected by hand so a single click still
  // switches tabs immediately (InkWell.onDoubleTap would delay every onTap).
  // Gap in a tab strip where a dragged tab would land; drawn as a bar.
  ({bool isRightPane, int index})? _tabDropSlot;

  // Times are pointer-event timestamps, not wall-clock reads.
  String? _lastTabClickId;
  Duration? _lastTabClickAt;
  Duration _tabPointerDownAt = Duration.zero;

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

  void _addTab(SshConnection conn, {bool isRightPane = false, int? insertIndex}) {
    conn.onClosed = () {
      if (mounted) {
        if (SettingsService.instance.nexusAutoCloseTabOnDisconnect) {
          _closeTabForConnection(conn.id);
        }
      }
    };
    setState(() {
      _tabController.addTab(conn, isRightPane: isRightPane, insertIndex: insertIndex);
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
    _fullscreen.addListener(_onFullscreenChanged);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _commandFocusNode.onKeyEvent = _handleCommandInputKey;
    if (widget.initialHost != null) {
      _openSshTab(widget.initialHost!, widget.initialLabel ?? widget.initialHost!);
    }
  }

  void _onControllersChanged() {
    if (!mounted) return;
    setState(() {});
    // Fullscreen shows exactly one session; if another becomes active (tab
    // jump, newly opened session) leave fullscreen rather than show it under
    // the old session's label.
    final target = _fullscreen.target;
    if (target != null && !identical(_activeConnection, target)) {
      _fullscreen.exit();
    }
  }

  bool get isSessionFullscreen => _fullscreen.isActive;

  @visibleForTesting
  SessionFullscreenController get fullscreenController => _fullscreen;

  /// Toggles fullscreen for [conn], or for the active session when omitted.
  Future<void> toggleSessionFullscreen([SshConnection? conn]) async {
    if (_fullscreen.isActive) {
      await _fullscreen.exit();
      return;
    }
    final target = conn ?? _activeConnection;
    if (target == null) return;
    _selectConnection(target);
    await _fullscreen.enter(target);
  }

  Future<void> exitSessionFullscreen() => _fullscreen.exit();

  void _selectConnection(SshConnection conn) {
    final left = _tabs.indexOf(conn);
    if (left != -1) {
      _activeTab = left;
      _lastActivePaneIsRight = false;
      return;
    }
    final right = _rightTabs.indexOf(conn);
    if (right != -1) {
      _activeRightTab = right;
      _lastActivePaneIsRight = true;
    }
  }

  void _onFullscreenChanged() {
    if (!mounted) return;
    final active = _fullscreen.isActive;
    setState(() {});
    if (active != _wasSessionFullscreen) {
      _wasSessionFullscreen = active;
      widget.onSessionFullscreenChanged?.call(active);
      _focusActiveTerminal();
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

    if (widget.onSessionFullscreenChanged == null &&
        isSessionFullscreenShortcut(event.logicalKey,
            ctrl: isCtrl, shift: isShift, alt: isAlt)) {
      toggleSessionFullscreen();
      return true;
    }

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

    // Fullscreen shows one session: tab switching would swap it silently.
    if (_fullscreen.isActive &&
        isCtrl &&
        (isTab ||
            isT ||
            event.logicalKey == LogicalKeyboardKey.pageDown ||
            event.logicalKey == LogicalKeyboardKey.pageUp)) {
      return false;
    }

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

  void toggleSplitView() => _toggleSplitView();

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _tabController.removeListener(_onControllersChanged);
    _broadcastCoordinator.removeListener(_onControllersChanged);
    _fullscreen.removeListener(_onFullscreenChanged);
    _fullscreen.dispose();
    _tabScrollController.dispose();
    _rightTabScrollController.dispose();
    _commandInputController.dispose();
    _commandFocusNode.dispose();
    _tabController.dispose();
    _broadcastCoordinator.dispose();
    super.dispose();
  }

  // Destructive command guardrails
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

  @visibleForTesting
  String get syncedCommandPaneTargetLabel => _syncedCommandPaneTargetLabel;

  @visibleForTesting
  Future<void> executeRunbookScript(String targetNode, List<String> lines) =>
      _executeRunbookScript(targetNode, lines);

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
                    child: _isRightSidebarVisible && !_fullscreen.isActive
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
                  offstage: !_isRightSidebarVisible || _fullscreen.isActive,
                  child: ExcludeFocus(
                    excluding: !_isRightSidebarVisible || _fullscreen.isActive,
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

