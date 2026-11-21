import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexus_fx/services/app_log.dart';
import 'package:nexus_fx/widgets/file_operation_error.dart';

void main() {
  setUp(AppLog.clearForTesting);

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ),
    ));
    return context;
  }

  testWidgets('a failed file operation tells the user what failed and why', (tester) async {
    final context = await pumpHost(tester);

    reportFileOperationError(
      context,
      'rename "notes.nxnb"',
      const FileSystemException('Access is denied', 'notes.nxnb'),
      StackTrace.current,
    );
    await tester.pump();

    expect(find.textContaining('Could not rename "notes.nxnb"'), findsOneWidget);
    expect(find.textContaining('Access is denied'), findsOneWidget);
  });

  testWidgets('the failure is also written to the diagnostic log', (tester) async {
    final context = await pumpHost(tester);

    reportFileOperationError(context, 'delete folder "old"', StateError('busy'), StackTrace.current);
    await tester.pump();

    final entry = AppLog.recent.single;
    expect(entry.level, 'ERROR');
    expect(entry.where, contains('delete folder "old"'));
    expect(entry.message, contains('busy'));
  });

  testWidgets('without a Scaffold it still logs and does not throw', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
    ));

    expect(
      () => reportFileOperationError(context, 'create file', StateError('x'), StackTrace.current),
      returnsNormally,
    );
    expect(AppLog.recent, hasLength(1));
  });
}
