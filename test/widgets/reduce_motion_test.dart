import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/settings_service.dart';
import 'package:nexus_fx/theme/app_motion.dart';
import 'package:nexus_fx/widgets/animated_gradient_border.dart';
import 'package:nexus_fx/widgets/radar_pulse_indicator.dart';
import 'package:nexus_fx/widgets/shimmer_loading.dart';

Widget _app(Widget child, {bool osReduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: osReduce),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  setUp(() {
    AppMotion.debugAnimateInTests = true;
    SettingsService.instance.setReduceMotionForTesting(false);
  });
  tearDown(() {
    AppMotion.debugAnimateInTests = false;
    SettingsService.instance.setReduceMotionForTesting(false);
  });

  final loops = <String, Widget Function()>{
    'radar beacon': () => const RadarPulseIndicator(),
    'amber badge': () => const BreathingAmberBadge(count: 2),
    'cyan dot': () => const CyanPulseDot(),
    'gradient border': () => const AnimatedGradientBorder(child: SizedBox(width: 40, height: 40)),
    'shimmer': () => const ShimmerEffect(child: SizedBox(width: 40, height: 10)),
  };

  for (final e in loops.entries) {
    group(e.key, () {
      testWidgets('loops by default', (tester) async {
        await tester.pumpWidget(_app(e.value()));
        expect(tester.hasRunningAnimations, isTrue);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('holds still with the app setting, and resumes when cleared',
          (tester) async {
        await tester.pumpWidget(_app(e.value()));
        SettingsService.instance.setReduceMotionForTesting(true);
        await tester.pump();
        expect(tester.hasRunningAnimations, isFalse);

        SettingsService.instance.setReduceMotionForTesting(false);
        await tester.pump();
        expect(tester.hasRunningAnimations, isTrue);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('holds still when the OS turns animations off', (tester) async {
        await tester.pumpWidget(_app(e.value(), osReduce: true));
        expect(tester.hasRunningAnimations, isFalse);
      });
    });
  }
}
