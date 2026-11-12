import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/file_explorer_models.dart';
import 'file_explorer_service.dart';

enum TransferStatus { queued, running, completed, cancelled, failed }

/// What to do when an item already exists at the destination.
enum ConflictChoice {
  /// Overwrite the file, or delete the existing folder and put the new one in
  /// its place.
  replace,

  /// Leave the destination untouched and move on to the next item.
  skip,

  /// Transfer under a free name next to the existing one, e.g. `a (1).txt`.
  keepBoth,
}

/// A destination name clash the job is waiting on the user to resolve. The
/// job pauses (non-modally) until [TransferManager.resolveConflict] is called.
class TransferConflict {
  TransferConflict._({
    required this.itemName,
    required this.destPath,
    required this.existingIsDir,
    required this.remainingItems,
  });

  final String itemName;
  final String destPath;
  final bool existingIsDir;

  /// Items left after this one, so the UI only offers "apply to all" when it
  /// can matter.
  final int remainingItems;

  final Completer<ConflictChoice> _answer = Completer<ConflictChoice>();
}

/// A single copy/move operation. It is owned by [TransferManager], not by the
/// explorer tab that started it, so it keeps running when that tab is hidden
/// or closed.
class TransferJob {
  TransferJob._({
    required this.id,
    required this.isMove,
    required List<FileExplorerItem> items,
    required this.srcTarget,
    required this.srcDirPath,
    required this.destTarget,
    required this.destDirPath,
    this.owner,
  }) : items = List.unmodifiable(items);

  final int id;
  final bool isMove;
  final List<FileExplorerItem> items;
  final ExplorerNodeTarget srcTarget;
  final String srcDirPath;
  final ExplorerNodeTarget destTarget;
  final String destDirPath;

  /// Opaque identity of whoever enqueued the job (the explorer view state),
  /// used to route the completion message back to it.
  final Object? owner;

  final TransferCancelToken cancelToken = TransferCancelToken();

  TransferStatus status = TransferStatus.queued;
  int completedItems = 0;
  String currentFile = '';
  double progress = 0.0;
  int? currentBytes;
  int? totalBytes;
  String? error;
  DateTime? startedAt;
  DateTime? finishedAt;

  /// Source paths that finished transferring (all of them on success; a
  /// prefix on cancel/failure).
  final List<String> transferredPaths = [];

  /// Source paths left alone: skipped on a name conflict, or because the
  /// destination is the item itself.
  final List<String> skippedPaths = [];

  /// Set while the job is paused on a name conflict.
  TransferConflict? pendingConflict;

  /// Choice the user applied to all remaining conflicts of this job.
  ConflictChoice? conflictPolicy;

  int get totalItems => items.length;
  bool get isActive =>
      status == TransferStatus.queued || status == TransferStatus.running;
  bool get isCancelRequested => cancelToken.isCancelled;
  bool get needsAttention => isActive && pendingConflict != null;

  /// Pause requested (the job may still be finishing a file that cannot be
  /// paused mid-way; see [isHalted]).
  bool get isPaused => isActive && cancelToken.isPaused;

  /// The job's I/O is actually stopped.
  bool get isHalted => cancelToken.isHalted;

  DateTime? _pausedAt;
  Duration _pausedTotal = Duration.zero;

  /// Time spent transferring, excluding pauses.
  Duration get activeElapsed {
    if (startedAt == null) return Duration.zero;
    final end = finishedAt ?? DateTime.now();
    final pausedNow = _pausedAt == null ? Duration.zero : end.difference(_pausedAt!);
    return end.difference(startedAt!) - _pausedTotal - pausedNow;
  }

  String get title {
    final verb = isMove ? 'Moving' : 'Copying';
    return items.length == 1
        ? '$verb ${items.first.name}'
        : '$verb ${items.length} items';
  }

  String get destLabel =>
      destTarget.isLocal ? destDirPath : '${destTarget.label}:$destDirPath';

  /// Rough remaining time from elapsed time and overall progress.
  Duration? get eta {
    if (status != TransferStatus.running ||
        needsAttention ||
        isPaused ||
        startedAt == null ||
        progress < 0.02) {
      return null;
    }
    return activeElapsed * ((1 - progress) / progress);
  }

