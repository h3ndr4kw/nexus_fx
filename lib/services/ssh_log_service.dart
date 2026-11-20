import 'dart:async';
import 'dart:io';
import 'app_paths.dart';

/// Why a session log stopped recording.
class SshLogFailure {
  final Object error;

  /// Log file path, or null when the file could not even be opened.
  final String? path;
  final bool isDiskFull;

  SshLogFailure(this.error, this.path) : isDiskFull = looksLikeDiskFull(error);

  /// Windows: ERROR_DISK_FULL (112), ERROR_HANDLE_DISK_FULL (39).
  /// POSIX: ENOSPC (28).
  static bool looksLikeDiskFull(Object error) {
    if (error is! FileSystemException) return false;
    final code = error.osError?.errorCode;
    if (Platform.isWindows) {
      if (code == 112 || code == 39) return true;
    } else if (code == 28) {
      return true;
    }
    final msg = '${error.osError?.message ?? ''} ${error.message}'.toLowerCase();
    return msg.contains('no space left') ||
        msg.contains('disk full') ||
        msg.contains('not enough space');
  }

  String get message => isDiskFull
      ? 'Disk full - session logging stopped, the SSH session keeps running'
      : 'Session logging stopped: $error';
}

/// Appends terminal output of one SSH session to a log file.
///
/// Writes never touch the disk directly: they land in an in-memory buffer that
/// is written and flushed every [flushInterval]. At most one write/flush is in
/// flight at a time. When the disk cannot keep up the buffer stops growing at
/// [maxBufferedChars]; the overflow is dropped and a marker records how much.
/// The first I/O error (e.g. disk full) disables the logger for good and is
/// reported once through [onFailure]; the session itself is never affected.
class SshSessionLogger {
  static const Duration defaultFlushInterval = Duration(milliseconds: 200);
  static const int defaultMaxBufferedChars = 4 * 1024 * 1024;

  final File file;
  final IOSink sink;
  final String Function(String) sanitizer;
  final Duration flushInterval;
  final int maxBufferedChars;
  void Function(SshLogFailure failure)? onFailure;

  final StringBuffer _buffer = StringBuffer();
  int _droppedChars = 0;

  /// Trailing escape sequence cut off by a batch boundary, kept so the
  /// sanitizer sees it whole in the next batch.
  String _carry = '';
  Timer? _flushTimer;
  Future<void> _flushChain = Future<void>.value();
  bool _isClosed = false;
  SshLogFailure? _failure;

  SshSessionLogger({
    required this.file,
    required this.sink,
    required this.sanitizer,
    this.flushInterval = defaultFlushInterval,
    this.maxBufferedChars = defaultMaxBufferedChars,
    this.onFailure,
  }) {
    // Errors that happen outside a flush surface only on `done`; observing it
    // also keeps them from being reported as unhandled async errors.
    sink.done.then((_) {}, onError: (Object e) => _fail(e));
  }

  SshLogFailure? get failure => _failure;
  bool get isActive => !_isClosed && _failure == null;

  /// Characters dropped since the last marker because the disk was too slow.
  int get droppedChars => _droppedChars;

  void write(String data) {
    if (!isActive || data.isEmpty) return;
    _append(data);
  }

  void logCommand(String command) {
    if (!isActive) return;
    final clean = sanitizer(command).trim();
    if (clean.isEmpty) return;
    _append('\r\n[CMD] $clean\r\n');
  }

  void _append(String text) {
    if (_buffer.length + text.length > maxBufferedChars) {
      _droppedChars += text.length;
    } else {
      if (_droppedChars > 0) {
        _buffer.write('\r\n[LOG] $_droppedChars characters dropped: '
            'disk write too slow\r\n');
        _droppedChars = 0;
      }
      _buffer.write(text);
    }
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(flushInterval, () {
      _flushTimer = null;
      flush();
    });
  }

