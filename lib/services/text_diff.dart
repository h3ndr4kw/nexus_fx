/// Side-by-side text diff in the style of VS Code's diff editor: a line diff
/// (linear-space Myers), replaced lines paired up row by row, and a character
/// diff inside each paired line.
library;

enum DiffRowKind { unchanged, removed, added, modified }

/// A changed span inside a modified line, in [DiffLine.text] coordinates.
class DiffRange {
  final int start;
  final int end;
  const DiffRange(this.start, this.end);

  @override
  String toString() => '[$start,$end)';
}

/// One side of a row. A row with no line on a side shows a filler there.
class DiffLine {
  final int lineNumber;
  final String text;
  final List<DiffRange> changes;
  const DiffLine(this.lineNumber, this.text, [this.changes = const []]);
}

class DiffRow {
  final DiffRowKind kind;
  final DiffLine? left;
  final DiffLine? right;
  const DiffRow(this.kind, this.left, this.right);
}

/// A run of changed rows, [startRow] inclusive to [endRow] exclusive.
class DiffHunk {
  final int startRow;
  final int endRow;
  const DiffHunk(this.startRow, this.endRow);
}

class TextDiffResult {
  final List<DiffRow> rows;
  final List<DiffHunk> hunks;
  final int addedLines;
  final int removedLines;

  /// The raw texts are byte-for-byte equal. When [identical] is true but this
  /// is false, the files differ only in whitespace or line endings.
  final bool textEqual;

  /// Line diff gave up after the time limit and fell back to a coarse result.
  final bool timedOut;

  /// "CRLF", "LF", "CR", or null for text without a line break.
  final String? leftEol;
  final String? rightEol;

  const TextDiffResult({
    required this.rows,
    required this.hunks,
    required this.addedLines,
    required this.removedLines,
    required this.textEqual,
    required this.timedOut,
    required this.leftEol,
    required this.rightEol,
  });

  bool get identical => hunks.isEmpty;
}

