import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AppThemeType {
  antigravity,
  catppuccinMocha,
  catppuccinMacchiato,
  vscodeDark,
  jetbrainsDarcula,
  tokyoNight,
  tokyoNightStorm,
  nord,
  oneDarkPro,
  dracula,
  monokaiPro,
  gruvboxDark,
  light,
}

enum AppFontSize {
  small,
  medium,
  large,
  extraLarge,
}

class AppPalette {
  final String id;
  final String name;
  final Color background;
  final Color surfaceColor;
  final Color primaryColor;
  final Color accentColor;
  final Color textColor;
  final Color titleColor;
  final Color inputBorderColor;
  final Color errorColor;
  final Color successColor;
  final Color warningColor;
  final Brightness brightness;

  /// Panel tone between [background] and [surfaceColor]; derived when null.
  final Color? _surfaceSecondaryColor;

  /// Opaque muted label color; derived from [mutedTextColor] when null.
  final Color? _mutedColor;

  /// Neutral high-emphasis text; derived when null. Unlike [titleColor],
  /// which several palettes tint (cyan, purple), this stays neutral.
  final Color? _primaryTextColor;

  const AppPalette({
    required this.id,
    required this.name,
    required this.background,
    required this.surfaceColor,
    required this.primaryColor,
    required this.accentColor,
    required this.textColor,
    required this.titleColor,
    required this.inputBorderColor,
    required this.errorColor,
    required this.successColor,
    required this.warningColor,
    this.brightness = Brightness.dark,
    Color? surfaceSecondaryColor,
    Color? mutedColor,
    Color? primaryTextColor,
  })  : _surfaceSecondaryColor = surfaceSecondaryColor,
        _mutedColor = mutedColor,
        _primaryTextColor = primaryTextColor;

  Color get primaryTextColor =>
      _primaryTextColor ??
      (isLight ? titleColor : Color.lerp(textColor, const Color(0xFFFFFFFF), 0.5)!);

  bool get isLight => brightness == Brightness.light;

  Color get surfaceSecondaryColor =>
      _surfaceSecondaryColor ?? Color.lerp(background, surfaceColor, 0.5)!;

  /// Opaque muted text that still meets 4.5:1 on [background],
  /// [surfaceColor] and [surfaceSecondaryColor].
  Color get mutedColor => _mutedColor ?? (_mutedCache[id] ??= AppContrast.towardContrast(
      Color.lerp(textColor, background, 0.35)!, textColor,
      [background, surfaceColor, surfaceSecondaryColor]));

  static final Map<String, Color> _mutedCache = {};

  /// Foreground for text and icons placed on a [primaryColor] fill.
  Color get onPrimaryColor =>
      AppContrast.ratio(Colors.white, primaryColor) >= AppContrast.ratio(Colors.black, primaryColor)
          ? Colors.white
          : Colors.black;

  /// [textColor] faded to [alpha], but never fainter than WCAG AA (4.5:1)
  /// allows on [background] and [surfaceColor]. Keeps the relative
  /// hierarchy of dimmed labels while making the faintest ones readable.
  Color dimText(double alpha) =>
      textColor.withValues(alpha: math.max(alpha, minReadableTextAlpha));

  /// Text dimmed as far as it can go while still meeting 4.5:1.
  Color get mutedTextColor => dimText(0);

  /// Lowest alpha at which [textColor] still meets 4.5:1 on both
  /// [background] and [surfaceColor].
  double get minReadableTextAlpha =>
      _minAlphaCache[id] ??= AppContrast.minAlphaFor(textColor, [background, surfaceColor]);

  static final Map<String, double> _minAlphaCache = {};

  /// Outline for text fields and other controls: [inputBorderColor] moved
  /// toward [textColor] just far enough to reach the WCAG 3:1 non-text
  /// minimum on [background] and [surfaceColor], so an empty field is still
  /// visible. Decorative dividers keep [inputBorderColor].
  Color get inputOutlineColor => _outlineCache[id] ??=
      AppContrast.towardContrast(inputBorderColor, textColor, [background, surfaceColor],
          minimum: AppContrast.nonTextMinimum);

  static final Map<String, Color> _outlineCache = {};
}

/// WCAG 2.x contrast helpers.
class AppContrast {
  AppContrast._();

