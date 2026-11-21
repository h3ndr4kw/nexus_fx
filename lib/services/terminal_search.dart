import 'package:xterm/xterm.dart';

/// One hit in a terminal buffer, in cell coordinates. [endCol] is exclusive
/// and belongs to [endLine]; a hit can span soft-wrapped lines.
class TerminalSearchMatch {
  final int startLine;
  final int startCol;
  final int endLine;
  final int endCol;

  const TerminalSearchMatch(
      this.startLine, this.startCol, this.endLine, this.endCol);

  @override
  bool operator ==(Object other) =>
      other is TerminalSearchMatch &&
      other.startLine == startLine &&
      other.startCol == startCol &&
      other.endLine == endLine &&
      other.endCol == endCol;

  @override
  int get hashCode => Object.hash(startLine, startCol, endLine, endCol);

  @override
  String toString() =>
      'TerminalSearchMatch($startLine:$startCol-$endLine:$endCol)';
}

class TerminalSearchResult {
  final List<TerminalSearchMatch> matches;

  /// True when the scan stopped at the match limit.
  final bool truncated;

  /// Set when a regex query does not compile.
  final String? error;

  const TerminalSearchResult(this.matches,
      {this.truncated = false, this.error});

  static const empty = TerminalSearchResult([]);
}

/// Builds the pattern for [query], or throws [FormatException] for a bad regex.
RegExp buildTerminalSearchPattern(String query,
    {bool caseSensitive = false, bool regex = false}) {
  return RegExp(regex ? query : RegExp.escape(query),
      caseSensitive: caseSensitive, unicode: true);
}

/// Searches every line of [buffer] (scrollback included). Soft-wrapped rows
/// are joined first so a hit split by the terminal width is still found.
TerminalSearchResult searchTerminalBuffer(
  Buffer buffer,
  String query, {
  bool caseSensitive = false,
  bool regex = false,
  int maxMatches = 5000,
}) {
  if (query.isEmpty) return TerminalSearchResult.empty;

  final RegExp pattern;
  try {
    pattern = buildTerminalSearchPattern(query,
        caseSensitive: caseSensitive, regex: regex);
  } on FormatException catch (e) {
    return TerminalSearchResult(const [], error: e.message);
  }

  final lines = buffer.lines;
  final matches = <TerminalSearchMatch>[];
  final text = StringBuffer();
  // Per UTF-16 code unit of [text]: the row, the cell column and the width.
  final rows = <int>[];
  final cols = <int>[];
  final widths = <int>[];

  var i = 0;
  while (i < lines.length) {
    text.clear();
    rows.clear();
    cols.clear();
    widths.clear();

    // One logical line: row i plus the rows that wrap from it.
    var row = i;
    do {
      _appendRow(lines[row], row, text, rows, cols, widths,
          trimTrailing: row + 1 >= lines.length || !lines[row + 1].isWrapped);
      row++;
    } while (row < lines.length && lines[row].isWrapped);
    i = row;

    if (rows.isEmpty) continue;
    final s = text.toString();
    for (final m in pattern.allMatches(s)) {
      if (m.end == m.start) continue; // regexes like `a*` match empty runs
      final last = m.end - 1;
      matches.add(TerminalSearchMatch(
        rows[m.start],
        cols[m.start],
        rows[last],
        cols[last] + widths[last],
      ));
      if (matches.length >= maxMatches) {
        return TerminalSearchResult(matches, truncated: true);
      }
    }
  }
  return TerminalSearchResult(matches);
}

void _appendRow(
  BufferLine line,
  int row,
  StringBuffer text,
  List<int> rows,
  List<int> cols,
  List<int> widths, {
  required bool trimTrailing,
}) {
  var end = line.length;
  if (trimTrailing) {
    while (end > 0 && line.getCodePoint(end - 1) == 0) {
      end--;
    }
  }
  for (var col = 0; col < end; col++) {
    final cp = line.getCodePoint(col);
    final width = line.getWidth(col);
    if (cp == 0) {
      // The second cell of a wide character carries no glyph.
      if (col > 0 && line.getWidth(col - 1) == 2) continue;
      _push(0x20, row, col, 1, text, rows, cols, widths);
    } else {
      _push(cp, row, col, width < 1 ? 1 : width, text, rows, cols, widths);
    }
  }
}

void _push(int codePoint, int row, int col, int width, StringBuffer text,
    List<int> rows, List<int> cols, List<int> widths) {
  text.writeCharCode(codePoint);
  final units = codePoint > 0xFFFF ? 2 : 1;
  for (var u = 0; u < units; u++) {
    rows.add(row);
    cols.add(col);
    widths.add(width);
  }
}
