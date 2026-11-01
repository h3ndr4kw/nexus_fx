import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/screens/nexus_screen.dart';
import 'package:nexus_fx/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NexusPulseColor and NexusPulseStyle Tests', () {
    test('All NexusPulseColor values have labels and gradient color palettes', () {
      expect(NexusPulseColor.values.length, greaterThanOrEqualTo(5));

      final emerald = NexusPulseColor.emerald;
      expect(emerald.label, contains('Emerald'));
      expect(emerald.primary, const Color(0xFF10B981));
      expect(emerald.secondary, const Color(0xFF22D3EE));

      final ruby = NexusPulseColor.ruby;
      expect(ruby.label, contains('Ruby'));
      expect(ruby.primary, const Color(0xFFEF4444));
      expect(ruby.secondary, const Color(0xFFFB7185));

      final sapphire = NexusPulseColor.sapphire;
      expect(sapphire.label, contains('Sapphire'));
      expect(sapphire.primary, const Color(0xFF3B82F6));
      expect(sapphire.secondary, const Color(0xFF38BDF8));

      final amethyst = NexusPulseColor.amethyst;
      expect(amethyst.label, contains('Amethyst'));
      expect(amethyst.primary, const Color(0xFF8B5CF6));
      expect(amethyst.secondary, const Color(0xFFEC4899));

      final diamond = NexusPulseColor.diamond;
      expect(diamond.label, contains('Diamond'));
      expect(diamond.primary, const Color(0xFFF8FAFC));
      expect(diamond.secondary, const Color(0xFF38BDF8));

      final amber = NexusPulseColor.amber;
      expect(amber.label, contains('Amber'));
      expect(amber.primary, const Color(0xFFF59E0B));
      expect(amber.secondary, const Color(0xFFFBBF24));
    });

    test('SettingsService can change and cycle pulse styles and colors', () async {
      final settings = SettingsService.instance;

      await settings.setNexusPulseStyle(NexusPulseStyle.neonSonarWave);
      expect(settings.nexusPulseStyle, NexusPulseStyle.neonSonarWave);

      final nextStyle = await settings.cycleNexusPulseStyle();
      expect(nextStyle, isNot(NexusPulseStyle.neonSonarWave));

      await settings.setNexusPulseColor(NexusPulseColor.ruby);
      expect(settings.nexusPulseColor, NexusPulseColor.ruby);

      final nextColor = await settings.cycleNexusPulseColor();
      expect(nextColor, isNot(NexusPulseColor.ruby));

      // Reset back to defaults
      await settings.setNexusPulseStyle(NexusPulseStyle.neonSonarWave);
      await settings.setNexusPulseColor(NexusPulseColor.emerald);
      expect(settings.nexusPulseStyle, NexusPulseStyle.neonSonarWave);
      expect(settings.nexusPulseColor, NexusPulseColor.emerald);
    });

    testWidgets('RadarPulseIndicator renders across all styles and colors', (tester) async {
      for (final style in NexusPulseStyle.values) {
        for (final color in NexusPulseColor.values) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RadarPulseIndicator(
                  style: style,
                  pulseColor: color,
                ),
              ),
            ),
          );
          expect(find.byType(RadarPulseIndicator), findsOneWidget);
        }
      }
    });
  });
}
