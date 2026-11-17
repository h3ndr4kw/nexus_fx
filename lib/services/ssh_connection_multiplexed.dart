// Private members of SshConnection live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'ssh_service.dart';

/// Connections over the shared Network Manager master client (multiplexed channels).
extension _SshMultiplexedRoutes on SshConnection {
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
          pty: _createPtyConfig(),
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
        pty: _createPtyConfig(),
      );

      _decodedOutput(_session!.stdout).listen(
        (text) {
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

      _decodedOutput(_session!.stderr).listen((text) {
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
              host: host,
              port: port,
              via: nmConfig.host,
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
    String password, {
    required String host,
    required int port,
    String? via,
  }) async {
    final identities = await _loadTargetIdentities();
    final keyOnly = identities != null && password.isEmpty;
    final client = SSHClient(
      socket,
      username: username,
      onVerifyHostKey: KnownHostsService.instance.handlerFor(host, port, via: via),
      identities: identities,
      algorithms: SshAlgorithmHelper.buildAlgorithms(
        sshMacs: sshMacs,
        customSshOptions: customSshOptions,
      ),
      onPasswordRequest: keyOnly ? null : () => password,
      onUserInfoRequest: keyOnly
          ? null
          : (request) => request.prompts.map((p) => password).toList(),
      keepAliveInterval: const Duration(seconds: 15),
    );
    await client.authenticated;
    return client;
  }

  void _wireSession(SSHSession session) {
    _decodedOutput(session.stdout).listen(
      (text) {
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

    _decodedOutput(session.stderr).listen((text) {
      _addOutput(text);
    });
  }
}
