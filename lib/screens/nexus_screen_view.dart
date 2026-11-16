// Private members of NexusScreenState live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'nexus_screen.dart';

/// Layout builders: right sidebar, terminal main area and the empty state.
extension _NexusScreenView on NexusScreenState {
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

  /// One pane's terminals. Each [SshTabView] is built only here, keyed by its
  /// connection, so switching layouts reparents it instead of remounting.
  Widget _buildPaneStack({required bool isRightPane}) {
    final tabs = isRightPane ? _rightTabs : _tabs;
    final active = isRightPane ? _activeRightTab : _activeTab;
    return IndexedStack(
      index: active.clamp(0, tabs.isNotEmpty ? tabs.length - 1 : 0),
      children: [
        for (int i = 0; i < tabs.length; i++)
          SshTabView(
            key: GlobalObjectKey(tabs[i]),
            connection: tabs[i],
            isActive: isRightPane
                ? _lastActivePaneIsRight && i == _activeRightTab
                : (!_isSplitView || !_lastActivePaneIsRight) && i == _activeTab,
            onFocus: () => _lastActivePaneIsRight = isRightPane,
            onClose: () => _closeTab(i, isRightPane: isRightPane),
            bottomInset: _showCommandPane ? 68.0 : 0.0,
            isFullscreen: identical(_fullscreen.target, tabs[i]),
            onToggleFullscreen: () => toggleSessionFullscreen(tabs[i]),
          ),
      ],
    );
  }

  Widget _buildCommandPaneOverlay() {
    return ListenableBuilder(
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildFloatingCommandPane(),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Only the fullscreen session is visible. The other pane stays mounted
  /// offstage so its terminals keep their state.
  Widget _buildFullscreenArea(SshConnection target) {
    final targetIsRight = _rightTabs.contains(target);
    Widget pane(bool isRightPane) {
      final hidden = isRightPane != targetIsRight;
      return Positioned.fill(
        child: Offstage(
          offstage: hidden,
          child: ExcludeFocus(
            excluding: hidden,
            child: _buildPaneStack(isRightPane: isRightPane),
          ),
        ),
      );
    }

    return Stack(
      children: [
        if (_tabs.isNotEmpty) pane(false),
        if (_rightTabs.isNotEmpty) pane(true),
        if (_showCommandPane) _buildCommandPaneOverlay(),
        Positioned.fill(
          child: SessionFullscreenOverlay(
            key: ObjectKey(target),
            label: target.currentLabel,
            onExit: exitSessionFullscreen,
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalMainArea() {
    final fullscreenTarget = _fullscreen.target;
    if (fullscreenTarget != null) {
      return _buildFullscreenArea(fullscreenTarget);
    }
    if (_tabs.isEmpty && _rightTabs.isEmpty) {
      return Stack(
        children: [
          Positioned.fill(
            child: _buildEmptyState(),
          ),
          if (_showCommandPane) _buildCommandPaneOverlay(),
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
                          _buildFullscreenButton(),
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
                    _buildFullscreenButton(),
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
                  'PRODUCTION ENVIRONMENT: EXECUTE COMMANDS WITH CAUTION',
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
                    // Left Terminal Pane: accepts drops from right pane
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
                                : _buildPaneStack(isRightPane: false);
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
                    // Right Terminal Pane: accepts drops from left pane
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
                                : _buildPaneStack(isRightPane: true);
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
              // Single pane mode: show drop target on right half when dragging
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final terminalContent =
                        _buildPaneStack(isRightPane: false);

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
              if (_showCommandPane) _buildCommandPaneOverlay(),
            ],
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
