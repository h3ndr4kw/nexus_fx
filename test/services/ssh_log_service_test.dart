import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/ssh_log_service.dart';

/// IOSink double: records what reached it and lets a test decide how each
/// flush ends.
class _FakeSink implements IOSink {
  final StringBuffer written = StringBuffer();
  final Completer<void> _done = Completer<void>();
  Future<void> Function()? onFlush;
  int flushCount = 0;
  bool closed = false;

  @override
  Encoding encoding = utf8;

  @override
  void write(Object? object) {
    if (closed) throw StateError('StreamSink is closed');
    written.write(object);
  }

  @override
  Future flush() {
    flushCount++;
    return onFlush?.call() ?? Future<void>.value();
  }

  @override
  Future close() {
    closed = true;
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future get done => _done.future;

  void failDone(Object error) {
    if (!_done.isCompleted) _done.completeError(error);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FileSystemException _diskFull() => FileSystemException(
      'Write failed',
      'C:/logs/session.log',
      Platform.isWindows
          ? const OSError('There is not enough space on the disk.', 112)
          : const OSError('No space left on device', 28),
    );

void main() {
  final svc = SshLogService();

  SshSessionLogger logger(_FakeSink sink,
          {int maxBufferedChars = SshSessionLogger.defaultMaxBufferedChars,
          void Function(SshLogFailure)? onFailure}) =>
      SshSessionLogger(
        file: File('session.log'),
        sink: sink,
        sanitizer: svc.stripAnsi,
        flushInterval: const Duration(milliseconds: 10),
        maxBufferedChars: maxBufferedChars,
        onFailure: onFailure,
      );

  test('buffered output is written and flushed periodically, not on close',
      () async {
    final sink = _FakeSink();
    final log = logger(sink);
    log.write('hello ');
    log.write('world\r\n');
    expect(sink.written.toString(), isEmpty,
        reason: 'writes are batched in memory first');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sink.written.toString(), 'hello world\r\n');
    expect(sink.flushCount, greaterThanOrEqualTo(1));
    expect(sink.closed, isFalse);
  });

  test('ANSI escape split across two batches is still stripped', () async {
    final sink = _FakeSink();
    final log = logger(sink);
    log.write('a\x1B[3');
    await log.flush();
    log.write('1mb\x1B[0m');
    await log.close();
    expect(sink.written.toString(), 'ab');
  });

  test('disk full on flush disables the logger once without throwing',
      () async {
    final sink = _FakeSink()..onFlush = () => Future.error(_diskFull());
    final failures = <SshLogFailure>[];
    final log = logger(sink, onFailure: failures.add);

    log.write('first');
    await log.flush();

    expect(failures, hasLength(1));
    expect(failures.single.isDiskFull, isTrue);
    expect(failures.single.message, contains('Disk full'));
    expect(log.isActive, isFalse);
    expect(log.failure, same(failures.single));

    final writtenBefore = sink.written.length;
    log.write('ignored');
    log.logCommand('ls');
    await log.flush();
    await log.close();
    expect(sink.written.length, writtenBefore);
    expect(failures, hasLength(1));
  });

  test('error reported only through IOSink.done is also handled', () async {
    final sink = _FakeSink();
    final failures = <SshLogFailure>[];
    final log = logger(sink, onFailure: failures.add);

    sink.failDone(_diskFull());
    await Future<void>.delayed(Duration.zero);

    expect(failures, hasLength(1));
    expect(log.isActive, isFalse);
  });

  test('a slow disk caps the buffer and records how much was dropped',
      () async {
    final gate = Completer<void>();
    final sink = _FakeSink();
    final log = logger(sink, maxBufferedChars: 100);

    log.write('A' * 50);
    sink.onFlush = () => gate.future; // first flush never finishes yet
    final pending = log.flush();
    await Future<void>.delayed(Duration.zero); // let the batch reach the sink
    log.write('B' * 80); // fits (80 <= 100)
    log.write('C' * 40); // would exceed 100 -> dropped
    expect(log.droppedChars, 40);

    sink.onFlush = null;
    gate.complete();
    await pending;
    await log.flush(); // drains the 80 Bs
    log.write('D');
    await log.close();

    final out = sink.written.toString();
    expect(out, startsWith('A' * 50 + 'B' * 80));
    expect(out, contains('[LOG] 40 characters dropped'));
    expect(out, endsWith('D'));
    expect(out, isNot(contains('C')));
  });

  test('looksLikeDiskFull recognises disk-full errors only', () {
    expect(SshLogFailure.looksLikeDiskFull(_diskFull()), isTrue);
    expect(
        SshLogFailure.looksLikeDiskFull(
            const FileSystemException('x', 'p', OSError('Access is denied.', 5))),
        isFalse);
    expect(SshLogFailure.looksLikeDiskFull(StateError('closed')), isFalse);
  });

  test('incompleteEscapeStart finds only unterminated CSI sequences', () {
    expect(SshSessionLogger.incompleteEscapeStart('abc'), -1);
    expect(SshSessionLogger.incompleteEscapeStart('abc\x1B'), 3);
    expect(SshSessionLogger.incompleteEscapeStart('abc\x1B[3'), 3);
    expect(SshSessionLogger.incompleteEscapeStart('abc\x1B[31m'), -1);
    expect(SshSessionLogger.incompleteEscapeStart('abc\x1B]0;title'), -1);
  });

  test('real file: output reaches disk while the session is still open',
      () async {
    final dir = await Directory.systemTemp.createTemp('ssh_log_rt_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = SshLogService(baseDir: dir.path);
    final log = await service.createSessionLogger(sessionName: 'RT');

    log.write('\x1B[32mgreen\x1B[0m text\r\n');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await log.file.readAsString(), 'green text\r\n');

    await log.close();
  });
}
