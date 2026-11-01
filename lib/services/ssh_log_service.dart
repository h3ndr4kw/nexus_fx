import 'dart:async';
import 'dart:io';

class SshSessionLogger {
  final File file;
  final IOSink sink;
  final String Function(String) sanitizer;
  bool _isClosed = false;
  Timer? _flushTimer;
  bool _isFlushing = false;
  bool _needsFlush = false;
  final List<String> _pendingWrites = [];

  SshSessionLogger({
    required this.file,
    required this.sink,
    required this.sanitizer,
  });

  void write(String data) {
    if (_isClosed) return;
    final clean = sanitizer(data);
    if (clean.isNotEmpty) {
      if (_isFlushing) {
        _pendingWrites.add(clean);
      } else {
        sink.write(clean);
        _scheduleFlush();
      }
    }
  }

  void logCommand(String command) {
    if (_isClosed) return;
    final clean = sanitizer(command).trim();
    if (clean.isNotEmpty) {
      final text = '\r\n[CMD] $clean\r\n';
      if (_isFlushing) {
        _pendingWrites.add(text);
      } else {
        sink.write(text);
        _scheduleFlush();
      }
    }
  }

  void _scheduleFlush() {
    if (_isClosed) return;
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(const Duration(milliseconds: 200), () {
      flush();
    });
  }

  Future<void> flush() async {
    if (_isClosed) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_isFlushing) {
      _needsFlush = true;
      return;
    }
    _isFlushing = true;
    try {
      await sink.flush();
    } catch (_) {
    } finally {
      _isFlushing = false;
      if (!_isClosed && _pendingWrites.isNotEmpty) {
        while (_pendingWrites.isNotEmpty) {
          sink.write(_pendingWrites.removeAt(0));
        }
        _needsFlush = true;
      }
      if (_needsFlush && !_isClosed) {
        _needsFlush = false;
        flush();
      }
    }
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    try {
      if (_pendingWrites.isNotEmpty) {
        while (_pendingWrites.isNotEmpty) {
          sink.write(_pendingWrites.removeAt(0));
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {}
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
    return baseDir ?? Directory.current.path;
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
    );
  }
}
