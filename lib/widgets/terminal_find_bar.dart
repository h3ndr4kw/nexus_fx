import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../services/terminal_search.dart';
import '../theme/app_theme.dart';

/// Floating find panel for a terminal buffer. Highlights every hit through
/// [controller], marks the current one and asks the host to scroll it into
/// view through [onReveal]. Highlights are removed when the bar is disposed.
///
/// Enter walks up to older output (the usual terminal direction), Shift+Enter
/// walks down; F3 / Shift+F3 do the same. Escape closes.
class TerminalFindBar extends StatefulWidget {
  final Terminal terminal;
  final TerminalController controller;
  final TerminalTheme theme;
  final String initialQuery;
  final VoidCallback onClose;

  /// Scrolls the given buffer row into view.
  final ValueChanged<int> onReveal;

  /// Bumped by the host to pull focus back into the field (e.g. Ctrl+F while
  /// the bar is already open), optionally with a new query.
  final int focusRequest;

  const TerminalFindBar({
    super.key,
    required this.terminal,
    required this.controller,
    required this.theme,
    required this.onClose,
    required this.onReveal,
    this.initialQuery = '',
    this.focusRequest = 0,
  });

  @override
  State<TerminalFindBar> createState() => TerminalFindBarState();
}

class TerminalFindBarState extends State<TerminalFindBar> {
  static const _searchDebounce = Duration(milliseconds: 120);

  /// Live output re-runs the search at most this often while the bar is open.
  static const _refreshThrottle = Duration(milliseconds: 500);

  late final TextEditingController _query =
      TextEditingController(text: widget.initialQuery);
  final FocusNode _fieldFocus = FocusNode();

  bool _caseSensitive = false;
  bool _regex = false;

  TerminalSearchResult _result = TerminalSearchResult.empty;
  int _current = -1;
  final List<TerminalHighlight> _highlights = [];
  TerminalHighlight? _currentHighlight;

  Timer? _debounce;
  Timer? _refresh;
  bool _bufferDirty = false;

  int get matchCount => _result.matches.length;
  int get currentIndex => _current;

