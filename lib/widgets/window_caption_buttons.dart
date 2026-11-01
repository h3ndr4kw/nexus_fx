import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/window_state_service.dart';
import '../theme/app_theme.dart';

/// A set of desktop window controls (fullscreen, minimize, maximize/restore, close)
/// with customizable spacing and hover effects matching the Smart-E dark theme.
class WindowCaptionButtons extends StatefulWidget {
  final double spacing;
  final double buttonWidth;
  final double buttonHeight;
  final bool showFullScreen;

  const WindowCaptionButtons({
    super.key,
    this.spacing = 8.0,
    this.buttonWidth = 32.0,
    this.buttonHeight = 28.0,
    this.showFullScreen = false,
  });

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons> {
  final WindowStateService _windowState = WindowStateService.instance;

  @override
  void initState() {
    super.initState();
    _windowState.addListener(_onWindowStateChanged);
    _windowState.checkWindowState();
  }

  @override
  void dispose() {
    _windowState.removeListener(_onWindowStateChanged);
    super.dispose();
  }

  void _onWindowStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return const SizedBox.shrink();
    }

    final isFullScreen = _windowState.isFullScreen;
    final isMaximized = _windowState.isMaximized;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showFullScreen) ...[
          _WindowCaptionButton(
            tooltip: isFullScreen ? 'Exit Full Screen (F11)' : 'Full Screen (F11)',
            icon: isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
            iconSize: 18,
            width: widget.buttonWidth,
            height: widget.buttonHeight,
            onPressed: _windowState.toggleFullScreen,
          ),
          SizedBox(width: widget.spacing),
          Container(
            width: 1,
            height: 16,
            color: AppTheme.inputBorderColor.withValues(alpha: 0.7),
          ),
          SizedBox(width: widget.spacing),
        ],
        _WindowCaptionButton(
          tooltip: 'Minimize',
          icon: Icons.remove,
          iconSize: 14,
          width: widget.buttonWidth,
          height: widget.buttonHeight,
          onPressed: _windowState.minimize,
        ),
        SizedBox(width: widget.spacing),
        _WindowCaptionButton(
          tooltip: isMaximized ? 'Restore' : 'Maximize',
          icon: isMaximized ? Icons.filter_none_outlined : Icons.crop_square,
          iconSize: 12,
          width: widget.buttonWidth,
          height: widget.buttonHeight,
          onPressed: _windowState.toggleMaximize,
        ),
        SizedBox(width: widget.spacing),
        _WindowCaptionButton(
          tooltip: 'Close',
          icon: Icons.close,
          iconSize: 14,
          width: widget.buttonWidth,
          height: widget.buttonHeight,
          isClose: true,
          onPressed: _windowState.close,
        ),
      ],
    );
  }
}

class _WindowCaptionButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final double width;
  final double height;
  final bool isClose;
  final VoidCallback onPressed;

  const _WindowCaptionButton({
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    required this.width,
    required this.height,
    this.isClose = false,
    required this.onPressed,
  });

  @override
  State<_WindowCaptionButton> createState() => _WindowCaptionButtonState();
}

class _WindowCaptionButtonState extends State<_WindowCaptionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBgColor = widget.isClose
        ? const Color(0xFFC42B1C)
        : Colors.white.withValues(alpha: 0.1);

    final defaultIconColor = widget.isClose
        ? AppTheme.textColor.withValues(alpha: 0.8)
        : AppTheme.textColor;

    final iconColor = _isHovered
        ? Colors.white
        : defaultIconColor;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: _isHovered ? hoverBgColor : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
