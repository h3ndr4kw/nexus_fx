import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/ssh_service.dart';
import '../services/window_state_service.dart';

/// Ctrl+Shift+Enter (main or numpad Enter) toggles session fullscreen.
bool isSessionFullscreenShortcut(
  LogicalKeyboardKey key, {
  required bool ctrl,
  required bool shift,
  required bool alt,
}) {
  final isEnter =
      key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
  return isEnter && ctrl && shift && !alt;
}

/// Tracks which SSH session fills the screen and keeps the OS window's
/// fullscreen state in step with it.
class SessionFullscreenController extends ChangeNotifier {
  SessionFullscreenController({WindowStateService? window})
      : _window = window ?? WindowStateService.instance {
    _window.addListener(_onWindowChanged);
  }

  final WindowStateService _window;
  SshConnection? _target;
  bool _wasWindowFullscreen = false;
  // While our own setFullScreen(true) is in flight the window may still
  // report "not fullscreen"; that must not end the session fullscreen.
  bool _settling = false;

  SshConnection? get target => _target;
  bool get isActive => _target != null;

  Future<void> enter(SshConnection conn) async {
    if (identical(_target, conn)) return;
    if (_target == null) {
      _wasWindowFullscreen = _window.isFullScreen;
    }
    _target = conn;
    notifyListeners();
    if (!_window.isFullScreen) {
      _settling = true;
      try {
        await _window.setFullScreen(true);
      } finally {
        _settling = false;
      }
    }
  }

  Future<void> exit() async {
    if (_target == null) return;
    _target = null;
    notifyListeners();
    if (!_wasWindowFullscreen && _window.isFullScreen) {
      await _window.setFullScreen(false);
    }
  }

  Future<void> toggle(SshConnection? conn) async {
    if (isActive) {
      await exit();
    } else if (conn != null) {
      await enter(conn);
    }
  }

  void onConnectionRemoved(String connectionId) {
    if (_target?.id == connectionId) {
      exit();
    }
  }

  void _onWindowChanged() {
    if (isActive && !_settling && !_window.isFullScreen) {
      _target = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _window.removeListener(_onWindowChanged);
    super.dispose();
  }
}
