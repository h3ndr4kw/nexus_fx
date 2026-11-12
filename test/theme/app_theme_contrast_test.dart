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
        // Primary is also a fill behind white text, so only the 3:1
        // non-text minimum is required of it as a foreground.
        for (final bg in bgs.values) {
          expect(AppContrast.ratio(p.primaryColor, bg), greaterThanOrEqualTo(3.0),
              reason: '${p.name}: primary');
        }
      });
    }
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