  /// Minimum ratio for normal-size text (WCAG AA).
  static const double textMinimum = 4.5;

  /// Minimum ratio for UI component boundaries such as field outlines
  /// (WCAG 1.4.11).
  static const double nonTextMinimum = 3.0;

  /// Contrast ratio between two opaque colors (1..21).
  static double ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Contrast of [fg] at its own alpha, drawn over opaque [bg].
  static double ratioOver(Color fg, Color bg) =>
      ratio(Color.alphaBlend(fg, bg), bg);

  /// Smallest alpha (in 0.01 steps) at which [fg] reaches [minimum] on every
  /// color in [backgrounds]; 1.0 if even the opaque color does not.
  static double minAlphaFor(Color fg, List<Color> backgrounds,
      {double minimum = textMinimum}) {
    for (var step = 0; step <= 100; step++) {
      final a = step / 100;
      final c = fg.withValues(alpha: a);
      if (backgrounds.every((bg) => ratioOver(c, bg) >= minimum)) return a;
    }
    return 1.0;
  }

  /// [from] blended toward [to] (in 2% steps) until it reaches [minimum] on
  /// every color in [backgrounds]; [to] itself if nothing closer does.
  static Color towardContrast(Color from, Color to, List<Color> backgrounds,
      {double minimum = textMinimum}) {
    for (var step = 0; step <= 50; step++) {
      final c = Color.lerp(from, to, step / 50)!;
      if (backgrounds.every((bg) => ratio(c, bg) >= minimum)) return c;
    }
    return to;
  }
}

class AppTheme {
  // Colors of the active palette. These used to be compile-time constants
  // fixed to the Antigravity palette; they now follow [currentTheme] so light
  // palettes apply everywhere.
  static Color get background => activePalette.background;
  static Color get surfaceColor => activePalette.surfaceColor;
  static Color get primaryColor => activePalette.primaryColor;
  static Color get accentColor => activePalette.accentColor;
  static Color get textColor => activePalette.textColor;
  static Color get titleColor => activePalette.titleColor;
  static Color get inputBorderColor => activePalette.inputBorderColor;
  static Color get errorColor => activePalette.errorColor;
  static Color get successColor => activePalette.successColor;
  static Color get warningColor => activePalette.warningColor;

  // Semantic aliases for modern widgets
  static Color get bgSurface => surfaceColor;
  static Color get bgSurfaceSecondary => activePalette.surfaceSecondaryColor;
  static Color get accentPrimary => primaryColor;
  static Color get borderSubtle => inputBorderColor;

  /// Field outline for the active theme (meets 3:1); see
  /// [AppPalette.inputOutlineColor].
  static Color get inputOutline => activePalette.inputOutlineColor;
  static Color get textPrimary => activePalette.primaryTextColor;
  static Color get textSecondary => textColor;
  static Color get textMuted => activePalette.mutedColor;
  static Color get statusError => errorColor;
  static Color get statusSuccess => successColor;
  static Color get statusWarning => warningColor;

  /// Text/icon color for content on a [primaryColor] fill.
  static Color get onPrimary => activePalette.onPrimaryColor;

  static bool get isLight => activePalette.isLight;

  /// High-contrast "ink" for overlays (hover tints, shadows-as-highlights):
  /// white on dark palettes, near-black on light ones.
  static Color get ink => isLight ? const Color(0xFF111827) : Colors.white;

  /// [textColor] faded to [alpha], floored at WCAG AA on the active
  /// background and surface.
  static Color dimText(double alpha) => activePalette.dimText(alpha);

  /// A color picked for a dark UI, carried over to the active palette.
  ///
  /// Dark palettes return [c] unchanged. Light palettes mirror its HSL
  /// lightness: dark surfaces and borders become light ones (kept close to
  /// white so panels stay distinguishable), and light text and accents
  /// become dark ones, darkened further if needed to reach 4.5:1 on the
  /// background. Alpha is preserved.
  static Color adaptive(Color c) {
    if (!isLight) return c;
    final p = activePalette;
    return _adaptiveCache.putIfAbsent('${p.id}:${c.toARGB32()}', () => adaptToLight(c, p.background));
  }

  static final Map<String, Color> _adaptiveCache = {};

