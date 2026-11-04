import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'models/nexus_tool.dart';
import 'screens/main_screen.dart';
import 'services/nexus_tool_registry.dart';
import 'services/session_manager_service.dart';
import 'services/settings_service.dart';
import 'services/window_state_service.dart';
import 'theme/app_theme.dart';

void main() async {
  await runNexusFxApp();
}

/// Initializes and runs the NexusFX desktop application.
///
/// Downstream projects can invoke [runNexusFxApp] with custom [tools] and
/// a custom [title] so they automatically inherit all upstream updates.
Future<void> runNexusFxApp({
  List<NexusTool> tools = const [],
  String title = 'NexusFX',
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (tools.isNotEmpty) {
    NexusToolRegistry.instance.registerAll(tools);
  }

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
        title: title,
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

  runApp(NexusFxApp(title: title));
}

class NexusFxApp extends StatelessWidget {
  final String title;
  final List<NexusTool>? customTools;

  const NexusFxApp({
    super.key,
    this.title = 'NexusFX',
    this.customTools,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: title,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: MainScreen(
            appTitle: title,
            customTools: customTools,
          ),
        );
      },
    );
  }
}
