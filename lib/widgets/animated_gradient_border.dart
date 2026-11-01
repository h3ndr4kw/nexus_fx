import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// Style presets for the animated border beam.
enum GradientBorderPreset {
  /// Iconic Google Stitch / Gemini AI light beam:
  /// Blue -> Violet -> Cyan with a bright luminous spark at the head.
  geminiAurora,

  /// Soft electric cyan & sky blue beam
  cyberCyan,

  /// Google multi-color light stream (Blue, Red, Yellow, Green)
  googleRainbow,
}

/// A high-performance, perimeter-following animated border beam inspired by
/// Google Stitch (`stitch.withgoogle.com`) and modern AI prompt inputs.
///
/// Unlike naive angular sweep gradients (which distort and jump erratically
/// on rectangular text boxes), this widget computes the exact perimeter
/// path metric of the rounded rectangle and glides a glowing light beam
/// at a constant, buttery-smooth linear velocity around every edge and corner.
class AnimatedGradientBorder extends StatefulWidget {
  final Widget child;

  /// Thickness of the border stroke. Default is 1.5.
  final double borderWidth;

  /// Corner radius of the container. Default is 8.0.
  final BorderRadius borderRadius;

  /// Blur radius of the outer neon glow. Set to 0 to disable glow. Default is 8.0.
  final double glowRadius;

  /// Maximum opacity of the glow effect (0.0 to 1.0). Default is 0.75.
  final double glowOpacity;

  /// Duration for one complete cycle around the perimeter.
  /// If null, automatically uses [SettingsService.instance.borderAnimationDurationObj].
  final Duration? duration;

  /// Fraction of the perimeter covered by the beam (0.1 to 0.6). Default is 0.35 (35%).
  final double beamLengthFactor;

  /// Number of simultaneous beams traveling along the perimeter. Default is 1.
  final int beamCount;

  /// Custom beam colors from tail (transparent/dark) to head (bright highlight).
  /// If null, uses [preset].
  final List<Color>? colors;

  /// Color stops matching [colors].
  final List<double>? stops;

  /// Preset style used when [colors] is null. Default is [GradientBorderPreset.geminiAurora].
  final GradientBorderPreset preset;

  /// When true, the beam animation and glow only activate when [focusNode] is focused.
  /// When false, it animates continuously. Default is false.
  final bool animateOnlyOnFocus;

  /// Optional FocusNode to automatically trigger animation on focus.
  final FocusNode? focusNode;

  /// Explicit override to turn animation on (true) or off (false).
  final bool? active;

  /// Base border color drawn under the beam so the input has a clean outline.
  /// If null, a subtle border is drawn.
  final Color? idleBorderColor;

  /// Background color of the container, if any.
  final Color? backgroundColor;

  const AnimatedGradientBorder({
    super.key,
    required this.child,
    this.borderWidth = 1.5,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.glowRadius = 8.0,
    this.glowOpacity = 0.75,
    this.duration,
    this.beamLengthFactor = 0.35,
    this.beamCount = 1,
    this.colors,
    this.stops,
    this.preset = GradientBorderPreset.geminiAurora,
    this.animateOnlyOnFocus = false,
    this.focusNode,
    this.active,
    this.idleBorderColor,
    this.backgroundColor,
  });

  @override
  State<AnimatedGradientBorder> createState() => _AnimatedGradientBorderState();
}