/// True when [bytes] looks like binary data (a NUL in the first 8 KB), the
/// same test git and VS Code use.
bool looksBinary(List<int> bytes) {
  final n = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// Lines longer than this get a whole-line highlight instead of a char diff.
const int _maxCharDiffLength = 2000;

TextDiffResult computeTextDiff(
  String left,
  String right, {
  bool ignoreTrimWhitespace = true,
  int tabSize = 4,
  int timeoutMs = 5000,
}) {
  final leftLines = _splitLines(left, tabSize);
  final rightLines = _splitLines(right, tabSize);

  final ids = <String, int>{};
  int idOf(String line) {
    final key = ignoreTrimWhitespace ? line.trim() : line;
    return ids.putIfAbsent(key, () => ids.length);
  }

  final a = [for (final l in leftLines) idOf(l)];
  final b = [for (final l in rightLines) idOf(l)];

  final lineCtx = _Ctx(timeoutMs);
  final ops = <_Op>[];
  _diffRange(a, 0, a.length, b, 0, b.length, lineCtx, ops);

  final rows = <DiffRow>[];
  final hunks = <DiffHunk>[];
  var added = 0;
  var removed = 0;
  var i = 0; // next left line
  var j = 0; // next right line
  var k = 0;
  while (k < ops.length) {
    final op = ops[k];
    if (op.type == _OpType.equal) {
      for (var n = 0; n < op.count; n++) {
        rows.add(DiffRow(
          DiffRowKind.unchanged,
          DiffLine(i + 1, leftLines[i]),
          DiffLine(j + 1, rightLines[j]),
        ));
        i++;
        j++;
      }
      k++;
      continue;
    }

    // Everything up to the next equal run is one change block.
    var dels = 0;
    var ins = 0;
    while (k < ops.length && ops[k].type != _OpType.equal) {
      if (ops[k].type == _OpType.delete) {
        dels += ops[k].count;
      } else {
        ins += ops[k].count;
      }
      k++;
    }
    final start = rows.length;
    final paired = dels < ins ? dels : ins;
    for (var n = 0; n < paired; n++) {
      final lt = leftLines[i + n];
      final rt = rightLines[j + n];
      final (lc, rc) = _charChanges(lt, rt);
      rows.add(DiffRow(
        DiffRowKind.modified,
        DiffLine(i + n + 1, lt, lc),
        DiffLine(j + n + 1, rt, rc),
      ));
    }
    for (var n = paired; n < dels; n++) {
      final t = leftLines[i + n];
      rows.add(DiffRow(DiffRowKind.removed, DiffLine(i + n + 1, t), null));
    }
    for (var n = paired; n < ins; n++) {
      final t = rightLines[j + n];
      rows.add(DiffRow(DiffRowKind.added, null, DiffLine(j + n + 1, t)));
    }
    i += dels;
    j += ins;
    removed += dels;
    added += ins;
    hunks.add(DiffHunk(start, rows.length));
  }

  return TextDiffResult(
    rows: rows,
    hunks: hunks,
    addedLines: added,
    removedLines: removed,
    textEqual: left == right,
    timedOut: lineCtx.timedOut,
    leftEol: _detectEol(left),
    rightEol: _detectEol(right),
  );
}

String? _detectEol(String text) {
  final idx = text.indexOf(RegExp(r'[\r\n]'));
  if (idx < 0) return null;
  if (text.codeUnitAt(idx) == 0x0A) return 'LF';
  return idx + 1 < text.length && text.codeUnitAt(idx + 1) == 0x0A ? 'CRLF' : 'CR';
}

List<String> _splitLines(String text, int tabSize) {
  if (text.startsWith('﻿')) text = text.substring(1);
  if (text.isEmpty) return const [];
  final lines = text.split(RegExp(r'\r\n|\r|\n'));
  if (lines.last.isEmpty) lines.removeLast();
  if (tabSize <= 0) return lines;
  return [for (final l in lines) l.contains('\t') ? _expandTabs(l, tabSize) : l];
}

String _expandTabs(String line, int tabSize) {
  final sb = StringBuffer();
  var col = 0;
  for (final ch in line.codeUnits) {
    if (ch == 0x09) {
      final pad = tabSize - (col % tabSize);
      sb.write(' ' * pad);
      col += pad;
    } else {
      sb.writeCharCode(ch);
      col++;
    }
  }
  return sb.toString();
}

/// Changed character spans of a paired line on each side.
(List<DiffRange>, List<DiffRange>) _charChanges(String left, String right) {
  if (left.length > _maxCharDiffLength || right.length > _maxCharDiffLength) {
    return ([DiffRange(0, left.length)], [DiffRange(0, right.length)]);
  }
  final ops = <_Op>[];
  _diffRange(left.codeUnits, 0, left.length, right.codeUnits, 0, right.length, _Ctx(50), ops);

  // Short equal islands between two changes make a confetti of highlights;
  // fold them into the surrounding change, the way VS Code smooths it.
  final l = <DiffRange>[];
  final r = <DiffRange>[];
  var i = 0;
  var j = 0;
  for (var k = 0; k < ops.length; k++) {
    final op = ops[k];
    switch (op.type) {
      case _OpType.equal:
        final sandwiched = k > 0 && k < ops.length - 1 && op.count <= 2;
        if (sandwiched) {
          _addRange(l, i, i + op.count);
          _addRange(r, j, j + op.count);
        }
        i += op.count;
        j += op.count;
      case _OpType.delete:
        _addRange(l, i, i + op.count);
        i += op.count;
      case _OpType.insert:
        _addRange(r, j, j + op.count);
        j += op.count;
    }
  }
  return (l, r);
}

void _addRange(List<DiffRange> ranges, int start, int end) {
  if (ranges.isNotEmpty && ranges.last.end >= start) {
    final last = ranges.removeLast();
    ranges.add(DiffRange(last.start, end > last.end ? end : last.end));
  } else {
    ranges.add(DiffRange(start, end));
  }
}

// Myers diff over int sequences

enum _OpType { equal, delete, insert }

class _Op {
  final _OpType type;
  int count;
  _Op(this.type, this.count);
}

class _Ctx {
  final int timeoutMs;
  final Stopwatch watch = Stopwatch()..start();
  bool timedOut = false;
  _Ctx(this.timeoutMs);

  bool get expired {
    if (!timedOut && watch.elapsedMilliseconds > timeoutMs) timedOut = true;
    return timedOut;
  }
}

void _emit(List<_Op> out, _OpType type, int count) {
  if (count <= 0) return;
  if (out.isNotEmpty && out.last.type == type) {
    out.last.count += count;
  } else {
    out.add(_Op(type, count));
  }
}

void _diffRange(
  List<int> a, int aLo, int aHi,
  List<int> b, int bLo, int bHi,
  _Ctx ctx, List<_Op> out,
) {
  var prefix = 0;
  while (aLo + prefix < aHi && bLo + prefix < bHi && a[aLo + prefix] == b[bLo + prefix]) {
    prefix++;
  }
  _emit(out, _OpType.equal, prefix);
  aLo += prefix;
  bLo += prefix;

  var suffix = 0;
  while (aHi - suffix > aLo && bHi - suffix > bLo && a[aHi - 1 - suffix] == b[bHi - 1 - suffix]) {
    suffix++;
  }
  aHi -= suffix;
  bHi -= suffix;

  final n = aHi - aLo;
  final m = bHi - bLo;
  if (n == 0) {
    _emit(out, _OpType.insert, m);
  } else if (m == 0) {
    _emit(out, _OpType.delete, n);
  } else {
    final split = _bisect(a, aLo, n, b, bLo, m, ctx);
    if (split == null ||
        (split.$1 == 0 && split.$2 == 0) ||
        (split.$1 == n && split.$2 == m)) {
      _emit(out, _OpType.delete, n);
      _emit(out, _OpType.insert, m);
    } else {
      final (x, y) = split;
      _diffRange(a, aLo, aLo + x, b, bLo, bLo + y, ctx, out);
      _diffRange(a, aLo + x, aHi, b, bLo + y, bHi, ctx, out);
    }
  }
  _emit(out, _OpType.equal, suffix);
}

/// Middle snake of the edit graph, searched from both ends at once
/// (Myers 1986, as in diff-match-patch). Returns the split point, or null
/// when the inputs share nothing or [ctx] ran out of time.
(int, int)? _bisect(List<int> a, int aOff, int n, List<int> b, int bOff, int m, _Ctx ctx) {
  final maxD = (n + m + 1) ~/ 2;
  final vOffset = maxD;
  final vLength = 2 * maxD + 2;
  final v1 = List<int>.filled(vLength, -1);
  final v2 = List<int>.filled(vLength, -1);
  v1[vOffset + 1] = 0;
  v2[vOffset + 1] = 0;
  final delta = n - m;
  final front = delta.isOdd;
  var k1start = 0, k1end = 0, k2start = 0, k2end = 0;

  for (var d = 0; d < maxD; d++) {
    if (ctx.expired) return null;

    for (var k1 = -d + k1start; k1 <= d - k1end; k1 += 2) {
      final k1Offset = vOffset + k1;
      var x1 = (k1 == -d || (k1 != d && v1[k1Offset - 1] < v1[k1Offset + 1]))
          ? v1[k1Offset + 1]
          : v1[k1Offset - 1] + 1;
      var y1 = x1 - k1;
      while (x1 < n && y1 < m && a[aOff + x1] == b[bOff + y1]) {
        x1++;
        y1++;
      }
      v1[k1Offset] = x1;
      if (x1 > n) {
        k1end += 2;
      } else if (y1 > m) {
        k1start += 2;
      } else if (front) {
        final k2Offset = vOffset + delta - k1;
        if (k2Offset >= 0 && k2Offset < vLength && v2[k2Offset] != -1) {
          if (x1 >= n - v2[k2Offset]) return (x1, y1);
        }
      }
    }

    for (var k2 = -d + k2start; k2 <= d - k2end; k2 += 2) {
      final k2Offset = vOffset + k2;
      var x2 = (k2 == -d || (k2 != d && v2[k2Offset - 1] < v2[k2Offset + 1]))
          ? v2[k2Offset + 1]
          : v2[k2Offset - 1] + 1;
      var y2 = x2 - k2;
      while (x2 < n && y2 < m && a[aOff + n - x2 - 1] == b[bOff + m - y2 - 1]) {
        x2++;
        y2++;
      }
      v2[k2Offset] = x2;
      if (x2 > n) {
        k2end += 2;
      } else if (y2 > m) {
        k2start += 2;
      } else if (!front) {
        final k1Offset = vOffset + delta - k2;
        if (k1Offset >= 0 && k1Offset < vLength && v1[k1Offset] != -1) {
          final x1 = v1[k1Offset];
          final y1 = vOffset + x1 - k1Offset;
          if (x1 >= n - x2) return (x1, y1);
        }
      }
    }
  }
  return null;
}
