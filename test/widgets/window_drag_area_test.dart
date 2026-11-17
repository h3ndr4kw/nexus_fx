import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/window_drag_area.dart';

void main() {
  group('restoredWindowOrigin', () {
    test('keeps the pointer at the same horizontal proportion', () {
      // Grabbed at 25% across a 1920-wide maximized window, 20px down.
      final origin = restoredWindowOrigin(
        maximizedBounds: const Rect.fromLTWH(0, 0, 1920, 1040),
        restoredSize: const Size(1280, 780),
        pointerInWindow: const Offset(480, 20),
      );
      // Pointer stays at 25% of the restored width (320px) and 20px down.
      expect(origin, const Offset(480 - 320, 0));
    });

    test('accounts for a maximized window on a secondary monitor', () {
      final origin = restoredWindowOrigin(
        maximizedBounds: const Rect.fromLTWH(1920, 0, 2560, 1400),
        restoredSize: const Size(1280, 780),
        pointerInWindow: const Offset(2560, 10),
      );
      // Right edge grab: restored window's right edge sits under the pointer.
      expect(origin, const Offset(1920 + 2560 - 1280, 0));
    });

    test('falls back to centre when bounds have no width', () {
      final origin = restoredWindowOrigin(
        maximizedBounds: Rect.zero,
        restoredSize: const Size(1000, 600),
        pointerInWindow: const Offset(0, 5),
      );
      expect(origin, const Offset(-500, 0));
    });
  });
}
