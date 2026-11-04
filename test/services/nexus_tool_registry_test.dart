import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/nexus_fx.dart';

class _MockCounterTool extends NexusTool {
  final void Function(NexusToolContext ctx)? onActionTriggered;

  _MockCounterTool({this.onActionTriggered});

  @override
  String get id => 'mock_counter_tool';

  @override
  String get title => 'Cluster Monitor';

  @override
  String get subtitle => 'Real-time cluster health & metrics';

  @override
  IconData get icon => Icons.analytics_outlined;

  @override
  Widget buildView(BuildContext context, NexusToolContext toolContext) {
    return _MockCounterView(toolContext: toolContext);
  }

  @override
  List<NexusToolCommand> buildCommands(NexusToolContext toolContext) {
    return [
      NexusToolCommand(
        id: 'run_cluster_diag',
        label: 'Run Cluster Diagnostics',
        subtitle: 'Execute health check across active nodes',
        icon: Icons.health_and_safety_outlined,
        badge: 'TOOL',
        onExecute: (ctx) {
          onActionTriggered?.call(ctx);
        },
      ),
    ];
  }
}

class _MockCounterView extends StatefulWidget {
  final NexusToolContext toolContext;

  const _MockCounterView({required this.toolContext});

  @override
  State<_MockCounterView> createState() => _MockCounterViewState();
}

class _MockCounterViewState extends State<_MockCounterView> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Cluster Monitor Active: $_counter'),
          Text('Sessions Count: ${widget.toolContext.sessionManager.sessions.length}'),
          ElevatedButton(
            key: const ValueKey('increment_tool_counter'),
            onPressed: () => setState(() => _counter++),
            child: const Text('Increment'),
          ),
          ElevatedButton(
            key: const ValueKey('switch_to_terminal_btn'),
            onPressed: () => widget.toolContext.navigateToTerminal(),
            child: const Text('Go To Terminal'),
          ),
        ],
      ),
    );
  }
}

void main() {
  late Directory tempDir;
  late File sessionFile;
  late SessionManagerService sessionService;
  late NexusToolRegistry registry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nexus_fx_tool_test_');
    sessionFile = File('${tempDir.path}/sessions.json');
    sessionService = SessionManagerService.forTesting();
    await sessionService.loadSessions(customFilePath: sessionFile.path);
    registry = NexusToolRegistry.forTesting();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('NexusToolRegistry Unit Tests', () {
    test('registers, updates, unregisters, and clears custom tools with notifications', () {
      int notifyCount = 0;
      registry.addListener(() => notifyCount++);

      final tool = _MockCounterTool();
      registry.registerTool(tool);

      expect(registry.tools.length, 1);
      expect(registry.getToolById('mock_counter_tool')?.title, 'Cluster Monitor');
      expect(notifyCount, 1);

      // Re-registering with same ID updates in place without duplicating
      registry.registerTool(tool);
      expect(registry.tools.length, 1);
      expect(notifyCount, 2);

      registry.unregisterTool('mock_counter_tool');
      expect(registry.tools, isEmpty);
      expect(notifyCount, 3);

      registry.registerAll([tool]);
      expect(registry.tools.length, 1);

      registry.clear();
      expect(registry.tools, isEmpty);
    });
  });

  group('MainScreen Custom Tools Integration Tests', () {
    testWidgets('renders custom tool in sidebar, switches view, preserves state, and provides NexusToolContext', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      final tool = _MockCounterTool();
      registry.registerTool(tool);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MainScreen(
            sessionManager: sessionService,
            toolRegistry: registry,
            suppressStartupDialog: true,
            appTitle: 'CustomOps FX',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify custom app title and custom tool in sidebar
      expect(find.text('CustomOps FX'), findsOneWidget);
      expect(find.text('Cluster Monitor'), findsOneWidget);
      expect(find.byIcon(Icons.analytics_outlined), findsOneWidget);

      // Tap the custom tool in the left sidebar
      await tester.tap(find.text('Cluster Monitor'));
      await tester.pumpAndSettle();

      // Verify custom tool view is displayed and receives NexusToolContext
      expect(find.text('Cluster Monitor Active: 0'), findsOneWidget);
      expect(find.textContaining('Sessions Count:'), findsOneWidget);

      // Increment stateful counter inside custom tool
      await tester.tap(find.byKey(const ValueKey('increment_tool_counter')));
      await tester.pumpAndSettle();
      expect(find.text('Cluster Monitor Active: 1'), findsOneWidget);

      // Switch to Sessions tab and back to verify state preservation in IndexedStack
      await tester.tap(find.text('Sessions'));
      await tester.pumpAndSettle();
      expect(find.text('All Sessions'), findsOneWidget);

      await tester.tap(find.text('Cluster Monitor'));
      await tester.pumpAndSettle();
      expect(find.text('Cluster Monitor Active: 1'), findsOneWidget);

      // Test NexusToolContext.navigateToTerminal()
      await tester.tap(find.byKey(const ValueKey('switch_to_terminal_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(RightSidebarToggleButton), findsOneWidget);
    });

    testWidgets('exposes custom tool and its commands in Command Palette (Ctrl+Shift+P)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      NexusToolContext? capturedContext;
      final tool = _MockCounterTool(
        onActionTriggered: (ctx) => capturedContext = ctx,
      );
      registry.registerTool(tool);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MainScreen(
            sessionManager: sessionService,
            toolRegistry: registry,
            suppressStartupDialog: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Full Command Palette via Ctrl+Shift+P
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Verify both "Open Tool: Cluster Monitor" and "Run Cluster Diagnostics" appear
      expect(find.text('Open Tool: Cluster Monitor'), findsOneWidget);
      expect(find.text('Run Cluster Diagnostics'), findsOneWidget);

      // Tap "Run Cluster Diagnostics" command
      await tester.tap(find.text('Run Cluster Diagnostics'));
      await tester.pumpAndSettle();

      expect(capturedContext, isNotNull);
      expect(capturedContext!.sessionManager, equals(sessionService));
      expect(capturedContext!.tabController, isNotNull);
      expect(capturedContext!.broadcastCoordinator, isNotNull);
    });
  });
}
