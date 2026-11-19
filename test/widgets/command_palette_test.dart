import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/services/web_launcher.dart';
import 'package:nexus_fx/widgets/command_palette.dart';

void main() {
  Future<SessionManagerService> buildSessions() async {
    final manager = SessionManagerService.forTesting();
    await manager.createSession(SessionProfile(
      id: 'local',
      name: 'LOCAL',
      protocol: SessionProtocol.local,
      modifiedAt: DateTime(2026),
    ));
    await manager.createSession(SessionProfile(
      id: 'debian',
      name: 'Debian',
      host: '192.168.100.130',
      webEnabled: true,
      modifiedAt: DateTime(2026),
    ));
    await manager.createSession(SessionProfile(
      id: 'behind-jump',
      name: 'BehindJump',
      host: '10.0.0.9',
      jumpHostMode: JumpHostMode.existingSession,
      jumpSessionId: 'debian',
      webEnabled: true,
      modifiedAt: DateTime(2026),
    ));
    await manager.createSession(SessionProfile(
      id: 'web-off',
      name: 'WebOff',
      host: '10.0.0.10',
      modifiedAt: DateTime(2026),
    ));
    return manager;
  }

  final opened = <String>[];

  setUp(opened.clear);

  Future<List<CommandItem>> pumpPalette(WidgetTester tester, {ThemeData? theme}) async {
    final manager = await buildSessions();
    final selected = <CommandItem>[];
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CommandPalette(
                sessionsOnly: true,
                sessionManager: manager,
                onSelect: selected.add,
                openWeb: (urls) async {
                  opened.add(urls.first);
                  return WebOpenResult(url: urls.first);
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return selected;
  }

  testWidgets('shows sessions with subtitles, badges and an ESC keycap', (tester) async {
    await pumpPalette(tester);

    expect(find.text('ESC'), findsOneWidget);
    expect(find.text('LOCAL'), findsNWidgets(2)); // name + badge
    expect(find.text('Local System Shell'), findsOneWidget);
    expect(find.text('Debian'), findsOneWidget);
    expect(find.text('Connect SSH to 192.168.100.130:22'), findsOneWidget);
    expect(find.text('SSH'), findsNWidgets(3));
    // WebOff has Web disabled, so only Debian and BehindJump show WEB.
    expect(find.text('WEB'), findsNWidgets(2));
  });

  testWidgets('tapping WEB opens https://<host> without connecting SSH', (tester) async {
    final selected = await pumpPalette(tester);

    await tester.tap(find.text('WEB').first);
    await tester.pumpAndSettle();

    expect(opened, ['https://192.168.100.130']);
    expect(selected, isEmpty);
    expect(find.byType(CommandPalette), findsNothing);
  });

  testWidgets('ctrl+enter opens the web UI of the selected session', (tester) async {
    final selected = await pumpPalette(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(opened, ['https://192.168.100.130']);
    expect(selected, isEmpty);
  });

  testWidgets('WEB is disabled for a session behind a jump host', (tester) async {
    await pumpPalette(tester);

    await tester.tap(find.text('WEB').last);
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.byType(CommandPalette), findsOneWidget);
  });

  testWidgets('tapping the SSH badge connects the session', (tester) async {
    final selected = await pumpPalette(tester);

    await tester.tap(find.text('SSH').first);
    await tester.pumpAndSettle();

    expect(selected.single.session?.id, 'debian');
    expect(opened, isEmpty);
  });

  testWidgets('arrow down + enter selects the second session', (tester) async {
    final selected = await pumpPalette(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected.single.session?.id, 'debian');
    expect(find.byType(CommandPalette), findsNothing);
  });

  testWidgets('tapping the ESC keycap closes the palette', (tester) async {
    final selected = await pumpPalette(tester);

    await tester.tap(find.text('ESC'));
    await tester.pumpAndSettle();

    expect(find.byType(CommandPalette), findsNothing);
    expect(selected, isEmpty);
  });

  testWidgets('search field has no outline even when the theme sets one', (tester) async {
    const outline = OutlineInputBorder(borderSide: BorderSide(color: Colors.red));
    await pumpPalette(
      tester,
      theme: ThemeData(
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          enabledBorder: outline,
          focusedBorder: outline,
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
    expect(decoration.filled, isFalse);
  });
}
