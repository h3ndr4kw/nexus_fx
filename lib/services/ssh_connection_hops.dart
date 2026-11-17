// Private members of SshConnection live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'ssh_service.dart';

/// Interactive shell hops (`ssh` run on a jump host) and the prompt detection they rely on.
extension _SshShellHops on SshConnection {
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
        onVerifyHostKey: KnownHostsService.instance.handlerFor(nmConfig.host, nmConfig.port),
        algorithms: SshAlgorithmHelper.buildAlgorithms(),
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

        // Hop through cluster OAM (with fallback support) to reach target FE node
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

        // Hop from cluster OAM prompt to target FE node
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
        // Direct hop to target host
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
    final extraFlags = SshAlgorithmHelper.buildCliOptionFlags(
      sshMacs: sshMacs,
      customSshOptions: customSshOptions,
    );
    final extraFlagsArg = extraFlags.isEmpty ? '' : '$extraFlags ';
    // Host keys are checked: the jump host's known_hosts catches a changed
    // key, and a first-time key is shown to the user (see below) instead of
    // being accepted blindly.
    final sshCmd =
        'ssh -tt -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes $extraFlagsArg$portArg$userPrefix$host\n';
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
      final trusted = await _verifyHopHostKey(host, port, _hopBuffer);
      if (!trusted) {
        write('no\n');
        _log('\r\n✖ Host key for $host was not accepted; connection cancelled.\r\n',
            color: 'red');
        return false;
      }
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

  void _handleHopOutput(String text) {
    _hopBuffer = SshConnection._keepTail(_hopBuffer, text, 4096);
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
    const promptChars = {
      r'$', '#', '>', '%',
      '❯', '➜', '▶', '⚡', '»', '›', 'λ',
      ')',
    };
    if (promptChars.contains(last)) return true;

    final lines = clean.split('\n');
    final lastLine = lines.isNotEmpty ? lines.last.trim() : '';
    if (lastLine.isEmpty) return false;

    // Prompts starting with symbols like `➜  folder` or `❯  folder`
    if (lastLine.startsWith('➜') ||
        lastLine.startsWith('❯') ||
        lastLine.startsWith('▶') ||
        lastLine.startsWith('⚡')) {
      return true;
    }

    // Regex matching prompts like `user@host:path$`, `(venv) [user@host ~]#`, `PS C:\path>`, `host>`
    final promptRegex = RegExp(r'([@:][^@:\n]+[\$#>\%❯➜▶⚡»›\)])\s*$');
    return promptRegex.hasMatch(lastLine);
  }

  bool _isHostKeyPrompt(String buffer) {
    final clean = stripAnsi(buffer).toLowerCase();
    return clean.contains('are you sure you want to continue connecting');
  }

  /// Asks the user about the key the remote `ssh` is showing in its
  /// first-connection prompt. A prompt without a readable fingerprint is
  /// refused rather than accepted blindly.
  Future<bool> _verifyHopHostKey(String host, int port, String promptText) async {
    final parsed = parseOpenSshHostKeyPrompt(stripAnsi(promptText));
    if (parsed == null) {
      _log('\r\n✖ Could not read the host key fingerprint for $host.\r\n', color: 'red');
      return false;
    }
    return KnownHostsService.instance.verify(
      host,
      port,
      parsed.keyType,
      parsed.fingerprint,
      // Hops can chain (NM -> cluster -> FE); the key is the one the
      // previous hop's ssh sees.
      via: 'ssh from a jump host',
    );
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
        clean.contains('host key verification failed') ||
        clean.contains('remote host identification has changed') ||
        clean.contains('ssh: connect to host');
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
}
