import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/terminal_search.dart';
import 'package:xterm/xterm.dart';

Terminal _term(String output, {int width = 80}) {
  final t = Terminal(maxLines: 1000);
  t.resize(width, 24);
  t.write(output);
  return t;
}

void main() {
  test('finds every hit, case-insensitive by default', () {
    final t = _term('Error one\r\nok\r\nanother error, ERROR\r\n');
    final r = searchTerminalBuffer(t.buffer, 'error');
    expect(r.matches, const [
      TerminalSearchMatch(0, 0, 0, 5),
      TerminalSearchMatch(2, 8, 2, 13),
      TerminalSearchMatch(2, 15, 2, 20),
    ]);
    expect(r.truncated, isFalse);
  });

  test('case-sensitive search skips other casings', () {
    final t = _term('Error error ERROR\r\n');
    final r = searchTerminalBuffer(t.buffer, 'error', caseSensitive: true);
    expect(r.matches, const [TerminalSearchMatch(0, 6, 0, 11)]);
  });

  test('plain queries treat regex metacharacters literally', () {
    final t = _term('a.b axb\r\n');
    final r = searchTerminalBuffer(t.buffer, 'a.b');
    expect(r.matches, const [TerminalSearchMatch(0, 0, 0, 3)]);
  });

  test('regex mode matches patterns and reports bad ones', () {
    final t = _term('pid=12 pid=345\r\n');
    final r = searchTerminalBuffer(t.buffer, r'pid=\d+', regex: true);
    expect(r.matches, const [
      TerminalSearchMatch(0, 0, 0, 6),
      TerminalSearchMatch(0, 7, 0, 14),
    ]);

    final bad = searchTerminalBuffer(t.buffer, '(', regex: true);
    expect(bad.matches, isEmpty);
    expect(bad.error, isNotNull);
  });

  test('empty-width regex hits are ignored', () {
    final t = _term('abc\r\n');
    expect(searchTerminalBuffer(t.buffer, 'x*', regex: true).matches, isEmpty);
  });

  test('a hit split by soft wrap spans both rows', () {
    // Width 10: "0123456789" fills row 0, "needle" wraps at "ne|edle".
    final t = _term('12345678needle\r\n', width: 10);
    final r = searchTerminalBuffer(t.buffer, 'needle');
    expect(r.matches, const [TerminalSearchMatch(0, 8, 1, 4)]);
  });

  test('wide characters map to their cell columns', () {
    final t = _term('日本 key\r\n');
    final r = searchTerminalBuffer(t.buffer, 'key');
    expect(r.matches, const [TerminalSearchMatch(0, 5, 0, 8)]);
    final wide = searchTerminalBuffer(t.buffer, '本');
    expect(wide.matches, const [TerminalSearchMatch(0, 2, 0, 4)]);
  });

  test('stops at the match limit', () {
    final t = _term('x x x x x\r\n');
    final r = searchTerminalBuffer(t.buffer, 'x', maxMatches: 3);
    expect(r.matches, hasLength(3));
    expect(r.truncated, isTrue);
  });

  test('empty query finds nothing', () {
    final t = _term('abc\r\n');
    expect(searchTerminalBuffer(t.buffer, '').matches, isEmpty);
  });
}
