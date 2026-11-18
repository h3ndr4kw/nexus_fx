// Private members of NexusScreenState live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'nexus_screen.dart';

/// Tab strip widgets: new-tab button, tab items, empty and drop-zone states.
extension _NexusTabStrip on NexusScreenState {
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

  /// Borderless "+" button: blends with the tab bar so
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
    // Drops outside any tab land at the end of the strip; tabs are inner
    // targets, so they win while the pointer is over one.
    return _buildTabDropTarget(
      isRightPane: isRightPane,
      index: tabs.length,
      splitHalves: false,
      child: _buildTabListContent(
        tabs: tabs,
        activeIndex: activeIndex,
        controller: controller,
        isRightPane: isRightPane,
      ),
    );
  }

  Widget _buildTabListContent({
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
                color: AppTheme.dimText(0.5),
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
        if (_registerTabClick(conn)) {
          _duplicateTab(conn, isRightPane: isRightPane);
          return;
        }
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
                    color: isActive ? palette.textColor : palette.dimText(0.6),
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
                    : palette.dimText(0.5),
              ),
            ),
          ],
        ),
      ),
    );

    final clickTimedTab = Listener(
      onPointerDown: (event) => _tabPointerDownAt = event.timeStamp,
      child: tabItemWidget,
    );

    final draggable = Draggable<_TabDragData>(
      data: _TabDragData(connection: conn, fromRightPane: isRightPane),
      // Feedback sits at the pointer, so drop targets read the pointer
      // position from the drag offset.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        setState(() => _isDraggingTab = true);
      },
      onDragEnd: (_) {
        setState(() {
          _isDraggingTab = false;
          _tabDropSlot = null;
        });
      },
      onDraggableCanceled: (velocity, offset) {
        setState(() {
          _isDraggingTab = false;
          _tabDropSlot = null;
        });
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
      child: clickTimedTab,
    );

    return _buildTabDropTarget(
      isRightPane: isRightPane,
      index: index,
      splitHalves: true,
      child: draggable,
    );
  }

  /// Makes [child] a drop target for reordering tabs. A tab ([splitHalves])
  /// maps its left half to gap [index] and its right half to [index] + 1;
  /// the whole strip, outside any tab, maps to gap [index] (its end).
  Widget _buildTabDropTarget({
    required bool isRightPane,
    required int index,
    required bool splitHalves,
    required Widget child,
  }) {
    return Builder(builder: (targetContext) {
      int slotFor(Offset globalPointer) {
        if (!splitHalves) return index;
        final box = targetContext.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return index;
        final dx = box.globalToLocal(globalPointer).dx;
        return dx < box.size.width / 2 ? index : index + 1;
      }

      // A drop next to the dragged tab itself would not move it.
      bool isNoOp(_TabDragData data, int slot) {
        if (data.fromRightPane != isRightPane) return false;
        final list = isRightPane ? _rightTabs : _tabs;
        final from = list.indexWhere((c) => c.id == data.connection.id);
        return slot == from || slot == from + 1;
      }

      return DragTarget<_TabDragData>(
        onMove: (details) {
          final slot = slotFor(details.offset);
          final next = isNoOp(details.data, slot)
              ? null
              : (isRightPane: isRightPane, index: slot);
          if (_tabDropSlot != next) setState(() => _tabDropSlot = next);
        },
        onLeave: (_) {
          if (_tabDropSlot != null) setState(() => _tabDropSlot = null);
        },
        onAcceptWithDetails: (details) {
          final slot = slotFor(details.offset);
          if (isNoOp(details.data, slot)) {
            setState(() => _tabDropSlot = null);
            return;
          }
          _moveTabToSlot(details.data.connection, toRightPane: isRightPane, toIndex: slot);
        },
        builder: (context, candidateData, rejectedData) {
          // One bar per gap: tabs draw it on their left edge, the last tab
          // also on its right edge for the end gap; the strip itself draws
          // it only when the pane has no tabs.
          final slot = _tabDropSlot;
          final paneLength = (isRightPane ? _rightTabs : _tabs).length;
          if (slot == null || slot.isRightPane != isRightPane) return child;
          final atLeftEdge = splitHalves ? slot.index == index : paneLength == 0;
          final atRightEdge =
              splitHalves && slot.index == index + 1 && index + 1 == paneLength;
          if (!atLeftEdge && !atRightEdge) return child;
          return Stack(
            children: [
              child,
              Positioned(
                key: const ValueKey('nexus_tab_drop_indicator'),
                top: 4,
                bottom: 4,
                left: atRightEdge ? null : 0,
                right: atRightEdge ? 0 : null,
                width: 2,
                child: ColoredBox(color: AppTheme.activePalette.primaryColor),
              ),
            ],
          );
        },
      );
    });
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
              color: AppTheme.dimText(0.7),
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
}
