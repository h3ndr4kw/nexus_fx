import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Shared look for the quick pickers (Nexus command palette, File Explorer
// node picker): a top-anchored card with a borderless search header, an ESC
// keycap, fixed-height rows with a left accent bar, and outlined badges.

/// Badge colors for session kinds, shared by the pickers.
class PaletteColors {
  static const Color local = Color(0xFF64B5F6);
  static const Color ssh = Color(0xFFFF7043);
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

  const PaletteBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
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
