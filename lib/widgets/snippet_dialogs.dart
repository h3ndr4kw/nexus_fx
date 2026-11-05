import 'package:flutter/material.dart';
import '../models/snippet_model.dart';
import '../services/snippet_manager_service.dart';
import '../theme/app_theme.dart';

/// Modal dialog for creating or editing a command snippet.
class SnippetEditorDialog extends StatefulWidget {
  final SnippetItem? snippet;

  const SnippetEditorDialog({
    super.key,
    this.snippet,
  });

  static Future<bool?> show(BuildContext context, {SnippetItem? snippet}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SnippetEditorDialog(snippet: snippet),
    );
  }

  @override
  State<SnippetEditorDialog> createState() => _SnippetEditorDialogState();
}

class _SnippetEditorDialogState extends State<SnippetEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _commandsController;
  bool _isSaving = false;

  bool get _isEditMode => widget.snippet != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.snippet?.name ?? '');
    _descController =
        TextEditingController(text: widget.snippet?.description ?? '');
    _commandsController = TextEditingController(
      text: widget.snippet != null ? widget.snippet!.fullScript : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commandsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final rawCommands = _commandsController.text
        .split('\n')
        .map((c) => c.trimRight())
        .where((c) => c.isNotEmpty)
        .toList();

    if (rawCommands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one command.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (_isEditMode) {
        final updated = widget.snippet!.copyWith(
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          commands: rawCommands,
        );
        await SnippetManagerService.instance.updateSnippet(updated);
      } else {
        await SnippetManagerService.instance.createSnippet(
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          commands: rawCommands,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.activePalette.surfaceColor,
        title: const Text('Delete Snippet?'),
        content: Text('Are you sure you want to delete "${widget.snippet!.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await SnippetManagerService.instance.deleteSnippet(widget.snippet!.id);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.activePalette;

    return Dialog(
      backgroundColor: palette.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.inputBorderColor, width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      _isEditMode ? Icons.edit_note_rounded : Icons.bookmark_add_rounded,
                      color: palette.primaryColor,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEditMode ? 'Edit Snippet' : 'New Command Snippet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: palette.textColor,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      color: palette.textColor.withValues(alpha: 0.6),
                      splashRadius: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Snippet Name
                        Text(
                          'Snippet Name',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.textColor.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          autofocus: !_isEditMode,
                          style: TextStyle(fontSize: 13, color: palette.textColor),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Snippet name is required';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'e.g. Restart Web Server & Check Status',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: palette.textColor.withValues(alpha: 0.35),
                            ),
                            filled: true,
                            fillColor: palette.background,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.inputBorderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.inputBorderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.primaryColor, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Description (Optional)
                        Text(
                          'Description (Optional)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.textColor.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _descController,
                          style: TextStyle(fontSize: 13, color: palette.textColor),
                          decoration: InputDecoration(
                            hintText: 'Brief explanation of this snippet',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: palette.textColor.withValues(alpha: 0.35),
                            ),
                            filled: true,
                            fillColor: palette.background,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.inputBorderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.inputBorderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.primaryColor, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Commands (Multiline)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Commands (One or Multiple Lines)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: palette.textColor.withValues(alpha: 0.8),
                              ),
                            ),
                            Text(
                              'Supports multi-line script',
                              style: TextStyle(
                                fontSize: 11,
                                color: palette.textColor.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _commandsController,
                          minLines: 5,
                          maxLines: 12,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontFamily: 'Courier New',
                            color: palette.textColor,
                            height: 1.35,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'At least one command is required';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'systemctl stop myapp\ngit pull origin main\nsystemctl start myapp',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              fontFamily: 'Courier New',
                              color: palette.textColor.withValues(alpha: 0.35),
                            ),
                            filled: true,
                            fillColor: palette.background,
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.inputBorderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.inputBorderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.primaryColor, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Footer Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_isEditMode)
                      TextButton.icon(
                        onPressed: _isSaving ? null : _delete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: const Text('Delete'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: palette.textColor,
                            side: BorderSide(color: palette.inputBorderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 16),
                          label: Text(_isEditMode ? 'Update Snippet' : 'Save Snippet'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal palette dialog for searching, running, and managing snippets.
class SnippetPickerModal extends StatefulWidget {
  const SnippetPickerModal({super.key});

  static Future<SnippetItem?> show(BuildContext context) {
    return showDialog<SnippetItem>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const SnippetPickerModal(),
    );
  }

  @override
  State<SnippetPickerModal> createState() => _SnippetPickerModalState();
}

class _SnippetPickerModalState extends State<SnippetPickerModal> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    SnippetManagerService.instance.loadSnippets();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openEditor({SnippetItem? snippet}) async {
    final changed = await SnippetEditorDialog.show(context, snippet: snippet);
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.activePalette;

    return ListenableBuilder(
      listenable: SnippetManagerService.instance,
      builder: (context, _) {
        final items = SnippetManagerService.instance.searchSnippets(_searchQuery);

        return Dialog(
          backgroundColor: palette.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: palette.inputBorderColor, width: 1.2),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search & Header bar
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.terminal_rounded, size: 20, color: palette.primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          autofocus: true,
                          style: TextStyle(fontSize: 13, color: palette.textColor),
                          decoration: InputDecoration(
                            hintText: 'Search snippet by name or command...',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: palette.textColor.withValues(alpha: 0.4),
                            ),
                            isDense: true,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty) ...[
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () => _searchController.clear(),
                          color: palette.textColor.withValues(alpha: 0.5),
                          splashRadius: 14,
                        ),
                      ],
                      const SizedBox(width: 4),
                      // Add new snippet button
                      Tooltip(
                        message: 'Create new snippet',
                        child: ElevatedButton.icon(
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add_rounded, size: 15),
                          label: const Text('New Snippet', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: palette.inputBorderColor),

                // Snippets List
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bookmark_border_rounded,
                                size: 36,
                                color: palette.textColor.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'No snippets saved yet.'
                                    : 'No snippets matching "$_searchQuery"',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textColor.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: palette.inputBorderColor.withValues(alpha: 0.4),
                          ),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final lineCount = item.lineCount;

                            return InkWell(
                              onTap: () => Navigator.of(context).pop(item),
                              hoverColor: palette.primaryColor.withValues(alpha: 0.08),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                item.name,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: palette.textColor,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: palette.textColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  lineCount > 1
                                                      ? '$lineCount lines'
                                                      : '1 cmd',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontFamily: 'Courier New',
                                                    color: palette.textColor.withValues(alpha: 0.7),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (item.description.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              item.description,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: palette.textColor.withValues(alpha: 0.5),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: palette.background,
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              item.fullScript,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontFamily: 'Courier New',
                                                color: palette.textColor.withValues(alpha: 0.8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Quick Edit button
                                    Tooltip(
                                      message: 'Edit snippet',
                                      child: IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 16),
                                        color: palette.textColor.withValues(alpha: 0.6),
                                        hoverColor: palette.primaryColor.withValues(alpha: 0.15),
                                        splashRadius: 16,
                                        onPressed: () => _openEditor(snippet: item),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    // Select/Insert icon indicator
                                    Icon(
                                      Icons.keyboard_return_rounded,
                                      size: 14,
                                      color: palette.primaryColor.withValues(alpha: 0.6),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Footer hint
                Divider(height: 1, color: palette.inputBorderColor),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Click snippet to insert into command line',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textColor.withValues(alpha: 0.5),
                        ),
                      ),
                      Text(
                        'ESC to close',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'Courier New',
                          color: palette.textColor.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
