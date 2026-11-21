import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'models/nexus_tool.dart';
import 'screens/main_screen.dart';
import 'services/known_hosts_service.dart';
import 'services/nexus_tool_registry.dart';
import 'services/session_manager_service.dart';
import 'services/settings_service.dart';
import 'services/window_state_service.dart';
import 'theme/app_theme.dart';
import 'widgets/host_key_dialog.dart';

/// Lets services (such as the host key prompt) open dialogs without a
/// widget context of their own.
final GlobalKey<NavigatorState> nexusNavigatorKey = GlobalKey<NavigatorState>();

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
  await KnownHostsService.instance.load();
  KnownHostsService.instance.prompter = (request) async {
    final context = nexusNavigatorKey.currentContext;
    if (context == null || !context.mounted) return HostKeyDecision.reject;
    return showHostKeyDialog(context, request);
  };

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

class NexusFxApp extends StatefulWidget {
  final String title;
  final List<NexusTool>? customTools;

  const NexusFxApp({
    super.key,
    this.title = 'NexusFX',
    this.customTools,
  });

  @override
  State<NexusFxApp> createState() => _NexusFxAppState();
}

class _NexusFxAppState extends State<NexusFxApp> {
  AppThemeType _theme = AppTheme.currentTheme;

  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// Most widgets read colors straight from [AppTheme] instead of
  /// `Theme.of(context)`, so they don't depend on the theme and would keep
  /// the old palette. Mark the whole tree dirty when the palette changes.
  void _onSettingsChanged() {
    final theme = SettingsService.instance.appTheme;
    if (theme == _theme) return;
    _theme = theme;
    void markAll(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markAll);
    }
    (context as Element).visitChildren(markAll);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: nexusNavigatorKey,
          title: widget.title,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.theme,
          // Widgets reading AppTheme directly switch at once; animating
          // only the Material ones would show a mixed palette for a moment.
          themeAnimationDuration: Duration.zero,
          home: MainScreen(
            appTitle: widget.title,
            customTools: widget.customTools,
          ),
        );
      },
    );
  }
}
