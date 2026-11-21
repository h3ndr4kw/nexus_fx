import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/app_log.dart';

void main() {
  late Directory dir;
  late String logPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nexus_fx_app_log_');
    logPath = '${dir.path}${Platform.pathSeparator}logs${Platform.pathSeparator}app.log';
    AppLog.clearForTesting();
    AppLog.setLogFileForTesting(logPath);
  });

  tearDown(() {
    AppLog.setLogFileForTesting(null);
    AppLog.clearForTesting();
    dir.deleteSync(recursive: true);
  });

  test('a warning is kept in memory with its origin and error', () {
    AppLog.warning('SshTunnelManager.close', const SocketException('reset'));

    final entry = AppLog.recent.single;
    expect(entry.level, 'WARN');
    expect(entry.where, 'SshTunnelManager.close');
    expect(entry.message, contains('reset'));
  });

  test('a warning is appended to the log file, creating its folder', () {
    AppLog.warning('A.first', 'one');
    AppLog.warning('B.second', 'two');

    final lines = File(logPath).readAsLinesSync();
    expect(lines, hasLength(2));
    expect(lines[0], allOf(contains('WARN'), contains('A.first'), contains('one')));
    expect(lines[1], allOf(contains('B.second'), contains('two')));
  });

  test('an error entry includes the stack trace in the file', () {
    AppLog.error('C.third', StateError('boom'), StackTrace.fromString('#0 frame_marker'));

    final text = File(logPath).readAsStringSync();
    expect(text, allOf(contains('ERROR'), contains('boom'), contains('frame_marker')));
  });

  test('memory keeps only the most recent entries', () {
    for (var i = 0; i < AppLog.maxRecent + 5; i++) {
      AppLog.warning('Loop', 'entry $i');
    }

    expect(AppLog.recent, hasLength(AppLog.maxRecent));
    expect(AppLog.recent.first.message, 'entry 5');
    expect(AppLog.recent.last.message, 'entry ${AppLog.maxRecent + 4}');
  });

  test('a full log file is rotated to .1 before the next write', () {
    final file = File(logPath)..createSync(recursive: true);
    file.writeAsStringSync('x' * (AppLog.maxFileBytes + 1));

    AppLog.warning('After.rotate', 'fresh');

    expect(File('$logPath.1').lengthSync(), AppLog.maxFileBytes + 1);
    expect(file.readAsStringSync(), contains('fresh'));
    expect(file.lengthSync(), lessThan(1000));
  });

  test('an unwritable log path never throws and still records in memory', () {
    // A path below a regular file cannot be created.
    final blocker = File('${dir.path}${Platform.pathSeparator}blocker')..writeAsStringSync('x');
    AppLog.setLogFileForTesting('${blocker.path}${Platform.pathSeparator}app.log');

    expect(() => AppLog.warning('D.fourth', 'still recorded'), returnsNormally);
    expect(AppLog.recent.single.message, 'still recorded');
  });

  test('with no log file only memory is used', () {
    AppLog.setLogFileForTesting(null);

    AppLog.warning('E.fifth', 'memory only');

    expect(AppLog.recent, hasLength(1));
    expect(File(logPath).existsSync(), isFalse);
  });
}
