import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/main_screen.dart';
import 'services/session_manager_service.dart';
import 'services/settings_service.dart';
import 'services/window_state_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persistent settings & sessions before running app
  await SettingsService.instance.loadSettings();
  await SessionManagerService.instance.loadSessions();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();
      WindowStateService.instance.init();

      final windowOptions = WindowOptions(
        size: const Size(1280, 780),
        minimumSize: const Size(800, 500),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        title: 'NexusFX',
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.center();
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('Window manager initialization error: $e');
    }
  }

  runApp(const NexusFxApp());
}

class NexusFxApp extends StatelessWidget {
  const NexusFxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'NexusFX',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: const MainScreen(),
        );
      },
    );
  }
}
