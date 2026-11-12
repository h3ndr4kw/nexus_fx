// Private members of SshConnection live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'ssh_service.dart';

/// Direct connections, optionally through a jump host over a direct-tcpip forward, and key loading.
extension _SshDirectRoutes on SshConnection {
  Future<bool> _connectDirect({
    required String targetUsername,
    required String targetPassword,
  }) async {
    try {
      // Load (and decrypt) the key first, so a bad key file fails before
      // anything is sent to the server.
      final identities = await _loadTargetIdentities();
      final keyOnly = identities != null && targetPassword.isEmpty;
      final viaJump = _hasDirectJumpRoute;
      final socket = viaJump
          ? await _openJumpForward()
          : await SSHSocket.connect(_currentHost, port,
              timeout: const Duration(seconds: 10));

      _client = SSHClient(
        socket,
        username: targetUsername,
        onVerifyHostKey: KnownHostsService.instance
            .handlerFor(_currentHost, port, via: viaJump ? _activeJumpHost : null),
        identities: identities,
        algorithms: SshAlgorithmHelper.buildAlgorithms(
          sshMacs: sshMacs,
          customSshOptions: customSshOptions,
        ),
        onPasswordRequest: keyOnly ? null : () => targetPassword,
        onUserInfoRequest: keyOnly
            ? null
            : (request) => request.prompts.map((p) => targetPassword).toList(),
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

      _tracked(_session!.stdout).listen(
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

      _tracked(_session!.stderr).listen((data) {
        _addOutput(utf8.decode(data, allowMalformed: true));
      });

      return true;
    } catch (e) {
      _log(
          _hasDirectJumpRoute
              ? '✖ Connection to $_currentHost via ${_activeJumpHost ?? jumpClusterHost} failed: $e'
              : '✖ Direct connection to $_currentHost failed: $e',
          color: 'red');
      _client?.close();
      _client = null;
      _jumpClient?.close();
      _jumpClient = null;
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

  /// The session's key pairs, or null when it logs in with a password.
  /// Throws [SshKeyLoadException] with a user-facing message.
  /// A jump route that is not served by a Network Manager: the target is
  /// reached through a direct-tcpip forward on the jump host.
  bool get _hasDirectJumpRoute =>
      jumpClusterHost != null && jumpClusterHost!.trim().isNotEmpty;

  /// Opens an SSH connection to the jump host (its fallback when the primary
  /// cannot be reached) and forwards a channel to the current target.
  Future<SSHSocket> _openJumpForward() async {
    final jumpKey = jumpClusterPrivateKey;
    // Bad key files fail here, before connecting anywhere.
    final jumpIdentities = jumpKey == null ? null : await loadSshIdentities(jumpKey);
    final jumpPass = jumpClusterPassword ?? '';
    final jumpKeyOnly = jumpIdentities != null && jumpPass.isEmpty;
    final candidates = <String>[
      jumpClusterHost!.trim(),
      if (jumpClusterFallback != null &&
          jumpClusterFallback!.trim().isNotEmpty &&
          jumpClusterFallback!.trim() != jumpClusterHost!.trim())
        jumpClusterFallback!.trim(),
    ];

    Object? lastError;
    for (final jumpHost in candidates) {
      SSHClient? jump;
      try {
        _log('⏳ Connecting to jump host $jumpHost:$jumpClusterPort...', color: 'yellow');
        if (jumpKey != null) {
          _log('Using private key ${expandKeyPath(jumpKey.path)} for the jump host',
              color: 'cyan');
        }
        final socket = await SSHSocket.connect(jumpHost, jumpClusterPort,
            timeout: const Duration(seconds: 10));
        jump = SSHClient(
          socket,
          username: (jumpClusterUsername ?? '').trim().isNotEmpty
              ? jumpClusterUsername!.trim()
              : 'root',
          onVerifyHostKey:
              KnownHostsService.instance.handlerFor(jumpHost, jumpClusterPort),
          identities: jumpIdentities,
          algorithms: SshAlgorithmHelper.buildAlgorithms(),
          onPasswordRequest: jumpKeyOnly ? null : () => jumpPass,
          onUserInfoRequest: jumpKeyOnly
              ? null
              : (request) => request.prompts.map((p) => jumpPass).toList(),
          keepAliveInterval: const Duration(seconds: 15),
        );
        await jump.authenticated;
        final channel = await jump.forwardLocal(_currentHost, port);
        _jumpClient = jump;
        _activeJumpHost = jumpHost;
        _log('✔ Tunnel via $jumpHost to $_currentHost:$port open', color: 'green');
        return channel;
      } catch (e) {
        jump?.close();
        lastError = e;
        _log('✖ Jump host $jumpHost failed: $e', color: 'red');
      }
    }
    throw lastError ?? StateError('No jump host');
  }

  Future<List<SSHKeyPair>?> _loadTargetIdentities() async {
    final key = targetPrivateKey;
    if (key == null) return null;
    final keys = await loadSshIdentities(key);
    _log('Using private key ${expandKeyPath(key.path)}', color: 'cyan');
    return keys;
  }
}