  /// One-line outcome for a finished job.
  String get resultSummary {
    final past = isMove ? 'Moved' : 'Copied';
    final noun = isMove ? 'Move' : 'Copy';
    final skipped = skippedPaths.isEmpty ? '' : ', skipped ${skippedPaths.length}';
    switch (status) {
      case TransferStatus.completed:
        return '$past ${transferredPaths.length} item(s)$skipped to $destLabel';
      case TransferStatus.cancelled:
        return '$noun cancelled (${transferredPaths.length}/$totalItems items transferred)';
      case TransferStatus.failed:
        return '$noun failed: ${error ?? 'unknown error'}';
      case TransferStatus.queued:
        return 'Queued: $title';
      case TransferStatus.running:
        return title;
    }
  }
}

/// Reports progress from inside a [TransferRunner]. Calls are throttled to
/// ~10 per second per job unless [force] is set.
typedef TransferReporter = void Function({
  String? currentFile,
  int? completedItems,
  double? progress,
  int? currentBytes,
  int? totalBytes,
  bool force,
});

/// Performs the actual I/O of a job. Must honour `job.cancelToken`.
typedef TransferRunner = Future<void> Function(
  TransferJob job,
  TransferReporter report,
);

/// App-wide queue of copy/move jobs. Explorer tabs only enqueue; progress is
/// shown by the global transfer status bar, so no tab or page is blocked.
///
/// Jobs that touch the same remote host run one at a time (they share one
/// SSH/SFTP session); otherwise up to [maxConcurrent] jobs run in parallel
/// and the rest wait in FIFO order.
class TransferManager extends ChangeNotifier {
  TransferManager({
    FileExplorerService? service,
    TransferRunner? runner,
    this.finishedLinger = const Duration(seconds: 5),
    this.maxConcurrent = 3,
  })  : assert(maxConcurrent > 0),
        _explicitService = service {
    _runner = runner ?? _defaultRunner;
  }

  /// Upper bound on jobs doing I/O at the same time. More parallel copies to
  /// one disk or link only slow each other down.
  final int maxConcurrent;
  int _runningCount = 0;
  final List<Completer<void>> _slotWaiters = [];

  static TransferManager? _instance;
  static TransferManager get instance => _instance ??= TransferManager();
  static set instance(TransferManager manager) => _instance = manager;

  final FileExplorerService? _explicitService;
  FileExplorerService get service =>
      _explicitService ?? FileExplorerService.instance;
  late final TransferRunner _runner;

  /// How long completed/cancelled jobs stay visible. Failed jobs stay until
  /// dismissed. `null` keeps every finished job until dismissed.
  final Duration? finishedLinger;

  final List<TransferJob> _jobs = [];
  final Map<String, Future<void>> _laneTails = {};
  final Map<int, Timer> _lingerTimers = {};
  final StreamController<TransferJob> _finished =
      StreamController<TransferJob>.broadcast();
  int _nextId = 1;
  bool _disposed = false;

  List<TransferJob> get jobs => List.unmodifiable(_jobs);
  List<TransferJob> get activeJobs => _jobs.where((j) => j.isActive).toList();
  bool get hasActiveJobs => _jobs.any((j) => j.isActive);

  /// Emits each job once, when it reaches a terminal status.
  Stream<TransferJob> get finished => _finished.stream;

  /// Mean progress of active jobs (0..1), or null when nothing is active.
  double? get aggregateProgress {
    final active = activeJobs;
    if (active.isEmpty) return null;
    return active.fold<double>(0, (sum, j) => sum + j.progress) / active.length;
  }

  /// Queues a job and returns immediately.
  TransferJob enqueue({
    required List<FileExplorerItem> items,
    required ExplorerNodeTarget srcTarget,
    required String srcDirPath,
    required ExplorerNodeTarget destTarget,
    required String destDirPath,
    required bool isMove,
    Object? owner,
  }) {
    final job = TransferJob._(
      id: _nextId++,
      isMove: isMove,
      items: items,
      srcTarget: srcTarget,
      srcDirPath: srcDirPath,
      destTarget: destTarget,
      destDirPath: destDirPath,
      owner: owner,
    );
    job.currentFile = items.isNotEmpty ? items.first.name : '';
    job.cancelToken.onPauseStateChanged = _notify;
    _jobs.add(job);

    // Claim the lanes synchronously so FIFO order holds per remote host.
    final lanes = _lanesFor(job);
    final waits = [
      for (final lane in lanes)
        if (_laneTails[lane] != null) _laneTails[lane]!,
    ];
    final ownDone = Completer<void>();
    // A lane frees only once both this job and everything ahead of it are
    // done, so a job cancelled while queued never lets a later one overtake.
    final tail = Future.wait([...waits, ownDone.future]).then((_) {});
    for (final lane in lanes) {
      _laneTails[lane] = tail;
    }
    unawaited(tail.then((_) {
      for (final lane in lanes) {
        if (identical(_laneTails[lane], tail)) _laneTails.remove(lane);
      }
    }));

    unawaited(_start(job, waits, ownDone));
    _notify();
    return job;
  }

