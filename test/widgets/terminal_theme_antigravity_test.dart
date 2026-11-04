import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/screens/main_screen.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/services/settings_service.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/theme/terminal_theme_helper.dart';
import 'package:nexus_fx/widgets/ssh_tab_view.dart';
import 'package:xterm/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sessionFile;
  late SessionManagerService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nexus_fx_antigravity_theme_test_');
    sessionFile = File('${tempDir.path}/sessions.json');
    service = SessionManagerService.forTesting();
    await service.loadSessions(customFilePath: sessionFile.path);
    await SettingsService.instance.setNexusTerminalThemeMode(NexusTerminalThemeMode.antigravityDark);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Antigravity Theme & Color Palette Tests', () {
    test('AppTheme constants and antigravity palette match dark obsidian specification', () {
      expect(AppTheme.background, const Color(0xFF0D0E12));
      expect(AppTheme.surfaceColor, const Color(0xFF16181F));
      expect(AppTheme.bgSurfaceSecondary, const Color(0xFF13151B));
      expect(AppTheme.primaryColor, const Color(0xFF60A5FA));
      expect(AppTheme.accentPrimary, const Color(0xFF60A5FA));
      expect(AppTheme.borderSubtle, const Color(0xFF232630));
      expect(AppTheme.textPrimary, const Color(0xFFE2E4E9));
      expect(AppTheme.textSecondary, const Color(0xFF9AA0A6));

      final palette = AppTheme.getPalette(AppThemeType.antigravity);
      expect(palette.background, const Color(0xFF0D0E12));
      expect(palette.surfaceColor, const Color(0xFF16181F));
      expect(palette.primaryColor, const Color(0xFF60A5FA));
      expect(palette.accentColor, const Color(0xFF34D399));
      expect(palette.textColor, const Color(0xFF9AA0A6));
      expect(palette.titleColor, const Color(0xFFE2E4E9));
      expect(palette.inputBorderColor, const Color(0xFF232630));
    });

    test('TerminalThemeHelper resolves antigravityDark with calibrated ANSI spectrum', () {
      final theme = TerminalThemeHelper.resolveTheme(
        mode: NexusTerminalThemeMode.antigravityDark,
        palette: AppTheme.activePalette,
      );

      expect(theme.background, const Color(0xFF0D0E12));
      expect(theme.foreground, const Color(0xFFE2E5EB));
      expect(theme.cursor, const Color(0xFF60A5FA));
      expect(theme.selection, const Color(0x4760A5FA));

      // 16 ANSI Spectrum
      expect(theme.black, const Color(0xFF16181E));
      expect(theme.red, const Color(0xFFF87171));
      expect(theme.green, const Color(0xFF34D399));
      expect(theme.yellow, const Color(0xFFFBBF24));
      expect(theme.blue, const Color(0xFF60A5FA));
      expect(theme.magenta, const Color(0xFFC084FC));
      expect(theme.cyan, const Color(0xFF38BDF8));
      expect(theme.white, const Color(0xFFE2E5EB));

      expect(theme.brightBlack, const Color(0xFF5C6370));
      expect(theme.brightRed, const Color(0xFFFB7185));
      expect(theme.brightGreen, const Color(0xFF4ADE80));
      expect(theme.brightYellow, const Color(0xFFFDE047));
      expect(theme.brightBlue, const Color(0xFF93C5FD));
      expect(theme.brightMagenta, const Color(0xFFE879F9));
      expect(theme.brightCyan, const Color(0xFF67E8F9));
      expect(theme.brightWhite, const Color(0xFFFFFFFF));
    });

    test('TerminalThemeHelper followAppTheme resolves antigravityDark when palette is antigravity', () {
      final theme = TerminalThemeHelper.resolveTheme(
        mode: NexusTerminalThemeMode.followAppTheme,
        palette: AppTheme.getPalette(AppThemeType.antigravity),
      );

      expect(theme.background, const Color(0xFF0D0E12));
      expect(theme.foreground, const Color(0xFFE2E5EB));
      expect(theme.cursor, const Color(0xFF60A5FA));
    });

    testWidgets('SshTabView renders with antigravity terminal theme and background container', (tester) async {
      final conn = SshConnection(id: 'test-antigravity', host: '10.0.0.1', port: 22, label: 'Antigravity Ssh');
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

      final TerminalView tv = tester.widget<TerminalView>(terminalViewFinder);
      expect(tv.theme.background, const Color(0xFF0D0E12));
      expect(tv.theme.foreground, const Color(0xFFE2E5EB));
      expect(tv.theme.cursor, const Color(0xFF60A5FA));
    });

    testWidgets('Settings screen renders Terminal Theme dropdown with Antigravity Dark', (tester) async {
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

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Terminal Theme:'), findsOneWidget);
      expect(find.text('Antigravity Dark'), findsWidgets);
    });
  });
}