class _AnimatedGradientBorderState extends State<AnimatedGradientBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Google Stitch / Gemini signature palette:
  // Starts transparent at tail, ramps through Gemini Blue, Violet, Cyan, and white head.
  static const List<Color> _geminiColors = [
    Color(0x004285F4), // Transparent Blue (tail)
    Color(0x664285F4), // Soft Blue
    Color(0xFF4285F4), // Solid Google Blue
    Color(0xFF9B72CF), // Violet / Purple
    Color(0xFF56CCF2), // Electric Cyan
    Color(0xFFFFFFFF), // Bright spark tip (head)
  ];

  static const List<double> _geminiStops = [
    0.0,
    0.2,
    0.45,
    0.7,
    0.9,
    1.0,
  ];

  static const List<Color> _cyberCyanColors = [
    Color(0x000072FF),
    Color(0x660072FF),
    Color(0xFF0072FF),
    Color(0xFF00C6FF),
    Color(0xFF80EEFF),
    Color(0xFFFFFFFF),
  ];

  static const List<Color> _googleRainbowColors = [
    Color(0x004285F4),
    Color(0xFF4285F4), // Blue
    Color(0xFFEA4335), // Red
    Color(0xFFFBBC05), // Yellow
    Color(0xFF34A853), // Green
    Color(0xFFFFFFFF), // White tip
  ];

  List<Color> get _effectiveColors {
    if (widget.colors != null && widget.colors!.isNotEmpty) {
      return widget.colors!;
    }
    switch (widget.preset) {
      case GradientBorderPreset.geminiAurora:
        return _geminiColors;
      case GradientBorderPreset.cyberCyan:
        return _cyberCyanColors;
      case GradientBorderPreset.googleRainbow:
        return _googleRainbowColors;
    }
  }

  List<double>? get _effectiveStops {
    if (widget.stops != null) return widget.stops;
    if (widget.colors == null && widget.preset == GradientBorderPreset.geminiAurora) {
      return _geminiStops;
    }
    return null;
  }

  bool get _isCurrentlyActive {
    if (widget.active != null) return widget.active!;
    if (widget.animateOnlyOnFocus) {
      return widget.focusNode?.hasFocus ?? false;
    }
    return true;
  }

  static final bool _isRunningInTest = () {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }();

  Duration get _effectiveDuration =>
      widget.duration ?? SettingsService.instance.borderAnimationDurationObj;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _effectiveDuration,
    );

    widget.focusNode?.addListener(_onFocusChange);
    SettingsService.instance.addListener(_onSettingsChange);

    if (_isCurrentlyActive) {
      if (_isRunningInTest) {
        _controller.value = 0.5;
      } else {
        _controller.repeat();
      }
    }
  }

  void _onSettingsChange() {
    if (!mounted) return;
    if (widget.duration == null) {
      final newDuration = SettingsService.instance.borderAnimationDurationObj;
      if (_controller.duration != newDuration) {
        _controller.duration = newDuration;
        if (_isCurrentlyActive && !_isRunningInTest) {
          _controller.repeat();
        }
      }
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() {});
    _syncController();
  }

  void _syncController() {
    if (_isRunningInTest) {
      _controller.value = 0.5;
      return;
    }
    if (_isCurrentlyActive) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedGradientBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
    }
    if (widget.duration != oldWidget.duration) {
      _controller.duration = _effectiveDuration;
    }
    _syncController();
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChange);
    widget.focusNode?.removeListener(_onFocusChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _isCurrentlyActive;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _PerimeterBeamBackgroundPainter(
            animationValue: active ? _controller.value : 0.0,
            borderWidth: widget.borderWidth,
            borderRadius: widget.borderRadius,
            glowRadius: active ? widget.glowRadius : 0.0,
            glowOpacity: widget.glowOpacity,
            beamLengthFactor: widget.beamLengthFactor,
            beamCount: widget.beamCount,
            colors: _effectiveColors,
            stops: _effectiveStops,
            isActive: active,
            backgroundColor: widget.backgroundColor,
          ),
          foregroundPainter: _PerimeterBeamForegroundPainter(
            animationValue: active ? _controller.value : 0.0,
            borderWidth: widget.borderWidth,
            borderRadius: widget.borderRadius,
            beamLengthFactor: widget.beamLengthFactor,
            beamCount: widget.beamCount,
            colors: _effectiveColors,
            stops: _effectiveStops,
            isActive: active,
            idleBorderColor: widget.idleBorderColor,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Paints the optional background fill and the outer glowing aura of the moving beam.
class _PerimeterBeamBackgroundPainter extends CustomPainter {
  final double animationValue;
  final double borderWidth;
  final BorderRadius borderRadius;
  final double glowRadius;
  final double glowOpacity;
  final double beamLengthFactor;
  final int beamCount;
  final List<Color> colors;
  final List<double>? stops;
  final bool isActive;
  final Color? backgroundColor;

  _PerimeterBeamBackgroundPainter({
    required this.animationValue,
    required this.borderWidth,
    required this.borderRadius,
    required this.glowRadius,
    required this.glowOpacity,
    required this.beamLengthFactor,
    required this.beamCount,
    required this.colors,
    required this.stops,
    required this.isActive,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    // 1. Draw solid background if provided
    if (backgroundColor != null && backgroundColor != Colors.transparent) {
      final bgPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = backgroundColor!;
      canvas.drawRRect(rrect, bgPaint);
    }

    // 2. Draw outer ambient glow along perimeter if active
    if (!isActive || glowRadius <= 0 || colors.isEmpty) return;

    final strokeRect = rect.deflate(borderWidth / 2);
    final path = Path()..addRRect(borderRadius.toRRect(strokeRect));
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final totalLength = metric.length;
    if (totalLength <= 0) return;

    final beamLength = totalLength * beamLengthFactor.clamp(0.05, 0.95);
    const int segments = 24;
    final step = beamLength / segments;

    for (int b = 0; b < beamCount; b++) {
      final offsetFrac = (b / beamCount);
      final head = ((animationValue + offsetFrac) * totalLength) % totalLength;
      final tail = head - beamLength;

      for (int i = 0; i < segments; i++) {
        final dStart = tail + i * step;
        final dEnd = dStart + step;
        final t = (i + 0.5) / segments;

        final color = _sampleGradient(colors, stops, t);
        final alpha = math.pow(t, 1.4).toDouble() * glowOpacity;
        if (alpha <= 0.01) continue;

        final segPath = _extractSubPath(metric, dStart, dEnd, totalLength);

        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth * 2.8
          ..color = color.withValues(alpha: (color.a * alpha).clamp(0.0, 1.0))
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);

        canvas.drawPath(segPath, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PerimeterBeamBackgroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isActive != isActive ||
        oldDelegate.glowRadius != glowRadius ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

/// Paints the crisp border base and the radiant foreground laser beam.
class _PerimeterBeamForegroundPainter extends CustomPainter {
  final double animationValue;
  final double borderWidth;
  final BorderRadius borderRadius;
  final double beamLengthFactor;
  final int beamCount;
  final List<Color> colors;
  final List<double>? stops;
  final bool isActive;
  final Color? idleBorderColor;

  _PerimeterBeamForegroundPainter({
    required this.animationValue,
    required this.borderWidth,
    required this.borderRadius,
    required this.beamLengthFactor,
    required this.beamCount,
    required this.colors,
    required this.stops,
    required this.isActive,
    required this.idleBorderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || borderWidth <= 0) return;

    final rect = Offset.zero & size;
    final strokeRect = rect.deflate(borderWidth / 2);
    final strokeRRect = borderRadius.toRRect(strokeRect);

    // 1. Draw base idle border so the container has clean structure
    final baseColor = idleBorderColor ??
        (isActive
            ? const Color(0xFF333538)
            : const Color(0xFF2B2D31));
    if (baseColor != Colors.transparent) {
      final basePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.min(1.0, borderWidth)
        ..color = baseColor;
      canvas.drawRRect(strokeRRect, basePaint);
    }

    if (!isActive || colors.isEmpty) return;

    // 2. Draw crisp light beam traveling along the exact perimeter path
    final path = Path()..addRRect(strokeRRect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final totalLength = metric.length;
    if (totalLength <= 0) return;

    final beamLength = totalLength * beamLengthFactor.clamp(0.05, 0.95);
    const int segments = 28;
    final step = beamLength / segments;

    for (int b = 0; b < beamCount; b++) {
      final offsetFrac = (b / beamCount);
      final head = ((animationValue + offsetFrac) * totalLength) % totalLength;
      final tail = head - beamLength;

      for (int i = 0; i < segments; i++) {
        final dStart = tail + i * step;
        final dEnd = dStart + step;
        final t = (i + 0.5) / segments;

        final color = _sampleGradient(colors, stops, t);
        final alpha = math.pow(t, 1.2).toDouble();
        if (alpha <= 0.02) continue;

        final segPath = _extractSubPath(metric, dStart, dEnd, totalLength);

        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = color.withValues(alpha: (color.a * alpha).clamp(0.0, 1.0))
          ..strokeCap = StrokeCap.round;

        canvas.drawPath(segPath, strokePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PerimeterBeamForegroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isActive != isActive ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.idleBorderColor != idleBorderColor;
  }
}

/// Extracts a subsegment of a circular path metric, seamlessly handling wrap-around.
Path _extractSubPath(PathMetric metric, double start, double end, double totalLength) {
  double s = start % totalLength;
  double e = end % totalLength;
  if (s < 0) s += totalLength;
  if (e < 0) e += totalLength;

  if (s < e) {
    return metric.extractPath(s, e);
  } else {
    // Crosses perimeter boundary seam
    final p = Path();
    p.addPath(metric.extractPath(s, totalLength), Offset.zero);
    p.addPath(metric.extractPath(0, e), Offset.zero);
    return p;
  }
}

/// Samples gradient color at normalized position `t` (0.0 to 1.0).
Color _sampleGradient(List<Color> colors, List<double>? stops, double t) {
  if (colors.isEmpty) return Colors.transparent;
  if (colors.length == 1) return colors.first;

  final effectiveStops = stops ??
      List.generate(colors.length, (i) => i / (colors.length - 1));

  if (t <= effectiveStops.first) return colors.first;
  if (t >= effectiveStops.last) return colors.last;

  for (int i = 0; i < effectiveStops.length - 1; i++) {
    final s0 = effectiveStops[i];
    final s1 = effectiveStops[i + 1];
    if (t >= s0 && t <= s1) {
      final localT = (t - s0) / (s1 - s0);
      return Color.lerp(colors[i], colors[i + 1], localT) ?? colors[i];
    }
  }
  return colors.last;
}
