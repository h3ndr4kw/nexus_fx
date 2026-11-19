// Private members of SshConnection live in part files as extensions on the
// class, so they keep access to its state; calling setState from them is
// still the State updating itself.
// ignore_for_file: invalid_use_of_protected_member

part of 'ssh_service.dart';

/// Terminal output pipeline: queueing remote output, time-boxed draining into xterm and back-pressure on the SSH streams.
extension _SshOutputPipeline on SshConnection {
  void _addOutput(String data) {
    if (data.isEmpty) return;
    _enqueueTerminal(data);
    if (!_outputController.isClosed) {
      _outputController.add(data);
    }
    recordLogOutput(data);
  }

  void _enqueueTerminal(String data) {
    if (data.isEmpty || _isDisposed) return;
    // Fast path for interactive use: with nothing queued, write small output
    // straight away, up to one slice per ~frame. Anything beyond that (a
    // burst) goes through the queue.
    if (_pendingChars == 0) {
      final nowUs = _syncWriteClock.elapsedMicroseconds;
      if (nowUs - _syncWindowStartUs > 16000) {
        _syncWindowStartUs = nowUs;
        _syncWindowChars = 0;
      }
      final allowance = isForeground
          ? SshConnection._syncWriteCharsForeground
          : SshConnection._syncWriteCharsBackground;
      if (_syncWindowChars + data.length <= allowance) {
        _syncWindowChars += data.length;
        terminal.write(data);
        return;
      }
    }
    _pendingChunks.add(data);
    _pendingChars += data.length;
    TerminalOutputScheduler.instance.request(_drainSink);
    if (!_outputPaused && _pendingChars > SshConnection.outputHighWaterChars) {
      _setOutputPaused(true);
    }
  }

  /// UTF-8 decoded, back-pressure tracked output of an SSH or process stream.
  /// The decoder keeps state across chunks, so a character split between
  /// two packets is not turned into U+FFFD.
  /// (`cast` because SSH streams are `Stream<Uint8List>`, which cannot take a
  /// `List<int>` transformer directly.)
  Stream<String> _decodedOutput(Stream<List<int>> source) => _tracked(source
      .cast<List<int>>()
      .transform(const Utf8Decoder(allowMalformed: true)));

  int _drainTerminal(int maxChars) {
    if (_pendingChars == 0 || maxChars <= 0) return 0;
    final out = StringBuffer();
    var remaining = maxChars;
    while (remaining > 0 && _pendingChunks.isNotEmpty) {
      final head = _pendingChunks.first;
      final available = head.length - _pendingHeadOffset;
      if (available <= remaining) {
        out.write(_pendingHeadOffset == 0
            ? head
            : head.substring(_pendingHeadOffset));
        remaining -= available;
        _pendingChunks.removeFirst();
        _pendingHeadOffset = 0;
      } else {
        var end = _pendingHeadOffset + remaining;
        // Never split a UTF-16 surrogate pair.
        final unit = head.codeUnitAt(end - 1);
        if (unit >= 0xD800 && unit <= 0xDBFF) end++;
        out.write(head.substring(_pendingHeadOffset, end));
        remaining -= end - _pendingHeadOffset;
        _pendingHeadOffset = end;
        if (_pendingHeadOffset >= head.length) {
          _pendingChunks.removeFirst();
          _pendingHeadOffset = 0;
        }
      }
    }
    _pendingChars -= out.length;
    if (_pendingChars < 0) _pendingChars = 0;
    terminal.write(out.toString());
    if (_outputPaused && _pendingChars <= SshConnection.outputLowWaterChars) {
      _setOutputPaused(false);
    }
    return out.length;
  }

  Stream<T> _tracked<T>(Stream<T> source) =>
      _TrackedStream<T>(source, (sub) {
        _outputSubscriptions.add(sub);
        if (_outputPaused) sub.pause();
      });

  void _setOutputPaused(bool paused) {
    if (_outputPaused == paused) return;
    _outputPaused = paused;
    for (final sub in _outputSubscriptions) {
      paused ? sub.pause() : sub.resume();
    }
  }

  void _releaseOutputSubscriptions() {
    if (_outputPaused) {
      for (final sub in _outputSubscriptions) {
        sub.resume();
      }
    }
    _outputPaused = false;
    _outputSubscriptions.clear();
  }

  void _onLogFailure(SshLogFailure failure) {
    debugPrint('SSH session log failed (${failure.path}): ${failure.error}');
    if (_isDisposed) return;
    logFailure.value = failure;
    final where = failure.path != null ? ' (${failure.path})' : '';
    _enqueueTerminal('\r\n\x1B[33m⚠ ${failure.message}$where\x1B[0m\r\n');
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
}

/// Lets [TerminalOutputScheduler] drain a session's queue without exposing
/// the drain on [SshConnection]'s public API.
class _ConnectionDrainSink implements TerminalDrainSink {
  _ConnectionDrainSink(this._connection);

  final SshConnection _connection;

  @override
  bool isForeground = true;

  @override
  bool get hasPendingOutput =>
      !_connection._isDisposed && _connection._pendingChars > 0;

  @override
  int drainOutput(int maxChars) => _connection._drainTerminal(maxChars);
}
