import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/settings_service.dart';
import 'package:nexus_fx/widgets/file_explorer_dialogs.dart';

void main() {
  tearDown(() => SettingsService.instance
      .setFileExplorerArchiveFormat(FileExplorerArchiveFormat.tarGz));

  test('archive format defaults to tar.gz and survives a reload', () async {
    final settings = SettingsService.instance;
    expect(settings.fileExplorerArchiveFormat, FileExplorerArchiveFormat.tarGz);

    await settings.setFileExplorerArchiveFormat(FileExplorerArchiveFormat.zip);
    await settings.loadSettings();

    expect(settings.fileExplorerArchiveFormat, FileExplorerArchiveFormat.zip);
  });

  testWidgets('settings dialog offers the archive formats', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: FileExplorerSettingsDialog()),
    ));

    expect(find.text('COMPRESS FORMAT'), findsOneWidget);
    await tester.ensureVisible(find.text('zip'));
    await tester.tap(find.text('zip'));
    await tester.pump();

    expect(
      SettingsService.instance.fileExplorerArchiveFormat,
      FileExplorerArchiveFormat.zip,
    );
  });
}
