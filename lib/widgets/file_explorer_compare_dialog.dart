part of 'file_explorer_dialogs.dart';

// Side-by-side compare, modeled on VS Code's diff editor.

/// One file in a compare: [name] heads the dialog, [location] (node and full
/// path) labels its column.
class CompareSource {
  final String name;
  final String location;
  final String text;
  const CompareSource({required this.name, required this.location, required this.text});
}

/// Shows [left] (original) and [right] (modified) side by side: removed lines
/// red on the left, added lines green on the right, changed characters
/// highlighted inside paired lines, fillers where a side has no line.
/// F7 / Shift+F7 (or Alt+Down / Alt+Up) step through the changes.
class FileExplorerCompareDialog extends StatefulWidget {
  final CompareSource left;
  final CompareSource right;

  const FileExplorerCompareDialog({super.key, required this.left, required this.right});

  @override
  State<FileExplorerCompareDialog> createState() => _FileExplorerCompareDialogState();
}

class _Diff {
  const _Diff._();

  // VS Code dark diff colors, line and character strengths.
  static const Color removedLine = Color(0x33FF0000);
  static const Color removedText = Color(0x66FF3B3B);
  static const Color addedLine = Color(0x339BB955);
  static const Color addedText = Color(0x669CCC2C);
  static const Color removedMark = Color(0xFFE06C75);
  static const Color addedMark = Color(0xFF98C379);
  static const Color filler = Color(0xFF15171C);
  static const Color fillerStripe = Color(0xFF1F222A);
  static const Color gutterText = Color(0xFF6E7681);

  static const double fontSize = 12;
  static const double rowHeight = 19;
  static const int maxDisplayChars = 5000;

  /// Inputs above this size are diffed off the UI isolate.
  static const int isolateThreshold = 200 * 1024;
}

