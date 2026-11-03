import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/file_explorer_models.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';
import 'package:nexus_fx/widgets/file_explorer_dialogs.dart';
import 'package:nexus_fx/widgets/file_explorer_view.dart';

class FakeFileExplorerService extends FileExplorerService {
  final List<FileExplorerItem> mockFiles;

  FakeFileExplorerService(this.mockFiles);

  @override
  Future<List<FileExplorerItem>> listLocal(String dirPath, {String filter = ''}) async {
    return List.from(mockFiles);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExplorerNodeTarget isSameTarget', () {
    test('local targets match', () {
      expect(ExplorerNodeTarget.local.isSameTarget(ExplorerNodeTarget.local), isTrue);
    });

    test('remote targets with same properties match', () {
      const targetA = ExplorerNodeTarget(
        type: ExplorerTargetType.sessionSsh,
        label: 'Node A',
        host: '192.168.1.10',
        port: 22,
        username: 'root',
        sessionId: 'sess_1',
      );
      const targetB = ExplorerNodeTarget(
        type: ExplorerTargetType.sessionSsh,
        label: 'Node A (Alias)',
        host: '192.168.1.10',
        port: 22,
        username: 'root',
        sessionId: 'sess_1',
      );
      expect(targetA.isSameTarget(targetB), isTrue);
    });

    test('targets with different host do not match', () {
      const targetA = ExplorerNodeTarget(
        type: ExplorerTargetType.sessionSsh,
        label: 'Node A',
        host: '192.168.1.10',
        port: 22,
        username: 'root',
      );
      const targetB = ExplorerNodeTarget(
        type: ExplorerTargetType.sessionSsh,
        label: 'Node B',
        host: '192.168.1.20',
        port: 22,
        username: 'root',
      );
      expect(targetA.isSameTarget(targetB), isFalse);
    });
  });

  group('FileExplorerView Multiple Selection & Unselected Focus', () {
    late FakeFileExplorerService fakeService;
    late List<FileExplorerItem> files;

    setUp(() {
      files = [
        FileExplorerItem(name: '..', path: '/root', isDir: true, size: 0, modified: '- -'),
        FileExplorerItem(name: 'docs', path: '/root/docs', isDir: true, size: 0, modified: 'Jan 01 10:00'),
        FileExplorerItem(name: 'file1.txt', path: '/root/file1.txt', isDir: false, size: 1024, modified: 'Jan 01 10:05'),
        FileExplorerItem(name: 'file2.txt', path: '/root/file2.txt', isDir: false, size: 2048, modified: 'Jan 01 10:10'),
      ];
      fakeService = FakeFileExplorerService(files);
    });

    testWidgets('renders items with checkboxes and handles selection toggle', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileExplorerView(
              service: fakeService,
              initialLeftPath: '/root',
              initialRightPath: '/root',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify filenames are rendered
      expect(find.text('file1.txt'), findsWidgets);
      expect(find.text('file2.txt'), findsWidgets);
      expect(find.text('docs'), findsWidgets);

      // Verify Draggable is present for normal items
      expect(find.byType(Draggable<FileDragPayload>), findsWidgets);

      // Verify DragTarget is present for directory items
      expect(find.byType(DragTarget<FileDragPayload>), findsWidgets);

      // Select file1.txt via its checkbox '[ ]' or clicking item
      final file1Finder = find.text('file1.txt').first;
      await tester.tap(file1Finder);
      await tester.pumpAndSettle();

      // Press Escape to unselect / unfocus
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Verify no crash and Escape properly unselects focus
      expect(find.byType(FileExplorerView), findsOneWidget);
    });

    testWidgets('checkbox tap selects item and regular item tap resets multi-selection', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileExplorerView(
              service: fakeService,
              initialLeftPath: '/root',
              initialRightPath: '/root',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap checkbox for file1.txt (index 2, since index 0 is '..')
      final file1Checkbox = find.text('   ').at(2);
      await tester.tap(file1Checkbox);
      await tester.pumpAndSettle();

      // '[*]' should now appear
      expect(find.text('[*]'), findsWidgets);

      // Tap another file directly (regular click on file2.txt)
      final file2Finder = find.text('file2.txt').first;
      await tester.tap(file2Finder);
      await tester.pumpAndSettle();

      // Regular click should clear multi-selection
      expect(find.text('[*]'), findsNothing);
    });

    testWidgets('FileExplorerDropActionDialog options work properly', (tester) async {
      FileDropAction? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<FileDropAction>(
                    context: context,
                    builder: (ctx) => const FileExplorerDropActionDialog(
                      title: 'DRAG & DROP TRANSFER',
                      message: 'Transfer 2 items?',
                      destPath: '/target/path',
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('DRAG & DROP TRANSFER'), findsOneWidget);
      expect(find.text('[c] Copy'), findsOneWidget);
      expect(find.text('[m] Move'), findsOneWidget);
      expect(find.text('[Esc] Cancel'), findsOneWidget);

      // Tap Copy
      await tester.tap(find.text('[c] Copy'));
      await tester.pumpAndSettle();

      expect(result, equals(FileDropAction.copy));
    });
  });
}
