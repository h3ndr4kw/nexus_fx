import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/screens/main_screen.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/services/settings_service.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/ssh_tab_view.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sessionFile;
  late SessionManagerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nexus_fx_font_test_');
    sessionFile = File('${tempDir.path}/sessions.json');
    service = SessionManagerService.forTesting();
    await service.loadSessions(customFilePath: sessionFile.path);
    await SettingsService.instance.setNexusTerminalFontSize(14.0);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('Settings screen renders Terminal Font Size and allows stepping font size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MainScreen(
          sessionManager: service,
          suppressStartupDialog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to Settings
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    // Verify Terminal Font and Terminal Font Size are rendered
    expect(find.text('Terminal Font:'), findsOneWidget);
    expect(find.text('Terminal Font Size:'), findsOneWidget);
    expect(find.text('14 pt'), findsWidgets);
    expect(find.text('nexus@terminal:~ \$'), findsOneWidget);

    // Tap increase font size
    final increaseButton = find.byTooltip('Increase font size (1 pt)');
    expect(increaseButton, findsOneWidget);
    await tester.tap(increaseButton);
    await tester.pumpAndSettle();

    expect(SettingsService.instance.nexusTerminalFontSize, 15.0);
    expect(find.text('15 pt'), findsWidgets);

    // Tap decrease font size twice
    final decreaseButton = find.byTooltip('Decrease font size (1 pt)');
    expect(decreaseButton, findsOneWidget);
    await tester.tap(decreaseButton);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.nexusTerminalFontSize, 14.0);

    await tester.tap(decreaseButton);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.nexusTerminalFontSize, 13.0);
    expect(find.text('13 pt'), findsWidgets);
  });

  testWidgets('SshTabView dynamically updates terminal fontSize when SettingsService changes', (tester) async {
    await SettingsService.instance.setNexusTerminalFontSize(14.0);
    final conn = SshConnection(id: 'test-c1', host: '10.0.0.1', port: 22, label: 'Test Terminal');
    conn.setConnectedForTesting(true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SshTabView(
            connection: conn,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final terminalViewFinder = find.byType(TerminalView);
    expect(terminalViewFinder, findsOneWidget);

    TerminalView tv = tester.widget<TerminalView>(terminalViewFinder);
    expect(tv.textStyle.fontSize, 14.0);

    // Update font size in settings service
    await SettingsService.instance.setNexusTerminalFontSize(18.0);
    await tester.pumpAndSettle();

    tv = tester.widget<TerminalView>(terminalViewFinder);
    expect(tv.textStyle.fontSize, 18.0);
  });
}
