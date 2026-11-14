import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Radar pulse expanding ripple beacon for active session tabs (ping-slow)
class RadarPulseIndicator extends StatefulWidget {
  final Color? color;
  final double size;
  final NexusPulseStyle? style;
  final NexusPulseColor? pulseColor;

  const RadarPulseIndicator({
    super.key,
    this.color,
    this.size = 7.5,
    this.style,
    this.pulseColor,
  });

  @override
  State<RadarPulseIndicator> createState() => _RadarPulseIndicatorState();
}

class _RadarPulseIndicatorState extends State<RadarPulseIndicator>
    with SingleTickerProviderStateMixin, ReduceMotionLoop {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  AnimationController get loopController => _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.linear);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeStyle = widget.style ?? SettingsService.instance.nexusPulseStyle;
    final activeColor = widget.pulseColor ?? SettingsService.instance.nexusPulseColor;
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(right: 6),
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return CustomPaint(
            painter: _RadarPulsePainter(
              progress: _animation.value,
              color: widget.color ?? activeColor.primary,
              dotSize: widget.size,
              style: activeStyle,
              palette: activeColor,
            ),
            size: const Size(18, 18),
          );
        },
      ),
    );
  }
}

class _RadarPulsePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double dotSize;
  final NexusPulseStyle style;
  final NexusPulseColor palette;

  _RadarPulsePainter({
    required this.progress,
    required this.color,
    required this.dotSize,
    required this.style,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    switch (style) {
      case NexusPulseStyle.neonSonarWave:
        _paintNeonSonarWave(canvas, center, maxRadius);
        break;
      case NexusPulseStyle.breathingGlowCore:
        _paintBreathingGlowCore(canvas, center, maxRadius);
        break;
      case NexusPulseStyle.telemetryHeartbeat:
        _paintTelemetryHeartbeat(canvas, center, maxRadius);
        break;
      case NexusPulseStyle.classicRadar:
        _paintClassicRadar(canvas, center, maxRadius);
        break;
    }
  }

  void _paintNeonSonarWave(Canvas canvas, Offset center, double maxRadius) {
    final primary = palette.primary;
    final secondary = palette.secondary;
    final baseRadius = dotSize / 2;

    // Ring 1 (phase 0)
    final t1 = progress;
    final r1 = baseRadius + (t1 * (maxRadius - baseRadius));
    final op1 = ((1.0 - t1) * 0.85).clamp(0.0, 1.0);
    final color1 = Color.lerp(primary, secondary, t1)!;
    final ringPaint1 = Paint()
      ..color = color1.withValues(alpha: op1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, r1, ringPaint1);

    // Ring 2 (phase 0.5 offset)
    final t2 = (progress + 0.5) % 1.0;
    final r2 = baseRadius + (t2 * (maxRadius - baseRadius));
    final op2 = ((1.0 - t2) * 0.85).clamp(0.0, 1.0);
    final color2 = Color.lerp(primary, secondary, t2)!;
    final ringPaint2 = Paint()
      ..color = color2.withValues(alpha: op2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, r2, ringPaint2);

    // Center Core: primary with subtle secondary inner ring
    final corePaint = Paint()
      ..color = primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius, corePaint);

    final innerHighlight = Paint()
      ..color = secondary.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius * 0.45, innerHighlight);
  }

  void _paintBreathingGlowCore(Canvas canvas, Offset center, double maxRadius) {
    final darkColor = palette.dark;
    final accentColor = palette.accent;

    // Smooth sinusoidal breath (0.0 -> 1.0 -> 0.0)
    final breath = 0.5 + 0.5 * math.sin((progress * 2 * math.pi) - (math.pi / 2));
    final coreRadius = (dotSize / 2) * (0.85 + (0.35 * breath));
    final dynamicColor = Color.lerp(darkColor, accentColor, breath)!;

    // Outer soft aura / halo bloom
    final haloRadius = coreRadius + (breath * (maxRadius - coreRadius));
    final haloPaint = Paint()
      ..color = dynamicColor.withValues(alpha: 0.18 + (0.18 * breath))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, haloRadius, haloPaint);

    // Secondary subtle aura ring
    final auraRingPaint = Paint()
      ..color = dynamicColor.withValues(alpha: (0.45 * (1.0 - breath)).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, haloRadius * 0.9, auraRingPaint);

    // Glowing Core Dot
    final corePaint = Paint()
      ..color = dynamicColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, coreRadius, corePaint);
  }

  void _paintTelemetryHeartbeat(Canvas canvas, Offset center, double maxRadius) {
    final primary = palette.primary;
    final secondary = palette.secondary;
    final baseRadius = dotSize / 2;

    double coreRadius = baseRadius;
    Color coreColor = primary;

    if (progress < 0.22) {
      // Beat 1: First burst
      final t = progress / 0.22;
      coreRadius = baseRadius * (1.0 + (0.28 * math.sin(t * math.pi)));
      final waveRadius = baseRadius + (t * (maxRadius * 0.7 - baseRadius));
      final ringPaint = Paint()
        ..color = primary.withValues(alpha: (1.0 - t) * 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(center, waveRadius, ringPaint);
    } else if (progress >= 0.22 && progress < 0.58) {
      // Beat 2: Larger secondary burst with secondary shift
      final t = (progress - 0.22) / 0.36;
      coreRadius = baseRadius * (1.0 + (0.35 * math.sin(t * math.pi)));
      coreColor = Color.lerp(primary, secondary, t)!;
      final waveRadius = baseRadius + (t * (maxRadius - baseRadius));
      final ringPaint = Paint()
        ..color = secondary.withValues(alpha: (1.0 - t) * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(center, waveRadius, ringPaint);
    } else {
      // Rest period
      coreRadius = baseRadius;
      coreColor = primary;
    }

    final corePaint = Paint()
      ..color = coreColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, coreRadius, corePaint);
  }

  void _paintClassicRadar(Canvas canvas, Offset center, double maxRadius) {
    final ringRadius = (dotSize / 2) + (progress * (maxRadius - (dotSize / 2)));
    final ringOpacity = (1.0 - progress).clamp(0.0, 1.0) * 0.7;
    final ringPaint = Paint()
      ..color = color.withValues(alpha: ringOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, ringRadius, ringPaint);

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, dotSize / 2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPulsePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.dotSize != dotSize ||
        oldDelegate.style != style ||
        oldDelegate.palette != palette;
  }
}