  /// Requests cancellation. A queued job finishes as cancelled right away; a
  /// running one stops at its next cancellation point.
  void cancel(TransferJob job) {
    if (!job.isActive) return;
    job.cancelToken.cancel();
    _notify();
  }

  bool canPause(TransferJob job) =>
      job.status == TransferStatus.running &&
      !job.isCancelRequested &&
      !job.isPaused &&
      !job.needsAttention;

  /// Pauses a running job. Byte-streamed transfers stop within a chunk;
  /// server-side copies/moves and the native engine stop after the current
  /// file. A paused job keeps its place (slot / host lane) in the queue.
  void pause(TransferJob job) {
    if (!canPause(job)) return;
    job._pausedAt = DateTime.now();
    job.cancelToken.pause();
  }

  void resume(TransferJob job) {
    if (!job.isPaused) return;
    final pausedAt = job._pausedAt;
    if (pausedAt != null) {
      job._pausedTotal += DateTime.now().difference(pausedAt);
      job._pausedAt = null;
    }
    job.cancelToken.resume();
  }

  void pauseAll() {
    for (final job in activeJobs) {
      pause(job);
    }
  }

  void resumeAll() {
    for (final job in activeJobs) {
      resume(job);
    }
  }

  void cancelAll() {
    for (final job in activeJobs) {
      job.cancelToken.cancel();
    }
    _notify();
  }

  /// Removes a finished job from the list.
  void dismiss(TransferJob job) {
    if (job.isActive) return;
    _lingerTimers.remove(job.id)?.cancel();
    if (_jobs.remove(job)) _notify();
  }

  /// Items of a finished job that neither transferred nor were skipped on
  /// purpose: what [retry] would run again.
  List<FileExplorerItem> retryableItems(TransferJob job) {
    if (job.status != TransferStatus.failed &&
        job.status != TransferStatus.cancelled) {
      return const [];
    }
    final done = {...job.transferredPaths, ...job.skippedPaths};
    return job.items.where((i) => !done.contains(i.path)).toList();
  }

  bool canRetry(TransferJob job) => retryableItems(job).isNotEmpty;

  /// Replaces a failed/cancelled job with a new one for its unfinished items
  /// (an item that broke mid-way runs again in full). Returns the new job, or
  /// null if there is nothing to retry.
  TransferJob? retry(TransferJob job) {
    final remaining = retryableItems(job);
    if (remaining.isEmpty) return null;
    dismiss(job);
    return enqueue(
      items: remaining,
      srcTarget: job.srcTarget,
      srcDirPath: job.srcDirPath,
      destTarget: job.destTarget,
      destDirPath: job.destDirPath,
      isMove: job.isMove,
      owner: job.owner,
    );
  }

  void clearFinished() {
    final finished = _jobs.where((j) => !j.isActive).toList();
    for (final job in finished) {
      _lingerTimers.remove(job.id)?.cancel();
    }
    _jobs.removeWhere((j) => !j.isActive);
    if (finished.isNotEmpty) _notify();
  }

  /// Answers the conflict [job] is paused on. With [applyToAll] the same
  /// choice is used, without asking, for the job's remaining conflicts.
  void resolveConflict(
    TransferJob job,
    ConflictChoice choice, {
    bool applyToAll = false,
  }) {
    final conflict = job.pendingConflict;
    if (conflict == null || conflict._answer.isCompleted) return;
    if (applyToAll) job.conflictPolicy = choice;
    job.pendingConflict = null;
    conflict._answer.complete(choice);
    _notify();
  }

  /// Pauses [job] until the user resolves the clash (or cancels the job).
  Future<ConflictChoice> _askConflict(
    TransferJob job, {
    required String itemName,
    required String destPath,
    required bool existingIsDir,
    required int remainingItems,
  }) async {
    final policy = job.conflictPolicy;
    if (policy != null) return policy;
    final conflict = TransferConflict._(
      itemName: itemName,
      destPath: destPath,
      existingIsDir: existingIsDir,
      remainingItems: remainingItems,
    );
    job.pendingConflict = conflict;
    _notify();
    final unregister = job.cancelToken.onCancel(() {
      if (!conflict._answer.isCompleted) {
        conflict._answer.complete(ConflictChoice.skip);
      }
    });
    try {
      final choice = await conflict._answer.future;
      job.cancelToken.throwIfCancelled();
      return choice;
    } finally {
      unregister();
      if (identical(job.pendingConflict, conflict)) job.pendingConflict = null;
    }
  }