  @override
  void initState() {
    super.initState();
    widget.terminal.addListener(_onTerminalChanged);
    _query.selection =
        TextSelection(baseOffset: 0, extentOffset: _query.text.length);
    // Highlights notify the TerminalView, so never search during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_query.text.isNotEmpty) _runSearch(keepPosition: false);
      _fieldFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(TerminalFindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.terminal != oldWidget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalChanged);
      widget.terminal.addListener(_onTerminalChanged);
    }
    if (widget.focusRequest != oldWidget.focusRequest) {
      if (widget.initialQuery.isNotEmpty &&
          widget.initialQuery != _query.text) {
        _query.text = widget.initialQuery;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _runSearch(keepPosition: false);
        });
      }
      _query.selection =
          TextSelection(baseOffset: 0, extentOffset: _query.text.length);
      _fieldFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalChanged);
    _debounce?.cancel();
    _refresh?.cancel();
    _clearHighlights();
    _query.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _onTerminalChanged() {
    if (_query.text.isEmpty) return;
    _bufferDirty = true;
    _refresh ??= Timer(_refreshThrottle, () {
      _refresh = null;
      if (mounted && _bufferDirty) _runSearch(keepPosition: true);
    });
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (mounted) _runSearch(keepPosition: false);
    });
  }

  void _toggleCase() {
    setState(() => _caseSensitive = !_caseSensitive);
    _runSearch(keepPosition: false);
    _fieldFocus.requestFocus();
  }

  void _toggleRegex() {
    setState(() => _regex = !_regex);
    _runSearch(keepPosition: false);
    _fieldFocus.requestFocus();
  }

  /// [keepPosition] keeps the current hit selected across a refresh caused by
  /// new output; otherwise the hit nearest the bottom (latest output) wins.
  void _runSearch({required bool keepPosition}) {
    _bufferDirty = false;
    final previous = keepPosition ? _currentHighlight?.range?.begin : null;
    final hadCurrent = keepPosition && _current >= 0;

    final result = searchTerminalBuffer(
      widget.terminal.buffer,
      _query.text,
      caseSensitive: _caseSensitive,
      regex: _regex,
    );

    var current = -1;
    if (result.matches.isNotEmpty) {
      current = result.matches.length - 1;
      if (previous != null) {
        final i = result.matches.indexWhere((m) =>
            m.startLine > previous.y ||
            (m.startLine == previous.y && m.startCol >= previous.x));
        if (i >= 0) current = i;
      }
    }

    setState(() {
      _result = result;
      _current = current;
    });
    _paintHighlights();
    // A live refresh must not yank the view while the user reads elsewhere.
    if (!hadCurrent) _revealCurrent();
  }

  void _clearHighlights() {
    for (final h in _highlights) {
      h.dispose();
    }
    _highlights.clear();
    _currentHighlight?.dispose();
    _currentHighlight = null;
  }

  TerminalHighlight? _highlight(TerminalSearchMatch m, Color color) {
    final buffer = widget.terminal.buffer;
    final lines = buffer.lines.length;
    if (m.startLine >= lines || m.endLine >= lines) return null;
    return widget.controller.highlight(
      p1: buffer.createAnchor(m.startCol, m.startLine),
      p2: buffer.createAnchor(m.endCol, m.endLine),
      color: color,
    );
  }

  void _paintHighlights() {
    _clearHighlights();
    // Highlights are painted over the glyphs, so they must stay translucent.
    final hit = widget.theme.searchHitBackground.withValues(alpha: 0.35);
    for (final m in _result.matches) {
      final h = _highlight(m, hit);
      if (h != null) _highlights.add(h);
    }
    _paintCurrent();
  }

  void _paintCurrent() {
    _currentHighlight?.dispose();
    _currentHighlight = null;
    if (_current < 0 || _current >= _result.matches.length) return;
    _currentHighlight = _highlight(
      _result.matches[_current],
      widget.theme.searchHitBackgroundCurrent.withValues(alpha: 0.6),
    );
  }

  void _revealCurrent() {
    if (_current < 0 || _current >= _result.matches.length) return;
    widget.onReveal(_result.matches[_current].startLine);
  }

  /// Moves to an older hit ([up]) or a newer one, wrapping at the ends.
  void step({required bool up}) {
    if (_bufferDirty) {
      _refresh?.cancel();
      _refresh = null;
      _runSearch(keepPosition: true);
    }
    final n = _result.matches.length;
    if (n == 0) return;
    setState(() {
      _current = up ? (_current - 1 + n) % n : (_current + 1) % n;
    });
    _paintCurrent();
    _revealCurrent();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.f3) {
      // Flush a pending keystroke search first so Enter acts on what's typed.
      if (_debounce?.isActive ?? false) {
        _debounce!.cancel();
        _runSearch(keepPosition: false);
        return KeyEventResult.handled;
      }
      step(up: !shift);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _status {
    if (_result.error != null) return 'Invalid regex';
    if (_query.text.isEmpty) return '';
    final n = _result.matches.length;
    if (n == 0) return 'No results';
    final total = _result.truncated ? '$n+' : '$n';
    return '${_current + 1} of $total';
  }

  @override
  Widget build(BuildContext context) {
    final hasMatches = _result.matches.isNotEmpty;
    final error = _result.error != null ||
        (_query.text.isNotEmpty && !hasMatches);

    return Material(
      color: AppTheme.surfaceColor,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppTheme.inputBorderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const ValueKey('terminal-find-field'),
                  controller: _query,
                  focusNode: _fieldFocus,
                  onChanged: _onQueryChanged,
                  style: TextStyle(fontSize: 12, color: AppTheme.textColor),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Find in buffer',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(
                          color: error
                              ? AppTheme.errorColor
                              : AppTheme.inputBorderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(
                          color: error
                              ? AppTheme.errorColor
                              : AppTheme.inputBorderColor),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _Toggle(
              label: 'Aa',
              tooltip: 'Match case',
              active: _caseSensitive,
              onTap: _toggleCase,
            ),
            _Toggle(
              label: '.*',
              tooltip: 'Use regular expression',
              active: _regex,
              onTap: _toggleRegex,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 72),
              child: Text(
                _status,
                key: const ValueKey('terminal-find-status'),
                style: TextStyle(
                  fontSize: 11,
                  color: error ? AppTheme.errorColor : Colors.grey,
                ),
              ),
            ),
            _IconBtn(
              icon: Icons.arrow_upward,
              tooltip: 'Previous match (Enter)',
              onTap: hasMatches ? () => step(up: true) : null,
            ),
            _IconBtn(
              icon: Icons.arrow_downward,
              tooltip: 'Next match (Shift+Enter)',
              onTap: hasMatches ? () => step(up: false) : null,
            ),
            _IconBtn(
              icon: Icons.close,
              tooltip: 'Close (Esc)',
              onTap: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _Toggle({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active
                ? AppTheme.accentPrimary.withValues(alpha: 0.25)
                : Colors.transparent,
            border: Border.all(
              color: active ? AppTheme.accentPrimary : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: active ? AppTheme.textColor : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      onPressed: onTap,
      color: AppTheme.textColor,
      disabledColor: Colors.grey.withValues(alpha: 0.5),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 14,
    );
  }
}