  /// See [adaptive]; exposed for tests.
  static Color adaptToLight(Color c, Color background) {
    final hsl = HSLColor.fromColor(c.withValues(alpha: 1));
    final l = hsl.lightness;
    if (l < 0.5) {
      // Surface / border: 0.0 -> 1.0, 0.5 -> 0.75.
      return hsl.withLightness(1 - l * 0.5).toColor().withValues(alpha: c.a);
    }
    var fg = hsl.withLightness((1 - l).clamp(0.08, 0.45)).toColor();
    fg = AppContrast.towardContrast(fg, const Color(0xFF000000), [background]);
    return fg.withValues(alpha: c.a);
  }

  // Current active palette (defaults to antigravity)
  static AppThemeType currentTheme = AppThemeType.antigravity;

  static AppPalette get activePalette => getPalette(currentTheme);

  static final Map<AppThemeType, AppPalette> _palettes = {
    // 1. Dark Mode Antigravity (Original default)
    AppThemeType.antigravity: const AppPalette(
      id: 'antigravity',
      name: 'Dark Mode Antigravity',
      background: Color(0xFF0D0E12),
      surfaceColor: Color(0xFF16181F),
      primaryColor: Color(0xFF60A5FA),
      accentColor: Color(0xFF34D399),
      textColor: Color(0xFF9AA0A6),
      titleColor: Color(0xFFE2E4E9),
      inputBorderColor: Color(0xFF232630),
      errorColor: Color(0xFFF87171),
      successColor: Color(0xFF34D399),
      warningColor: Color(0xFFFBBF24),
      surfaceSecondaryColor: Color(0xFF13151B),
      mutedColor: Color(0xFF7B828E),
      primaryTextColor: Color(0xFFE2E4E9),
    ),

    // 2. Catppuccin Mocha
    AppThemeType.catppuccinMocha: const AppPalette(
      id: 'catppuccin_mocha',
      name: 'Catppuccin Mocha',
      background: Color(0xFF1E1E2E),
      surfaceColor: Color(0xFF2A2B3D),
      primaryColor: Color(0xFF89B4FA),
      accentColor: Color(0xFFF9E2AF),
      textColor: Color(0xFFCDD6F4),
      titleColor: Color(0xFFCBA6F7),
      inputBorderColor: Color(0xFF45475A),
      errorColor: Color(0xFFF38BA8),
      successColor: Color(0xFFA6E3A1),
      warningColor: Color(0xFFFAB387),
    ),

    // 3. Catppuccin Macchiato
    AppThemeType.catppuccinMacchiato: const AppPalette(
      id: 'catppuccin_macchiato',
      name: 'Catppuccin Macchiato',
      background: Color(0xFF24273A),
      surfaceColor: Color(0xFF303446),
      primaryColor: Color(0xFF8AADF4),
      accentColor: Color(0xFFEED49F),
      textColor: Color(0xFFCAD3F5),
      titleColor: Color(0xFFC6A0F6),
      inputBorderColor: Color(0xFF494D64),
      errorColor: Color(0xFFED8796),
      successColor: Color(0xFFA6DA95),
      warningColor: Color(0xFFF5A97F),
    ),

    // 4. VS Code Dark+
    AppThemeType.vscodeDark: const AppPalette(
      id: 'vscode_dark',
      name: 'VS Code Dark+',
      background: Color(0xFF1E1E1E),
      surfaceColor: Color(0xFF252526),
      primaryColor: Color(0xFF3794FF),
      accentColor: Color(0xFFDCDCAA),
      textColor: Color(0xFFCCCCCC),
      titleColor: Color(0xFF4EC9B0),
      inputBorderColor: Color(0xFF3C3C3C),
      errorColor: Color(0xFFF25555),
      successColor: Color(0xFF89D185),
      warningColor: Color(0xFFCCA700),
    ),

    // 5. JetBrains Darcula
    AppThemeType.jetbrainsDarcula: const AppPalette(
      id: 'jetbrains_darcula',
      name: 'JetBrains Darcula',
      background: Color(0xFF2B2B2B),
      surfaceColor: Color(0xFF313335),
      primaryColor: Color(0xFF589DF6),
      accentColor: Color(0xFFFFC66D),
      textColor: Color(0xFFA9B7C6),
      titleColor: Color(0xFF749FC0),
      inputBorderColor: Color(0xFF4B4B4B),
      errorColor: Color(0xFFD58684),
      successColor: Color(0xFF78A66D),
      warningColor: Color(0xFFBBB529),
    ),

    // 6. Tokyo Night
    AppThemeType.tokyoNight: const AppPalette(
      id: 'tokyo_night',
      name: 'Tokyo Night',
      background: Color(0xFF1A1B26),
      surfaceColor: Color(0xFF24283B),
      primaryColor: Color(0xFF7AA2F7),
      accentColor: Color(0xFFE0AF68),
      textColor: Color(0xFFA9B1D6),
      titleColor: Color(0xFF7DCFFF),
      inputBorderColor: Color(0xFF383E5A),
      errorColor: Color(0xFFF7768E),
      successColor: Color(0xFF9ECE6A),
      warningColor: Color(0xFFFF9E64),
    ),

    // 7. Tokyo Night Storm
    AppThemeType.tokyoNightStorm: const AppPalette(
      id: 'tokyo_night_storm',
      name: 'Tokyo Night Storm',
      background: Color(0xFF24283B),
      surfaceColor: Color(0xFF2E334D),
      primaryColor: Color(0xFF7AA2F7),
      accentColor: Color(0xFFE0AF68),
      textColor: Color(0xFFC0CAF5),
      titleColor: Color(0xFF7DCFFF),
      inputBorderColor: Color(0xFF414868),
      errorColor: Color(0xFFF7768E),
      successColor: Color(0xFF9ECE6A),
      warningColor: Color(0xFFFF9E64),
    ),

    // 8. Nord
    AppThemeType.nord: const AppPalette(
      id: 'nord',
      name: 'Nord',
      background: Color(0xFF2E3440),
      surfaceColor: Color(0xFF3B4252),
      primaryColor: Color(0xFF88C0D0),
      accentColor: Color(0xFFEBCB8B),
      textColor: Color(0xFFECEFF4),
      titleColor: Color(0xFF96B1CC),
      inputBorderColor: Color(0xFF4C566A),
      errorColor: Color(0xFFD89FA4),
      successColor: Color(0xFFA3BE8C),
      warningColor: Color(0xFFDAA08E),
    ),

    // 9. One Dark Pro
    AppThemeType.oneDarkPro: const AppPalette(
      id: 'one_dark_pro',
      name: 'One Dark Pro',
      background: Color(0xFF282C34),
      surfaceColor: Color(0xFF21252B),
      primaryColor: Color(0xFF61AFEF),
      accentColor: Color(0xFFE5C07B),
      textColor: Color(0xFFABB2BF),
      titleColor: Color(0xFFC678DD),
      inputBorderColor: Color(0xFF3E4451),
      errorColor: Color(0xFFE17079),
      successColor: Color(0xFF98C379),
      warningColor: Color(0xFFD19A66),
    ),

    // 10. Dracula
    AppThemeType.dracula: const AppPalette(
      id: 'dracula',
      name: 'Dracula',
      background: Color(0xFF282A36),
      surfaceColor: Color(0xFF343746),
      primaryColor: Color(0xFFBD93F9),
      accentColor: Color(0xFFF1FA8C),
      textColor: Color(0xFFF8F8F2),
      titleColor: Color(0xFF8BE9FD),
      inputBorderColor: Color(0xFF44475A),
      errorColor: Color(0xFFFF7575),
      successColor: Color(0xFF50FA7B),
      warningColor: Color(0xFFFFB86C),
    ),

    // 11. Monokai Pro
    AppThemeType.monokaiPro: const AppPalette(
      id: 'monokai_pro',
      name: 'Monokai Pro',
      background: Color(0xFF2D2A2E),
      surfaceColor: Color(0xFF3A373B),
      primaryColor: Color(0xFFFFD866),
      accentColor: Color(0xFFFC9867),
      textColor: Color(0xFFFCFCFA),
      titleColor: Color(0xFF78DCE8),
      inputBorderColor: Color(0xFF49464E),
      errorColor: Color(0xFFFF7295),
      successColor: Color(0xFFA9DC76),
      warningColor: Color(0xFFFFD866),
    ),

    // 12. Gruvbox Dark
    AppThemeType.gruvboxDark: const AppPalette(
      id: 'gruvbox_dark',
      name: 'Gruvbox Dark',
      background: Color(0xFF282828),
      surfaceColor: Color(0xFF32302F),
      primaryColor: Color(0xFF83A598),
      accentColor: Color(0xFFFABD2F),
      textColor: Color(0xFFEBDBB2),
      titleColor: Color(0xFF8EC07C),
      inputBorderColor: Color(0xFF504945),
      errorColor: Color(0xFFFC6857),
      successColor: Color(0xFFB8BB26),
      warningColor: Color(0xFFFE8019),
    ),

    // 13. Light (white)
    AppThemeType.light: const AppPalette(
      id: 'light',
      name: 'Light',
      brightness: Brightness.light,
      background: Color(0xFFFFFFFF),
      surfaceColor: Color(0xFFF4F5F7),
      primaryColor: Color(0xFF2563EB),
      accentColor: Color(0xFF047857),
      textColor: Color(0xFF4B5563),
      titleColor: Color(0xFF111827),
      inputBorderColor: Color(0xFFE2E5EA),
      errorColor: Color(0xFFB91C1C),
      successColor: Color(0xFF047857),
      warningColor: Color(0xFFA16207),
      surfaceSecondaryColor: Color(0xFFF9FAFB),
    ),
  };

