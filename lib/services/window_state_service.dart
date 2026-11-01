import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Centralized service to manage and synchronize window states
/// (fullscreen, maximize, minimize, restore) across desktop platforms.
class WindowStateService extends ChangeNotifier
    with WindowListener, WidgetsBindingObserver {
  static WindowStateService? _instance;

  bool _isFullScreen = false;
  bool _isMaximized = false;
  bool _initialized = false;

  WindowStateService._();

  static WindowStateService get instance {
    _instance ??= WindowStateService._();
    return _instance!;
  }

  bool get isFullScreen => _isFullScreen;
  bool get isMaximized => _isMaximized;

  void init() {
    if (_initialized) return;
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        _initialized = true;
        windowManager.addListener(this);
        WidgetsBinding.instance.addObserver(this);
        checkWindowState();
      }
    } catch (_) {
      // In test environments or when binding is not yet attached
    }
  }

  /// Query the actual window manager state and notify if values differ.
  Future<void> checkWindowState() async {
    try {
      final maximized = await windowManager.isMaximized();
      final fullScreen = await windowManager.isFullScreen();
      if (_isMaximized != maximized || _isFullScreen != fullScreen) {
        _isMaximized = maximized;
        _isFullScreen = fullScreen;
        notifyListeners();
      }
    } catch (_) {
      // Gracefully ignore during test or non-desktop environment
    }
  }

  /// Toggles fullscreen mode and updates state immediately.
  Future<void> toggleFullScreen() async {
    final target = !_isFullScreen;
    _isFullScreen = target;
    notifyListeners();

    try {
      await windowManager.setFullScreen(target);
      // Give window manager a moment to settle, then verify state
      await Future.delayed(const Duration(milliseconds: 50));
      await checkWindowState();
    } catch (_) {
      // Gracefully ignore during test or non-desktop environment
    }
  }

  /// Toggles maximize/unmaximize mode and updates state immediately.
  Future<void> toggleMaximize() async {
    final target = !_isMaximized;
    _isMaximized = target;
    notifyListeners();

    try {
      if (target) {
        await windowManager.maximize();
      } else {
        await windowManager.unmaximize();
      }
      await Future.delayed(const Duration(milliseconds: 50));
      await checkWindowState();
    } catch (_) {
      // Gracefully ignore during test or non-desktop environment
    }
  }

  /// Minimizes the window.
  Future<void> minimize() async {
    try {
      await windowManager.minimize();
    } catch (_) {}
  }

  /// Centers the window if window manager is initialized.
  Future<void> center() async {
    if (!_initialized) return;
    try {
      await windowManager.center();
    } catch (_) {}
  }

  @visibleForTesting
  VoidCallback? onCloseRequestedForTesting;

  /// Closes the window.
  Future<void> close() async {
    onCloseRequestedForTesting?.call();
    try {
      await windowManager.close();
    } catch (_) {}
  }

  // --- WindowListener overrides ---

  @override
  void onWindowMaximize() {
    _isMaximized = true;
    _isFullScreen = false;
    notifyListeners();
  }

  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    notifyListeners();
  }

  @override
  void onWindowRestore() {
    _isMaximized = false;
    _isFullScreen = false;
    notifyListeners();
  }

  @override
  void onWindowEnterFullScreen() {
    _isFullScreen = true;
    notifyListeners();
  }

  @override
  void onWindowLeaveFullScreen() {
    _isFullScreen = false;
    notifyListeners();
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'enter-full-screen') {
      _isFullScreen = true;
      notifyListeners();
    } else if (eventName == 'leave-full-screen') {
      _isFullScreen = false;
      notifyListeners();
    } else if (eventName == 'maximize') {
      _isMaximized = true;
      _isFullScreen = false;
      notifyListeners();
    } else if (eventName == 'unmaximize' || eventName == 'restore') {
      _isMaximized = false;
      _isFullScreen = false;
      notifyListeners();
    }
  }

  // --- WidgetsBindingObserver overrides ---

  @override
  void didChangeMetrics() {
    checkWindowState();
  }

  // --- Testing utilities ---

  @visibleForTesting
  void setFullScreenForTesting(bool value) {
    _isFullScreen = value;
    notifyListeners();
  }

  @visibleForTesting
  void setMaximizedForTesting(bool value) {
    _isMaximized = value;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() {
    _isFullScreen = false;
    _isMaximized = false;
    onCloseRequestedForTesting = null;
    notifyListeners();
  }
}
