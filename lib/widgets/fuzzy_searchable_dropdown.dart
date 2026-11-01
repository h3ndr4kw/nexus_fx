import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class FuzzyMatchResult {
  final int score;
  final List<int> matchedIndices;

  const FuzzyMatchResult(this.score, this.matchedIndices);
}

class FuzzySearchHelper {
  /// Calculates fuzzy match score and matched indices between query and target.
  /// Higher score means better match. Returns null if not matched.
  static FuzzyMatchResult? match(String query, String target) {
    if (query.isEmpty) return const FuzzyMatchResult(0, []);
    final q = query.toLowerCase().trim();
    final t = target.toLowerCase();

    // 1. Exact match
    if (t == q) {
      return FuzzyMatchResult(
        1000,
        List.generate(target.length, (i) => i),
      );
    }

    // 2. Starts with exact query
    if (t.startsWith(q)) {
      return FuzzyMatchResult(
        800,
        List.generate(q.length, (i) => i),
      );
    }

    // 3. Substring match
    final subIdx = t.indexOf(q);
    if (subIdx != -1) {
      return FuzzyMatchResult(
        600 - subIdx,
        List.generate(q.length, (i) => subIdx + i),
      );
    }

    // 4. Token-based match (e.g. "crb 85" matches "crb1-fecp-02 10.63.23.85")
    final tokens = q.split(RegExp(r'[\s\-_/]+')).where((e) => e.isNotEmpty).toList();
    if (tokens.length > 1) {
      bool allTokensMatched = true;
      final tokenIndices = <int>[];
      int tokenScore = 500;

      for (final tok in tokens) {
        final idx = t.indexOf(tok);
        if (idx == -1) {
          allTokensMatched = false;
          break;
        }
        for (int i = 0; i < tok.length; i++) {
          tokenIndices.add(idx + i);
        }
      }

      if (allTokensMatched) {
        return FuzzyMatchResult(tokenScore, tokenIndices);
      }
    }

    // 5. Subsequence fuzzy match (e.g. "crb02" matches "crb1-fecp-02")
    int qIdx = 0;
    final seqIndices = <int>[];
    int consecutiveStreak = 0;
    int streakScore = 0;

    for (int tIdx = 0; tIdx < t.length; tIdx++) {
      if (qIdx < q.length && t[tIdx] == q[qIdx]) {
        seqIndices.add(tIdx);
        qIdx++;
        consecutiveStreak++;
        streakScore += consecutiveStreak * 10;
      } else {
        consecutiveStreak = 0;
      }
    }

    if (qIdx == q.length) {
      final score = 300 + streakScore - (t.length - q.length);
      return FuzzyMatchResult(score, seqIndices);
    }

    return null;
  }
}

class FuzzySearchableDropdown<T> extends StatefulWidget {
  final List<T> items;
  final T? selectedItem;
  final ValueChanged<T?> onChanged;
  final String Function(T) itemLabel;
  final String Function(T)? itemSubtitle;
  final Widget Function(T)? itemLeading;
  final Widget Function(T)? itemBadge;
  final List<String> Function(T)? searchTerms;
  final String hintText;
  final String searchPlaceholder;
  final bool isClearable;
  final double maxHeight;

  const FuzzySearchableDropdown({
    super.key,
    required this.items,
    required this.selectedItem,
    required this.onChanged,
    required this.itemLabel,
    this.itemSubtitle,
    this.itemLeading,
    this.itemBadge,
    this.searchTerms,
    this.hintText = 'Select an item...',
    this.searchPlaceholder = 'Type to search with fuzzy logic...',
    this.isClearable = false,
    this.maxHeight = 360,
  });

  @override
  State<FuzzySearchableDropdown<T>> createState() =>
      _FuzzySearchableDropdownState<T>();
}

