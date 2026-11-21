import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../theme/app_theme.dart';

// Shared look for the quick pickers (Nexus command palette, File Explorer
// node picker): a top-anchored card with a borderless search header, an ESC
// keycap, fixed-height rows with a left accent bar, and outlined badges.

/// Badge colors for session kinds, shared by the pickers.
class PaletteColors {
  static const Color local = Color(0xFF64B5F6);
  static const Color ssh = Color(0xFFFF7043);
  static const Color web = Color(0xFF4DB6AC);
}

/// Top-anchored card holding a [PaletteSearchHeader], a list and an optional
/// [footer].
class PaletteFrame extends StatelessWidget {
  final Widget header;
  final Widget body;
  final Widget? footer;
  final double width;
  final double maxBodyHeight;

  const PaletteFrame({
    super.key,
    required this.header,
    required this.body,
    this.footer,
    this.width = 620,
    this.maxBodyHeight = 380,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      alignment: Alignment.topCenter,
      child: Container(
        width: width,
        margin: const EdgeInsets.only(top: 60),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxBodyHeight),
              child: body,
            ),
            if (footer != null) ...[
              const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Search icon, borderless text field and an ESC keycap that calls [onClose].
/// Arrow/enter/escape handling belongs on [focusNode].
class PaletteSearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClose;

  const PaletteSearchHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onClose,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: AppTheme.accentPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(fontSize: 14, color: AppTheme.textMuted),
                // Theme sets enabled/focused outlines; the card is the field,
                // so suppress every state.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          const SizedBox(width: 12),
          PaletteEscKeycap(onTap: onClose),
        ],
      ),
    );
  }
}

class PaletteEscKeycap extends StatelessWidget {
  final VoidCallback onTap;

  const PaletteEscKeycap({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close',
      child: InkWell(
        onTap: onTap,
        // The Esc key does the same; keep Tab on the dialog's own controls.
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceSecondary,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.inputOutline),
          ),
          child: const Text(
            'ESC',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class PaletteBadge extends StatelessWidget {
  final String text;
  final Color color;

  /// Makes the badge its own click target, separate from the row.
  final VoidCallback? onTap;
  final String? tooltip;
  final bool enabled;

  const PaletteBadge({
    super.key,
    required this.text,
    required this.color,
    this.onTap,
    this.tooltip,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget badge = _buildBox(enabled ? color : AppTheme.textMuted);
    if (onTap != null) {
      // A disabled badge still swallows the tap so it doesn't fall through
      // to the row's own action.
      badge = MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(onTap: enabled ? onTap : () {}, child: badge),
      );
    }
    if (tooltip != null) {
      badge = Tooltip(message: tooltip!, child: badge);
    }
    return badge;
  }

  Widget _buildBox(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

/// One fixed-height row: icon box, title + subtitle, then [trailing].
/// Use with `ListView.builder(itemExtent: PaletteRow.extent)`.
class PaletteRow extends StatelessWidget {
  /// Row height including its bottom divider.
  static const double extent = 53;

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final List<Widget> trailing;

  const PaletteRow({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    const accent = AppTheme.accentPrimary;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.08) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? accent : Colors.transparent,
              width: 3,
            ),
            bottom: const BorderSide(color: AppTheme.borderSubtle),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(13, 0, 16, 0),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.15)
                    : AppTheme.bgSurfaceSecondary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? accent.withValues(alpha: 0.35) : AppTheme.borderSubtle,
                ),
              ),
              child: Icon(
                icon,
                size: 16,
                color: isSelected ? accent : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? accent : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            for (final w in trailing) ...[const SizedBox(width: 8), w],
          ],
        ),
      ),
    );
  }
}

/// Right-click menu in the palette look: a bordered card with a soft shadow,
/// [PaletteMenuItem] rows and [PaletteMenuDivider] separators.
Future<T?> showPaletteMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<PopupMenuEntry<T>> items,
}) {
  return showMenu<T>(
    context: context,
    popUpAnimationStyle: AnimationStyle.noAnimation,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
    color: AppTheme.bgSurface,
    surfaceTintColor: Colors.transparent,
    elevation: 16,
    shadowColor: Colors.black,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: AppTheme.borderSubtle),
    ),
    clipBehavior: Clip.antiAlias,
    menuPadding: const EdgeInsets.symmetric(vertical: 6),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 380),
    items: items,
  );
}

class PaletteMenuDivider extends PopupMenuDivider {
  const PaletteMenuDivider({super.key}) : super(height: 9, color: AppTheme.borderSubtle);
}

/// A [showPaletteMenu] row: icon box, label, optional shortcut keycap. Hover
/// and keyboard focus both show the palette's accent bar and tint.
class PaletteMenuItem<T> extends PopupMenuEntry<T> {
  final T value;
  final IconData icon;
  final String label;
  final String? shortcut;
  final Color iconColor;

  /// Overrides the label color, e.g. for destructive actions.
  final Color? labelColor;
  final bool enabled;

  const PaletteMenuItem({
    super.key,
    required this.value,
    required this.icon,
    required this.label,
    this.shortcut,
    this.iconColor = AppTheme.textSecondary,
    this.labelColor,
    this.enabled = true,
  });

  @override
  double get height => 34;

  @override
  bool represents(T? value) => false;

  @override
  State<PaletteMenuItem<T>> createState() => _PaletteMenuItemState<T>();
}

class _PaletteMenuItemState<T> extends State<PaletteMenuItem<T>> {
  bool _hovered = false;
  bool _focused = false;

  void _select() => Navigator.pop<T>(context, widget.value);

  @override
  Widget build(BuildContext context) {
    const accent = AppTheme.accentPrimary;
    final enabled = widget.enabled;
    final active = enabled && (_hovered || _focused);
    final iconColor = enabled ? widget.iconColor : AppTheme.textMuted;

    final row = Container(
      height: widget.height,
      padding: const EdgeInsets.fromLTRB(9, 0, 12, 0),
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.08) : Colors.transparent,
        border: Border(
          left: BorderSide(color: active ? accent : Colors.transparent, width: 3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? iconColor.withValues(alpha: 0.15) : AppTheme.bgSurfaceSecondary,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: active ? iconColor.withValues(alpha: 0.35) : AppTheme.borderSubtle,
              ),
            ),
            child: Icon(widget.icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: enabled ? (widget.labelColor ?? AppTheme.textPrimary) : AppTheme.textMuted,
              ),
            ),
          ),
          if (widget.shortcut != null) ...[
            const SizedBox(width: 16),
            Opacity(
              opacity: enabled ? 1 : 0.5,
              child: _PaletteKeycap(widget.shortcut!),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      role: SemanticsRole.menuItem,
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _select();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _select : null,
          child: row,
        ),
      ),
    );
  }
}

/// Shortcut hint drawn like the palette's ESC keycap.
class _PaletteKeycap extends StatelessWidget {
  final String text;

  const _PaletteKeycap(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.bgSurfaceSecondary,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.inputOutline),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

/// Scrolls [controller] so the row at [index] is fully visible.
void ensurePaletteRowVisible(ScrollController controller, int index) {
  if (!controller.hasClients) return;
  final position = controller.position;
  final top = index * PaletteRow.extent;
  final bottom = top + PaletteRow.extent;
  if (top < position.pixels) {
    controller.jumpTo(top.clamp(0.0, position.maxScrollExtent));
  } else if (bottom > position.pixels + position.viewportDimension) {
    controller.jumpTo(
      (bottom - position.viewportDimension).clamp(0.0, position.maxScrollExtent),
    );
  }
}
