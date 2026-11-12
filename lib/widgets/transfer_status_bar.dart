import 'package:flutter/material.dart';

import '../services/transfer_manager.dart';
import '../theme/app_theme.dart';

const _kGreen = Color(0xFF98C379);
const _kRed = Color(0xFFE06C75);
const _kCyan = Color(0xFF56B6C2);
const _kText = Color(0xFFABB2BF);
const _kMuted = Color(0xFF5C6370);
const _kAmber = Color(0xFFE5C07B);

/// App-wide strip at the bottom of the window showing copy/move jobs.
///
/// Non-modal: it never blocks tabs or pages. Collapsed it shows one summary
/// line with an overall progress bar; clicking it (or the chevron) expands a
/// per-job list with individual cancel/dismiss buttons. Hidden when there is
/// nothing to show.
class TransferStatusBar extends StatefulWidget {
  const TransferStatusBar({super.key, this.manager});

  final TransferManager? manager;

  @override
  State<TransferStatusBar> createState() => _TransferStatusBarState();
}

class _TransferStatusBarState extends State<TransferStatusBar> {
  bool _expanded = false;

  /// "Apply to all" checkbox state per job id.
  final Map<int, bool> _applyToAll = {};

  TransferManager get _manager => widget.manager ?? TransferManager.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _manager,
      builder: (context, _) {
        final jobs = _manager.jobs;
        _applyToAll.removeWhere((id, _) => !jobs.any((j) => j.id == id));
        if (jobs.isEmpty) {
          _expanded = false;
          return const SizedBox.shrink();
        }
        final conflictJob = jobs.where((j) => j.needsAttention).firstOrNull;
        return Container(
          key: const ValueKey('transfer_status_bar'),
          margin: const EdgeInsets.fromLTRB(3, 0, 3, 3),
          decoration: BoxDecoration(
            color: AppTheme.bgSurfaceSecondary,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: conflictJob != null ? _kAmber : AppTheme.borderSubtle,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_expanded) _buildExpanded(jobs),
              if (conflictJob != null) _buildConflictRow(conflictJob),
              _buildSummaryRow(jobs),
            ],
          ),
        );
      },
    );
  }

  // ---------- collapsed summary ----------

  Widget _buildSummaryRow(List<TransferJob> jobs) {
    final active = jobs.where((j) => j.isActive).toList();
    final queued = active.where((j) => j.status == TransferStatus.queued).length;
    final single = jobs.length == 1 ? jobs.first : null;

    final Widget leading;
    final String text;
    final Color color;
    double? progress;
    var paused = false;

    if (active.isEmpty) {
      // Only finished jobs left: show the latest outcome.
      final last = jobs.last;
      leading = _statusIcon(last);
      text = jobs.length == 1
          ? last.resultSummary
          : '${last.resultSummary}  (+${jobs.length - 1} more)';
      color = _colorFor(last);
    } else if (active.length == 1) {
      final job = active.first;
      leading = _statusIcon(job);
      text = _activeLine(job);
      color = _kText;
      progress = job.status == TransferStatus.queued ? null : job.progress;
      paused = job.isPaused;
    } else {
      final pausedCount = active.where((j) => j.isPaused).length;
      leading = pausedCount == active.length
          ? const Icon(Icons.pause_circle, size: 13, color: _kMuted)
          : _spinner();
      text = '${active.length} transfers'
          '${pausedCount > 0 ? ' · $pausedCount paused' : ''}'
          '${queued > 0 ? ' · $queued queued' : ''}'
          ' · ${_pct(_manager.aggregateProgress ?? 0)}';
      paused = pausedCount == active.length;
      color = _kText;
      progress = _manager.aggregateProgress;
    }

    final canToggle = jobs.length > 1;

    return InkWell(
      onTap: canToggle ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                key: const ValueKey('transfer_status_summary'),
                overflow: TextOverflow.ellipsis,
                style: _mono(11, color),
              ),
            ),
            if (active.isNotEmpty) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: _progressBar(progress, paused: paused),
              ),
            ],
            if (canToggle)
              _iconButton(
                key: const ValueKey('transfer_status_toggle'),
                icon: _expanded ? Icons.expand_more : Icons.expand_less,
                tooltip: _expanded ? 'Hide transfers' : 'Show all transfers',
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            if (single != null) _jobAction(single),
          ],
        ),
      ),
    );
  }

  // ---------- name conflict prompt ----------

  /// Non-modal decision row: the job waits, everything else keeps working.
  Widget _buildConflictRow(TransferJob job) {
    final conflict = job.pendingConflict!;
    final applyAll = _applyToAll[job.id] ?? false;
    final what = conflict.existingIsDir ? 'Folder' : 'File';
    final message = "$what '${conflict.itemName}' already exists in ${job.destLabel}"
        "${conflict.existingIsDir ? ' (Replace deletes the existing folder first)' : ''}";

    void resolve(ConflictChoice choice) =>
        _manager.resolveConflict(job, choice, applyToAll: applyAll);

    return Container(
      key: ValueKey('transfer_conflict_${job.id}'),
      color: _kAmber.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: _kAmber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              overflow: TextOverflow.ellipsis,
              style: _mono(11, _kAmber),
            ),
          ),
          if (conflict.remainingItems > 0) ...[
            const SizedBox(width: 8),
            InkWell(
              key: ValueKey('transfer_conflict_apply_all_${job.id}'),
              onTap: () => setState(() => _applyToAll[job.id] = !applyAll),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    applyAll ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 14,
                    color: _kText,
                  ),
                  const SizedBox(width: 4),
                  Text('Apply to all (${conflict.remainingItems} more)',
                      style: _mono(10, _kText)),
                ],
              ),
            ),
          ],
          const SizedBox(width: 6),
          _textButton('Replace', () => resolve(ConflictChoice.replace),
              key: ValueKey('transfer_conflict_replace_${job.id}'), color: _kRed),
          _textButton('Keep both', () => resolve(ConflictChoice.keepBoth),
              key: ValueKey('transfer_conflict_keep_both_${job.id}'), color: _kCyan),
          _textButton('Skip', () => resolve(ConflictChoice.skip),
              key: ValueKey('transfer_conflict_skip_${job.id}'), color: _kGreen),
          _iconButton(
            icon: Icons.close,
            tooltip: 'Cancel transfer',
            color: _kRed,
            onPressed: () => _manager.cancel(job),
          ),
        ],
      ),
    );
  }

  // ---------- expanded list ----------

  Widget _buildExpanded(List<TransferJob> jobs) {
    final hasActive = jobs.any((j) => j.isActive);
    final hasFinished = jobs.any((j) => !j.isActive);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 2),
          child: Row(
            children: [
              Text('TRANSFERS (${jobs.length})',
                  style: _mono(10, _kMuted, bold: true)),
              const Spacer(),
              if (hasFinished)
                _textButton('Clear finished', _manager.clearFinished),
              if (jobs.any(_manager.canPause))
                _textButton('Pause all', _manager.pauseAll,
                    key: const ValueKey('transfer_pause_all')),
              if (jobs.any((j) => j.isPaused))
                _textButton('Resume all', _manager.resumeAll,
                    key: const ValueKey('transfer_resume_all'), color: _kCyan),
              if (hasActive)
                _textButton('Cancel all', _manager.cancelAll,
                    key: const ValueKey('transfer_cancel_all'), color: _kRed),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [for (final job in jobs) _jobRow(job)],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppTheme.borderSubtle),
      ],
    );
  }

  Widget _jobRow(TransferJob job) {
    final detail = job.isActive ? _activeDetail(job) : job.resultSummary;
    return Padding(
      key: ValueKey('transfer_job_${job.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Row(
        children: [
          _statusIcon(job),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${job.title} → ${job.destLabel}',
                    overflow: TextOverflow.ellipsis,
                    style: _mono(11, AppTheme.textPrimary)),
                Text(detail,
                    overflow: TextOverflow.ellipsis,
                    style: _mono(10, job.isActive ? _kMuted : _colorFor(job))),
              ],
            ),
          ),
          if (job.isActive) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: _progressBar(
                  job.status == TransferStatus.queued ? null : job.progress,
                  paused: job.isPaused),
            ),
          ],
          _jobAction(job),
        ],
      ),
    );
  }

  /// Cancel for active jobs, dismiss for finished ones.
  Widget _jobAction(TransferJob job) {
    if (job.isActive) {
      final cancel = _iconButton(
        key: ValueKey('transfer_cancel_${job.id}'),
        icon: Icons.close,
        tooltip: job.isCancelRequested ? 'Cancelling…' : 'Cancel transfer',
        color: _kRed,
        onPressed: job.isCancelRequested ? null : () => _manager.cancel(job),
      );
      final Widget? pauseToggle = job.isPaused
          ? _iconButton(
              key: ValueKey('transfer_resume_${job.id}'),
              icon: Icons.play_arrow,
              tooltip: 'Resume',
              color: _kCyan,
              onPressed: () => _manager.resume(job),
            )
          : _manager.canPause(job)
              ? _iconButton(
                  key: ValueKey('transfer_pause_${job.id}'),
                  icon: Icons.pause,
                  tooltip: 'Pause',
                  onPressed: () => _manager.pause(job),
                )
              : null;
      if (pauseToggle == null) return cancel;
      return Row(mainAxisSize: MainAxisSize.min, children: [pauseToggle, cancel]);
    }
    final dismiss = _iconButton(
      key: ValueKey('transfer_dismiss_${job.id}'),
      icon: Icons.close,
      tooltip: 'Dismiss',
      onPressed: () => _manager.dismiss(job),
    );
    final retryCount = _manager.retryableItems(job).length;
    if (retryCount == 0) return dismiss;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconButton(
          key: ValueKey('transfer_retry_${job.id}'),
          icon: Icons.refresh,
          tooltip: retryCount == job.totalItems
              ? 'Retry'
              : 'Retry the $retryCount unfinished item(s)',
          color: _kCyan,
          onPressed: () => _manager.retry(job),
        ),
        dismiss,
      ],
    );
  }

  // ---------- text helpers ----------

  String _activeLine(TransferJob job) {
    if (job.status == TransferStatus.queued) {
      return 'Queued: ${job.title} → ${job.destLabel}';
    }
    return '${job.title} → ${job.destLabel} · ${_activeDetail(job)}';
  }

  String _activeDetail(TransferJob job) {
    if (job.isCancelRequested) return 'Cancelling…';
    if (job.isPaused) {
      // Server-side cp/mv and the native engine cannot stop mid-file.
      return job.isHalted
          ? 'Paused · ${_pct(job.progress)}'
          : 'Pausing after the current file (${job.currentFile})…';
    }
    if (job.needsAttention) {
      return "Waiting for your decision: '${job.pendingConflict!.itemName}' already exists";
    }
    if (job.status == TransferStatus.queued) return 'Queued (waiting for a free slot or same host)';
    final parts = <String>[
      if (job.totalItems > 1)
        '${(job.completedItems + 1).clamp(1, job.totalItems)}/${job.totalItems}',
      job.currentFile,
      _pct(job.progress),
    ];
    final eta = job.eta;
    if (eta != null) parts.add('~${_fmtDuration(eta)} left');
    return parts.where((p) => p.isNotEmpty).join(' · ');
  }

  static String _pct(double p) => '${(p * 100).clamp(0, 100).toInt()}%';

  static String _fmtDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  // ---------- visual helpers ----------

  Color _colorFor(TransferJob job) {
    switch (job.status) {
      case TransferStatus.completed:
        return _kGreen;
      case TransferStatus.failed:
        return _kRed;
      case TransferStatus.cancelled:
        return _kMuted;
      case TransferStatus.queued:
      case TransferStatus.running:
        return _kText;
    }
  }

  Widget _statusIcon(TransferJob job) {
    if (job.needsAttention) {
      return const Icon(Icons.warning_amber_rounded, size: 13, color: _kAmber);
    }
    if (job.isPaused) {
      return const Icon(Icons.pause_circle, size: 13, color: _kMuted);
    }
    switch (job.status) {
      case TransferStatus.running:
        return _spinner();
      case TransferStatus.queued:
        return const Icon(Icons.schedule, size: 13, color: _kMuted);
      case TransferStatus.completed:
        return const Icon(Icons.check_circle, size: 13, color: _kGreen);
      case TransferStatus.cancelled:
        return const Icon(Icons.block, size: 13, color: _kMuted);
      case TransferStatus.failed:
        return const Icon(Icons.error, size: 13, color: _kRed);
    }
  }

  Widget _spinner() => const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: _kCyan),
      );

  Widget _progressBar(double? value, {bool paused = false}) => Semantics(
        label: paused ? 'Transfer progress (paused)' : 'Transfer progress',
        value: value == null ? 'waiting' : _pct(value),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: AppTheme.borderSubtle,
            color: paused ? _kMuted : _kCyan,
          ),
        ),
      );

  Widget _iconButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color color = _kText,
  }) {
    return IconButton(
      key: key,
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 14),
      color: color,
      disabledColor: _kMuted,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 22),
    );
  }

  Widget _textButton(String label, VoidCallback onPressed,
      {Key? key, Color color = _kText}) {
    return TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 22),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: _mono(10, color, bold: true)),
    );
  }

  static TextStyle _mono(double size, Color color, {bool bold = false}) =>
      TextStyle(
        fontFamily: 'monospace',
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      );
}