class _FuzzySearchableDropdownState<T> extends State<FuzzySearchableDropdown<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    _closeDropdown();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    if (mounted && _isOpen) {
      setState(() => _isOpen = false);
    }
  }

  @override
  void dispose() {
    _closeDropdown();
    super.dispose();
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            // Barrier to dismiss
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDropdown,
                child: Container(color: Colors.transparent),
              ),
            ),
            // Popup container
            Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0, size.height + 4),
                child: Material(
                  elevation: 12,
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    constraints: BoxConstraints(maxHeight: widget.maxHeight),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _DropdownOverlayContent<T>(
                      items: widget.items,
                      selectedItem: widget.selectedItem,
                      itemLabel: widget.itemLabel,
                      itemSubtitle: widget.itemSubtitle,
                      itemLeading: widget.itemLeading,
                      itemBadge: widget.itemBadge,
                      searchTerms: widget.searchTerms,
                      searchPlaceholder: widget.searchPlaceholder,
                      onSelected: (val) {
                        widget.onChanged(val);
                        _closeDropdown();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.selectedItem;

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isOpen ? AppTheme.primaryColor : AppTheme.inputBorderColor,
              width: _isOpen ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              if (item != null && widget.itemLeading != null) ...[
                widget.itemLeading!(item),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: item != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.itemLabel(item),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.itemSubtitle != null) ...[
                            Text(
                              widget.itemSubtitle!(item),
                              style: TextStyle(
                                color: AppTheme.textColor.withValues(alpha: 0.6),
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      )
                    : Text(
                        widget.hintText,
                        style: TextStyle(
                          color: AppTheme.textColor.withValues(alpha: 0.4),
                          fontSize: 13,
                        ),
                      ),
              ),
              if (item != null && widget.itemBadge != null) ...[
                const SizedBox(width: 8),
                widget.itemBadge!(item),
                const SizedBox(width: 4),
              ],
              if (widget.isClearable && item != null) ...[
                InkWell(
                  onTap: () => widget.onChanged(null),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.clear, size: 14, color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.textColor,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownOverlayContent<T> extends StatefulWidget {
  final List<T> items;
  final T? selectedItem;
  final String Function(T) itemLabel;
  final String Function(T)? itemSubtitle;
  final Widget Function(T)? itemLeading;
  final Widget Function(T)? itemBadge;
  final List<String> Function(T)? searchTerms;
  final String searchPlaceholder;
  final ValueChanged<T> onSelected;

  const _DropdownOverlayContent({
    required this.items,
    required this.selectedItem,
    required this.itemLabel,
    this.itemSubtitle,
    this.itemLeading,
    this.itemBadge,
    this.searchTerms,
    required this.searchPlaceholder,
    required this.onSelected,
  });

  @override
  State<_DropdownOverlayContent<T>> createState() =>
      _DropdownOverlayContentState<T>();
}

class _ScoredItem<T> {
  final T item;
  final int score;
  final List<int> labelIndices;

  const _ScoredItem(this.item, this.score, this.labelIndices);
}

class _DropdownOverlayContentState<T> extends State<_DropdownOverlayContent<T>> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _highlightedIndex = 0;
  List<_ScoredItem<T>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _applyFilter('');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _applyFilter(String q) {
    if (q.trim().isEmpty) {
      _filtered = widget.items
          .map((it) => _ScoredItem(it, 0, const []))
          .toList();
      _highlightedIndex = 0;
      return;
    }

    final query = q.trim();
    final scored = <_ScoredItem<T>>[];

    for (final it in widget.items) {
      final label = widget.itemLabel(it);
      final subtitle = widget.itemSubtitle != null ? widget.itemSubtitle!(it) : '';
      final terms = widget.searchTerms != null ? widget.searchTerms!(it) : <String>[];

      // Match against label
      final labelMatch = FuzzySearchHelper.match(query, label);

      // Match against subtitle / terms
      int bestScore = labelMatch?.score ?? -1;
      final labelIndices = labelMatch?.matchedIndices ?? <int>[];

      if (subtitle.isNotEmpty) {
        final subMatch = FuzzySearchHelper.match(query, subtitle);
        if (subMatch != null && subMatch.score > bestScore) {
          bestScore = subMatch.score;
        }
      }

      for (final t in terms) {
        final termMatch = FuzzySearchHelper.match(query, t);
        if (termMatch != null && termMatch.score > bestScore) {
          bestScore = termMatch.score;
        }
      }

      if (bestScore >= 0) {
        scored.add(_ScoredItem(it, bestScore, labelIndices));
      }
    }

    // Sort descending by score
    scored.sort((a, b) => b.score.compareTo(a.score));

    setState(() {
      _filtered = scored;
      _highlightedIndex = 0;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_filtered.isNotEmpty) {
        setState(() {
          _highlightedIndex = (_highlightedIndex + 1) % _filtered.length;
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_filtered.isNotEmpty) {
        setState(() {
          _highlightedIndex =
              (_highlightedIndex - 1 + _filtered.length) % _filtered.length;
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_filtered.isNotEmpty && _highlightedIndex < _filtered.length) {
        widget.onSelected(_filtered[_highlightedIndex].item);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search input bar
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _focusNode,
              onChanged: _applyFilter,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: widget.searchPlaceholder,
                hintStyle:
                    TextStyle(color: AppTheme.textColor.withValues(alpha: 0.4)),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: AppTheme.primaryColor),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: Colors.white60),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilter('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.background,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppTheme.inputBorderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: AppTheme.inputBorderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppTheme.inputBorderColor),
          // List of items
          Flexible(
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 28,
                              color: AppTheme.textColor.withValues(alpha: 0.3)),
                          const SizedBox(height: 6),
                          Text(
                            'No items match "${_searchCtrl.text}"',
                            style: TextStyle(
                              color: AppTheme.textColor.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, idx) {
                      final scored = _filtered[idx];
                      final it = scored.item;
                      final isSelected = it == widget.selectedItem;
                      final isHighlighted = idx == _highlightedIndex;
                      final label = widget.itemLabel(it);
                      final subtitle = widget.itemSubtitle != null
                          ? widget.itemSubtitle!(it)
                          : null;

                      return InkWell(
                        onTap: () => widget.onSelected(it),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? AppTheme.primaryColor.withValues(alpha: 0.18)
                                : isSelected
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: isHighlighted
                                    ? AppTheme.primaryColor
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (widget.itemLeading != null) ...[
                                widget.itemLeading!(it),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildHighlightedText(
                                      label,
                                      scored.labelIndices,
                                    ),
                                    if (subtitle != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                          color: AppTheme.textColor
                                              .withValues(alpha: 0.6),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (widget.itemBadge != null) ...[
                                const SizedBox(width: 8),
                                widget.itemBadge!(it),
                              ],
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: AppTheme.primaryColor,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(String text, List<int> matchedIndices) {
    if (matchedIndices.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final matchedSet = matchedIndices.toSet();
    final spans = <TextSpan>[];

    for (int i = 0; i < text.length; i++) {
      final isMatched = matchedSet.contains(i);
      spans.add(TextSpan(
        text: text[i],
        style: TextStyle(
          color: isMatched ? AppTheme.accentColor : Colors.white,
          fontWeight: isMatched ? FontWeight.bold : FontWeight.normal,
          backgroundColor: isMatched
              ? AppTheme.accentColor.withValues(alpha: 0.2)
              : null,
        ),
      ));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: spans,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
