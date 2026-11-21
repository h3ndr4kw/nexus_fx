part of 'file_explorer_dialogs.dart';

// Shared palette and frame for every File Explorer dialog.

/// File Explorer dialog palette, mapped onto the app theme so dialogs share the
/// quick-picker look (see palette_widgets.dart).
///
/// One accent (blue) marks the selected or focused item and the primary
/// action. Red is reserved for status: failure or a destructive action.
class _Dlg {
  const _Dlg._();

  static Color get surface => AppTheme.bgSurface;
  static Color get field => AppTheme.bgSurfaceSecondary;
  static Color get editor =>
      AppTheme.isLight ? AppTheme.bgSurfaceSecondary : const Color(0xFF111318);
  static Color get divider => AppTheme.borderSubtle;

  /// Accent at 8% on [surface]: the palette's selected-row tint.
  static Color get selected => AppTheme.isLight
      ? Color.alphaBlend(AppTheme.accentPrimary.withValues(alpha: 0.10), surface)
      : const Color(0xFF1C2330);

  /// Field and unselected-control boundary (3:1 on [surface] and [field]).
  static Color get outline =>
      AppTheme.isLight ? const Color(0xFF8A919C) : const Color(0xFF6B7280);

  static Color get textPrimary => AppTheme.textPrimary;
  static Color get textSecondary => AppTheme.textSecondary;
  static Color get textMuted => AppTheme.textMuted;

  static const OutlinedBorder buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(6)),
  );

  static Color get accent => AppTheme.accentPrimary;
  static Color get danger => AppTheme.errorColor;
}

const _titleAcronyms = {
  'SSH', 'SFTP', 'FTP', 'OAM', 'FE', 'NM', 'IP', 'URL', 'PCAP', 'OK', 'ID',
};
const _titleSmallWords = {
  'to', 'of', 'and', 'with', 'for', 'in', 'on', 'the', 'a', 'an', 'or',
};

/// "DRAG & DROP TRANSFER" -> "Drag & Drop Transfer". Words that already
/// contain lowercase letters, and known acronyms, are left alone.
String _displayTitle(String title) {
  var first = true;
  return title.replaceAllMapped(RegExp(r"[A-Za-z][A-Za-z0-9']*"), (m) {
    final word = m[0]!;
    final isFirst = first;
    first = false;
    if (word.length < 2 ||
        word != word.toUpperCase() ||
        _titleAcronyms.contains(word)) {
      return word;
    }
    final lower = word.toLowerCase();
    if (!isFirst && _titleSmallWords.contains(lower)) return lower;
    return lower[0].toUpperCase() + lower.substring(1);
  });
}

/// Dialog frame in the quick-picker style: a rounded card, a header with an
/// icon box, the title and an ESC keycap ([onClose]), then [child] and an
/// optional right-aligned [actions] footer. [height] makes the frame
/// fixed-height and gives [child] the remaining space; without it the frame
/// wraps its content. [accent] tints the header icon (e.g. red for delete).
class _DialogShell extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? accent;
  final double width;
  final double? height;
  final VoidCallback? onClose;
  final EdgeInsets insetPadding;
  final Widget child;

  /// Show [title] verbatim (e.g. a file name) instead of title-casing it.
  final bool rawTitle;

  /// Trailing buttons, right-aligned in a footer under [child].
  final List<Widget>? actions;

  /// Text left of [actions] in the footer, e.g. key hints.
  final Widget? footerLeading;

  const _DialogShell({
    required this.title,
    required this.child,
    required this.width,
    this.height,
    this.icon,
    this.accent,
    this.onClose,
    this.actions,
    this.footerLeading,
    this.rawTitle = false,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 40,
      vertical: 24,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final hasFooter = actions != null || footerLeading != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: insetPadding,
      child: Theme(
        data: Theme.of(context).copyWith(
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(shape: _Dlg.buttonShape),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(shape: _Dlg.buttonShape),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(shape: _Dlg.buttonShape),
          ),
        ),
        child: Container(
          width: width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _Dlg.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _Dlg.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Divider(height: 1, thickness: 1, color: _Dlg.divider),
              if (height != null) Expanded(child: child) else child,
              if (hasFooter) ...[
                Divider(height: 1, thickness: 1, color: _Dlg.divider),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      if (footerLeading != null) ...[
                        Expanded(child: footerLeading!),
                        const SizedBox(width: 12),
                      ],
                      if (actions != null)
                        Flexible(
                          flex: footerLeading == null ? 1 : 0,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 10,
                              runSpacing: 8,
                              children: actions!,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final accent = this.accent ?? _Dlg.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 15, color: accent),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              rawTitle ? title : _displayTitle(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _Dlg.textPrimary,
              ),
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 12),
            PaletteEscKeycap(onTap: onClose!),
          ],
        ],
      ),
    );
  }
}

/// Public entry to the File Explorer dialog frame, for dialogs built outside
/// this library (e.g. inline in the explorer view).
class FileExplorerDialogFrame extends StatelessWidget {
  final String title;
  final IconData? icon;
  final double width;
  final VoidCallback? onClose;
  final List<Widget>? actions;
  final Widget child;

  const FileExplorerDialogFrame({
    super.key,
    required this.title,
    required this.width,
    required this.child,
    this.icon,
    this.onClose,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: title,
      icon: icon,
      width: width,
      onClose: onClose,
      actions: actions,
      child: child,
    );
  }
}

/// Public entry to the shared dialog button.
class FileExplorerDialogButton extends StatelessWidget {
  final String label;
  final String? shortcut;
  final bool primary;
  final VoidCallback onTap;

  const FileExplorerDialogButton({
    super.key,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return _TerminalButton(
      label: label,
      shortcut: shortcut,
      isSelected: primary,
      highlightColor: _Dlg.accent,
      onTap: onTap,
    );
  }
}

/// Outlined field used by the credential and custom-SSH forms.
InputDecoration _formFieldDecoration(String label, {Widget? suffixIcon, String? errorText}) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(fontSize: 12, color: _Dlg.textSecondary),
    errorText: errorText,
    filled: true,
    fillColor: _Dlg.field,
    isDense: true,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: _Dlg.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: _Dlg.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: _Dlg.accent, width: 1.5),
    ),
  );
}
