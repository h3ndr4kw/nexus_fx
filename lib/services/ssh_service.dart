import 'dart:async';
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
  final String? jumpClusterHost;
  final int jumpClusterPort;
  final String? jumpClusterFallback;
  final String? jumpClusterUsername;
  final String? jumpClusterPassword;
  final String? feHostname;
  final String? clusterName;
  final bool isOam;
  final SshLogService? logService;
  final DateTime? logTimestamp;
  final bool enableLogging;
  bool isLocalShell;
  Process? _localProcess;

  TunnelMode _tunnelMode = TunnelMode.multiplexed;
  TunnelMode get tunnelMode => _tunnelMode;

  String? _leaseId;
  String? get leaseId => _leaseId;

  SshSessionLogger? _sessionLogger;
  File? _logFile;
  File? get logFile => _logFile ?? _sessionLogger?.file;

  String _currentHost;
  String _currentLabel;

  String get currentHost => _currentHost;
  String get currentLabel => _currentLabel;

  SSHClient? _client;
  SSHSession? _session;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _wasConnected = false;
  bool _isUserExiting = false;
  bool _hasNotifiedClose = false;
  String _inputLineBuffer = '';
  Timer? _exitTimer;

  void Function()? onClosed;

  @visibleForTesting
  void Function(String data)? onDataWritten;

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
  }

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

  late final Terminal terminal = Terminal(maxLines: 10000);
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
    this.jumpClusterHost,
    this.jumpClusterPort = 22,
    this.jumpClusterFallback,
    this.jumpClusterUsername,
    this.jumpClusterPassword,
    this.feHostname,
    this.clusterName,
    bool? isOam,
    this.isLocalShell = false,
    this.enableLogging = true,
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
      jumpClusterHost: route.jumpHost,
      jumpClusterPort: route.jumpPort,
      jumpClusterFallback: route.jumpFallbackHost,
      jumpClusterUsername: route.jumpUsername,
      jumpClusterPassword: route.jumpPassword,
      isLocalShell: isLocal,
      logService: logService,
      enableLogging: shouldLog,
      logTimestamp: shouldLog ? DateTime.now() : null,
      tunnelMode: profile.tunnelMode,
    );
    return conn;
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
      );
      _logFile = _sessionLogger?.file;
    } catch (e) {
      debugPrint('Failed to initialize SSH logger: $e');
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

  void _addOutput(String data) {
    terminal.write(data);
    if (!_outputController.isClosed) {
      _outputController.add(data);
    }
    recordLogOutput(data);
  }

  void _setConnectionState(bool state) {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void _setLabel(String label) {
    if (!_labelController.isClosed) {
      _labelController.add(label);
    }
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
          _localProcess!.stdout.listen((bytes) {
            final s = utf8.decode(bytes, allowMalformed: true);
            var normalized = s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
            if (Platform.isWindows) {
              normalized = normalized.replaceAll('\b', '\b \b');
            }
            _addOutput(normalized);
          });
          _localProcess!.stderr.listen((bytes) {
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

  Future<bool> _connectMultiplexed({
    required String targetUsername,
    required String targetPassword,
    required NetworkManagerConfig nmConfig,
  }) async {
    try {
      await SshTunnelManager.instance.getMasterClient(nmConfig);
    } catch (e) {
      throw MasterConnectionException(e);
    }

    if (jumpClusterHost != null && jumpClusterHost!.trim().isNotEmpty) {
      return await _connectMultiplexedChained(
        targetUsername: targetUsername,
        targetPassword: targetPassword,
        nmConfig: nmConfig,
      );
    } else {
      return await _connectMultiplexedDirectNode(
        targetUsername: targetUsername,
        targetPassword: targetPassword,
        nmConfig: nmConfig,
      );
    }
  }

  Future<bool> _connectMultiplexedChained({
    required String targetUsername,
    required String targetPassword,
    required NetworkManagerConfig nmConfig,
  }) async {
    final clusterUser = jumpClusterUsername ?? 'root';
    final clusterPass = jumpClusterPassword ?? '';
    final activeClusterHost = jumpClusterHost!;
    final targetFe = (feHostname != null && feHostname!.trim().isNotEmpty)
        ? feHostname!
        : _currentHost;

    if (customTargetClientFactory != null) {
      final forwardChannel =
          await SshTunnelManager.instance.openChainedFeChannel(
        nmConfig: nmConfig,
        oamHost: activeClusterHost,
        fallbackOamHost: jumpClusterFallback,
        oamUsername: clusterUser,
        oamPassword: clusterPass,
        feHost: targetFe,
        fePort: port,
        onLeaseCreated: (lease) {
          _leaseId = lease.id;
        },
      );

      try {
        _client = await customTargetClientFactory!(
          forwardChannel,
          username: targetUsername,
          password: targetPassword,
        );

        _session = await _client!.shell(
          pty: SSHPtyConfig(
            width: 120,
            height: 40,
          ),
        );

        _isConnected = true;
        _wasConnected = true;
        _setConnectionState(true);

        _wireSession(_session!);
        return true;
      } catch (e) {
        _client?.close();
        _client = null;
        if (_leaseId != null) {
          SshTunnelManager.instance.releaseLease(_leaseId!);
          _leaseId = null;
        }
        try {
          forwardChannel.close();
        } catch (_) {}
        rethrow;
      }
    }

    return await _connectViaMultiplexedOamHop(
      nmConfig: nmConfig,
      oamHost: activeClusterHost,
      fallbackOamHost: jumpClusterFallback,
      oamUsername: clusterUser,
      oamPassword: clusterPass,
      targetFe: targetFe,
      targetPassword: targetPassword,
    );
  }

  Future<bool> _connectViaMultiplexedOamHop({
    required NetworkManagerConfig nmConfig,
    required String oamHost,
    String? fallbackOamHost,
    required String oamUsername,
    required String oamPassword,
    required String targetFe,
    required String targetPassword,
  }) async {
    final oamClient = await SshTunnelManager.instance.getClusterOamClient(
      nmConfig: nmConfig,
      oamHost: oamHost,
      fallbackOamHost: fallbackOamHost,
      username: oamUsername,
      password: oamPassword,
    );

    final lease = SshTunnelManager.instance.createSessionLease(
      targetHost: targetFe,
      targetPort: port,
      onRelease: () {
        try {
          _session?.close();
        } catch (_) {}
      },
    );
    _leaseId = lease.id;

    try {
      _suppressOutput = true;
      _suppressedBuffer.clear();

      _session = await oamClient.shell(
        pty: SSHPtyConfig(
          width: 120,
          height: 40,
        ),
      );

      _session!.stdout.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          if (_suppressOutput) {
            _suppressedBuffer.write(text);
          } else {
            _addOutput(text);
          }
          _handleHopOutput(text);
        },
        onDone: () {
          disconnect();
          if (_isUserExiting || _wasConnected) {
            _notifyClose();
          }
        },
        onError: (e) {
          _addOutput('\r\n[Error: $e]\r\n');
          disconnect();
          if (_isUserExiting) {
            _notifyClose();
          }
        },
      );

      _session!.stderr.listen((data) {
        final text = utf8.decode(data, allowMalformed: true);
        if (_suppressOutput) {
          _suppressedBuffer.write(text);
        } else {
          _addOutput(text);
        }
        _handleHopOutput(text);
      });

      // Wait for Cluster OAM prompt
      final oamPrompt = await _waitForHopCondition(
        test: (buf) => _isShellPrompt(buf),
        timeout: const Duration(seconds: 12),
        timeoutMessage: 'Timeout waiting for Cluster OAM prompt',
      );

      if (oamPrompt == null) {
        _suppressOutput = false;
        _suppressedBuffer.clear();
        _log('✖ Could not establish Cluster OAM shell.', color: 'red');
        disconnect();
        return false;
      }

      await Future.delayed(const Duration(milliseconds: 200));
      _hopBuffer = '';
      // Discard Cluster OAM login banner and prompt so it is not shown
      _suppressedBuffer.clear();

      final hopSuccess = await _executeHopTo(
        host: targetFe,
        username: null,
        password: targetPassword,
        port: port,
      );

      if (!hopSuccess) {
        _suppressOutput = false;
        final failedText = _suppressedBuffer.toString();
        _suppressedBuffer.clear();
        if (_isConnectionFailed(failedText)) {
          _addOutput('\r\n$failedText\r\n');
        }
        _log('\r\n✖ Failed to connect to FE node ($targetFe)\r\n', color: 'red');
        disconnect();
        return false;
      }

      // Filter hopping noise (ssh command echo, host key warnings)
      // and output the target FE login banner and prompt.
      final filteredOutput = _filterHopBanner(_suppressedBuffer.toString());
      _suppressedBuffer.clear();
      _suppressOutput = false;
      if (filteredOutput.isNotEmpty) {
        _addOutput(filteredOutput);
      }

      _isConnected = true;
      _wasConnected = true;
      _setConnectionState(true);
      return true;
    } catch (e) {
      _suppressOutput = false;
      _suppressedBuffer.clear();
      disconnect();
      rethrow;
    }
  }

  Future<bool> _connectMultiplexedDirectNode({
    required String targetUsername,
    required String targetPassword,
    required NetworkManagerConfig nmConfig,
  }) async {
    try {
      return await _connectSingleMultiplexedChannel(
        host: _currentHost,
        port: port,
        targetUsername: targetUsername,
        targetPassword: targetPassword,
        nmConfig: nmConfig,
      );
    } catch (primaryError) {
      if (fallbackHost != null &&
          fallbackHost!.trim().isNotEmpty &&
          _currentHost != fallbackHost) {
        _log('\r\n✖ Primary target $_currentHost multiplexed channel failed.', color: 'red');
        _log(
          '⏳ Switching to fallback target $fallbackHost (${fallbackLabel ?? 'OAM2'})...',
          color: 'yellow',
        );
        _currentHost = fallbackHost!;
        _currentLabel = fallbackLabel ?? '$label (OAM2)';
        _setLabel(_currentLabel);

        return await _connectSingleMultiplexedChannel(
          host: _currentHost,
          port: port,
          targetUsername: targetUsername,
          targetPassword: targetPassword,
          nmConfig: nmConfig,
        );
      }
      rethrow;
    }
  }

  Future<bool> _connectSingleMultiplexedChannel({
    required String host,
    required int port,
    required String targetUsername,
    required String targetPassword,
    required NetworkManagerConfig nmConfig,
  }) async {
    final forwardChannel = await SshTunnelManager.instance.openForwardChannel(
      nmConfig: nmConfig,
      targetHost: host,
      targetPort: port,
      onLeaseCreated: (lease) {
        _leaseId = lease.id;
      },
    );

    try {
      _client = await (customTargetClientFactory != null
          ? customTargetClientFactory!(
              forwardChannel,
              username: targetUsername,
              password: targetPassword,
            )
          : _defaultTargetClientFactory(
              forwardChannel,
              targetUsername,
              targetPassword,
            ));

      _session = await _client!.shell(
        pty: SSHPtyConfig(
          width: 120,
          height: 40,
        ),
      );

      _isConnected = true;
      _wasConnected = true;
      _setConnectionState(true);

      _wireSession(_session!);
      return true;
    } catch (e) {
      _client?.close();
      _client = null;
      if (_leaseId != null) {
        SshTunnelManager.instance.releaseLease(_leaseId!);
        _leaseId = null;
      }
      try {
        forwardChannel.close();
      } catch (_) {}
      rethrow;
    }
  }

  Future<SSHClient> _defaultTargetClientFactory(
    SSHSocket socket,
    String username,
    String password,
  ) async {
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
      onUserInfoRequest: (request) =>
          request.prompts.map((p) => password).toList(),
      keepAliveInterval: const Duration(seconds: 15),
    );
    await client.authenticated;
    return client;
  }

  void _wireSession(SSHSession session) {
    session.stdout.listen(
      (data) {
        final text = utf8.decode(data, allowMalformed: true);
        _addOutput(text);
      },
      onDone: () {
        disconnect();
        if (_isUserExiting || _wasConnected) {
          _notifyClose();
        }
      },
      onError: (e) {
        _addOutput('\r\n[Error: $e]\r\n');
        disconnect();
        if (_isUserExiting) {
          _notifyClose();
        }
      },
    );

    session.stderr.listen((data) {
      final text = utf8.decode(data, allowMalformed: true);
      _addOutput(text);
    });
  }

  Future<bool> _connectViaJumpHost({
    required String targetUsername,
    required String targetPassword,
    required NetworkManagerConfig nmConfig,
  }) async {
    if (customJumpHostConnector != null) {
      return await customJumpHostConnector!(
        targetUsername: targetUsername,
        targetPassword: targetPassword,
        nmConfig: nmConfig,
      );
    }
    try {
      final socket = await SSHSocket.connect(
        nmConfig.host,
        nmConfig.port,
        timeout: const Duration(seconds: 15),
      );

      _client = SSHClient(
        socket,
        username: nmConfig.username,
        onPasswordRequest: () => nmConfig.password,
        onUserInfoRequest: (request) =>
            request.prompts.map((p) => nmConfig.password).toList(),
        keepAliveInterval: const Duration(seconds: 15),
      );

      _session = await _client!.shell(
        pty: SSHPtyConfig(
          width: 120,
          height: 40,
        ),
      );

      _session!.stdout.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          if (_suppressOutput) {
            _suppressedBuffer.write(text);
          } else {
            _addOutput(text);
          }
          _handleHopOutput(text);
        },
        onDone: () {
          disconnect();
          if (_isUserExiting || _wasConnected) {
            _notifyClose();
          }
        },
        onError: (e) {
          _addOutput('\r\n[Error: $e]\r\n');
          disconnect();
          if (_isUserExiting) {
            _notifyClose();
          }
        },
      );

      _session!.stderr.listen((data) {
        final text = utf8.decode(data, allowMalformed: true);
        if (_suppressOutput) {
          _suppressedBuffer.write(text);
        } else {
          _addOutput(text);
        }
        _handleHopOutput(text);
      });

      // Wait for Network Manager shell prompt
      final nmPrompt = await _waitForHopCondition(
        test: (buf) => _isShellPrompt(buf),
        timeout: const Duration(seconds: 12),
        timeoutMessage: 'Timeout waiting for Network Manager prompt',
      );

      if (nmPrompt == null) {
        _log('✖ Could not establish Network Manager shell.', color: 'red');
        disconnect();
        return false;
      }

      bool success;

      if (jumpClusterHost != null && jumpClusterHost!.trim().isNotEmpty) {
        _suppressOutput = true;
        _suppressedBuffer.clear();

        // --- 3-HOP CONNECTION FOR FE NODE ---
        // Step 1: Hop from Network Manager to Cluster OAM1 (or fallback OAM2)
        final clusterUser = jumpClusterUsername ?? 'root';
        final clusterPass = jumpClusterPassword ?? '';
        String activeClusterHost = jumpClusterHost!;

        bool clusterSuccess = await _executeHopTo(
          host: activeClusterHost,
          username: clusterUser,
          password: clusterPass,
        );

        if (!clusterSuccess &&
            jumpClusterFallback != null &&
            jumpClusterFallback!.trim().isNotEmpty &&
            jumpClusterFallback != activeClusterHost) {
          _log('\r\n✖ Cluster primary OAM $activeClusterHost failed.', color: 'red');
          _log(
              '⏳ Switching to cluster fallback OAM ${jumpClusterFallback!}...',
              color: 'yellow');

          // Cancel active ssh on Network Manager
          write('\x03\n');
          await Future.delayed(const Duration(milliseconds: 600));
          _hopBuffer = '';
          _suppressedBuffer.clear();

          activeClusterHost = jumpClusterFallback!;
          clusterSuccess = await _executeHopTo(
            host: activeClusterHost,
            username: clusterUser,
            password: clusterPass,
          );
        }

        if (!clusterSuccess) {
          _suppressOutput = false;
          _suppressedBuffer.clear();
          _log(
              '\r\n✖ Failed to connect to Cluster OAM ($activeClusterHost)\r\n',
              color: 'red');
          disconnect();
          return false;
        }

        // Step 2: From Cluster OAM prompt, hop to FE node via: ssh [FE Hostname]
        await Future.delayed(const Duration(milliseconds: 400));
        _hopBuffer = '';
        _suppressedBuffer.clear();

        final targetFe = (feHostname != null && feHostname!.trim().isNotEmpty)
            ? feHostname!
            : _currentHost;

        success = await _executeHopTo(
          host: targetFe,
          username: null, // Command: ssh [FE Hostname]
          password: targetPassword,
        );

        if (success) {
          final filteredOutput = _filterHopBanner(_suppressedBuffer.toString());
          _suppressedBuffer.clear();
          _suppressOutput = false;
          if (filteredOutput.isNotEmpty) {
            _addOutput(filteredOutput);
          }
        } else {
          _suppressOutput = false;
          final failedText = _suppressedBuffer.toString();
          _suppressedBuffer.clear();
          if (_isConnectionFailed(failedText)) {
            _addOutput('\r\n$failedText\r\n');
          }
        }
      } else {
        // --- 2-HOP DIRECT HOP (e.g. Cluster OAM node) ---
        success = await _executeHopTo(
          host: _currentHost,
          username: targetUsername,
          password: targetPassword,
        );

        // Failover to fallback if primary failed
        if (!success &&
            fallbackHost != null &&
            _currentHost != fallbackHost &&
            fallbackHost!.trim().isNotEmpty) {
          _log('\r\n✖ Primary target $_currentHost failed.', color: 'red');
          _log(
              '⏳ Switching to fallback target $fallbackHost (${fallbackLabel ?? 'OAM2'})...',
              color: 'yellow');

          // Cancel any active ssh command on NM
          write('\x03\n');
          await Future.delayed(const Duration(milliseconds: 600));
          _hopBuffer = '';

          _currentHost = fallbackHost!;
          _currentLabel = fallbackLabel ?? '$label (OAM2)';
          _setLabel(_currentLabel);

          success = await _executeHopTo(
            host: _currentHost,
            username: targetUsername,
            password: targetPassword,
          );
        }
      }

      if (success) {
        _isConnected = true;
        _wasConnected = true;
        _setConnectionState(true);
        return true;
      } else {
        _log('\r\n✖ Connection failed to $_currentHost\r\n', color: 'red');
        disconnect();
        return false;
      }
    } catch (e) {
      _suppressOutput = false;
      _suppressedBuffer.clear();
      _log('✖ Connection failed: $e', color: 'red');
      disconnect();
      return false;
    }
  }

  Future<bool> _executeHopTo({
    required String host,
    String? username,
    required String password,
    int port = 22,
  }) async {
    _hopBuffer = '';

    final userPrefix = (username != null && username.isNotEmpty) ? '$username@' : '';
    final portArg = (port == 22) ? '' : '-p $port ';
    final sshCmd =
        'ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes $portArg$userPrefix$host\n';
    write(sshCmd);

    final step1 = await _waitForHopCondition(
      test: (buf) =>
          _isPasswordPrompt(buf) ||
          _isShellPrompt(buf) ||
          _isConnectionFailed(buf) ||
          _isHostKeyPrompt(buf),
      timeout: const Duration(seconds: 15),
      timeoutMessage: 'Timeout connecting to $host',
    );

    if (step1 == null || _isConnectionFailed(_hopBuffer)) {
      return false;
    }

    if (_isHostKeyPrompt(_hopBuffer)) {
      write('yes\n');
      _hopBuffer = '';
      final afterHostKey = await _waitForHopCondition(
        test: (buf) =>
            _isPasswordPrompt(buf) ||
            _isShellPrompt(buf) ||
            _isConnectionFailed(buf),
        timeout: const Duration(seconds: 10),
      );
      if (afterHostKey == null || _isConnectionFailed(_hopBuffer)) {
        return false;
      }
    }

    if (_isPasswordPrompt(_hopBuffer)) {
      if (password.trim().isNotEmpty) {
        _hopBuffer = '';
        write('$password\n');

        final targetShell = await _waitForHopCondition(
          test: (buf) => _isShellPrompt(buf) || _isConnectionFailed(buf),
          timeout: const Duration(seconds: 25),
          timeoutMessage: 'Timeout waiting for shell prompt on $host',
        );

        if (targetShell == null || _isConnectionFailed(_hopBuffer)) {
          return false;
        }
        return true;
      } else {
        final userDisplay =
            (username != null && username.isNotEmpty) ? '$username@$host' : host;
        _log(
            'Password required for $userDisplay. Enter password in terminal.\r\n',
            color: 'yellow');
        return true;
      }
    } else if (_isShellPrompt(_hopBuffer)) {
      return true;
    }

    return false;
  }

  Future<bool> _connectDirect({
    required String targetUsername,
    required String targetPassword,
  }) async {
    try {
      final socket = await SSHSocket.connect(_currentHost, port,
          timeout: const Duration(seconds: 10));

      _client = SSHClient(
        socket,
        username: targetUsername,
        onPasswordRequest: () => targetPassword,
        onUserInfoRequest: (request) =>
            request.prompts.map((p) => targetPassword).toList(),
        keepAliveInterval: const Duration(seconds: 15),
      );

      _session = await _client!.shell(
        pty: SSHPtyConfig(
          width: 120,
          height: 40,
        ),
      );

      _isConnected = true;
      _wasConnected = true;
      _setConnectionState(true);

      _session!.stdout.listen(
        (data) =>
            _addOutput(utf8.decode(data, allowMalformed: true)),
        onDone: () {
          disconnect();
          if (_isUserExiting || _wasConnected) {
            _notifyClose();
          }
        },
        onError: (e) {
          _addOutput('\r\n[Error: $e]\r\n');
          disconnect();
          if (_isUserExiting) {
            _notifyClose();
          }
        },
      );

      _session!.stderr.listen((data) {
        _addOutput(utf8.decode(data, allowMalformed: true));
      });

      return true;
    } catch (e) {
      _log('✖ Direct connection to $_currentHost failed: $e',
          color: 'red');
      if (fallbackHost != null &&
          _currentHost != fallbackHost &&
          fallbackHost!.trim().isNotEmpty) {
        _log('⏳ Switching to fallback target $fallbackHost...',
            color: 'yellow');
        _currentHost = fallbackHost!;
        _currentLabel = fallbackLabel ?? '$label (OAM2)';
        _setLabel(_currentLabel);
        return await _connectDirect(
          targetUsername: targetUsername,
          targetPassword: targetPassword,
        );
      }
      _isConnected = false;
      _setConnectionState(false);
      return false;
    }
  }

  void _handleHopOutput(String text) {
    _hopBuffer += text;
    if (_hopBuffer.length > 4096) {
      _hopBuffer = _hopBuffer.substring(_hopBuffer.length - 4096);
    }
    for (final listener in List<void Function()>.from(_hopListeners)) {
      listener();
    }
  }

  Future<String?> _waitForHopCondition({
    required bool Function(String buffer) test,
    required Duration timeout,
    String? timeoutMessage,
  }) async {
    if (test(_hopBuffer)) {
      return _hopBuffer;
    }

    final completer = Completer<String?>();
    void listener() {
      if (test(_hopBuffer)) {
        if (!completer.isCompleted) {
          completer.complete(_hopBuffer);
        }
      }
    }

    _hopListeners.add(listener);

    Timer? timer;
    if (timeout > Duration.zero) {
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          if (timeoutMessage != null) {
            _log('\r\n✖ $timeoutMessage', color: 'red');
          }
          completer.complete(null);
        }
      });
    }

    final result = await completer.future;
    timer?.cancel();
    _hopListeners.remove(listener);
    return result;
  }

  bool _isPasswordPrompt(String buffer) {
    final clean = stripAnsi(buffer).trimRight().toLowerCase();
    return clean.endsWith('password:') ||
        clean.endsWith('password for') ||
        clean.endsWith('passphrase:') ||
        clean.contains('password:');
  }

  bool _isShellPrompt(String buffer) {
    final clean = stripAnsi(buffer).trimRight();
    if (clean.isEmpty) return false;
    if (clean.toLowerCase().endsWith(':') ||
        clean.toLowerCase().contains('password:')) {
      return false;
    }
    final last = clean[clean.length - 1];
    return last == r'$' || last == '#' || last == '>' || last == '%';
  }

  bool _isHostKeyPrompt(String buffer) {
    final clean = stripAnsi(buffer).toLowerCase();
    return clean.contains('are you sure you want to continue connecting');
  }

  bool _isConnectionFailed(String buffer) {
    final clean = stripAnsi(buffer).toLowerCase();
    return clean.contains('connection timed out') ||
        clean.contains('connection timeout') ||
        clean.contains('no route to host') ||
        clean.contains('connection refused') ||
        clean.contains('host is down') ||
        clean.contains('network is unreachable') ||
        clean.contains('name or service not known') ||
        clean.contains('could not resolve hostname') ||
        clean.contains('unknown host') ||
        clean.contains('permission denied (publickey') ||
        clean.contains('permission denied, please try again') ||
        clean.contains('ssh: connect to host');
  }

  String stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  }

  String _filterHopBanner(String text) {
    final lines = text.split('\n');
    final keptLines = <String>[];
    bool inTargetOutput = false;

    for (final rawLine in lines) {
      final cleanLine = stripAnsi(rawLine).trim();

      if (!inTargetOutput) {
        final isSshCmd = cleanLine.startsWith('ssh ') ||
            cleanLine.contains('StrictHostKeyChecking') ||
            cleanLine.contains('-o UserKnownHostsFile');
        final isKnownHostsWarning =
            cleanLine.contains('Permanently added') ||
            cleanLine.contains('known hosts') ||
            cleanLine.contains('authenticity of host') ||
            cleanLine.contains('key fingerprint');
        final isPasswordPrompt = cleanLine.toLowerCase().contains('password:') ||
            cleanLine.toLowerCase().contains('passphrase:');
        final isHostKeyPrompt = cleanLine.toLowerCase().contains('continue connecting');
        final isYesEcho = cleanLine.toLowerCase() == 'yes';

        if (isSshCmd || isKnownHostsWarning || isPasswordPrompt || isHostKeyPrompt || isYesEcho) {
          continue;
        }

        if (cleanLine.isEmpty) {
          continue;
        }

        inTargetOutput = true;
      }

      keptLines.add(rawLine);
    }

    return keptLines.join('\n');
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
            terminal.write('\x1b[2J\x1b[H');
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
    Future.delayed(const Duration(milliseconds: 250), () {
      onClosed?.call();
    });
  }

  void resize(int width, int height) {
    if (_session != null) {
      _session!.resizeTerminal(width, height);
    }
  }

  Future<bool> sendCommandAndWaitForPrompt({
    required String command,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!_isConnected) return false;

    final completer = Completer<bool>();
    final buffer = StringBuffer();
    StreamSubscription<String>? sub;
    Timer? timeoutTimer;
    bool hasSeenEchoOrOutput = false;
    final sendTime = DateTime.now();

    Future<void> finish([bool result = true]) async {
      sub?.cancel();
      timeoutTimer?.cancel();
      await _sessionLogger?.flush();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    sub = outputStream.listen((chunk) {
      buffer.write(chunk);
      final text = buffer.toString();

      if (!hasSeenEchoOrOutput) {
        if (text.contains('\n') ||
            text.contains('\r') ||
            DateTime.now().difference(sendTime).inMilliseconds >= 150) {
          hasSeenEchoOrOutput = true;
        }
      }

      if (hasSeenEchoOrOutput && _isShellPrompt(text)) {
        finish(true);
      }
    });

    final clean = command.trimRight();
    recordLogCommand(clean);
    write('$clean\n');

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
    if (isLocalShell) {
      try {
        _localProcess?.kill();
      } catch (_) {}
      _localProcess = null;
    }
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
    if (_leaseId != null) {
      SshTunnelManager.instance.releaseLease(_leaseId!);
      _leaseId = null;
    }
    closeLogger();
  }

  bool _isDisposed = false;

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _exitTimer?.cancel();
    _exitTimer = null;
    disconnect();
    _outputController.close();
    _connectionStateController.close();
    _labelController.close();
    terminalController.dispose();
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
