import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
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
      modifiedAt: DateTime(2026),
    ));
    return manager;
  }

  Future<List<CommandItem>> pumpPalette(WidgetTester tester) async {
    final manager = await buildSessions();
    final selected = <CommandItem>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CommandPalette(
                sessionsOnly: true,
                sessionManager: manager,
                onSelect: selected.add,
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
    expect(find.text('SSH'), findsOneWidget);
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
}
