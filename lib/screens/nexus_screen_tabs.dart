// Private members of NexusScreenState live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'nexus_screen.dart';

/// Terminal tabs: focus, select, open, close, split panes, moving tabs and the tab context menu.
extension _NexusTabOps on NexusScreenState {
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
    _fullscreen.onConnectionRemoved(conn.id);
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
    _fullscreen.exit();
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
        _fullscreen.onConnectionRemoved(conn.id);
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
        PopupMenuItem<String>(
          value: 'fullscreen',
          height: 36,
          child: Row(
            children: [
              Icon(
                identical(_fullscreen.target, conn) ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 14,
                color: AppTheme.textColor,
              ),
              const SizedBox(width: 8),
              Text(
                identical(_fullscreen.target, conn) ? 'Exit Fullscreen' : 'Fullscreen',
                style: const TextStyle(fontSize: 12, color: AppTheme.textColor),
              ),
            ],
          ),
        ),
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
      case 'fullscreen':
        toggleSessionFullscreen(conn);
        break;
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
}
