import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/screens/sessions_screen.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/session_properties_dialog.dart';

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
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
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

  testWidgets('drag and drop session to folder moves session into that folder', (tester) async {
    SessionFolder? folder;
    SessionProfile? session;
    await tester.runAsync(() async {
      folder = await service.createFolder(name: 'Servers');
      session = await service.createSession(SessionProfile(
        id: 's_test',
        name: 'MyServer',
        protocol: SessionProtocol.ssh,
        host: '1.2.3.4',
        modifiedAt: DateTime.now(),
      ));
    });

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.text('MyServer'), findsOneWidget);
    expect(find.text('Servers'), findsOneWidget);

    final sessionCenter = tester.getCenter(find.text('MyServer'));
    final folderCenter = tester.getCenter(find.text('Servers'));

    await tester.runAsync(() async {
      final gesture = await tester.startGesture(sessionCenter);
      await gesture.moveTo(folderCenter);
      await gesture.up();
    });
    await tester.pump();

    expect(service.sessions.firstWhere((s) => s.id == session!.id).parentId, folder!.id);
  });

  testWidgets('drag and drop session inside folder to All Sessions moves it to root', (tester) async {
    SessionFolder? folder;
    SessionProfile? session;
    await tester.runAsync(() async {
      folder = await service.createFolder(name: 'Group1');
      session = await service.createSession(SessionProfile(
        id: 's_inside',
        parentId: folder!.id,
        name: 'InsideServer',
        protocol: SessionProtocol.ssh,
        host: '1.2.3.4',
        modifiedAt: DateTime.now(),
      ));
    });

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Double click Group1 to enter
    await tester.tap(find.text('Group1'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Group1'));
    await tester.pumpAndSettle();

    expect(find.text('InsideServer'), findsOneWidget);

    final sessionCenter = tester.getCenter(find.text('InsideServer'));
    final allSessionsCenter = tester.getCenter(find.text('All Sessions'));

    await tester.runAsync(() async {
      final gesture = await tester.startGesture(sessionCenter);
      await gesture.moveTo(allSessionsCenter);
      await gesture.up();
    });
    await tester.pump();

    expect(service.sessions.firstWhere((s) => s.id == session!.id).parentId, isNull);
  });

  testWidgets('keyboard navigation: j/k, Enter, Backspace, h/l, and Auto-Selection work properly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    SessionFolder? f1;
    await tester.runAsync(() async {
      f1 = await service.createFolder(name: 'FolderA');
      await service.createSession(SessionProfile(
        id: 's_inside_a',
        parentId: f1!.id,
        name: 'ServerInFolderA',
        protocol: SessionProtocol.ssh,
        host: '10.0.0.1',
        modifiedAt: DateTime.now(),
      ));
    });

    final connectedSessions = <SessionProfile>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: SessionsScreen(
          sessionManager: service,
          onConnectSessions: (sessions, {openInRightSplit = false}) {
            connectedSessions.addAll(sessions);
          },
          onOpenInFileExplorer: (session) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // At root, items are FolderA and default LOCAL session.
    // By auto-selection, FolderA is selected first.
    // Press 'l' or Enter to enter FolderA:
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();

    // Now inside FolderA, we should see '..' and 'ServerInFolderA'
    expect(find.text('..'), findsOneWidget);
    expect(find.text('ServerInFolderA'), findsOneWidget);

    // Auto-selection selects the first content item ('ServerInFolderA')
    // Press Enter to connect to ServerInFolderA
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(connectedSessions.length, 1);
    expect(connectedSessions.first.name, 'ServerInFolderA');

    // Press 'h' to navigate back to parent folder (Root)
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();

    // Now at root, FolderA should be selected again (remembered).
    // Press 'j' (or arrow down) to move down to LOCAL session
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();

    // Press Enter to connect to LOCAL session
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(connectedSessions.length, 2);
    expect(connectedSessions[1].name, 'LOCAL');

    // Press 'k' (or arrow up) to move back up to FolderA
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();

    // Press Enter to enter FolderA again
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('..'), findsOneWidget);

    // Press 'Backspace' to go back to root
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('..'), findsNothing);
  });

  testWidgets('keyboard navigation: search shortcut / focuses search and typing does not trigger j/k', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.runAsync(() async {
      await service.createFolder(name: 'JavaDev');
    });
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Press '/' to focus search field
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();

    final searchFieldFinder = find.byType(TextField);
    expect(searchFieldFinder, findsOneWidget);

    // Enter text in search field
    await tester.enterText(searchFieldFinder, 'java');
    await tester.pumpAndSettle();

    expect(find.text('JavaDev'), findsOneWidget);

    // Press Escape to clear and unfocus search field
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Search query is cleared, default items visible again
    expect(find.text('LOCAL'), findsNWidgets(2));
  });

  testWidgets('SessionPropertiesDialog shows MAC Algorithm dropdown and Custom SSH Options and saves them', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    SessionPropertiesResult? result;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await SessionPropertiesDialog.show(
                ctx,
                sessionManager: service,
                initialSession: SessionProfile(
                  id: 's_10_89',
                  name: 'Jump_10_89',
                  protocol: SessionProtocol.ssh,
                  host: '10.89.100.11',
                  username: '21339656',
                  sshMacs: 'hmac-sha1',
                  customSshOptions: '-o MACs=hmac-sha1',
                  modifiedAt: DateTime.now(),
                ),
              );
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('MAC Algorithm:'), findsOneWidget);
    expect(find.text('Custom SSH Options:'), findsOneWidget);
    expect(find.text('-o MACs=hmac-sha1'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.savedSession.sshMacs, 'hmac-sha1');
    expect(result!.savedSession.customSshOptions, '-o MACs=hmac-sha1');
  });
}
