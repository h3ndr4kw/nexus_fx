import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/widgets/file_explorer_dialogs.dart';
import 'package:nexus_fx/widgets/palette_widgets.dart';

void main() {
  setUpAll(() async {
    final manager = SessionManagerService.instance;
    if (!manager.sessions.any((s) => s.id == 'picker_debian')) {
      await manager.createSession(SessionProfile(
        id: 'picker_debian',
        name: 'Debian',
        host: '192.168.100.130',
        username: 'root',
        modifiedAt: DateTime(2026),
      ));
    }
  });

  Future<List<ExplorerNodeTarget?>> pumpPicker(WidgetTester tester) async {
    final results = <ExplorerNodeTarget?>[];
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          enabledBorder: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(),
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              results.add(await showDialog<ExplorerNodeTarget>(
                context: context,
                builder: (_) => const FileExplorerNodePickerDialog(
                  currentTarget: ExplorerNodeTarget.local,
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('uses the palette look: borderless search, ESC keycap, rows and badges',
      (tester) async {
    await pumpPicker(tester);

    expect(find.byType(PaletteFrame), findsOneWidget);
    expect(find.text('ESC'), findsOneWidget);
    final decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);

    expect(find.byType(PaletteRow), findsNWidgets(2));
    expect(find.text('Local Filesystem'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Debian'), findsOneWidget);
    expect(find.text('Host: 192.168.100.130 · User: root'), findsOneWidget);
    expect(find.text('SSH'), findsOneWidget);
    expect(find.text('Connect Custom SSH Node...'), findsOneWidget);
  });

  testWidgets('arrow down + enter picks the session node', (tester) async {
    final results = await pumpPicker(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(results.single?.host, '192.168.100.130');
    expect(find.byType(FileExplorerNodePickerDialog), findsNothing);
  });

  testWidgets('ESC keycap closes without a selection', (tester) async {
    final results = await pumpPicker(tester);

    await tester.tap(find.text('ESC'));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
  });
}
