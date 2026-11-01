import 'package:flutter/material.dart';
import '../services/window_state_service.dart';
import '../theme/app_theme.dart';

/// A vector icon representing the left sidebar toggle matching the layout panel design.
/// - When [isVisible] is false: renders an outline/hollow sidebar icon.
/// - When [isVisible] is true: renders an icon with the left sidebar filled.
class SidebarIcon extends StatelessWidget {
  final bool isVisible;
  final double size;
  final Color? color;
  final double strokeWidth;

  const SidebarIcon({
    super.key,
    this.isVisible = true,
    this.size = 16.0,
    this.color,
    this.strokeWidth = 1.4,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? IconTheme.of(context).color ?? AppTheme.textColor;
    return CustomPaint(
      size: Size(size, size),
      painter: SidebarIconPainter(
        isVisible: isVisible,
        color: effectiveColor,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class SidebarIconPainter extends CustomPainter {
  final bool isVisible;
  final Color color;
  final double strokeWidth;

  const SidebarIconPainter({
    required this.isVisible,
    required this.color,
    this.strokeWidth = 1.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 16.0, size.height / 16.0);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Outer rounded rectangle (matches codicon 16x16 geometry)
    final outerRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(1.0, 1.0, 14.0, 14.0),
      const Radius.circular(2.5),
    );

    // Right pane cutout: x=7 to 14, y=2 to 14 (top-right & bottom-right rounded by 1.5)
    final rightCutout = RRect.fromRectAndCorners(
      const Rect.fromLTWH(7.0, 2.0, 7.0, 12.0),
      topRight: const Radius.circular(1.5),
      bottomRight: const Radius.circular(1.5),
    );

    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outerRRect)
      ..addRRect(rightCutout);

    // If sidebar is NOT visible (off / closed state), the left sidebar is also cutout/hollow
    if (!isVisible) {
      final leftCutout = RRect.fromRectAndCorners(
        const Rect.fromLTWH(2.0, 2.0, 4.0, 12.0),
        topLeft: const Radius.circular(1.5),
        bottomLeft: const Radius.circular(1.5),
      );
      path.addRRect(leftCutout);
    }

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SidebarIconPainter oldDelegate) {
    return oldDelegate.isVisible != isVisible ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// A desktop button widget that toggles the left sidebar with hover animation and tooltip,
/// matching desktop window caption controls.
class SidebarToggleButton extends StatefulWidget {
  final bool isSidebarVisible;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double iconSize;
  final String? tooltip;

  const SidebarToggleButton({
    super.key,
    required this.isSidebarVisible,
    required this.onTap,
    this.width = 32.0,
    this.height = 28.0,
    this.iconSize = 16.0,
    this.tooltip,
  });

  @override
  State<SidebarToggleButton> createState() => _SidebarToggleButtonState();
}

class _SidebarToggleButtonState extends State<SidebarToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveTooltip = widget.tooltip ??
        (widget.isSidebarVisible
            ? 'Hide Sidebar (Ctrl+B)'
            : 'Show Sidebar (Ctrl+B)');

    final iconColor = _isHovered ? Colors.white : AppTheme.textColor;

    return Tooltip(
      message: effectiveTooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: SidebarIcon(
                isVisible: widget.isSidebarVisible,
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

/// A vector icon representing the right sidebar toggle matching the layout panel design.
/// - When [isVisible] is false: renders an outline/hollow right sidebar icon.
/// - When [isVisible] is true: renders an icon with the right sidebar filled.
class RightSidebarIcon extends StatelessWidget {
  final bool isVisible;
  final double size;
  final Color? color;
  final double strokeWidth;

  const RightSidebarIcon({
    super.key,
    this.isVisible = true,
    this.size = 16.0,
    this.color,
    this.strokeWidth = 1.4,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? IconTheme.of(context).color ?? AppTheme.textColor;
    return CustomPaint(
      size: Size(size, size),
      painter: RightSidebarIconPainter(
        isVisible: isVisible,
        color: effectiveColor,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class RightSidebarIconPainter extends CustomPainter {
  final bool isVisible;
  final Color color;
  final double strokeWidth;

  const RightSidebarIconPainter({
    required this.isVisible,
    required this.color,
    this.strokeWidth = 1.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 16.0, size.height / 16.0);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Outer rounded rectangle (matches codicon 16x16 geometry)
    final outerRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(1.0, 1.0, 14.0, 14.0),
      const Radius.circular(2.5),
    );

    // Left pane cutout: x=2 to 9, y=2 to 14 (top-left & bottom-left rounded by 1.5)
    final leftCutout = RRect.fromRectAndCorners(
      const Rect.fromLTWH(2.0, 2.0, 7.0, 12.0),
      topLeft: const Radius.circular(1.5),
      bottomLeft: const Radius.circular(1.5),
    );

    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outerRRect)
      ..addRRect(leftCutout);

    // If right sidebar is NOT visible (off / closed state), the right sidebar is also cutout/hollow
    if (!isVisible) {
      final rightCutout = RRect.fromRectAndCorners(
        const Rect.fromLTWH(10.0, 2.0, 4.0, 12.0),
        topRight: const Radius.circular(1.5),
        bottomRight: const Radius.circular(1.5),
      );
      path.addRRect(rightCutout);
    }

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RightSidebarIconPainter oldDelegate) {
    return oldDelegate.isVisible != isVisible ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// A desktop button widget that toggles the right sidebar with hover animation and tooltip.
class RightSidebarToggleButton extends StatefulWidget {
  final bool isSidebarVisible;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double iconSize;
  final String? tooltip;

  const RightSidebarToggleButton({
    super.key,
    required this.isSidebarVisible,
    required this.onTap,
    this.width = 32.0,
    this.height = 28.0,
    this.iconSize = 16.0,
    this.tooltip,
  });

  @override
  State<RightSidebarToggleButton> createState() =>
      _RightSidebarToggleButtonState();
}

class _RightSidebarToggleButtonState extends State<RightSidebarToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveTooltip =
        widget.tooltip ?? 'Toggle Runbook Sidebar (Ctrl+Shift+B)';
    final iconColor = _isHovered ? Colors.white : AppTheme.textColor;

    return Tooltip(
      message: effectiveTooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: RightSidebarIcon(
                isVisible: widget.isSidebarVisible,
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

/// A vector icon representing fullscreen toggle matching smart_e_he design.
/// - When [isFullScreen] is false: renders Icons.fullscreen (expand).
/// - When [isFullScreen] is true: renders Icons.fullscreen_exit (contract / unmaximize / exit fullscreen).
class FullscreenIcon extends StatelessWidget {
  final bool isFullScreen;
  final double size;
  final Color? color;
  final double strokeWidth;

  const FullscreenIcon({
    super.key,
    this.isFullScreen = false,
    this.size = 18.0,
    this.color,
    this.strokeWidth = 1.4,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        (isFullScreen
            ? (IconTheme.of(context).color ?? AppTheme.textPrimary)
            : AppTheme.textSecondary);
    return Icon(
      isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
      size: size,
      color: effectiveColor,
    );
  }
}

class FullscreenIconPainter extends CustomPainter {
  final bool isFullScreen;
  final Color color;
  final double strokeWidth;

  const FullscreenIconPainter({
    required this.isFullScreen,
    required this.color,
    this.strokeWidth = 1.4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final halfStroke = strokeWidth / 2.0;
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;

    if (!isFullScreen) {
      // Outward corner brackets (expand to fullscreen, matching user image)
      final armW = w * 0.30;
      final armH = h * 0.30;

      // Top-Left corner
      final tlPath = Path()
        ..moveTo(halfStroke, halfStroke + armH)
        ..lineTo(halfStroke, halfStroke)
        ..lineTo(halfStroke + armW, halfStroke);
      canvas.drawPath(tlPath, paint);

      // Top-Right corner
      final trPath = Path()
        ..moveTo(w - halfStroke - armW, halfStroke)
        ..lineTo(w - halfStroke, halfStroke)
        ..lineTo(w - halfStroke, halfStroke + armH);
      canvas.drawPath(trPath, paint);

      // Bottom-Left corner
      final blPath = Path()
        ..moveTo(halfStroke, h - halfStroke - armH)
        ..lineTo(halfStroke, h - halfStroke)
        ..lineTo(halfStroke + armW, h - halfStroke);
      canvas.drawPath(blPath, paint);

      // Bottom-Right corner
      final brPath = Path()
        ..moveTo(w - halfStroke - armW, h - halfStroke)
        ..lineTo(w - halfStroke, h - halfStroke)
        ..lineTo(w - halfStroke, h - halfStroke - armH);
      canvas.drawPath(brPath, paint);
    } else {
      // Inward corner brackets (contract / unfullscreen)
      final midW = w * 0.36;
      final midH = h * 0.36;

      // Top-Left inward
      final tlPath = Path()
        ..moveTo(halfStroke, halfStroke + midH)
        ..lineTo(halfStroke + midW, halfStroke + midH)
        ..lineTo(halfStroke + midW, halfStroke);
      canvas.drawPath(tlPath, paint);

      // Top-Right inward
      final trPath = Path()
        ..moveTo(w - halfStroke - midW, halfStroke)
        ..lineTo(w - halfStroke - midW, halfStroke + midH)
        ..lineTo(w - halfStroke, halfStroke + midH);
      canvas.drawPath(trPath, paint);

      // Bottom-Left inward
      final blPath = Path()
        ..moveTo(halfStroke, h - halfStroke - midH)
        ..lineTo(halfStroke + midW, h - halfStroke - midH)
        ..lineTo(halfStroke + midW, h - halfStroke);
      canvas.drawPath(blPath, paint);

      // Bottom-Right inward
      final brPath = Path()
        ..moveTo(w - halfStroke - midW, h - halfStroke)
        ..lineTo(w - halfStroke - midW, h - halfStroke - midH)
        ..lineTo(w - halfStroke, h - halfStroke - midH);
      canvas.drawPath(brPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FullscreenIconPainter oldDelegate) {
    return oldDelegate.isFullScreen != isFullScreen ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// A desktop button widget that toggles fullscreen with hover animation, tooltip,
/// and automatic synchronization with [WindowStateService].
class FullscreenToggleButton extends StatefulWidget {
  final bool? isFullScreen;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final double iconSize;
  final String? tooltip;

  const FullscreenToggleButton({
    super.key,
    this.isFullScreen,
    this.onTap,
    this.width = 32.0,
    this.height = 28.0,
    this.iconSize = 18.0,
    this.tooltip,
  });

  @override
  State<FullscreenToggleButton> createState() => _FullscreenToggleButtonState();
}

class _FullscreenToggleButtonState extends State<FullscreenToggleButton> {
  bool _isHovered = false;
  final WindowStateService _windowState = WindowStateService.instance;

  @override
  void initState() {
    super.initState();
    _windowState.addListener(_onWindowStateChanged);
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
    final effectiveIsFullScreen =
        widget.isFullScreen ?? _windowState.isFullScreen;
    final effectiveTooltip = widget.tooltip ??
        (effectiveIsFullScreen
            ? 'Exit Full Screen (F11)'
            : 'Full Screen (F11)');

    final iconColor = _isHovered
        ? Colors.white
        : (effectiveIsFullScreen
            ? AppTheme.textPrimary
            : AppTheme.textSecondary);

    return Tooltip(
      message: effectiveTooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap ?? _windowState.toggleFullScreen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: FullscreenIcon(
                isFullScreen: effectiveIsFullScreen,
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
