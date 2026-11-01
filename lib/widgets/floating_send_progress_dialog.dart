import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Floating card dialog showing execution progress of runbook commands being sent to a target node.
class FloatingSendProgressDialog extends StatefulWidget {
  final String targetNode;
  final int currentLineIndex;
  final int totalLines;
  final String currentCommand;
  final bool isCompleted;
  final String? errorMessage;
  final bool autoClose;
  final Duration autoCloseDuration;
  final VoidCallback onCancel;
  final VoidCallback? onClose;

  const FloatingSendProgressDialog({
    super.key,
    required this.targetNode,
    required this.currentLineIndex,
    required this.totalLines,
    required this.currentCommand,
    this.isCompleted = false,
    this.errorMessage,
    this.autoClose = true,
    this.autoCloseDuration = const Duration(seconds: 2),
    required this.onCancel,
    this.onClose,
  });

  @override
  State<FloatingSendProgressDialog> createState() => _FloatingSendProgressDialogState();
}

class _FloatingSendProgressDialogState extends State<FloatingSendProgressDialog> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'FloatingSendProgressDialog');
  Timer? _autoCloseTimer;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
    if (widget.isCompleted && widget.errorMessage == null && widget.autoClose) {
      _startAutoCloseTimer();
    }
  }

  @override
  void didUpdateWidget(FloatingSendProgressDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.isCompleted && !oldWidget.isCompleted) ||
        (widget.errorMessage != null && oldWidget.errorMessage == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }

    if (widget.isCompleted &&
        widget.errorMessage == null &&
        widget.autoClose) {
      if (!oldWidget.isCompleted || !oldWidget.autoClose || _autoCloseTimer == null) {
        _startAutoCloseTimer();
      }
    } else if (!widget.isCompleted || widget.errorMessage != null || !widget.autoClose) {
      _cancelAutoCloseTimer();
    }
  }

  void _startAutoCloseTimer() {
    _cancelAutoCloseTimer();
    if (!widget.autoClose || !widget.isCompleted || widget.errorMessage != null) {
      return;
    }

    final totalSeconds = widget.autoCloseDuration.inSeconds;
    if (widget.autoCloseDuration <= Duration.zero) {
      (widget.onClose ?? widget.onCancel)();
      return;
    }

    setState(() {
      _remainingSeconds = totalSeconds > 0 ? totalSeconds : 1;
    });

    if (totalSeconds > 1) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_remainingSeconds > 1) {
          setState(() {
            _remainingSeconds--;
          });
        } else {
          timer.cancel();
        }
      });
    }

    _autoCloseTimer = Timer(widget.autoCloseDuration, () {
      if (mounted) {
        (widget.onClose ?? widget.onCancel)();
      }
    });
  }

  void _cancelAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  @override
  void dispose() {
    _cancelAutoCloseTimer();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }

    final isDismissKey = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.space;

    if (widget.isCompleted || widget.errorMessage != null) {
      if (isDismissKey) {
        _cancelAutoCloseTimer();
        (widget.onClose ?? widget.onCancel)();
        return KeyEventResult.handled;
      }
    } else {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelAutoCloseTimer();
        widget.onCancel();
        return KeyEventResult.handled;
      }
    }

    // Always intercept key presses while the dialog is visible
    // so no keystrokes leak to the background terminal.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.activePalette;
    final progress = widget.totalLines > 0
        ? (widget.currentLineIndex / widget.totalLines).clamp(0.0, 1.0)
        : 0.0;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // Prevent taps inside dialog from reaching backdrop scrim
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 440,
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: palette.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: palette.inputBorderColor,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: Target node badge with terminal icon
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: palette.primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: palette.primaryColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.terminal,
                                size: 14,
                                color: palette.primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  widget.targetNode,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: palette.primaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: widget.isCompleted ? 1.0 : progress,
                      minHeight: 6,
                      backgroundColor: palette.background,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.errorMessage != null
                            ? palette.errorColor
                            : (widget.isCompleted
                                ? palette.successColor
                                : palette.primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Actions
                  _buildActions(context, palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, AppPalette palette) {
    if (widget.errorMessage != null) {
      return Row(
        children: [
          Icon(
            Icons.error_outline,
            color: palette.errorColor,
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.errorMessage!,
              style: TextStyle(
                color: palette.errorColor,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () {
              _cancelAutoCloseTimer();
              (widget.onClose ?? widget.onCancel)();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              side: BorderSide(color: palette.inputBorderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              'Close',
              style: TextStyle(
                color: palette.textColor,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    }

    if (widget.isCompleted) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                color: palette.successColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Execution Completed',
                style: TextStyle(
                  color: palette.successColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              if (widget.autoClose && _remainingSeconds > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '(${_remainingSeconds}s)',
                  style: TextStyle(
                    color: palette.textColor.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          OutlinedButton(
            onPressed: () {
              _cancelAutoCloseTimer();
              (widget.onClose ?? widget.onCancel)();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              side: BorderSide(
                color: palette.successColor.withValues(alpha: 0.5),
              ),
              backgroundColor: palette.successColor.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              'Close',
              style: TextStyle(
                color: palette.successColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () {
            _cancelAutoCloseTimer();
            widget.onCancel();
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            side: BorderSide(color: palette.inputBorderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: palette.textColor,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