  /// Writes everything buffered so far and waits for it to reach the file.
  /// Never throws; failures are reported through [onFailure].
  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    return _flushChain = _flushChain.then((_) => _writeBatch());
  }

  Future<void> _writeBatch({bool finalBatch = false}) async {
    if (_failure != null) return;
    if (_buffer.isEmpty && (!finalBatch || _carry.isEmpty)) return;
    var raw = _carry + _buffer.toString();
    _buffer.clear();
    _carry = '';
    if (!finalBatch) {
      final cut = incompleteEscapeStart(raw);
      if (cut >= 0) {
        _carry = raw.substring(cut);
        raw = raw.substring(0, cut);
      }
    }
    final clean = sanitizer(raw);
    if (clean.isEmpty) return;
    try {
      sink.write(clean);
      await sink.flush();
    } catch (e) {
      _fail(e);
    }
  }

  /// Index of a trailing, unterminated CSI escape sequence in [text], or -1.
  static int incompleteEscapeStart(String text) {
    final idx = text.lastIndexOf('\x1B');
    if (idx < 0 || text.length - idx > 64) return -1;
    final tail = text.substring(idx);
    if (tail.length == 1) return idx;
    if (tail[1] != '[') return -1;
    return RegExp(r'^\x1B\[[0-?]*[ -/]*$').hasMatch(tail) ? idx : -1;
  }

  void _fail(Object error) {
    if (_failure != null) return;
    final failure = _failure = SshLogFailure(error, file.path);
    _flushTimer?.cancel();
    _flushTimer = null;
    _buffer.clear();
    _carry = '';
    // The sink is already broken; just release the file handle.
    try {
      sink.close().then((_) {}, onError: (_) {});
    } catch (_) {}
    onFailure?.call(failure);
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await (_flushChain =
        _flushChain.then((_) => _writeBatch(finalBatch: true)));
    if (_failure != null) return;
    try {
      await sink.close();
    } catch (e) {
      _fail(e);
    }
  }
}

class SshLogService {
  static SshLogService? _instance;
  final String? baseDir;

  SshLogService({this.baseDir});

  static SshLogService get instance {
    _instance ??= SshLogService();
    return _instance!;
  }

  String get _resolvedBaseDir {
    return baseDir ?? AppPaths.dataDir;
  }

  String formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-${d}_$h-$min-$s';
  }

  String stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  }

  File getLogFile({
    String? clusterName,
    String? feHostname,
    bool isOam = true,
    DateTime? timestamp,
    String? sessionName,
  }) {
    final time = timestamp ?? DateTime.now();
    final dateStr = formatDate(time);
    final dateTimeStr = formatDateTime(time);

    String fileName;
    if (sessionName != null && sessionName.trim().isNotEmpty) {
      final name = sessionName.trim();
      fileName = 'session_${name}_$dateTimeStr.log';
    } else if (clusterName != null &&
        clusterName.trim().isNotEmpty &&
        clusterName.trim() != 'UnknownCluster') {
      if (isOam) {
        fileName = 'OAM_${clusterName.trim()}_$dateTimeStr.log';
      } else {
        final name = (feHostname != null && feHostname.trim().isNotEmpty)
            ? feHostname.trim()
            : clusterName.trim();
        fileName = 'FE_${name}_$dateTimeStr.log';
      }
    } else if (feHostname != null &&
        feHostname.trim().isNotEmpty &&
        feHostname.trim() != 'UnknownHost') {
      fileName = 'FE_${feHostname.trim()}_$dateTimeStr.log';
    } else {
      fileName = 'session_terminal_$dateTimeStr.log';
    }

    // Sanitize file name for filesystem safety
    final safeFileName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '$_resolvedBaseDir${Platform.pathSeparator}logs${Platform.pathSeparator}nexus${Platform.pathSeparator}$dateStr${Platform.pathSeparator}$safeFileName';
    return File(path);
  }

  Future<SshSessionLogger> createSessionLogger({
    String? clusterName,
    String? feHostname,
    bool isOam = true,
    DateTime? timestamp,
    String? sessionName,
    void Function(SshLogFailure failure)? onFailure,
  }) async {
    final file = getLogFile(
      clusterName: clusterName,
      feHostname: feHostname,
      isOam: isOam,
      timestamp: timestamp,
      sessionName: sessionName,
    );

    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    if (!file.existsSync()) {
      file.createSync();
    }

    final sink = file.openWrite(mode: FileMode.append);
    return SshSessionLogger(
      file: file,
      sink: sink,
      sanitizer: stripAnsi,
      onFailure: onFailure,
    );
  }
}
