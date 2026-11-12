import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/settings_service.dart';

/// Reduce-motion support for looping, decorative animations.
class AppMotion {
  AppMotion._();

  /// True when the user asked for less motion, in NexusFX settings or in the
  /// OS (Windows: "Animation effects" off), which Flutter reports through
  /// [MediaQueryData.disableAnimations].
  static bool reduced(BuildContext context) =>
      SettingsService.instance.reduceMotion ||
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  static final bool _inTest = Platform.environment.containsKey('FLUTTER_TEST');

  /// Lets widget tests run the loops that are otherwise held still under
  /// `flutter test`.
  @visibleForTesting
  static bool debugAnimateInTests = false;

  static bool get _holdStill => _inTest && !debugAnimateInTests;
}

/// Keeps a looping [AnimationController] in step with the reduce-motion
/// preference: it loops normally, and rests on a still frame when motion is
/// reduced (and under `flutter test`, where an endless loop would never
/// settle).
///
/// Mix into a [State] that owns the controller, and implement
/// [loopController], [restValue] and [startLoop].
mixin ReduceMotionLoop<T extends StatefulWidget> on State<T> {
  AnimationController get loopController;

  /// Frame shown while the loop is stopped.
  double get restValue => 1.0;

  /// Whether the loop should run at all right now (e.g. only when focused).
  bool get loopActive => true;

  /// Starts the loop; override for `repeat(reverse: true)`.
  void startLoop() => loopController.repeat();

  bool _listening = false;

  /// Whether motion is currently reduced for this widget.
  bool get motionReduced => !mounted || AppMotion._holdStill || AppMotion.reduced(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listening) {
      _listening = true;
      SettingsService.instance.addListener(_onMotionSettingChanged);
    }
    syncLoop();
  }

  void _onMotionSettingChanged() {
    if (mounted) syncLoop();
  }

  /// Starts or stops the loop to match the preference and [loopActive].
  void syncLoop() {
    final c = loopController;
    if (motionReduced) {
      if (c.isAnimating) c.stop();
      c.value = restValue;
    } else if (loopActive) {
      if (!c.isAnimating) startLoop();
    } else if (c.isAnimating) {
      c.stop();
    }
  }

  @override
  void dispose() {
    if (_listening) SettingsService.instance.removeListener(_onMotionSettingChanged);
    super.dispose();
  }
}
