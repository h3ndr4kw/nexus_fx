import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/screens/sessions_screen.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';

void main() {
  late Directory tempDir;
  late File sessionFile;
  late SessionManagerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nexus_fx_widget_test_');
    sessionFile = File('${tempDir.path}/sessions.json');
    service = SessionManagerService.forTesting();
    await service.loadSessions(customFilePath: sessionFile.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget createTestWidget() {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: SessionsScreen(
          sessionManager: service,
          onConnectSessions: (sessions, {openInRightSplit = false}) {},
          onOpenInFileExplorer: (session) {},
        ),
      ),
    );
  }

  testWidgets('SessionsScreen renders toolbar, breadcrumbs, and default LOCAL session', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Verify toolbar items
    expect(find.text('New'), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.paste_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.settings_ethernet), findsOneWidget);

    // Verify breadcrumb
    expect(find.text('All Sessions'), findsOneWidget);

    // Verify table header columns
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Protocol'), findsOneWidget);

    // Verify default LOCAL session is visible (both in Name column and Protocol column)
    expect(find.text('LOCAL'), findsNWidgets(2));
  });
}
