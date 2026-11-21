import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/screens/sessions_screen.dart';
import 'package:nexus_fx/services/session_import/imported_host.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/session_import_dialog.dart';

void main() {
  const scan = ImportScan(
    [
      ImportedHost(name: 'web', host: '10.0.0.5', username: 'deploy', identityFile: '/k/web'),
      ImportedHost(name: 'db', host: '10.0.0.6', username: 'root'),
      ImportedHost(
        name: 'legacy',
        host: '10.0.0.7',
        notes: ['Key is a PuTTY .ppk file; convert it.'],
        jump: ImportedJump(host: 'gw', username: 'ops'),
      ),
    ],
    ['Line 3: "Include x" was not followed; import that file separately.'],
  );

  final existing = [
    SessionProfile(id: 'old', name: 'old db', host: '10.0.0.6', username: 'root', modifiedAt: DateTime(2026)),
  ];

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () =>
                SessionImportDialog.show(ctx, sourceLabel: 'OpenSSH config', scan: scan, existing: existing),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows hosts, notes and warnings; already-saved hosts start unchecked', (tester) async {
    await open(tester);
    expect(find.text('Import from OpenSSH config'), findsOneWidget);
    expect(find.text('3 hosts found'), findsOneWidget);
    expect(find.text('already saved'), findsOneWidget);
    expect(find.textContaining('via ops@gw'), findsOneWidget);
    expect(find.textContaining('.ppk'), findsOneWidget);
    expect(find.textContaining('Include x'), findsOneWidget);

    bool checked(String name) =>
        tester.widget<CheckboxListTile>(find.byKey(Key('session_import_$name'))).value!;
    expect(checked('web'), isTrue);
    expect(checked('db'), isFalse);
    expect(checked('legacy'), isTrue);
    expect(find.text('Import 2'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('returns only the checked hosts; Select none disables Import', (tester) async {
    late List<ImportedHost>? picked;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                picked = await SessionImportDialog.show(ctx, sourceLabel: 'PuTTY', scan: scan, existing: existing),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select none'));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('session_import_confirm'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('session_import_legacy')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('session_import_confirm')));
    await tester.pumpAndSettle();
    expect(picked!.map((h) => h.name), ['legacy']);
  });

  group('Sessions screen', () {
    late Directory tempDir;
    late SessionManagerService mgr;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nexus_fx_import_menu_');
      mgr = SessionManagerService.forTesting();
      await mgr.loadSessions(customFilePath: '${tempDir.path}/sessions.json');
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    testWidgets('"New" menu offers the importers', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SessionsScreen(
            sessionManager: mgr,
            onConnectSessions: (sessions, {openInRightSplit = false}) {},
            onOpenInFileExplorer: (session) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('Import from OpenSSH config...'), findsOneWidget);
      expect(find.text('Import from PuTTY...'), Platform.isWindows ? findsOneWidget : findsNothing);
    });
  });
}
