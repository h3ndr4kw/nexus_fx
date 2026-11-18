import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import '../models/network_manager_config.dart';
import '../models/ssh_tunnel_models.dart';
import '../models/session_models.dart';
import 'session_manager_service.dart';
import 'ssh_log_service.dart';
import 'ssh_tunnel_manager.dart';
import 'settings_service.dart';
import 'known_hosts_service.dart';
import 'ssh_key_loader.dart';
import 'ssh_algorithm_helper.dart';

export 'ssh_algorithm_helper.dart';

part 'ssh_connection_output.dart';
part 'ssh_connection_multiplexed.dart';
part 'ssh_connection_hops.dart';
part 'ssh_connection_direct.dart';

class MasterConnectionException implements Exception {
  final Object cause;
  MasterConnectionException(this.cause);

  @override
  String toString() => 'MasterConnectionException: $cause';
}

class SshConnection {
  final String id;
  final String host;
  final int port;
  final String label;
  final String? fallbackHost;
  final String? fallbackLabel;
  final String? targetUsername;
  final String? targetPassword;

  /// Key the target logs in with, when its session uses one.
  final SshPrivateKeyRef? targetPrivateKey;
  final String? jumpClusterHost;
  final int jumpClusterPort;
  final String? jumpClusterFallback;
  final String? jumpClusterUsername;
  final String? jumpClusterPassword;

  /// Key the jump host logs in with, when its session uses one.
  final SshPrivateKeyRef? jumpClusterPrivateKey;
  final String? feHostname;
  final String? clusterName;
  final bool isOam;
  final SshLogService? logService;
  final DateTime? logTimestamp;
  final bool enableLogging;
  final String sshMacs;
  final String customSshOptions;
  bool isLocalShell;
  Process? _localProcess;

  TunnelMode _tunnelMode = TunnelMode.multiplexed;
  TunnelMode get tunnelMode => _tunnelMode;

  String? _leaseId;
  String? get leaseId => _leaseId;

  SshSessionLogger? _sessionLogger;
  File? _logFile;

  /// Set when session logging stopped because of an I/O error (e.g. disk
  /// full). The SSH session itself keeps running.
  final ValueNotifier<SshLogFailure?> logFailure = ValueNotifier(null);
  File? get logFile => _logFile ?? _sessionLogger?.file;

  String _currentHost;
  String _currentLabel;

  String get currentHost => _currentHost;
  String get currentLabel => _currentLabel;

  SSHClient? _client;

  /// Jump host client when the target is reached through a direct-tcpip
  /// forward (jump route without a Network Manager).
  SSHClient? _jumpClient;
  SSHSession? _session;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _wasConnected = false;
  bool _isUserExiting = false;
  bool _hasNotifiedClose = false;
  String _inputLineBuffer = '';
  Timer? _exitTimer;
  Timer? _resizeDebounceTimer;
  int? _lastSentPtyWidth;
  int? _lastSentPtyHeight;

  void Function()? onClosed;

  @visibleForTesting
  void Function(String data)? onDataWritten;

  @visibleForTesting
  void Function(int width, int height)? onPtyResizeForTesting;

  @visibleForTesting
  Future<SSHClient> Function(
    SSHSocket socket, {
    required String username,
    required String password,
  })? customTargetClientFactory;

  @visibleForTesting
  Future<bool> Function({
    required String targetUsername,
    required String targetPassword,
    required NetworkManagerConfig nmConfig,
  })? customJumpHostConnector;

  @visibleForTesting
  void setConnectedForTesting(bool connected) {
    _isConnected = connected;
    _setConnectionState(connected);
  }

  @visibleForTesting
  void simulateHopOutputForTesting(String text) {
    _handleHopOutput(text);
  }

  @visibleForTesting
  void simulateOutputForTesting(String text) {
    _addOutput(text);
    flushTerminalOutput();
  }

  /// Like [simulateOutputForTesting] but leaves the output queued, as real
  /// remote output is.
  @visibleForTesting
  void enqueueOutputForTesting(String text) => _addOutput(text);

