import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// A modal dialog container with a draggable desktop-style title bar.
///
/// Holding left click on the title bar allows moving the dialog anywhere on screen.
class DraggableDialog extends StatefulWidget {
  final Widget child;
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onClose;
  final List<Widget>? actions;
  final double maxWidth;
  final double maxHeight;
  final double minWidth;
  final double minHeight;

  const DraggableDialog({
    super.key,
    required this.child,
    required this.title,
    this.icon,
    this.iconColor,
    this.onClose,
    this.actions,
    this.maxWidth = 950,
    this.maxHeight = 650,
    this.minWidth = 700,
    this.minHeight = 500,
  });

  @override
  State<DraggableDialog> createState() => _DraggableDialogState();
}

class _DraggableDialogState extends State<DraggableDialog> {
  Offset _offset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Transform.translate(
        offset: _offset,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.maxWidth,
            maxHeight: widget.maxHeight,
            minWidth: widget.minWidth,
            minHeight: widget.minHeight,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderSubtle),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _headerFocused = false;

  /// Alt+arrows nudge the dialog (Alt+Shift for bigger steps) and Alt+Home puts
  /// it back, so repositioning does not need a mouse. Alt is required because
  /// the content (e.g. the sessions list) uses plain arrows and Home itself, and
  /// the title bar can hold focus when the dialog opens.
  KeyEventResult _onHeaderKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus ||
        event is KeyUpEvent ||
        !HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 64.0 : 16.0;
    final key = event.logicalKey;
    Offset? delta;
    if (key == LogicalKeyboardKey.arrowLeft) delta = Offset(-step, 0);
    if (key == LogicalKeyboardKey.arrowRight) delta = Offset(step, 0);
    if (key == LogicalKeyboardKey.arrowUp) delta = Offset(0, -step);
    if (key == LogicalKeyboardKey.arrowDown) delta = Offset(0, step);
    if (delta != null) {
      setState(() => _offset += delta!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => _offset = Offset.zero);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildHeader() {
    return Semantics(
      label: '${widget.title} title bar',
      hint: 'Alt plus arrow keys move the dialog, Alt plus Home resets its position',
      child: Focus(
        onFocusChange: (f) => setState(() => _headerFocused = f),
        onKeyEvent: _onHeaderKey,
        child: _buildHeaderBar(),
      ),
    );
  }

  Widget _buildHeaderBar() {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            _offset += details.delta;
          });
        },
        onDoubleTap: () {
          setState(() {
            _offset = Offset.zero;
          });
        },
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceSecondary,
            border: Border(
              bottom: BorderSide(
                color: _headerFocused
                    ? AppTheme.accentPrimary
                    : AppTheme.borderSubtle,
                width: _headerFocused ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.iconColor ?? AppTheme.accentPrimary,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (widget.actions != null) ...widget.actions!,
              IconButton(
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                tooltip: 'Close',
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
