import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/settings_service.dart';
import 'package:nexus_fx/widgets/file_explorer_dialogs.dart';

void main() {
  tearDown(() => SettingsService.instance
      .setFileExplorerStatusBarStyle(FileExplorerStatusBarStyle.detailed));

  test('status bar style defaults to detailed and survives a reload', () async {
    final settings = SettingsService.instance;
    expect(settings.fileExplorerStatusBarStyle, FileExplorerStatusBarStyle.detailed);

    await settings.setFileExplorerStatusBarStyle(FileExplorerStatusBarStyle.minimal);
    await settings.loadSettings();

    expect(settings.fileExplorerStatusBarStyle, FileExplorerStatusBarStyle.minimal);
  });

  testWidgets('settings dialog offers the status bar styles', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: FileExplorerSettingsDialog()),
    ));

    expect(find.text('STATUS BAR'), findsOneWidget);
    expect(find.text('Detailed'), findsOneWidget);
    expect(find.text('Minimal'), findsOneWidget);

    await tester.tap(find.text('Minimal'));
    await tester.pump();

    expect(
      SettingsService.instance.fileExplorerStatusBarStyle,
      FileExplorerStatusBarStyle.minimal,
    );
  });
}