  @visibleForTesting
  bool get isOutputPausedForTesting => _outputPaused;

  @visibleForTesting
  int get pendingTerminalCharsForTesting => _pendingChars;

  /// Registers [source] so it is paused while the terminal is behind.
  @visibleForTesting
  Stream<T> trackOutputForTesting<T>(Stream<T> source) => _tracked(source);

  bool isShellPrompt(String buffer) => _isShellPrompt(buffer);

  @visibleForTesting
  String filterHopBannerForTesting(String text) => _filterHopBanner(text);

  @visibleForTesting
  bool get suppressOutputForTesting => _suppressOutput;

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<String> _labelController =
      StreamController<String>.broadcast();

  String _hopBuffer = '';
  final List<void Function()> _hopListeners = [];
  bool _suppressOutput = false;
  final StringBuffer _suppressedBuffer = StringBuffer();

  // Terminal output pipeline
  // Remote output is queued and fed to xterm in time-boxed slices so a burst
  // (e.g. `cat` of a big file) cannot monopolise the UI isolate. When the
  // queue grows past [outputHighWaterChars] the SSH/process output streams are
  // paused; dartssh2 then stops granting window, so the server stops sending
  // until the terminal has caught up below [outputLowWaterChars].
  static const int outputHighWaterChars = 1024 * 1024;
  static const int outputLowWaterChars = 256 * 1024;
  static const int _terminalSliceChars = 16 * 1024;
  static const Duration _terminalSliceBudget = Duration(milliseconds: 8);

  final ListQueue<String> _pendingChunks = ListQueue<String>();
  int _pendingHeadOffset = 0;
  int _pendingChars = 0;
  Timer? _terminalDrainTimer;
  final Stopwatch _syncWriteClock = Stopwatch()..start();
  int _syncWindowStartUs = -1000000;
  int _syncWindowChars = 0;
  final List<StreamSubscription<dynamic>> _outputSubscriptions = [];
  bool _outputPaused = false;

  late final Terminal terminal = Terminal(
    maxLines: 10000,
    reflowEnabled: false,
  );
  late final TerminalController terminalController = TerminalController();

