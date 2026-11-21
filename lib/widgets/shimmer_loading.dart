import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Color? _baseColor;
  final Color? _highlightColor;
  Color get baseColor => _baseColor ?? AppTheme.adaptive(const Color(0xFF1B2433));
  Color get highlightColor => _highlightColor ?? AppTheme.adaptive(const Color(0xFF2E3D56));

  static bool enableAnimation = true;

  const ShimmerEffect({
    super.key,
    required this.child,
    Color? baseColor,
    Color? highlightColor,
  })  : _baseColor = baseColor,
        _highlightColor = highlightColor;

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with TickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettings);
  }

  void _onSettings() {
    if (mounted) setState(_syncMotion);
  }

  /// Shimmer is purely decorative: with reduced motion the placeholder is
  /// shown still.
  void _syncMotion() {
    final animate = ShimmerEffect.enableAnimation && !AppMotion.reduced(context);
    if (animate && _ctrl == null) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat();
    } else if (!animate && _ctrl != null) {
      _ctrl!.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettings);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ShimmerEffect.enableAnimation || _ctrl == null) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: _ctrl!.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0.0,
      0.0,
    );
  }
}

class ShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? color;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 6,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? AppTheme.surfaceColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
