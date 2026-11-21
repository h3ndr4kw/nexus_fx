import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/text_diff.dart';

/// Compact picture of the rows: "=a|a", "-a|", "+|b", "~a|b".
List<String> _shape(TextDiffResult r) => r.rows.map((row) {
      final tag = switch (row.kind) {
        DiffRowKind.unchanged => '=',
        DiffRowKind.removed => '-',
        DiffRowKind.added => '+',
        DiffRowKind.modified => '~',
      };
      return '$tag${row.left?.text ?? ''}|${row.right?.text ?? ''}';
    }).toList();

void main() {
  group('computeTextDiff', () {
    test('identical text has no changes', () {
      final r = computeTextDiff('a\nb\nc', 'a\nb\nc');
      expect(r.identical, isTrue);
      expect(r.hunks, isEmpty);
      expect(_shape(r), ['=a|a', '=b|b', '=c|c']);
    });

    test('pure insertion leaves a filler on the left', () {
      final r = computeTextDiff('a\nc', 'a\nb\nc');
      expect(_shape(r), ['=a|a', '+|b', '=c|c']);
      expect(r.addedLines, 1);
      expect(r.removedLines, 0);
      expect(r.rows[1].left, isNull);
      expect(r.rows[1].right!.lineNumber, 2);
    });

    test('pure deletion leaves a filler on the right', () {
      final r = computeTextDiff('a\nb\nc', 'a\nc');
      expect(_shape(r), ['=a|a', '-b|', '=c|c']);
      expect(r.removedLines, 1);
    });

    test('replaced lines pair up as modified, extras stay added', () {
      final r = computeTextDiff('a\nold\nz', 'a\nnew1\nnew2\nz');
      expect(_shape(r), ['=a|a', '~old|new1', '+|new2', '=z|z']);
      expect(r.hunks.length, 1);
      expect(r.hunks.first.startRow, 1);
      expect(r.hunks.first.endRow, 3);
    });

    test('line numbers follow each side independently', () {
      final r = computeTextDiff('x\na\nb', 'a\nb\ny');
      final left = r.rows.map((e) => e.left?.lineNumber).toList();
      final right = r.rows.map((e) => e.right?.lineNumber).toList();
      expect(_shape(r), ['-x|', '=a|a', '=b|b', '+|y']);
      expect(left, [1, 2, 3, null]);
      expect(right, [null, 1, 2, 3]);
      expect(r.hunks.length, 2);
    });

    test('modified lines carry character-level ranges', () {
      final r = computeTextDiff('timeout = 30;', 'timeout = 45;');
      final row = r.rows.single;
      expect(row.kind, DiffRowKind.modified);
      String pick(DiffLine l) =>
          l.changes.map((c) => l.text.substring(c.start, c.end)).join(',');
      expect(pick(row.left!), '30');
      expect(pick(row.right!), '45');
    });

    test('ignoreTrimWhitespace treats indentation changes as equal', () {
      final ignore = computeTextDiff('a\n  b', 'a\n\tb  ', ignoreTrimWhitespace: true);
      expect(ignore.identical, isTrue);
      expect(ignore.textEqual, isFalse);

      final strict = computeTextDiff('a\n  b', 'a\n\tb  ', ignoreTrimWhitespace: false);
      expect(strict.identical, isFalse);
    });

    test('CRLF and LF are the same lines', () {
      final r = computeTextDiff('a\r\nb\r\n', 'a\nb\n');
      expect(r.identical, isTrue);
      expect(r.leftEol, 'CRLF');
      expect(r.rightEol, 'LF');
    });

    test('empty against text is all added', () {
      final r = computeTextDiff('', 'a\nb');
      expect(_shape(r), ['+|a', '+|b']);
      expect(r.hunks.length, 1);
    });

    test('tabs are expanded for display', () {
      final r = computeTextDiff('\tx', '\tx', tabSize: 4);
      expect(r.rows.single.left!.text, '    x');
    });

    test('large inputs finish and stay consistent', () {
      final a = List.generate(5000, (i) => 'line $i').join('\n');
      final b = List.generate(5000, (i) => i % 50 == 0 ? 'changed $i' : 'line $i').join('\n');
      final r = computeTextDiff(a, b);
      expect(r.hunks.length, 100);
      expect(r.rows.where((e) => e.left != null).length, 5000);
      expect(r.rows.where((e) => e.right != null).length, 5000);
    });
  });

  group('looksBinary', () {
    test('detects NUL bytes', () {
      expect(looksBinary([0x41, 0x00, 0x42]), isTrue);
      expect(looksBinary('hello'.codeUnits), isFalse);
    });
  });
}