  SshConnection({
    required this.id,
    required this.host,
    this.port = 22,
    required this.label,
    this.fallbackHost,
    this.fallbackLabel,
    this.targetUsername,
    this.targetPassword,
    this.targetPrivateKey,
    this.jumpClusterHost,
    this.jumpClusterPort = 22,
    this.jumpClusterFallback,
    this.jumpClusterUsername,
    this.jumpClusterPassword,
    this.jumpClusterPrivateKey,
    this.feHostname,
    this.clusterName,
    bool? isOam,
    this.isLocalShell = false,
    this.enableLogging = true,
    this.sshMacs = 'auto',
    this.customSshOptions = '',
    this.logService,
    this.logTimestamp,
    TunnelMode? tunnelMode,
  })  : _currentHost = host,
        _currentLabel = label,
        _tunnelMode = tunnelMode ?? TunnelMode.multiplexed,
        isOam = isOam ??
            _resolveIsOam(host, jumpClusterHost, feHostname) {
    terminal.onOutput = (data) {
      write(data);
    };
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      resize(width, height);
    };
  }

  factory SshConnection.fromSessionProfile(
    SessionProfile profile, {
    required ResolvedSshRoute route,
    SshLogService? logService,
  }) {
    final isLocal = profile.protocol == SessionProtocol.local;
    final id = '${profile.name}_${DateTime.now().millisecondsSinceEpoch}';
    final shouldLog = profile.enableSessionLogging && SettingsService.instance.nexusAutoSessionLogging;
    final conn = SshConnection(
      id: id,
      host: isLocal ? 'localhost' : profile.host,
      port: isLocal ? 0 : profile.port,
      label: profile.name,
      fallbackHost: profile.fallbackHost,
      targetUsername: profile.username,
      targetPassword: profile.password,
      targetPrivateKey: SshPrivateKeyRef.of(
        usesKey: profile.authMethod == AuthMethod.privateKey,
        path: profile.privateKeyPath,
        passphrase: profile.privateKeyPassphrase,
      ),
      jumpClusterHost: route.jumpHost,
      jumpClusterPort: route.jumpPort,
      jumpClusterFallback: route.jumpFallbackHost,
      jumpClusterUsername: route.jumpUsername,
      jumpClusterPassword: route.jumpPassword,
      jumpClusterPrivateKey: route.jumpPrivateKey,
      isLocalShell: isLocal,
      logService: logService,
      enableLogging: shouldLog,
      logTimestamp: shouldLog ? DateTime.now() : null,
      sshMacs: profile.sshMacs,
      customSshOptions: profile.customSshOptions,
      tunnelMode: profile.tunnelMode,
    );
    return conn;
  }

  /// A fresh, unconnected connection to the same target, shown as [newLabel].
  SshConnection duplicate({required String newLabel, String? newFallbackLabel}) {
    return SshConnection(
      id: '${newLabel}_${DateTime.now().microsecondsSinceEpoch}',
      host: host,
      port: port,
      label: newLabel,
      fallbackHost: fallbackHost,
      fallbackLabel: newFallbackLabel,
      targetUsername: targetUsername,
      targetPassword: targetPassword,
      targetPrivateKey: targetPrivateKey,
      jumpClusterHost: jumpClusterHost,
      jumpClusterPort: jumpClusterPort,
      jumpClusterFallback: jumpClusterFallback,
      jumpClusterUsername: jumpClusterUsername,
      jumpClusterPassword: jumpClusterPassword,
      jumpClusterPrivateKey: jumpClusterPrivateKey,
      feHostname: feHostname,
      clusterName: clusterName,
      isOam: isOam,
      isLocalShell: isLocalShell,
      enableLogging: enableLogging,
      logService: logService,
      logTimestamp: enableLogging ? DateTime.now() : null,
      sshMacs: sshMacs,
      customSshOptions: customSshOptions,
      tunnelMode: _tunnelMode,
    );
  }

  static bool _resolveIsOam(
    String targetHost,
    String? jcHost,
    String? feHost,
  ) {
    if ((jcHost != null && jcHost.isNotEmpty) ||
        (feHost != null && feHost.isNotEmpty)) {
      return false;
    }
    return true;
  }

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  Stream<String> get outputStream => _outputController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<String> get labelStream => _labelController.stream;

  Future<void> initLogger() async {
    if (_sessionLogger != null) return;
    if (!enableLogging) return;
    if (logService == null &&
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      final svc = logService ?? SshLogService.instance;
      final resolvedCluster = (clusterName != null && clusterName!.trim().isNotEmpty)
          ? clusterName!.trim()
          : _detectClusterName();

      final String? sessionName = (label.trim().isNotEmpty && label != 'Terminal')
          ? label.trim()
          : (currentLabel.trim().isNotEmpty ? currentLabel.trim() : null);

      if (isOam &&
          (resolvedCluster == null ||
              resolvedCluster.isEmpty ||
              resolvedCluster == 'UnknownCluster') &&
          sessionName == null) {
        return;
      }
      _sessionLogger = await svc.createSessionLogger(
        clusterName: resolvedCluster,
        feHostname: feHostname ?? (isOam ? null : _currentHost),
        isOam: isOam,
        timestamp: logTimestamp ?? DateTime.now(),
        sessionName: sessionName,
        onFailure: _onLogFailure,
      );
      _logFile = _sessionLogger?.file;
    } catch (e) {
      debugPrint('Failed to initialize SSH logger: $e');
      _onLogFailure(SshLogFailure(e, null));
    }
  }

  String? _detectClusterName() => clusterName;

  void recordLogOutput(String data) {
    _sessionLogger?.write(data);
  }

  void recordLogCommand(String command) {
    _sessionLogger?.logCommand(command);
  }

  Future<void> flushLogger() async {
    await _sessionLogger?.flush();
  }

  Future<void> closeLogger() async {
    final logger = _sessionLogger;
    _sessionLogger = null;
    await logger?.close();
  }

  /// Shows [text] in the terminal only (not logged, not on [outputStream]),
  /// in order with remote output that is still queued.
  void writeLocal(String text) => _enqueueTerminal(text);

  /// Synchronously writes all queued output to the terminal.
  void flushTerminalOutput() {
    _terminalDrainTimer?.cancel();
    _terminalDrainTimer = null;
    _drainTerminal(_pendingChars);
  }

  Future<bool> connect({
    String targetUsername = '',
    String targetPassword = '',
    NetworkManagerConfig? nmConfig,
  }) async {
    if (_isConnected) return true;
    if (_isConnecting) return false;
    _isConnecting = true;

    try {
      _isConnected = false;
      _setConnectionState(false);
      _hasNotifiedClose = false;
      _isUserExiting = false;
      _inputLineBuffer = '';
      await initLogger();

      final effectiveUsername = targetUsername.trim().isNotEmpty
          ? targetUsername.trim()
          : (this.targetUsername?.trim().isNotEmpty == true
              ? this.targetUsername!.trim()
              : 'root');
      final effectivePassword = targetPassword.isNotEmpty
          ? targetPassword
          : (this.targetPassword ?? '');

      if (isLocalShell) {
        String executable;
        final List<String> args;
        if (Platform.isWindows) {
          const pwsh7Path = r'C:\Program Files\PowerShell\7\pwsh.exe';
          if (File(pwsh7Path).existsSync()) {
            executable = pwsh7Path;
          } else {
            executable = 'powershell.exe';
          }
          args = [
            '-NoLogo',
            '-NoExit',
            '-Command',
            r'function Clear-Host { [Console]::Write("$([char]27)[2J$([char]27)[H") }',
          ];
        } else {
          executable = Platform.environment['SHELL'] ?? '/bin/bash';
          args = ['-l'];
        }
        try {
          try {
            _localProcess = await Process.start(executable, args);
          } catch (_) {
            if (Platform.isWindows && executable != 'powershell.exe') {
              executable = 'powershell.exe';
              _localProcess = await Process.start(executable, args);
            } else {
              rethrow;
            }
          }
          _isConnected = true;
          _setConnectionState(true);
          _addOutput('\r\n--- Local Shell Ready ($executable) ---\r\n\r\n');
          _tracked(_localProcess!.stdout).listen((bytes) {
            final s = utf8.decode(bytes, allowMalformed: true);
            var normalized = s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
            if (Platform.isWindows) {
              normalized = normalized.replaceAll('\b', '\b \b');
            }
            _addOutput(normalized);
          });
          _tracked(_localProcess!.stderr).listen((bytes) {
            final s = utf8.decode(bytes, allowMalformed: true);
            var normalized = s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
            if (Platform.isWindows) {
              normalized = normalized.replaceAll('\b', '\b \b');
            }
            _addOutput(normalized);
          });
          _localProcess!.exitCode.then((code) {
            _isConnected = false;
            _setConnectionState(false);
            _addOutput('\r\n[Process terminated with code $code]\r\n');
            onClosed?.call();
          });
          return true;
        } catch (e) {
          _isConnected = false;
          _setConnectionState(false);
          _addOutput('\r\nFailed to start local shell: $e\r\n');
          return false;
        }
      }

      if (nmConfig != null && nmConfig.host.trim().isNotEmpty) {
        if (_tunnelMode == TunnelMode.multiplexed) {
          bool multiplexedSuccess = false;
          bool masterFailed = false;
          try {
            multiplexedSuccess = await _connectMultiplexed(
              targetUsername: effectiveUsername,
              targetPassword: effectivePassword,
              nmConfig: nmConfig,
            );
          } on MasterConnectionException catch (e) {
            masterFailed = true;
            _log('✖ Network Manager connection failed: ${e.cause}', color: 'red');
          } catch (_) {
            multiplexedSuccess = false;
          }

          if (multiplexedSuccess) {
            return true;
          }

          if (masterFailed) {
            disconnect();
            return false;
          }

          _log(
            '[Tunnel] Multiplexed channel connection failed, falling back to interactive hopping...',
            color: 'yellow',
          );
          _tunnelMode = TunnelMode.legacyInteractive;
          _currentHost = host;
          _currentLabel = label;
          _setLabel(_currentLabel);
        }

        return await _connectViaJumpHost(
          targetUsername: effectiveUsername,
          targetPassword: effectivePassword,
          nmConfig: nmConfig,
        );
      } else {
        return await _connectDirect(
          targetUsername: effectiveUsername,
          targetPassword: effectivePassword,
        );
      }
    } finally {
      _isConnecting = false;
    }
  }

  /// The jump host the current forward runs through.
  String? _activeJumpHost;

  String stripAnsi(String text) {
    var s = text;
    // OSC (Operating System Command): \x1B] ... (\x07|\x1B\)
    s = s.replaceAll(RegExp(r'\x1B\].*?(\x07|\x1B\\)', dotAll: true), '');
    // DCS, SOS, PM, APC sequences
    s = s.replaceAll(RegExp(r'\x1B[P^_].*?(\x07|\x1B\\)', dotAll: true), '');
    // CSI (Control Sequence Introducer): \x1b[ ... [@-~]
    s = s.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    // 2-character escape sequences like \x1b(B, \x1b=, etc.
    s = s.replaceAll(RegExp(r'\x1B[@-Z\\-_]'), '');
    s = s.replaceAll(RegExp(r'\x1B[\(\)][0-B]'), '');
    // Non-printable control characters except \r, \n, and \t
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    return s;
  }

  /// [previous] + [chunk], cut to its last [max] characters without copying
  /// a large chunk first.
  static String _keepTail(String previous, String chunk, int max) {
    if (chunk.length >= max) return chunk.substring(chunk.length - max);
    final joined = previous + chunk;
    return joined.length > max ? joined.substring(joined.length - max) : joined;
  }

  void _log(String message, {String? color}) {
    if (_outputController.isClosed) return;
    // Suppress informational messages
    if (color == 'cyan' || color == 'green') return;

    final cleanMessage =
        message.replaceAll('[SYS] ', '').replaceAll('[SYS]', '');
    String colored;
    switch (color) {
      case 'yellow':
        colored = '\x1B[33m$cleanMessage\x1B[0m\r\n';
        break;
      case 'red':
        colored = '\x1B[31m$cleanMessage\x1B[0m\r\n';
        break;
      default:
        colored = '$cleanMessage\r\n';
    }
    _addOutput(colored);
  }

  void _sendRaw(String data) {
    if (isLocalShell && _localProcess != null) {
      String localData = data;
      if (Platform.isWindows) {
        // Windows shells (powershell.exe, cmd.exe) expect CRLF (\r\n) on Enter
        localData = localData
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .replaceAll('\n', '\r\n')
            .replaceAll('\x7f', '\b');
      } else {
        // Unix shells (bash, zsh) reading from a pipe expect LF (\n) on Enter
        localData = localData
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n');
      }
      _localProcess!.stdin.write(localData);
      _localProcess!.stdin.flush().catchError((_) {});
    } else if (_session != null) {
      _session!.stdin.add(Uint8List.fromList(utf8.encode(data)));
    }
    onDataWritten?.call(data);
  }

  void write(String data) {
    if (isLocalShell && _localProcess != null) {
      final buffer = StringBuffer();
      for (int i = 0; i < data.length; i++) {
        final char = data[i];
        if (char == '\r' || char == '\n') {
          final command = _inputLineBuffer.trim().toLowerCase();
          if (command == 'exit' || command == 'logout') {
            if (SettingsService.instance.nexusCascadeExit) {
              _handleUserExit();
            }
          } else if (command == 'cls' || command == 'clear') {
            _enqueueTerminal('\x1b[2J\x1b[H');
          }
          _inputLineBuffer = '';
          buffer.write(Platform.isWindows ? '\r\n' : '\n');
        } else if (char == '\x7f' || char == '\b' || char == '\x08') {
          if (_inputLineBuffer.isNotEmpty) {
            _inputLineBuffer =
                _inputLineBuffer.substring(0, _inputLineBuffer.length - 1);
            buffer.write(Platform.isWindows ? '\b' : '\x7f');
          }
        } else if (char == '\x03' || char == '\x15') {
          _inputLineBuffer = '';
          buffer.write(char);
        } else if (char.codeUnitAt(0) >= 32) {
          _inputLineBuffer += char;
          buffer.write(char);
        } else {
          buffer.write(char);
        }
      }
      final toSend = buffer.toString();
      if (toSend.isNotEmpty) {
        _localProcess!.stdin.write(toSend);
        _localProcess!.stdin.flush().catchError((_) {});
      }
      onDataWritten?.call(data);
      return;
    }

    _sendRaw(data);

    if (!_isConnected) return;

    for (int i = 0; i < data.length; i++) {
      final char = data[i];
      if (char == '\r' || char == '\n') {
        final command = _inputLineBuffer.trim().toLowerCase();
        if (command == 'exit' || command == 'logout') {
          if (SettingsService.instance.nexusCascadeExit) {
            _handleUserExit();
          }
        }
        _inputLineBuffer = '';
      } else if (char == '\x7f' || char == '\b' || char == '\x08') {
        if (_inputLineBuffer.isNotEmpty) {
          _inputLineBuffer =
              _inputLineBuffer.substring(0, _inputLineBuffer.length - 1);
        }
      } else if (char == '\x03' || char == '\x15') {
        _inputLineBuffer = '';
      } else if (char.codeUnitAt(0) >= 32) {
        _inputLineBuffer += char;
      }
    }
  }

  void _handleUserExit() {
    if (_isUserExiting && _exitTimer != null) return;
    _isUserExiting = true;
    _exitTimer?.cancel();

    int ticks = 0;
    _exitTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      ticks++;
      if (!_isConnected) {
        timer.cancel();
        _exitTimer = null;
        _notifyClose();
        return;
      }

      // If child hop exited and we see a shell prompt ($ or # or > or %),
      // cascade exit by writing exit\r\n until Network Manager session closes.
      if (_isShellPrompt(_hopBuffer)) {
        _hopBuffer = '';
        _sendRaw('exit\r\n');
      }

      // Safety timeout after 5 seconds
      if (ticks >= 20) {
        timer.cancel();
        _exitTimer = null;
        disconnect();
        _notifyClose();
      }
    });
  }

  Future<void> gracefulDisconnect({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!_isConnected) {
      dispose();
      return;
    }

    _isUserExiting = true;
    _exitTimer?.cancel();

    // Send Ctrl+C and exit\r\n to break any foreground process and initiate exit
    _hopBuffer = '';
    _sendRaw('\x03\rexit\r\n');

    final completer = Completer<void>();
    final maxTicks = (timeout.inMilliseconds / 250).ceil();
    int ticks = 0;

    _exitTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      ticks++;
      if (!_isConnected) {
        timer.cancel();
        _exitTimer = null;
        if (!completer.isCompleted) completer.complete();
        return;
      }

      if (_isShellPrompt(_hopBuffer)) {
        _hopBuffer = '';
        _sendRaw('exit\r\n');
      }

      if (ticks >= maxTicks) {
        timer.cancel();
        _exitTimer = null;
        disconnect();
        if (!completer.isCompleted) completer.complete();
      }
    });

    final prevOnClosed = onClosed;
    onClosed = () {
      prevOnClosed?.call();
      if (!completer.isCompleted) {
        completer.complete();
      }
    };

    await completer.future;
    dispose();
  }

  void _notifyClose() {
    if (_hasNotifiedClose) return;
    _hasNotifiedClose = true;
    _exitTimer?.cancel();
    _exitTimer = null;
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = null;
    Future.delayed(const Duration(milliseconds: 250), () {
      onClosed?.call();
    });
  }

  SSHPtyConfig _createPtyConfig() {
    final w = terminal.viewWidth > 0 ? terminal.viewWidth : 120;
    final h = terminal.viewHeight > 0 ? terminal.viewHeight : 40;
    _lastSentPtyWidth = w;
    _lastSentPtyHeight = h;
    return SSHPtyConfig(
      width: w,
      height: h,
    );
  }

  /// Delay before forwarding a local terminal resize (e.g. font zoom) to the
  /// remote PTY. Some shells (e.g. F5 BIG-IP TMOS) reprint their prompt on
  /// every SIGWINCH, so consecutive zoom steps are coalesced into one resize.
  static const Duration ptyResizeDebounce = Duration(milliseconds: 800);

  void resize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    // Nothing to notify when there is no remote PTY yet; the initial PTY size
    // is taken from the terminal viewport when the shell is opened.
    if (_session == null && onPtyResizeForTesting == null) return;
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(ptyResizeDebounce, () {
      if (_lastSentPtyWidth == width && _lastSentPtyHeight == height) {
        return;
      }
      _lastSentPtyWidth = width;
      _lastSentPtyHeight = height;
      onPtyResizeForTesting?.call(width, height);
      if (_session != null) {
        _session!.resizeTerminal(width, height);
      }
    });
  }

  Future<bool> sendCommandAndWaitForPrompt({
    required String command,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!_isConnected) return false;

    final clean = command.trimRight();
    recordLogCommand(clean);

    if (isLocalShell) {
      write('$clean\n');
      // For local shells running on pipes without a pseudo-console,
      // no interactive prompt is emitted. Small delay allows stdin flush.
      await Future.delayed(const Duration(milliseconds: 60));
      return true;
    }

    final completer = Completer<bool>();
    // Prompt detection only looks at the end of the output; keeping just a
    // tail avoids re-scanning everything a long command has printed.
    var tail = '';
    StreamSubscription<String>? sub;
    Timer? timeoutTimer;
    Timer? echoGraceTimer;
    bool hasSeenEchoOrOutput = false;

    Future<void> finish([bool result = true]) async {
      echoGraceTimer?.cancel();
      sub?.cancel();
      timeoutTimer?.cancel();
      await _sessionLogger?.flush();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    void checkPrompt() {
      if (_isShellPrompt(tail)) {
        finish(true);
      }
    }

    sub = outputStream.listen((chunk) {
      tail = _keepTail(tail, chunk, 4096);

      if (!hasSeenEchoOrOutput) {
        if (chunk.contains('\n') || chunk.contains('\r')) {
          hasSeenEchoOrOutput = true;
        }
      }

      if (hasSeenEchoOrOutput) {
        checkPrompt();
      }
    });

    write('$clean\n');

    // If the command produced no output (or echo didn't contain a newline),
    // allow prompt checking after a brief grace period (120ms).
    echoGraceTimer = Timer(const Duration(milliseconds: 120), () {
      hasSeenEchoOrOutput = true;
      checkPrompt();
    });

    timeoutTimer = Timer(timeout, () {
      finish(true);
    });

    return completer.future;
  }

  void disconnect() {
    _isConnecting = false;
    _isConnected = false;
    _setConnectionState(false);
    _suppressOutput = false;
    _suppressedBuffer.clear();
    _exitTimer?.cancel();
    _exitTimer = null;
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = null;
    if (isLocalShell) {
      try {
        _localProcess?.kill();
      } catch (_) {}
      _localProcess = null;
    }
    _session?.close();
    _client?.close();
    _jumpClient?.close();
    _session = null;
    _client = null;
    _jumpClient = null;
    if (_leaseId != null) {
      SshTunnelManager.instance.releaseLease(_leaseId!);
      _leaseId = null;
    }
    _releaseOutputSubscriptions();
    closeLogger();
  }

  bool _isDisposed = false;

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _exitTimer?.cancel();
    _exitTimer = null;
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = null;
    disconnect();
    _terminalDrainTimer?.cancel();
    _terminalDrainTimer = null;
    _pendingChunks.clear();
    _pendingHeadOffset = 0;
    _pendingChars = 0;
    _outputController.close();
    _connectionStateController.close();
    _labelController.close();
    terminalController.dispose();
    logFailure.dispose();
  }
}