class _FileExplorerCompareDialogState extends State<FileExplorerCompareDialog> {
  static const _textStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: _Diff.fontSize,
    height: _Diff.rowHeight / _Diff.fontSize,
    color: _Dlg.textPrimary,
  );

  late CompareSource _left = widget.left;
  late CompareSource _right = widget.right;
  bool _ignoreWhitespace = true;
  TextDiffResult? _result;
  String? _error;
  int _current = -1;
  int _computeToken = 0;

  final _leftGutter = ScrollController();
  final _leftText = ScrollController();
  final _rightGutter = ScrollController();
  final _rightText = ScrollController();
  final _leftH = ScrollController();
  final _rightH = ScrollController();
  late final List<ScrollController> _vertical = [_leftGutter, _leftText, _rightGutter, _rightText];
  bool _syncing = false;

  late final double _charWidth = _measureCharWidth();

  @override
  void initState() {
    super.initState();
    for (final c in _vertical) {
      c.addListener(() => _syncFrom(c));
    }
    _compute();
  }

  @override
  void dispose() {
    for (final c in [..._vertical, _leftH, _rightH]) {
      c.dispose();
    }
    super.dispose();
  }

  double _measureCharWidth() {
    final tp = TextPainter(
      text: TextSpan(text: 'M' * 20, style: _textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width / 20;
    tp.dispose();
    return w;
  }

  Future<void> _compute() async {
    final token = ++_computeToken;
    final left = _left.text;
    final right = _right.text;
    final ignore = _ignoreWhitespace;
    setState(() {
      _result = null;
      _error = null;
      _current = -1;
    });
    try {
      final result = left.length + right.length < _Diff.isolateThreshold
          ? computeTextDiff(left, right, ignoreTrimWhitespace: ignore)
          : await Isolate.run(() => computeTextDiff(left, right, ignoreTrimWhitespace: ignore));
      if (!mounted || token != _computeToken) return;
      setState(() => _result = result);
      // Like VS Code, open on the first change.
      if (result.hunks.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && token == _computeToken) _goTo(0);
        });
      }
    } catch (e) {
      if (mounted && token == _computeToken) setState(() => _error = '$e');
    }
  }

  void _syncFrom(ScrollController source) {
    if (_syncing || !source.hasClients) return;
    _syncing = true;
    final offset = source.offset;
    for (final c in _vertical) {
      if (identical(c, source) || !c.hasClients) continue;
      final target = offset.clamp(0.0, c.position.maxScrollExtent);
      if (c.offset != target) c.jumpTo(target);
    }
    _syncing = false;
  }

  void _scrollToRow(int row) {
    final c = _rightText;
    if (!c.hasClients) return;
    final viewport = c.position.viewportDimension;
    final target = (row * _Diff.rowHeight - viewport / 3).clamp(0.0, c.position.maxScrollExtent);
    c.jumpTo(target);
  }

  void _goTo(int hunk) {
    final hunks = _result?.hunks ?? const [];
    if (hunks.isEmpty) return;
    setState(() => _current = hunk % hunks.length);
    _scrollToRow(hunks[_current].startRow);
  }

  void _next() => _goTo(_current + 1);

  void _previous() {
    final n = _result?.hunks.length ?? 0;
    if (n == 0) return;
    _goTo(_current <= 0 ? n - 1 : _current - 1);
  }

  void _swap() {
    setState(() {
      final t = _left;
      _left = _right;
      _right = t;
    });
    _compute();
  }

  void _toggleWhitespace() {
    setState(() => _ignoreWhitespace = !_ignoreWhitespace);
    _compute();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f7) {
      keyboard.isShiftPressed ? _previous() : _next();
      return KeyEventResult.handled;
    }
    if (keyboard.isAltPressed && key == LogicalKeyboardKey.arrowDown) {
      _next();
      return KeyEventResult.handled;
    }
    if (keyboard.isAltPressed && key == LogicalKeyboardKey.arrowUp) {
      _previous();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: _DialogShell(
        title: '${_left.name} ↔ ${_right.name}',
        rawTitle: true,
        icon: Icons.compare_arrows,
        width: math.max(600, size.width - 32),
        height: math.max(400, size.height - 32),
        insetPadding: const EdgeInsets.all(16),
        onClose: () => Navigator.pop(context),
        child: Column(
          children: [
            _buildToolbar(),
            const Divider(height: 1, color: _Dlg.divider),
            _buildLocations(),
            const Divider(height: 1, color: _Dlg.divider),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final r = _result;
    final hunkCount = r?.hunks.length ?? 0;
    final summary = <InlineSpan>[];
    if (_error != null) {
      summary.add(TextSpan(text: 'Compare failed: $_error', style: const TextStyle(color: _Dlg.danger)));
    } else if (r == null) {
      summary.add(const TextSpan(text: 'Comparing…'));
    } else if (r.identical) {
      summary.add(TextSpan(
        text: r.textEqual
            ? 'No differences'
            : _ignoreWhitespace
                ? 'No differences (ignoring whitespace and line endings)'
                : 'No differences (line endings or final newline differ)',
      ));
    } else {
      summary.add(TextSpan(text: '$hunkCount change${hunkCount == 1 ? '' : 's'}'));
      if (_current >= 0) summary.add(TextSpan(text: '  ·  ${_current + 1} of $hunkCount'));
      summary.add(const TextSpan(text: '    '));
      summary.add(TextSpan(text: '+${r.addedLines}', style: const TextStyle(color: _Diff.addedMark)));
      summary.add(const TextSpan(text: '  '));
      summary.add(TextSpan(text: '−${r.removedLines}', style: const TextStyle(color: _Diff.removedMark)));
    }
    if (r != null && r.timedOut) {
      summary.add(const TextSpan(
        text: '    (diff took too long; showing a coarse result)',
        style: TextStyle(color: AppTheme.warningColor),
      ));
    }

    final canStep = hunkCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: summary),
              key: const ValueKey('compare-summary'),
              style: const TextStyle(fontSize: 12, color: _Dlg.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: _toggleWhitespace,
            icon: Icon(
              _ignoreWhitespace ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              size: 16,
              color: _ignoreWhitespace ? _Dlg.accent : _Dlg.textSecondary,
            ),
            label: const Text('Ignore whitespace', style: TextStyle(fontSize: 12, color: _Dlg.textSecondary)),
          ),
          const SizedBox(width: 4),
          _toolButton(Icons.swap_horiz, 'Swap Sides', _swap),
          _toolButton(Icons.arrow_upward, 'Previous Change (Shift+F7)', canStep ? _previous : null),
          _toolButton(Icons.arrow_downward, 'Next Change (F7)', canStep ? _next : null),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: _Dlg.textSecondary,
      disabledColor: _Dlg.textMuted.withValues(alpha: 0.4),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }

  Widget _buildLocations() {
    Widget label(CompareSource s, String? eol) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: s.location,
                    child: Text(
                      s.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: _Dlg.textSecondary, fontFamily: 'monospace'),
                    ),
                  ),
                ),
                if (eol != null) ...[
                  const SizedBox(width: 8),
                  Text(eol, style: const TextStyle(fontSize: 10, color: _Dlg.textMuted)),
                ],
              ],
            ),
          ),
        );
    return Row(
      children: [
        label(_left, _result?.leftEol),
        const SizedBox(height: 24, child: VerticalDivider(width: 1, color: _Dlg.divider)),
        label(_right, _result?.rightEol),
        const SizedBox(width: 14),
      ],
    );
  }

  Widget _buildBody() {
    final r = _result;
    if (r == null) {
      return Container(
        color: _Dlg.editor,
        alignment: Alignment.center,
        child: _error == null
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.error_outline, color: _Dlg.danger),
      );
    }
    return Container(
      color: _Dlg.editor,
      child: Row(
        children: [
          Expanded(child: _buildSide(r, isLeft: true)),
          const VerticalDivider(width: 1, color: _Dlg.divider),
          Expanded(child: _buildSide(r, isLeft: false)),
          _OverviewRuler(
            result: r,
            controller: _rightText,
            rowHeight: _Diff.rowHeight,
            onJumpToRow: _scrollToRow,
          ),
        ],
      ),
    );
  }

  Widget _buildSide(TextDiffResult r, {required bool isLeft}) {
    final rows = r.rows;
    var maxLine = 0;
    var maxChars = 0;
    for (final row in rows) {
      final line = isLeft ? row.left : row.right;
      if (line == null) continue;
      if (line.lineNumber > maxLine) maxLine = line.lineNumber;
      final len = math.min(line.text.length, _Diff.maxDisplayChars + 1);
      if (len > maxChars) maxChars = len;
    }
    final gutterWidth = math.max(3, '$maxLine'.length) * _charWidth + 28;
    final noBars = ScrollConfiguration.of(context).copyWith(scrollbars: false);
    final vText = isLeft ? _leftText : _rightText;
    final h = isLeft ? _leftH : _rightH;

    return Row(
      children: [
        SizedBox(
          width: gutterWidth,
          child: ScrollConfiguration(
            behavior: noBars,
            child: ListView.builder(
              controller: isLeft ? _leftGutter : _rightGutter,
              itemExtent: _Diff.rowHeight,
              itemCount: rows.length,
              itemBuilder: (_, i) => _gutterCell(rows[i], isLeft),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = math.max(constraints.maxWidth, maxChars * _charWidth + 32);
              return Scrollbar(
                controller: vText,
                notificationPredicate: (n) => n.depth == 1,
                child: Scrollbar(
                  controller: h,
                  child: ScrollConfiguration(
                    behavior: noBars,
                    child: SingleChildScrollView(
                      controller: h,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: contentWidth,
                        child: ListView.builder(
                          controller: vText,
                          itemExtent: _Diff.rowHeight,
                          itemCount: rows.length,
                          itemBuilder: (_, i) => _textCell(rows[i], isLeft),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color? _lineColor(DiffRow row, bool isLeft) {
    switch (row.kind) {
      case DiffRowKind.unchanged:
        return null;
      case DiffRowKind.removed:
        return isLeft ? _Diff.removedLine : null;
      case DiffRowKind.added:
        return isLeft ? null : _Diff.addedLine;
      case DiffRowKind.modified:
        return isLeft ? _Diff.removedLine : _Diff.addedLine;
    }
  }

  Widget _gutterCell(DiffRow row, bool isLeft) {
    final line = isLeft ? row.left : row.right;
    if (line == null) return const _Filler();
    final changed = row.kind != DiffRowKind.unchanged;
    return Container(
      color: _lineColor(row, isLeft),
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${line.lineNumber}',
              textAlign: TextAlign.right,
              style: _textStyle.copyWith(color: _Diff.gutterText),
            ),
          ),
          SizedBox(
            width: 14,
            child: Text(
              changed ? (isLeft ? '−' : '+') : '',
              textAlign: TextAlign.center,
              style: _textStyle.copyWith(color: isLeft ? _Diff.removedMark : _Diff.addedMark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textCell(DiffRow row, bool isLeft) {
    final line = isLeft ? row.left : row.right;
    if (line == null) return const _Filler();

    var text = line.text;
    var clipped = false;
    if (text.length > _Diff.maxDisplayChars) {
      text = text.substring(0, _Diff.maxDisplayChars);
      clipped = true;
    }

    final spans = <TextSpan>[];
    if (row.kind == DiffRowKind.modified && line.changes.isNotEmpty) {
      final highlight = isLeft ? _Diff.removedText : _Diff.addedText;
      var pos = 0;
      for (final c in line.changes) {
        final start = math.min(c.start, text.length);
        final end = math.min(c.end, text.length);
        if (start > pos) spans.add(TextSpan(text: text.substring(pos, start)));
        if (end > start) {
          spans.add(TextSpan(text: text.substring(start, end), style: TextStyle(backgroundColor: highlight)));
        }
        pos = math.max(pos, end);
      }
      if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    } else {
      spans.add(TextSpan(text: text));
    }
    if (clipped) {
      spans.add(TextSpan(
        text: '  … ${line.text.length - _Diff.maxDisplayChars} more characters',
        style: const TextStyle(color: _Dlg.textMuted, fontStyle: FontStyle.italic),
      ));
    }

    return Container(
      color: _lineColor(row, isLeft),
      padding: const EdgeInsets.only(left: 8),
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(children: spans),
        style: _textStyle,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      ),
    );
  }
}

/// Diagonal-stripe placeholder where a side has no line, as in VS Code.
class _Filler extends StatelessWidget {
  const _Filler();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _StripePainter(), child: SizedBox.expand());
}

class _StripePainter extends CustomPainter {
  const _StripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _Diff.filler);
    final stripe = Paint()
      ..color = _Diff.fillerStripe
      ..strokeWidth = 1.5;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), stripe);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => false;
}

/// Thin strip right of the panes marking every change over the whole file,
/// with the visible window outlined; click or drag to jump.
class _OverviewRuler extends StatelessWidget {
  final TextDiffResult result;
  final ScrollController controller;
  final double rowHeight;
  final ValueChanged<int> onJumpToRow;

  const _OverviewRuler({
    required this.result,
    required this.controller,
    required this.rowHeight,
    required this.onJumpToRow,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        void jump(double dy) {
          final total = result.rows.length;
          if (total == 0 || height <= 0) return;
          final row = (dy / height * total).clamp(0, total - 1).toInt();
          onJumpToRow(row);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => jump(d.localPosition.dy),
          onVerticalDragUpdate: (d) => jump(d.localPosition.dy),
          child: SizedBox(
            width: 14,
            height: height,
            child: AnimatedBuilder(
              animation: controller,
              builder: (_, _) => CustomPaint(
                painter: _RulerPainter(
                  result: result,
                  offset: controller.hasClients ? controller.offset : 0,
                  viewport: controller.hasClients ? controller.position.viewportDimension : 0,
                  rowHeight: rowHeight,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  final TextDiffResult result;
  final double offset;
  final double viewport;
  final double rowHeight;

  _RulerPainter({required this.result, required this.offset, required this.viewport, required this.rowHeight});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _Dlg.surface);
    final total = result.rows.length;
    if (total == 0) return;
    final scale = size.height / total;
    final half = size.width / 2;
    final removed = Paint()..color = _Diff.removedMark;
    final added = Paint()..color = _Diff.addedMark;

    for (final hunk in result.hunks) {
      final top = hunk.startRow * scale;
      final h = math.max(2.0, (hunk.endRow - hunk.startRow) * scale);
      var hasRemoved = false;
      var hasAdded = false;
      for (var i = hunk.startRow; i < hunk.endRow; i++) {
        final row = result.rows[i];
        if (row.left != null) hasRemoved = true;
        if (row.right != null) hasAdded = true;
      }
      if (hasRemoved) canvas.drawRect(Rect.fromLTWH(1, top, half - 1, h), removed);
      if (hasAdded) canvas.drawRect(Rect.fromLTWH(half, top, half - 1, h), added);
    }

    if (viewport > 0) {
      final contentHeight = total * rowHeight;
      if (contentHeight > viewport) {
        final top = offset / contentHeight * size.height;
        final h = viewport / contentHeight * size.height;
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, h),
          Paint()..color = const Color(0x22FFFFFF),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.result != result || old.offset != offset || old.viewport != viewport;
}
