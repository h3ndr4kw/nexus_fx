part of 'interactive_runbook_sidebar.dart';

// Small hover-aware buttons used in the sidebar chrome.

class _SidebarToolbarButton extends StatefulWidget {
  final AppPalette palette;
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final bool isDanger;

  const _SidebarToolbarButton({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.icon,
    this.iconSize = 14.5,
    this.onPressed,
    this.iconColor,
    this.isDanger = false,
  });

  @override
  State<_SidebarToolbarButton> createState() => _SidebarToolbarButtonState();
}

class _SidebarToolbarButtonState extends State<_SidebarToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    final Color effectiveIdleColor = widget.iconColor ??
        (widget.isDanger && enabled
            ? widget.palette.dimText(0.72)
            : widget.palette.textColor.withValues(alpha: enabled ? 0.72 : 0.28));

    final Color hoverColor = widget.isDanger
        ? widget.palette.errorColor
        : AppTheme.ink;

    final Color hoverBgColor = widget.isDanger
        ? widget.palette.errorColor.withValues(alpha: 0.18)
        : AppTheme.ink.withValues(alpha: 0.1);

    final displayIconColor = enabled
        ? (_isHovered ? hoverColor : effectiveIdleColor)
        : effectiveIdleColor;

    return IconButton(
      tooltip: widget.tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      visualDensity: VisualDensity.compact,
      splashRadius: 13,
      hoverColor: hoverBgColor,
      highlightColor: Colors.transparent,
      style: IconButton.styleFrom(
        minimumSize: const Size(22, 22),
        fixedSize: const Size(24, 24),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      icon: MouseRegion(
        onEnter: (_) {
          if (enabled) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (enabled) setState(() => _isHovered = false);
        },
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: displayIconColor,
        ),
      ),
      onPressed: widget.onPressed,
    );
  }
}

/// A desktop window-style close button for the sidebar title bar,
/// matching [WindowCaptionButtons] styling and hover behavior.
class _SidebarCaptionCloseButton extends StatefulWidget {
  final AppPalette palette;
  final String tooltip;
  final VoidCallback? onPressed;

  const _SidebarCaptionCloseButton({
    required this.palette,
    required this.tooltip,
    this.onPressed,
  });

  @override
  State<_SidebarCaptionCloseButton> createState() =>
      _SidebarCaptionCloseButtonState();
}

class _SidebarCaptionCloseButtonState
    extends State<_SidebarCaptionCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        splashRadius: 14,
        hoverColor: const Color(0xFFC42B1C),
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        icon: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Icon(
            Icons.close,
            size: 14,
            color: _isHovered
                ? AppTheme.ink
                : widget.palette.dimText(0.7),
          ),
        ),
        onPressed: widget.onPressed,
      ),
    );
  }
}

/// A compact close button for document tab headers with subtle hover effect.
class _SidebarTabCloseButton extends StatefulWidget {
  final AppPalette palette;
  final String tooltip;
  final VoidCallback? onPressed;

  const _SidebarTabCloseButton({
    required this.palette,
    required this.tooltip,
    this.onPressed,
  });

  @override
  State<_SidebarTabCloseButton> createState() => _SidebarTabCloseButtonState();
}

class _SidebarTabCloseButtonState extends State<_SidebarTabCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: widget.tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      splashRadius: 12,
      hoverColor: AppTheme.ink.withValues(alpha: 0.12),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      icon: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Icon(
          Icons.close,
          size: 13,
          color: _isHovered
              ? AppTheme.ink
              : widget.palette.dimText(0.7),
        ),
      ),
      onPressed: widget.onPressed,
    );
  }
}
