import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/theme/app_theme.dart';

void main() {
  const aa = AppContrast.textMinimum;

  group('every palette meets WCAG AA for text', () {
    for (final type in AppThemeType.values) {
      final p = AppTheme.getPalette(type);
      final bgs = {'background': p.background, 'surface': p.surfaceColor};

      test(p.name, () {
        final foregrounds = {
          'text': p.textColor,
          'title': p.titleColor,
          'accent': p.accentColor,
          'error': p.errorColor,
          'success': p.successColor,
          'warning': p.warningColor,
          'muted text': p.mutedTextColor,
          'dimText(0.3)': p.dimText(0.3),
          'hint': p.dimText(0.5),
        };
        for (final fg in foregrounds.entries) {
          for (final bg in bgs.entries) {
            final r = AppContrast.ratioOver(fg.value, bg.value);
            expect(r, greaterThanOrEqualTo(aa),
                reason: '${p.name}: ${fg.key} on ${bg.key} is ${r.toStringAsFixed(2)}:1');
          }
        }
        // Primary colors section titles, links and outlined buttons, so it
        // is held to the text minimum too.
        for (final bg in bgs.entries) {
          final r = AppContrast.ratio(p.primaryColor, bg.value);
          expect(r, greaterThanOrEqualTo(aa),
              reason: '${p.name}: primary on ${bg.key} is ${r.toStringAsFixed(2)}:1');
        }
        // Field outlines must be visible (WCAG 1.4.11, 3:1).
        for (final bg in bgs.entries) {
          final r = AppContrast.ratio(p.inputOutlineColor, bg.value);
          expect(r, greaterThanOrEqualTo(AppContrast.nonTextMinimum),
              reason: '${p.name}: input outline on ${bg.key} is ${r.toStringAsFixed(2)}:1');
        }
      });
    }
  });

  test('text fields use the 3:1 outline; dividers keep the subtle border', () {
    for (final type in AppThemeType.values) {
      final p = AppTheme.getPalette(type);
      final theme = AppTheme.getThemeData(type);
      final border = theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;
      expect(border.borderSide.color, p.inputOutlineColor, reason: p.name);
      expect(theme.dividerColor, p.inputBorderColor, reason: p.name);
    }
  });

  test('outline moves only as far as needed', () {
    // Already-visible borders are kept as they are.
    const fg = Color(0xFF808080);
    expect(AppContrast.towardContrast(fg, Colors.white, [Colors.black], minimum: 3.0), fg);
    final c = AppContrast.towardContrast(
        const Color(0xFF232630), Colors.white, [const Color(0xFF0D0E12)], minimum: 3.0);
    expect(AppContrast.ratio(c, const Color(0xFF0D0E12)), inInclusiveRange(3.0, 3.4));
  });

  test('dimText keeps brighter levels as they are', () {
    final p = AppTheme.getPalette(AppThemeType.dracula);
    expect(p.dimText(0.9), p.textColor.withValues(alpha: 0.9));
    expect(p.dimText(0.1).a, closeTo(p.minReadableTextAlpha, 0.001));
  });

  test('static default colors meet AA on the default surfaces', () {
    for (final fg in [AppTheme.textMuted, AppTheme.textColor, AppTheme.dimText(0.3)]) {
      for (final bg in [AppTheme.background, AppTheme.surfaceColor, AppTheme.bgSurfaceSecondary]) {
        expect(AppContrast.ratioOver(fg, bg), greaterThanOrEqualTo(aa), reason: '$fg on $bg');
      }
    }
  });

  test('contrast ratio matches the WCAG reference values', () {
    expect(AppContrast.ratio(Colors.white, Colors.black), closeTo(21, 0.01));
    expect(AppContrast.ratio(const Color(0xFF777777), Colors.white), closeTo(4.48, 0.01));
  });
}
