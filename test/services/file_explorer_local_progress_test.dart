import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/file_explorer_service.dart';

void main() {
  late Directory tmp;
  final service = FileExplorerService();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fx_progress_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<Directory> makeTree() async {
    final src = Directory('${tmp.path}${Platform.pathSeparator}src');
    final sub = Directory('${src.path}${Platform.pathSeparator}sub');
    await sub.create(recursive: true);
    await File('${src.path}${Platform.pathSeparator}a.bin')
        .writeAsBytes(List.filled(300 * 1024, 1));
    await File('${sub.path}${Platform.pathSeparator}b.bin')
        .writeAsBytes(List.filled(200 * 1024, 2));
    return src;
  }

  test('copyLocal reports cumulative, monotonic progress for a folder', () async {
    final src = await makeTree();
    final dest = await Directory('${tmp.path}${Platform.pathSeparator}dest').create();

    final events = <List<int>>[];
    await service.copyLocal(
      src.path,
      dest.path,
      onProgress: (sent, total) => events.add([sent, total]),
    );

    expect(events, isNotEmpty);
    const expectedTotal = 500 * 1024;
    expect(events.every((e) => e[1] == expectedTotal), isTrue);
    for (var i = 1; i < events.length; i++) {
      expect(events[i][0], greaterThanOrEqualTo(events[i - 1][0]),
          reason: 'progress must not reset between files');
    }
    expect(events.last[0], expectedTotal);
  });

  test('moveLocal reports completion and moves the folder', () async {
    final src = await makeTree();
    final dest = await Directory('${tmp.path}${Platform.pathSeparator}dest').create();

    final events = <List<int>>[];
    await service.moveLocal(
      src.path,
      dest.path,
      onProgress: (sent, total) => events.add([sent, total]),
    );

    expect(await src.exists(), isFalse);
    expect(
      await File('${dest.path}${Platform.pathSeparator}src${Platform.pathSeparator}sub${Platform.pathSeparator}b.bin').exists(),
      isTrue,
    );
    expect(events, isNotEmpty);
    expect(events.last[0], events.last[1]);
  });

  test('copyLocal stops on cancel and removes the partial file', () async {
    final big = File('${tmp.path}${Platform.pathSeparator}big.bin');
    await big.writeAsBytes(List.filled(8 * 1024 * 1024, 7));
    final dest = await Directory('${tmp.path}${Platform.pathSeparator}dest').create();
    final token = TransferCancelToken();

    await expectLater(
      service.copyLocal(
        big.path,
        dest.path,
        cancelToken: token,
        onProgress: (sent, total) {
          if (sent > 0) token.cancel();
        },
      ),
      throwsA(isA<TransferCancelledException>()),
    );
    expect(
      await File('${dest.path}${Platform.pathSeparator}big.bin').exists(),
      isFalse,
    );
  });

  test('TransferCancelToken runs hooks once and supports unregister', () {
    final token = TransferCancelToken();
    var a = 0, b = 0;
    token.onCancel(() => a++);
    final unregister = token.onCancel(() => b++);
    unregister();
    token.cancel();
    token.cancel();
    expect(a, 1);
    expect(b, 0);
    expect(token.throwIfCancelled, throwsA(isA<TransferCancelledException>()));
    var late = 0;
    token.onCancel(() => late++);
    expect(late, 1, reason: 'hooks registered after cancel run immediately');
  });
}
