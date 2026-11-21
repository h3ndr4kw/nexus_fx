// Private members of NexusScreenState live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'nexus_screen.dart';

/// Running runbook script cells on terminal sessions, with the progress dialog.
extension _NexusRunbookExecution on NexusScreenState {
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
        } catch (e, st) {
          AppLog.warning('Runbook: target not connected after waiting, running anyway', e, st);
        }
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
}
