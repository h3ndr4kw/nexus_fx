import 'package:flutter/material.dart';

import '../models/session_models.dart';
import '../services/session_import/imported_host.dart';
import '../theme/app_theme.dart';

/// Lets the user pick which imported hosts to save. Hosts already saved
/// (same host, port and user) start unchecked.
///
/// Returns the chosen hosts, or null when cancelled.
class SessionImportDialog extends StatefulWidget {
  final String sourceLabel;
  final ImportScan scan;
  final List<SessionProfile> existing;

  const SessionImportDialog({
    super.key,
    required this.sourceLabel,
    required this.scan,
    required this.existing,
  });

  static Future<List<ImportedHost>?> show(
    BuildContext context, {
    required String sourceLabel,
    required ImportScan scan,
    required List<SessionProfile> existing,
  }) {
    return showDialog<List<ImportedHost>>(
      context: context,
      builder: (_) => SessionImportDialog(sourceLabel: sourceLabel, scan: scan, existing: existing),
    );
  }

  @override
  State<SessionImportDialog> createState() => _SessionImportDialogState();
}

class _SessionImportDialogState extends State<SessionImportDialog> {
  late final List<bool> _duplicate;
  late final List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _duplicate = [for (final h in widget.scan.hosts) SessionImporter.isDuplicate(h, widget.existing)];
    _checked = [for (final d in _duplicate) !d];
  }

  int get _count => _checked.where((c) => c).length;

  @override
  Widget build(BuildContext context) {
    final hosts = widget.scan.hosts;
    final warnings = widget.scan.warnings;
    return AlertDialog(
      backgroundColor: AppTheme.bgSurface,
      title: Text(
        'Import from ${widget.sourceLabel}',
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hosts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No SSH hosts found.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              )
            else ...[
              Row(
                children: [
                  Text(
                    '${hosts.length} host${hosts.length == 1 ? '' : 's'} found',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _checked.fillRange(0, _checked.length, true)),
                    child: const Text('Select all', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _checked.fillRange(0, _checked.length, false)),
                    child: const Text('Select none', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: hosts.length,
                  itemBuilder: (_, i) => _hostTile(i, hosts[i]),
                ),
              ),
            ],
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: AppTheme.statusWarning),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(w, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('session_import_confirm'),
          onPressed: _count == 0
              ? null
              : () => Navigator.of(context).pop([
                    for (var i = 0; i < hosts.length; i++)
                      if (_checked[i]) hosts[i],
                  ]),
          child: Text('Import $_count'),
        ),
      ],
    );
  }

  Widget _hostTile(int i, ImportedHost h) {
    final details = <String>[
      h.target,
      if (h.jump != null) 'via ${h.jump!.alias ?? h.jump!.label}',
      if (h.identityFile != null) 'key ${h.identityFile}',
    ];
    return CheckboxListTile(
      key: Key('session_import_${h.name}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _checked[i],
      onChanged: (v) => setState(() => _checked[i] = v ?? false),
      title: Row(
        children: [
          Flexible(
            child: Text(
              h.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
          ),
          if (_duplicate[i]) ...[
            const SizedBox(width: 8),
            const Text('already saved', style: TextStyle(fontSize: 11, color: AppTheme.statusWarning)),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details.join('  ·  '), style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          for (final n in h.notes)
            Text(n, style: const TextStyle(fontSize: 11, color: AppTheme.statusWarning)),
        ],
      ),
    );
  }
}
