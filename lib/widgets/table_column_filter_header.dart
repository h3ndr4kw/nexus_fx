import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable Excel-style table column header with sorting and multi-select filtering.
class TableColumnFilterHeader extends StatelessWidget {
  final String title;
  final String columnKey;
  final Map<String, int> valueCounts;
  final Set<String>? selectedValues;
  final bool isSorted;
  final bool sortAscending;
  final ValueChanged<Set<String>?> onFilterChanged;
  final ValueChanged<bool>? onSortChanged;
  final VoidCallback? onClearSort;
  final bool showSort;

  const TableColumnFilterHeader({
    super.key,
    required this.title,
    required this.columnKey,
    required this.valueCounts,
    required this.selectedValues,
    required this.onFilterChanged,
    this.isSorted = false,
    this.sortAscending = true,
    this.onSortChanged,
    this.onClearSort,
    this.showSort = true,
  });

  bool get isFiltered =>
      selectedValues != null && selectedValues!.length < valueCounts.length;

  void _openFilterDialog(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final targetOffset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final targetSize = renderBox?.size ?? Size.zero;

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return _AnchoredFilterDialog(
          targetOffset: targetOffset,
          targetSize: targetSize,
          title: title,
          columnKey: columnKey,
          valueCounts: valueCounts,
          initialSelected: selectedValues ?? valueCounts.keys.toSet(),
          isSorted: isSorted,
          sortAscending: sortAscending,
          showSort: showSort,
          onSortChanged: (asc) {
            onSortChanged?.call(asc);
            Navigator.of(dialogCtx).pop();
          },
          onClearSort: () {
            onClearSort?.call();
            Navigator.of(dialogCtx).pop();
          },
          onApply: (selected) {
            if (selected.length == valueCounts.length) {
              onFilterChanged(null); // All selected = no filter
            } else {
              onFilterChanged(selected);
            }
            Navigator.of(dialogCtx).pop();
          },
          onClearFilter: () {
            onFilterChanged(null);
            Navigator.of(dialogCtx).pop();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = isFiltered;

    return InkWell(
      onTap: () => _openFilterDialog(context),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: filtered || isSorted ? Colors.white : AppTheme.textColor,
                letterSpacing: 0.5,
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 4),
              Icon(
                sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 13,
                color: AppTheme.primaryColor,
              ),
            ],
            const SizedBox(width: 4),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  filtered ? Icons.filter_alt : Icons.filter_alt_outlined,
                  size: 15,
                  color: filtered
                      ? AppTheme.primaryColor
                      : AppTheme.textColor.withValues(alpha: 0.6),
                ),
                if (filtered)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnchoredFilterDialog extends StatefulWidget {
  final Offset targetOffset;
  final Size targetSize;
  final String title;
  final String columnKey;
  final Map<String, int> valueCounts;
  final Set<String> initialSelected;
  final bool isSorted;
  final bool sortAscending;
  final bool showSort;
  final ValueChanged<bool> onSortChanged;
  final VoidCallback onClearSort;
  final ValueChanged<Set<String>> onApply;
  final VoidCallback onClearFilter;

  const _AnchoredFilterDialog({
    required this.targetOffset,
    required this.targetSize,
    required this.title,
    required this.columnKey,
    required this.valueCounts,
    required this.initialSelected,
    required this.isSorted,
    required this.sortAscending,
    required this.showSort,
    required this.onSortChanged,
    required this.onClearSort,
    required this.onApply,
    required this.onClearFilter,
  });

  @override
  State<_AnchoredFilterDialog> createState() => _AnchoredFilterDialogState();
}

class _AnchoredFilterDialogState extends State<_AnchoredFilterDialog> {
  late final TextEditingController _searchController;
  late Set<String> _selected;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _matchingKeys {
    final all = widget.valueCounts.keys.toList();
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((k) => k.toLowerCase().contains(q)).toList();
  }

  bool? get _selectAllState {
    final visible = _matchingKeys;
    if (visible.isEmpty) return false;
    final selectedVisibleCount = visible.where((k) => _selected.contains(k)).length;
    if (selectedVisibleCount == visible.length) return true;
    if (selectedVisibleCount == 0) return false;
    return null; // Indeterminate
  }

  void _toggleSelectAll(bool? value) {
    final visible = _matchingKeys;
    setState(() {
      if (value == true) {
        _selected.addAll(visible);
      } else {
        _selected.removeAll(visible);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const dialogWidth = 300.0;
    const maxDialogHeight = 440.0;

    // Position horizontally below the header, clamping within screen bounds
    double left = widget.targetOffset.dx;
    if (left + dialogWidth > screenSize.width - 16) {
      left = screenSize.width - dialogWidth - 16;
    }
    left = math.max(16.0, left);

    // Position vertically
    double top = widget.targetOffset.dy + widget.targetSize.height + 4;
    if (top + maxDialogHeight > screenSize.height - 16) {
      top = math.max(16.0, widget.targetOffset.dy - maxDialogHeight - 4);
    }

    final visibleKeys = _matchingKeys;
    final hasActiveFilter = _selected.length < widget.valueCounts.length;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dialogWidth,
              constraints: const BoxConstraints(maxHeight: maxDialogHeight),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.inputBorderColor, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.background.withValues(alpha: 0.6),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                      border: Border(
                        bottom: BorderSide(color: AppTheme.inputBorderColor, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_alt, size: 16, color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Filter: ${widget.title}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close, size: 16, color: AppTheme.textColor),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sort Buttons
                  if (widget.showSort) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSortButton(
                              icon: Icons.arrow_upward,
                              label: 'Sort A-Z',
                              isActive: widget.isSorted && widget.sortAscending,
                              onTap: () => widget.onSortChanged(true),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildSortButton(
                              icon: Icons.arrow_downward,
                              label: 'Sort Z-A',
                              isActive: widget.isSorted && !widget.sortAscending,
                              onTap: () => widget.onSortChanged(false),
                            ),
                          ),
                          if (widget.isSorted) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Clear sort',
                              child: InkWell(
                                onTap: widget.onClearSort,
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppTheme.inputBorderColor),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(Icons.sort_by_alpha, size: 14, color: AppTheme.textColor),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Divider(color: AppTheme.inputBorderColor, height: 12),
                  ],

                  // Search Box
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search values...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textColor.withValues(alpha: 0.6),
                          ),
                          prefixIcon: const Icon(Icons.search, size: 15, color: AppTheme.textColor),
                          prefixIconConstraints: const BoxConstraints(minWidth: 28),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? InkWell(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  child: const Icon(Icons.clear, size: 14, color: AppTheme.textColor),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(minWidth: 24),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                          filled: true,
                          fillColor: AppTheme.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: AppTheme.inputBorderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: AppTheme.inputBorderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: AppTheme.primaryColor),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Select All & Shortcuts
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selectAllState,
                          tristate: true,
                          onChanged: _toggleSelectAll,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          activeColor: AppTheme.primaryColor,
                          side: BorderSide(color: AppTheme.inputBorderColor, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '(Select All)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() => _selected.clear()),
                          child: Text(
                            'Clear',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.primaryColor.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Divider(color: AppTheme.inputBorderColor, height: 6),

                  // Scrollable Checklist
                  Flexible(
                    child: visibleKeys.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            alignment: Alignment.center,
                            child: Text(
                              'No matching values',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: visibleKeys.length,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            itemBuilder: (context, index) {
                              final key = visibleKeys[index];
                              final isChecked = _selected.contains(key);
                              final count = widget.valueCounts[key] ?? 0;

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isChecked) {
                                      _selected.remove(key);
                                    } else {
                                      _selected.add(key);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: Checkbox(
                                          value: isChecked,
                                          onChanged: (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selected.add(key);
                                              } else {
                                                _selected.remove(key);
                                              }
                                            });
                                          },
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                          activeColor: AppTheme.primaryColor,
                                          side: BorderSide(
                                            color: AppTheme.inputBorderColor,
                                            width: 1.2,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          key.isEmpty ? '(Empty)' : key,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: isChecked ? Colors.white : AppTheme.textColor,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '($count)',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: AppTheme.textColor.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Footer actions
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.background.withValues(alpha: 0.7),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                      border: Border(
                        top: BorderSide(color: AppTheme.inputBorderColor, width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (hasActiveFilter)
                          TextButton(
                            onPressed: widget.onClearFilter,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.errorColor,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Reset', style: TextStyle(fontSize: 11)),
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.textColor,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('Cancel', style: TextStyle(fontSize: 11)),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: () => widget.onApply(_selected),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              child: const Text(
                                'OK',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSortButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primaryColor.withValues(alpha: 0.2)
              : AppTheme.background,
          border: Border.all(
            color: isActive ? AppTheme.primaryColor : AppTheme.inputBorderColor,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: isActive ? AppTheme.primaryColor : AppTheme.textColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.white : AppTheme.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