/// Forwards to [_source] and reports every subscription to [_onListen].
class _TrackedStream<T> extends Stream<T> {
  final Stream<T> _source;
  final void Function(StreamSubscription<T>) _onListen;

  _TrackedStream(this._source, this._onListen);

  @override
  bool get isBroadcast => _source.isBroadcast;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final sub = _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    _onListen(sub);
    return sub;
  }
}

class SshService extends ChangeNotifier {
  static SshService? _instance;
  final Map<String, SshConnection> _connections = {};

  SshService._();

  static SshService get instance {
    _instance ??= SshService._();
    return _instance!;
  }

  @visibleForTesting
  void Function(SshConnection)? onConnectionCreated;

  Map<String, SshConnection> get connections => _connections;
  bool get hasActiveSessions => _connections.isNotEmpty;

  SshConnection createConnection({
    required String host,
    required String label,
    int port = 22,
    String? fallbackHost,
    String? fallbackLabel,
    String? targetUsername,
    String? targetPassword,
    String? jumpClusterHost,
    String? jumpClusterFallback,
    String? jumpClusterUsername,
    String? jumpClusterPassword,
    String? feHostname,
    String? clusterName,
    bool? isOam,
    SshLogService? logService,
    DateTime? logTimestamp,
    bool? enableLogging,
    TunnelMode tunnelMode = TunnelMode.multiplexed,
  }) {
    final id = '${label}_${DateTime.now().millisecondsSinceEpoch}';
    final shouldLog = enableLogging ?? SettingsService.instance.nexusAutoSessionLogging;
    final conn = SshConnection(
      id: id,
      host: host,
      port: port,
      label: label,
      fallbackHost: fallbackHost,
      fallbackLabel: fallbackLabel,
      targetUsername: targetUsername,
      targetPassword: targetPassword,
      jumpClusterHost: jumpClusterHost,
      jumpClusterFallback: jumpClusterFallback,
      jumpClusterUsername: jumpClusterUsername,
      jumpClusterPassword: jumpClusterPassword,
      feHostname: feHostname,
      clusterName: clusterName,
      isOam: isOam,
      logService: logService,
      logTimestamp: logTimestamp ?? (shouldLog ? DateTime.now() : null),
      enableLogging: shouldLog,
      tunnelMode: tunnelMode,
    );
    _connections[id] = conn;
    onConnectionCreated?.call(conn);
    notifyListeners();
    return conn;
  }

  /// Tracks a connection built outside [createConnection] (e.g. a duplicated
  /// tab) so closing it disconnects gracefully and flushes its log.
  void registerConnection(SshConnection conn) {
    _connections[conn.id] = conn;
    onConnectionCreated?.call(conn);
    notifyListeners();
  }

  Future<void> removeConnection(String id, {bool graceful = false}) async {
    final conn = _connections[id];
    if (conn == null) return;

    if (graceful && conn.isConnected) {
      _connections.remove(id);
      notifyListeners();
      await conn.gracefulDisconnect();
      await conn.closeLogger();
    } else {
      conn.dispose();
      await conn.closeLogger();
      _connections.remove(id);
      notifyListeners();
    }
  }

  Future<void> disconnectAll({bool graceful = false}) async {
    final list = _connections.values.toList();
    _connections.clear();
    notifyListeners();

    if (graceful) {
      await Future.wait(list.map((c) async {
        await c.gracefulDisconnect();
        await c.closeLogger();
      }));
    } else {
      for (final conn in list) {
        conn.dispose();
        await conn.closeLogger();
      }
    }
  }
}