  /// Completes when [future] does, or as soon as [job] is cancelled.
  static Future<void> _untilDoneOrCancelled(TransferJob job, Future<void> future) async {
    final cancelled = Completer<void>();
    final unregister = job.cancelToken.onCancel(() {
      if (!cancelled.isCompleted) cancelled.complete();
    });
    try {
      await Future.any([future, cancelled.future]);
    } finally {
      unregister();
    }
  }

  /// Takes one of the [maxConcurrent] slots, waiting FIFO if all are busy.
  /// Returns false if the job was cancelled while waiting.
  Future<bool> _acquireSlot(TransferJob job) async {
    if (_runningCount < maxConcurrent && _slotWaiters.isEmpty) {
      _runningCount++;
      return true;
    }
    final waiter = Completer<void>();
    _slotWaiters.add(waiter);
    await _untilDoneOrCancelled(job, waiter.future);
    if (waiter.isCompleted) return true; // slot was handed to us
    _slotWaiters.remove(waiter);
    return false;
  }

  void _releaseSlot() {
    if (_slotWaiters.isNotEmpty) {
      // Hand the slot straight to the next waiter; the count is unchanged.
      _slotWaiters.removeAt(0).complete();
    } else {
      _runningCount--;
    }
  }

  Future<void> _start(
    TransferJob job,
    List<Future<void>> waits,
    Completer<void> ownDone,
  ) async {
    var holdsSlot = false;
    try {
      if (waits.isNotEmpty) {
        await _untilDoneOrCancelled(job, Future.wait(waits));
      }
      job.cancelToken.throwIfCancelled();
      holdsSlot = await _acquireSlot(job);
      job.cancelToken.throwIfCancelled();

      job.status = TransferStatus.running;
      job.startedAt = DateTime.now();
      _notify();

      await _runner(job, _reporterFor(job));
      job.status = TransferStatus.completed;
      job.progress = 1.0;
      job.completedItems = job.totalItems;
    } on TransferCancelledException {
      job.status = TransferStatus.cancelled;
    } catch (e) {
      if (job.cancelToken.isCancelled) {
        // Errors raised by aborting the channel are just the cancellation.
        job.status = TransferStatus.cancelled;
      } else {
        job.status = TransferStatus.failed;
        job.error = describeTransferError(e);
      }
    } finally {
      if (holdsSlot) _releaseSlot();
      job.pendingConflict = null;
      job.finishedAt = DateTime.now();
      if (job._pausedAt != null) {
        job._pausedTotal += job.finishedAt!.difference(job._pausedAt!);
        job._pausedAt = null;
      }
      job.cancelToken.onPauseStateChanged = null;
      job.cancelToken.resume();
      ownDone.complete();
      if (!_disposed) {
        _scheduleLinger(job);
        _notify();
        _finished.add(job);
      }
    }
  }

  TransferReporter _reporterFor(TransferJob job) {
    var last = DateTime.fromMillisecondsSinceEpoch(0);
    return ({
      String? currentFile,
      int? completedItems,
      double? progress,
      int? currentBytes,
      int? totalBytes,
      bool force = false,
    }) {
      if (job.isCancelRequested) return;
      if (currentFile != null) job.currentFile = currentFile;
      if (completedItems != null) job.completedItems = completedItems;
      if (progress != null) job.progress = progress.clamp(0.0, 1.0);
      job.currentBytes = currentBytes;
      job.totalBytes = totalBytes;
      final now = DateTime.now();
      if (!force && now.difference(last) < const Duration(milliseconds: 100)) {
        return;
      }
      last = now;
      _notify();
    };
  }

