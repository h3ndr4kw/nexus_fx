import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/screens/nexus_screen.dart';
import 'package:nexus_fx/screens/sessions_screen.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/fuzzy_searchable_dropdown.dart';
import 'package:nexus_fx/widgets/session_properties_dialog.dart';

void main() {
  group('Environment Guardrails & Badges', () {
    late Directory tempDir;
    late File sessionFile;
    late SessionManagerService sessionManager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nexus_env_test_');
      sessionFile = File('${tempDir.path}/sessions.json');
      sessionManager = SessionManagerService.forTesting();
      await sessionManager.loadSessions(customFilePath: sessionFile.path);
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('SessionsScreen renders environment tags for dev and prod sessions', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.runAsync(() async {
        await sessionManager.createSession(SessionProfile(
          id: 'sess_dev_1',
          name: 'DEV_CLUSTER',
          protocol: SessionProtocol.ssh,
          host: '10.0.0.1',
          environment: SessionEnvironment.dev,
          modifiedAt: DateTime.now(),
        ));

        await sessionManager.createSession(SessionProfile(
          id: 'sess_prod_1',
          name: 'PROD_DATABASE',
          protocol: SessionProtocol.ssh,
          host: '10.0.0.2',
          environment: SessionEnvironment.prod,
          modifiedAt: DateTime.now(),
        ));
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SessionsScreen(
              sessionManager: sessionManager,
              onConnectSessions: (_, {openInRightSplit = false}) {},
              onOpenInFileExplorer: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('DEV_CLUSTER'), findsOneWidget);
      expect(find.text('PROD_DATABASE'), findsOneWidget);

      // Verify environment tag pills
      expect(find.text('DEV'), findsWidgets);
      expect(find.text('PROD'), findsOneWidget);
    });

    testWidgets('NexusScreen displays environment badges on tabs and warning banner for prod', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      final nexusKey = GlobalKey<NexusScreenState>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NexusScreen(key: nexusKey),
          ),
        ),
      );
      await tester.pump();

      // Initially empty, no warning banner
      expect(find.byKey(const ValueKey('prod_guardrail_banner')), findsNothing);

      // Add a DEV tab
      final devConn = SshConnection(
        id: 'conn_dev',
        host: '10.0.0.1',
        port: 22,
        label: 'DEV_NODE',
        environment: SessionEnvironment.dev,
      );
      devConn.setConnectedForTesting(true);
      nexusKey.currentState!.addConnectionForTesting(devConn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('tab_env_badge_dev')), findsOneWidget);
      expect(find.byKey(const ValueKey('prod_guardrail_banner')), findsNothing);

      // Add a PROD tab
      final prodConn = SshConnection(
        id: 'conn_prod',
        host: '10.0.0.2',
        port: 22,
        label: 'PROD_NODE',
        environment: SessionEnvironment.prod,
      );
      prodConn.setConnectedForTesting(true);
      nexusKey.currentState!.addConnectionForTesting(prodConn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('tab_env_badge_prod')), findsOneWidget);

      // Switch to PROD tab
      nexusKey.currentState!.tabController.setActiveTab(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Warning banner MUST be visible now
      expect(find.byKey(const ValueKey('prod_guardrail_banner')), findsOneWidget);
      expect(find.textContaining('PRODUCTION ENVIRONMENT'), findsOneWidget);

      // Switch back to DEV tab
      nexusKey.currentState!.tabController.setActiveTab(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Warning banner MUST disappear
      expect(find.byKey(const ValueKey('prod_guardrail_banner')), findsNothing);

      // Clean up tabs
      nexusKey.currentState!.tabController.closeAllTabs();
      await tester.pump();
    });

    testWidgets('SessionPropertiesDialog uses FuzzySearchableDropdown for SessionEnvironment', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      final testSession = SessionProfile(
        id: 'test_sess',
        name: 'STAGING_HOST',
        protocol: SessionProtocol.ssh,
        host: '10.0.0.3',
        environment: SessionEnvironment.staging,
        modifiedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SessionPropertiesDialog(
              initialSession: testSession,
              sessionManager: sessionManager,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Find FuzzySearchableDropdown for SessionEnvironment
      final envDropdownFinder = find.byType(FuzzySearchableDropdown<SessionEnvironment>);
      expect(envDropdownFinder, findsOneWidget);
      expect(find.textContaining('STAGING (Pre-production / QA)'), findsOneWidget);
    });
  });
}
