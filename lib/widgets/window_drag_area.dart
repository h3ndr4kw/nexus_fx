import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_log.dart';

/// Where to place a window that is restored from maximized mid-drag so the
/// pointer keeps the same horizontal proportion across the title bar and the
/// same distance from the window top, like a native Windows caption drag.
///
/// All values are logical pixels; [maximizedBounds] is in screen coordinates
/// and [pointerInWindow] is relative to the window's top-left corner.
Offset restoredWindowOrigin({
  required Rect maximizedBounds,
  required Size restoredSize,
  required Offset pointerInWindow,
}) {
  final pointerOnScreen = maximizedBounds.topLeft + pointerInWindow;
  final ratio = maximizedBounds.width <= 0
      ? 0.5
      : (pointerInWindow.dx / maximizedBounds.width).clamp(0.0, 1.0);
  return Offset(
    pointerOnScreen.dx - restoredSize.width * ratio,
    pointerOnScreen.dy - pointerInWindow.dy,
  );
}

/// Drag-to-move area for the custom title bar. Unlike window_manager's
/// DragToMoveArea it also handles a maximized window: Windows ignores the
/// SC_MOVE command `startDragging()` sends while maximized, so the window is
/// restored under the pointer first and then dragged.
class WindowDragArea extends StatelessWidget {
  final Widget child;

  const WindowDragArea({super.key, required this.child});

  Future<void> _onPanStart(DragStartDetails details) async {
    try {
      if (await windowManager.isMaximized()) {
        final maximizedBounds = await windowManager.getBounds();
        await windowManager.unmaximize();
        final restoredSize = await windowManager.getSize();
        await windowManager.setPosition(restoredWindowOrigin(
          maximizedBounds: maximizedBounds,
          restoredSize: restoredSize,
          pointerInWindow: details.globalPosition,
        ));
      }
      await windowManager.startDragging();
    } catch (e, st) {
      AppLog.warningUnlessPluginMissing('Window: start dragging', e, st);
      // Not available in tests / before window_manager is initialised.
    }
  }

  Future<void> _onDoubleTap() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (e, st) {
      AppLog.warningUnlessPluginMissing('Window: toggle maximize', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: _onPanStart,
      onDoubleTap: _onDoubleTap,
      child: child,
    );
  }
}
