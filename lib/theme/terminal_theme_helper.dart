import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import '../services/settings_service.dart';
import 'app_theme.dart';

class TerminalThemeHelper {
  static const TerminalTheme antigravityDark = TerminalTheme(
    cursor: Color(0xFF60A5FA),
    selection: Color(0x4760A5FA),
    foreground: Color(0xFFE2E5EB),
    background: Color(0xFF0D0E12),
    black: Color(0xFF16181E),
    red: Color(0xFFF87171),
    green: Color(0xFF34D399),
    yellow: Color(0xFFFBBF24),
    blue: Color(0xFF60A5FA),
    magenta: Color(0xFFC084FC),
    cyan: Color(0xFF38BDF8),
    white: Color(0xFFE2E5EB),
    brightBlack: Color(0xFF5C6370),
    brightRed: Color(0xFFFB7185),
    brightGreen: Color(0xFF4ADE80),
    brightYellow: Color(0xFFFDE047),
    brightBlue: Color(0xFF93C5FD),
    brightMagenta: Color(0xFFE879F9),
    brightCyan: Color(0xFF67E8F9),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFF38BDF8),
    searchHitBackgroundCurrent: Color(0xFF60A5FA),
    searchHitForeground: Color(0xFF0D0E12),
  );

  static TerminalTheme resolveTheme({
    required NexusTerminalThemeMode mode,
    required AppPalette palette,
  }) {
    switch (mode) {
      case NexusTerminalThemeMode.antigravityDark:
        return antigravityDark;
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
        if (palette.id == 'antigravity') {
          return antigravityDark;
        }
        return TerminalTheme(
          cursor: palette.primaryColor,
          selection: palette.primaryColor.withValues(alpha: 0.35),
          foreground: palette.titleColor,
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
