import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/controllers/session_fullscreen_controller.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/services/window_state_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final window = WindowStateService.instance;
  late SessionFullscreenController controller;
  late SshConnection a;

  setUp(() {
    window.resetForTesting();
    controller = SessionFullscreenController();
    a = SshConnection(id: 'a', host: '10.0.0.1', port: 22, label: 'A');
  });

  tearDown(() {
    controller.dispose();
    window.resetForTesting();
  });

  test('enter sets target and puts the window in fullscreen', () async {
    await controller.enter(a);
    expect(controller.isActive, isTrue);
    expect(controller.target, same(a));
    expect(window.isFullScreen, isTrue);
  });

  test('exit restores a window that was not fullscreen before', () async {
    await controller.enter(a);
    await controller.exit();
    expect(controller.isActive, isFalse);
    expect(controller.target, isNull);
    expect(window.isFullScreen, isFalse);
  });

  test('exit keeps the window fullscreen when it was already F11 fullscreen',
      () async {
    window.setFullScreenForTesting(true);
    await controller.enter(a);
    await controller.exit();
    expect(controller.isActive, isFalse);
    expect(window.isFullScreen, isTrue);
  });

  test('leaving OS fullscreen ends session fullscreen', () async {
    await controller.enter(a);
    window.setFullScreenForTesting(false);
    expect(controller.isActive, isFalse);
  });

  test('a transient non-fullscreen report while entering does not exit',
      () async {
    final pending = controller.enter(a);
    window.setFullScreenForTesting(false);
    await pending;
    expect(controller.isActive, isTrue);
  });

  test('onConnectionRemoved exits only for the fullscreen target', () async {
    await controller.enter(a);
    controller.onConnectionRemoved('b');
    expect(controller.isActive, isTrue);
    controller.onConnectionRemoved('a');
    await Future<void>.delayed(Duration.zero);
    expect(controller.isActive, isFalse);
  });

  test('toggle enters then exits', () async {
    await controller.toggle(a);
    expect(controller.isActive, isTrue);
    await controller.toggle(a);
    expect(controller.isActive, isFalse);
    await controller.toggle(null);
    expect(controller.isActive, isFalse);
  });

  test('isSessionFullscreenShortcut matches Ctrl+Shift+Enter only', () {
    expect(
        isSessionFullscreenShortcut(LogicalKeyboardKey.enter,
            ctrl: true, shift: true, alt: false),
        isTrue);
    expect(
        isSessionFullscreenShortcut(LogicalKeyboardKey.numpadEnter,
            ctrl: true, shift: true, alt: false),
        isTrue);
    expect(
        isSessionFullscreenShortcut(LogicalKeyboardKey.enter,
            ctrl: true, shift: false, alt: false),
        isFalse);
    expect(
        isSessionFullscreenShortcut(LogicalKeyboardKey.enter,
            ctrl: true, shift: true, alt: true),
        isFalse);
    expect(
        isSessionFullscreenShortcut(LogicalKeyboardKey.escape,
            ctrl: true, shift: true, alt: false),
        isFalse);
  });
}
