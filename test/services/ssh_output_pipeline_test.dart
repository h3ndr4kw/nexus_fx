import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/ssh_log_service.dart';
import 'package:nexus_fx/services/ssh_service.dart';

SshConnection _conn({bool enableLogging = false, SshLogService? logService}) =>
    SshConnection(
      id: 'pipe_${DateTime.now().microsecondsSinceEpoch}',
      host: '10.0.0.1',
      label: 'PIPE',
      enableLogging: enableLogging,
      logService: logService,
    );

String _terminalText(SshConnection c) {
  final lines = c.terminal.buffer.lines;
  final b = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    b.writeln(lines[i].getText().trimRight());
  }
  return b.toString();
}

Future<void> _until(bool Function() done,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > timeout) fail('condition not reached within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  test('large burst is drained asynchronously and pauses the source stream',
      () async {
    final conn = _conn();
    addTearDown(conn.dispose);

    final source = StreamController<String>();
    conn.trackOutputForTesting(source.stream).listen((_) {});
    expect(source.isPaused, isFalse);

    // ~3 MB of output in one go, like `cat` of a large file.
    final lines = List.generate(60000, (i) => 'line $i ${'x' * 40}\r\n');
    for (final l in lines) {
      conn.enqueueOutputForTesting(l);
    }

    expect(conn.pendingTerminalCharsForTesting,
        greaterThan(SshConnection.outputHighWaterChars));
    expect(conn.isOutputPausedForTesting, isTrue);
    expect(source.isPaused, isTrue,
        reason: 'pausing the subscription is what stops the SSH window');

    await _until(() => conn.pendingTerminalCharsForTesting == 0);

    expect(conn.isOutputPausedForTesting, isFalse);
    expect(source.isPaused, isFalse);
    expect(_terminalText(conn), contains('line 59999 '));
    await source.close();
  });

  test('a subscription added while paused starts paused', () async {
    final conn = _conn();
    addTearDown(conn.dispose);
    conn.enqueueOutputForTesting('y' * (SshConnection.outputHighWaterChars + 1));
    expect(conn.isOutputPausedForTesting, isTrue);

    final lateSource = StreamController<String>();
    conn.trackOutputForTesting(lateSource.stream).listen((_) {});
    expect(lateSource.isPaused, isTrue);

    await _until(() => conn.pendingTerminalCharsForTesting == 0);
    expect(lateSource.isPaused, isFalse);
    await lateSource.close();
  });

  test('local messages are shown after queued remote output', () {
    final conn = _conn();
    addTearDown(conn.dispose);
    conn.enqueueOutputForTesting('remote output\r\n');
    conn.writeLocal('Session stopped\r\n');
    conn.flushTerminalOutput();

    final text = _terminalText(conn);
    expect(text.indexOf('remote output'), lessThan(text.indexOf('Session stopped')));
  });

  test('slicing never splits a surrogate pair', () async {
    final conn = _conn();
    addTearDown(conn.dispose);
    // Put an emoji exactly on the 16K slice boundary.
    conn.enqueueOutputForTesting('${'a' * (16 * 1024 - 1)}\u{1F600}b\r\n');
    await _until(() => conn.pendingTerminalCharsForTesting == 0);
    expect(_terminalText(conn), isNot(contains('�')));
  });

  test('outputStream and log still receive every chunk immediately', () async {
    final conn = _conn();
    addTearDown(conn.dispose);
    final seen = <String>[];
    final sub = conn.outputStream.listen(seen.add);
    conn.enqueueOutputForTesting('abc');
    conn.enqueueOutputForTesting('def');
    await Future<void>.delayed(Duration.zero);
    expect(seen.join(), 'abcdef');
    await sub.cancel();
  });

  test('logger that cannot open its file reports logFailure, session unaffected',
      () async {
    final dir = await Directory.systemTemp.createTemp('ssh_log_fail_');
    addTearDown(() => dir.deleteSync(recursive: true));
    // A plain file where the "logs" directory should be makes creation fail.
    File('${dir.path}${Platform.pathSeparator}logs').writeAsStringSync('x');

    final conn = _conn(
        enableLogging: true, logService: SshLogService(baseDir: dir.path));
    addTearDown(conn.dispose);

    await conn.initLogger();

    expect(conn.logFile, isNull);
    expect(conn.logFailure.value, isNotNull);
    conn.flushTerminalOutput();
    expect(_terminalText(conn), contains('Session logging stopped'));

    // Output keeps flowing to the terminal.
    conn.simulateOutputForTesting('still alive\r\n');
    expect(_terminalText(conn), contains('still alive'));
  });
}