  void _scheduleLinger(TransferJob job) {
    final linger = finishedLinger;
    if (linger == null || job.status == TransferStatus.failed) return;
    _lingerTimers[job.id] = Timer(linger, () {
      _lingerTimers.remove(job.id);
      if (_jobs.remove(job)) _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Remote hosts the job talks to. Local-only jobs need no lane.
  static List<String> _lanesFor(TransferJob job) {
    final lanes = <String>{
      if (!job.srcTarget.isLocal) _laneKey(job.srcTarget),
      if (!job.destTarget.isLocal) _laneKey(job.destTarget),
    }.toList()
      ..sort();
    return lanes;
  }

  static String _laneKey(ExplorerNodeTarget t) =>
      '${t.type}|${t.host}|${t.port}|${t.username}|${t.feHostname}|${t.sessionId}';

  /// Human-readable transfer error for status lines.
  static String describeTransferError(Object e) {
    if (e is TimeoutException) return e.message ?? 'Transfer timed out';
    if (e is UnsupportedError) return e.message ?? e.toString();
    final text = e.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  // ==========================================
  // Default runner: real local / SFTP / SSH I/O
  // ==========================================

  static bool _caseInsensitive(ExplorerNodeTarget t) =>
      t.isLocal && Platform.isWindows;

  static String _nameKey(ExplorerNodeTarget t, String name) =>
      _caseInsensitive(t) ? name.toLowerCase() : name;

  /// First free variant of [name] in the style `report (1).pdf`, checking
  /// [taken] through [keyOf] (case folding etc.). Folders keep dots intact.
  @visibleForTesting
  static String uniqueName(
    String name,
    bool isDir,
    Set<String> taken, {
    String Function(String name)? keyOf,
  }) {
    final key = keyOf ?? (String n) => n;
    final dot = isDir ? -1 : name.lastIndexOf('.');
    final hasExt = dot > 0 && dot < name.length - 1;
    final stem = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';
    for (var n = 1;; n++) {
      final candidate = '$stem ($n)$ext';
      if (!taken.contains(key(candidate))) return candidate;
    }
  }

  /// Destination path the service will write, built the same way it does.
  static String _destPathFor(ExplorerNodeTarget dest, String destDir, String name) {
    if (dest.isLocal) return '$destDir${Platform.pathSeparator}$name';
    final clean = destDir.endsWith('/') && destDir.length > 1
        ? destDir.substring(0, destDir.length - 1)
        : destDir;
    return clean == '/' ? '/$name' : '$clean/$name';
  }

  static bool _samePath(ExplorerNodeTarget t, String a, String b) {
    String norm(String p) {
      var s = p.replaceAll('\\', '/');
      while (s.length > 1 && s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
      }
      return _caseInsensitive(t) ? s.toLowerCase() : s;
    }
    return norm(a) == norm(b);
  }

  /// Entries already in the destination folder. On failure returns an empty
  /// map, i.e. no conflict detection (the old, overwrite behaviour).
  Future<Map<String, bool>> _listDestEntries(
    ExplorerNodeTarget dest,
    String destDir,
    Future<RemoteSession> Function() destRemote,
  ) async {
    final entries = <String, bool>{};
    try {
      if (dest.isLocal) {
        await for (final e in Directory(destDir).list(followLinks: false)) {
          final name = e.path.split(Platform.pathSeparator).last;
          if (name.isNotEmpty) entries[_nameKey(dest, name)] = e is Directory;
        }
      } else {
        for (final item in await service.listRemote(await destRemote(), destDir)) {
          if (item.isParentDir) continue;
          entries[_nameKey(dest, item.name)] = item.isDir;
        }
      }
    } catch (e) {
      debugPrint('Transfer: could not list $destDir for conflict check: $e');
    }
    return entries;
  }

  Future<void> _defaultRunner(TransferJob job, TransferReporter report) async {
    final svc = service;
    final src = job.srcTarget;
    final dest = job.destTarget;
    final destDir = job.destDirPath;
    final token = job.cancelToken;
    final total = job.items.length;
    final isSameTarget = src.isSameTarget(dest);

    RemoteSession? srcSession;
    RemoteSession? destSession;
    Future<RemoteSession> srcRemote() async =>
        srcSession ??= await svc.getOrConnectRemote(src);
    Future<RemoteSession> destRemote() async =>
        destSession ??= await svc.getOrConnectRemote(dest);

    // Destination entries (name key -> isDir), listed once when first needed.
    Map<String, bool>? existing;

    for (var i = 0; i < total; i++) {
      token.throwIfCancelled();
      // Also where non-streamed operations honour a pause.
      if (token.isPaused) await token.waitIfPaused();
      final item = job.items[i];

      void onBytes(int sent, int size, {double offset = 0.0, double scale = 1.0}) {
        final fileRatio = size > 0 ? (sent / size).clamp(0.0, 1.0) : 0.0;
        report(
          currentFile: item.name,
          completedItems: i,
          progress: (i + offset + fileRatio * scale) / total,
          currentBytes: sent,
          totalBytes: size,
          force: sent >= size,
        );
      }

      report(
        currentFile: item.name,
        completedItems: i,
        progress: i / total,
        force: true,
      );

      void skip() {
        job.skippedPaths.add(item.path);
        report(completedItems: i + 1, progress: (i + 1) / total, force: true);
      }

      final destPath = _destPathFor(dest, destDir, item.name);
      // Copying an item onto itself would truncate it; moving it is a no-op.
      if (isSameTarget && _samePath(dest, destPath, item.path)) {
        skip();
        continue;
      }

      existing ??= await _listDestEntries(dest, destDir, destRemote);
      final existingIsDir = existing[_nameKey(dest, item.name)];
      String? destName; // null keeps the source name
      if (existingIsDir != null) {
        final choice = await _askConflict(
          job,
          itemName: item.name,
          destPath: destPath,
          existingIsDir: existingIsDir,
          remainingItems: total - i - 1,
        );
        if (choice == ConflictChoice.skip) {
          skip();
          continue;
        }
        if (choice == ConflictChoice.keepBoth) {
          destName = uniqueName(item.name, item.isDir, {
            ...existing.keys,
            // Names still to come in this job must stay free too.
            for (final later in job.items.skip(i + 1)) _nameKey(dest, later.name),
          }, keyOf: (n) => _nameKey(dest, n));
        } else {
          // Replace: clear the old entry first. Copying a folder onto an
          // existing one would otherwise nest it (`cp -r`) or merge it.
          token.throwIfCancelled();
          if (dest.isLocal) {
            await svc.deleteLocal(destPath);
          } else {
            await svc.deleteRemote(await destRemote(), destPath, existingIsDir);
          }
        }
      }

      if (src.isLocal && dest.isLocal) {
        if (job.isMove) {
          await svc.moveLocal(item.path, destDir,
              onProgress: onBytes, cancelToken: token, destName: destName);
        } else {
          await svc.copyLocal(item.path, destDir,
              onProgress: onBytes, cancelToken: token, destName: destName);
        }
      } else if (isSameTarget && !src.isLocal) {
        final session = await srcRemote();
        if (job.isMove) {
          await svc.moveRemote(session, item.path, destDir,
              onProgress: onBytes, cancelToken: token, destName: destName);
        } else {
          await svc.copyRemote(session, item.path, destDir,
              onProgress: onBytes, cancelToken: token, destName: destName);
        }
      } else if (src.isLocal && !dest.isLocal) {
        await svc.uploadLocalToRemote(item.path, await destRemote(), destDir,
            onProgress: onBytes, cancelToken: token, destName: destName);
        if (job.isMove) {
          token.throwIfCancelled();
          await svc.deleteLocal(item.path);
        }
      } else if (!src.isLocal && dest.isLocal) {
        final session = await srcRemote();
        await svc.downloadRemoteToLocal(session, item.path, item.isDir, destDir,
            onProgress: onBytes, cancelToken: token, destName: destName);
        if (job.isMove) {
          token.throwIfCancelled();
          await svc.deleteRemote(session, item.path, item.isDir);
        }
      } else {
        // Remote to a different remote: stage through a local temp dir.
        final tempDir = await Directory.systemTemp.createTemp('he_transfer_');
        try {
          final from = await srcRemote();
          await svc.downloadRemoteToLocal(from, item.path, item.isDir, tempDir.path,
              onProgress: (s, t) => onBytes(s, t, offset: 0.0, scale: 0.5),
              cancelToken: token);
          final staged = '${tempDir.path}${Platform.pathSeparator}${item.name}';
          await svc.uploadLocalToRemote(staged, await destRemote(), destDir,
              onProgress: (s, t) => onBytes(s, t, offset: 0.5, scale: 0.5),
              cancelToken: token,
              destName: destName);
          if (job.isMove) {
            token.throwIfCancelled();
            await svc.deleteRemote(from, item.path, item.isDir);
          }
        } finally {
          await tempDir.delete(recursive: true);
        }
      }

      job.transferredPaths.add(item.path);
      existing[_nameKey(dest, destName ?? item.name)] = item.isDir;
      report(completedItems: i + 1, progress: (i + 1) / total, force: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _lingerTimers.values) {
      timer.cancel();
    }
    _lingerTimers.clear();
    _finished.close();
    super.dispose();
  }
}
