import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Exit affordances drawn over a fullscreen terminal: a short hint on entry
/// and a bar that appears while the pointer is at the top edge.
///
/// Place it as a [Positioned.fill] child above the terminal. Only the top-edge
/// hot zone and the bar take pointer events; the rest passes through.
class SessionFullscreenOverlay extends StatefulWidget {
  final String label;
  final VoidCallback onExit;

  const SessionFullscreenOverlay({
    super.key,
    required this.label,
    required this.onExit,
  });

  @override
  State<SessionFullscreenOverlay> createState() =>
      _SessionFullscreenOverlayState();
}

class _SessionFullscreenOverlayState extends State<SessionFullscreenOverlay> {
  static const _hintDuration = Duration(seconds: 2);
  static const _barHideDelay = Duration(milliseconds: 1500);
  static const _hotZoneHeight = 6.0;

  bool _showHint = true;
  bool _showBar = false;
  Timer? _hintTimer;
  Timer? _barTimer;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(_hintDuration, () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _barTimer?.cancel();
    super.dispose();
  }

  void _revealBar() {
    _barTimer?.cancel();
    if (!_showBar) setState(() => _showBar = true);
  }

  void _scheduleBarHide() {
    _barTimer?.cancel();
    _barTimer = Timer(_barHideDelay, () {
      if (mounted) setState(() => _showBar = false);
    });
  }

  Duration _fade(BuildContext context) => AppMotion.reduced(context)
      ? Duration.zero
      : const Duration(milliseconds: 150);

  Widget _pill({required Widget child, Key? key}) {
    final p = AppTheme.activePalette;
    return Material(
      key: key,
      color: p.surfaceColor.withValues(alpha: 0.95),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: p.inputBorderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.activePalette;
    final fade = _fade(context);
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _hotZoneHeight,
          child: MouseRegion(
            onEnter: (_) => _revealBar(),
            onExit: (_) => _scheduleBarHide(),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                duration: fade,
                child: _showHint
                    ? _pill(
                        key: const ValueKey('session_fullscreen_hint'),
                        child: Text(
                          'Press Ctrl+Shift+Enter to exit fullscreen',
                          style: TextStyle(fontSize: 12, color: p.textColor),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 16,
          right: 16,
          child: Center(
            child: AnimatedSwitcher(
              duration: fade,
              child: _showBar
                  ? MouseRegion(
                      key: const ValueKey('session_fullscreen_bar'),
                      onEnter: (_) => _revealBar(),
                      onExit: (_) => _scheduleBarHide(),
                      child: _pill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: p.textColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              onPressed: widget.onExit,
                              icon: const Icon(Icons.fullscreen_exit, size: 16),
                              label: const Text('Exit fullscreen',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ctrl+Shift+Enter',
                              style: TextStyle(
                                fontSize: 11,
                                color: p.dimText(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