  static AppPalette getPalette(AppThemeType type) {
    return _palettes[type] ?? _palettes[AppThemeType.antigravity]!;
  }

  static ThemeData get theme => getThemeData(currentTheme);

  @Deprecated('Use AppTheme.theme; the active palette may be light.')
  static ThemeData get darkTheme => theme;

  // Cached per type: ThemeData holds WidgetStateProperty closures that never
  // compare equal, so a fresh instance on every settings-driven MaterialApp
  // rebuild made AnimatedTheme lerp the whole app for ~200ms.
  static final Map<AppThemeType, ThemeData> _themeCache = {};

  static ThemeData getThemeData(AppThemeType type) =>
      _themeCache.putIfAbsent(type, () => _buildThemeData(type));

  static ThemeData _buildThemeData(AppThemeType type) {
    final palette = getPalette(type);
    final scheme = palette.isLight
        ? ColorScheme.light(
            primary: palette.primaryColor,
            onPrimary: palette.onPrimaryColor,
            secondary: palette.accentColor,
            surface: palette.surfaceColor,
            onSurface: palette.titleColor,
            error: palette.errorColor,
          )
        : ColorScheme.dark(
            primary: palette.primaryColor,
            secondary: palette.accentColor,
            surface: palette.surfaceColor,
            error: palette.errorColor,
          );
    return ThemeData(
      brightness: palette.brightness,
      scaffoldBackgroundColor: palette.background,
      fontFamily: 'Courier',
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: palette.primaryColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier',
          letterSpacing: 2.0,
        ),
      ),
      dividerColor: palette.inputBorderColor,
      dividerTheme: DividerThemeData(
        color: palette.inputBorderColor,
        thickness: 1.0,
        space: 1.0,
      ),
      dataTableTheme: const DataTableThemeData(
        dividerThickness: 1.0,
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(
          color: palette.inputBorderColor,
          width: 1.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.primaryColor;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(palette.isLight ? palette.onPrimaryColor : Colors.white),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(false),
        trackVisibility: WidgetStatePropertyAll(false),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.transparent,
        hintStyle: TextStyle(color: palette.dimText(0.5)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: palette.inputOutlineColor, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: palette.primaryColor, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: palette.errorColor, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: palette.errorColor, width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: palette.textColor, fontFamily: 'Courier'),
        bodyLarge: TextStyle(color: palette.textColor, fontFamily: 'Courier'),
        bodySmall: TextStyle(color: palette.textColor, fontFamily: 'Courier'),
        titleMedium: TextStyle(color: palette.titleColor, fontFamily: 'Courier'),
        titleLarge: TextStyle(
          color: palette.primaryColor,
          fontFamily: 'Courier',
          fontWeight: FontWeight.w300,
          letterSpacing: 8.0,
        ),
      ),
    );
  }
}
