import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/settings_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/theme/terminal_theme_helper.dart';

void main() {
  tearDown(() => AppTheme.currentTheme = AppThemeType.antigravity);

  test('light palette builds a light Material theme', () {
    final p = AppTheme.getPalette(AppThemeType.light);
    final theme = AppTheme.getThemeData(AppThemeType.light);
    expect(p.isLight, isTrue);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, p.background);
  });

  test('dark palettes keep a dark Material theme', () {
    for (final type in AppThemeType.values.where((t) => t != AppThemeType.light)) {
      expect(AppTheme.getThemeData(type).brightness, Brightness.dark, reason: type.name);
    }
  });

  test('AppTheme colors follow the active palette', () {
    AppTheme.currentTheme = AppThemeType.light;
    final light = AppTheme.getPalette(AppThemeType.light);
    expect(AppTheme.background, light.background);
    expect(AppTheme.textPrimary, light.titleColor);
    expect(AppTheme.isLight, isTrue);
    expect(AppTheme.ink.computeLuminance(), lessThan(0.1));

    AppTheme.currentTheme = AppThemeType.antigravity;
    // Antigravity keeps its original hand-picked values.
    expect(AppTheme.background, const Color(0xFF0D0E12));
    expect(AppTheme.bgSurfaceSecondary, const Color(0xFF13151B));
    expect(AppTheme.textMuted, const Color(0xFF7B828E));
    expect(AppTheme.ink, Colors.white);
    expect(AppTheme.textPrimary, const Color(0xFFE2E4E9));
  });

  test('primary text stays neutral and readable on every palette', () {
    for (final type in AppThemeType.values) {
      final p = AppTheme.getPalette(type);
      final hsl = HSLColor.fromColor(p.primaryTextColor);
      expect(hsl.saturation * (1 - (2 * hsl.lightness - 1).abs()), lessThan(0.15), reason: p.name);
      for (final bg in [p.background, p.surfaceColor]) {
        expect(AppContrast.ratio(p.primaryTextColor, bg), greaterThanOrEqualTo(AppContrast.textMinimum),
            reason: p.name);
      }
    }
  });

  test('muted text meets AA on every palette surface', () {
    for (final type in AppThemeType.values) {
      final p = AppTheme.getPalette(type);
      for (final bg in [p.background, p.surfaceColor, p.surfaceSecondaryColor]) {
        expect(AppContrast.ratio(p.mutedColor, bg), greaterThanOrEqualTo(AppContrast.textMinimum),
            reason: p.name);
      }
    }
  });

  group('adaptive', () {
    test('is the identity on dark palettes', () {
      const c = Color(0xFF98C379);
      expect(AppTheme.adaptive(c), c);
    });

    test('maps dark surfaces to light ones and light text to readable dark text', () {
      AppTheme.currentTheme = AppThemeType.light;
      final bg = AppTheme.background;

      final surface = AppTheme.adaptive(const Color(0xFF171B24));
      expect(surface.computeLuminance(), greaterThan(0.75));

      for (final fg in const [Color(0xFFD8DEE9), Color(0xFF98C379), Color(0xFFE5C07B), Colors.white]) {
        final c = AppTheme.adaptive(fg);
        expect(AppContrast.ratio(c, bg), greaterThanOrEqualTo(AppContrast.textMinimum),
            reason: '$fg -> $c');
      }
    });

    test('keeps alpha', () {
      AppTheme.currentTheme = AppThemeType.light;
      expect(AppTheme.adaptive(const Color(0x4061AFEF)).a, closeTo(0x40 / 255, 0.01));
    });
  });

  test('terminal following a light app theme uses readable achromatic colors', () {
    final p = AppTheme.getPalette(AppThemeType.light);
    final t = TerminalThemeHelper.resolveTheme(
        mode: NexusTerminalThemeMode.followAppTheme, palette: p);
    expect(t.background, p.background);
    for (final c in [t.foreground, t.white, t.brightBlack]) {
      expect(AppContrast.ratio(c, t.background), greaterThanOrEqualTo(AppContrast.textMinimum));
    }
  });
}
