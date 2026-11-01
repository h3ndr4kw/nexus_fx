import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../services/settings_service.dart';
import 'app_theme.dart';

class TerminalThemeHelper {
  static TerminalTheme resolveTheme({
    required NexusTerminalThemeMode mode,
    required AppPalette palette,
  }) {
    switch (mode) {
      case NexusTerminalThemeMode.classicDark:
        return TerminalThemes.defaultTheme;
      case NexusTerminalThemeMode.highContrast:
        return TerminalThemes.whiteOnBlack;
      case NexusTerminalThemeMode.matrixGreen:
        return const TerminalTheme(
          cursor: Color(0xFF00FF66),
          selection: Color(0x5500FF66),
          foreground: Color(0xFF20C20E),
          background: Color(0xFF070B08),
          black: Color(0xFF000000),
          red: Color(0xFFFF4444),
          green: Color(0xFF20C20E),
          yellow: Color(0xFFD4E157),
          blue: Color(0xFF00E5FF),
          magenta: Color(0xFF00FF66),
          cyan: Color(0xFF26A69A),
          white: Color(0xFFA5D6A7),
          brightBlack: Color(0xFF2E7D32),
          brightRed: Color(0xFFFF5252),
          brightGreen: Color(0xFF69F0AE),
          brightYellow: Color(0xFFEEFF41),
          brightBlue: Color(0xFF40C4FF),
          brightMagenta: Color(0xFFB9F6CA),
          brightCyan: Color(0xFF64FFDA),
          brightWhite: Color(0xFFE8F5E9),
          searchHitBackground: Color(0xFF00E676),
          searchHitBackgroundCurrent: Color(0xFF76FF03),
          searchHitForeground: Color(0xFF000000),
        );
      case NexusTerminalThemeMode.followAppTheme:
        return TerminalTheme(
          cursor: palette.primaryColor,
          selection: palette.primaryColor.withValues(alpha: 0.35),
          foreground: palette.textColor,
          background: palette.background,
          black: const Color(0xFF000000),
          red: palette.errorColor,
          green: palette.successColor,
          yellow: palette.warningColor,
          blue: palette.primaryColor,
          magenta: palette.titleColor,
          cyan: palette.accentColor,
          white: const Color(0xFFE5E5E5),
          brightBlack: const Color(0xFF666666),
          brightRed: palette.errorColor,
          brightGreen: palette.successColor,
          brightYellow: palette.warningColor,
          brightBlue: palette.primaryColor,
          brightMagenta: palette.titleColor,
          brightCyan: palette.accentColor,
          brightWhite: const Color(0xFFFFFFFF),
          searchHitBackground: palette.accentColor.withValues(alpha: 0.5),
          searchHitBackgroundCurrent: palette.primaryColor,
          searchHitForeground: const Color(0xFF000000),
        );
    }
  }
}
