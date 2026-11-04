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
  });
}

class AppTheme {
  // Original constant colors for backwards compatibility with const widgets
  static const Color background = Color(0xFF0D0E12);
  static const Color surfaceColor = Color(0xFF16181F);
  static const Color primaryColor = Color(0xFF60A5FA);
  static const Color accentColor = Color(0xFF34D399);
  static const Color textColor = Color(0xFF9AA0A6);
  static const Color titleColor = Color(0xFFE2E4E9);
  static const Color inputBorderColor = Color(0xFF232630);
  static const Color errorColor = Color(0xFFF87171);
  static const Color successColor = Color(0xFF34D399);
  static const Color warningColor = Color(0xFFFBBF24);

  // Semantic aliases for modern widgets
  static const Color bgSurface = surfaceColor;
  static const Color bgSurfaceSecondary = Color(0xFF13151B);
  static const Color accentPrimary = primaryColor;
  static const Color borderSubtle = inputBorderColor;
  static const Color textPrimary = Color(0xFFE2E4E9);
  static const Color textSecondary = textColor;
  static const Color textMuted = Color(0xFF6B7280);
  static const Color statusError = errorColor;
  static const Color statusSuccess = successColor;
  static const Color statusWarning = warningColor;

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
      primaryColor: Color(0xFF007ACC),
      accentColor: Color(0xFFDCDCAA),
      textColor: Color(0xFFCCCCCC),
      titleColor: Color(0xFF4EC9B0),
      inputBorderColor: Color(0xFF3C3C3C),
      errorColor: Color(0xFFF14C4C),
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
      titleColor: Color(0xFF6897BB),
      inputBorderColor: Color(0xFF4B4B4B),
      errorColor: Color(0xFFBC3F3C),
      successColor: Color(0xFF629755),
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
      titleColor: Color(0xFF81A1C1),
      inputBorderColor: Color(0xFF4C566A),
      errorColor: Color(0xFFBF616A),
      successColor: Color(0xFFA3BE8C),
      warningColor: Color(0xFFD08770),
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
      errorColor: Color(0xFFE06C75),
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
      errorColor: Color(0xFFFF5555),
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
      errorColor: Color(0xFFFF6188),
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
      errorColor: Color(0xFFFB4934),
      successColor: Color(0xFFB8BB26),
      warningColor: Color(0xFFFE8019),
    ),
  };

  static AppPalette getPalette(AppThemeType type) {
    return _palettes[type] ?? _palettes[AppThemeType.antigravity]!;
  }

  static ThemeData get darkTheme => getThemeData(currentTheme);

  static ThemeData getThemeData(AppThemeType type) {
    final palette = getPalette(type);
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: palette.background,
      fontFamily: 'Courier',
      colorScheme: ColorScheme.dark(
        primary: palette.primaryColor,
        secondary: palette.accentColor,
        surface: palette.surfaceColor,
        error: palette.errorColor,
      ),
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
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(false),
        trackVisibility: WidgetStatePropertyAll(false),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.transparent,
        hintStyle: TextStyle(color: palette.textColor.withValues(alpha: 0.5)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: palette.inputBorderColor, width: 1.5),
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
