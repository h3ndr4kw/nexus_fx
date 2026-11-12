import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Result of comparing a presented host key with what we have on record.
enum HostKeyStatus {
  /// The key matches one we trust.
  trusted,

  /// We have no key of this kind for the host (first connection).
  unknown,

  /// We trust a different key of the same kind for this host: either the
  /// server was reinstalled or someone is intercepting the connection.
  changed,
}

/// What the user chose when asked about a host key.
enum HostKeyDecision { trustAlways, trustOnce, reject }

/// Everything the trust dialog needs to show.
@immutable
class HostKeyPromptRequest {
  const HostKeyPromptRequest({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.status,
    this.previousFingerprint,
    this.via,
  });

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final HostKeyStatus status;

  /// For [HostKeyStatus.changed]: the key we used to trust.
  final String? previousFingerprint;

  /// Human-readable route when the host is reached through a jump host.
  final String? via;
}

typedef HostKeyPrompter = Future<HostKeyDecision> Function(HostKeyPromptRequest request);

/// One trusted key.
@immutable
class KnownHostEntry {
  const KnownHostEntry({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.addedAt,
  });

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'keyType': keyType,
        'fingerprint': fingerprint,
        'addedAt': addedAt.toIso8601String(),
      };

  static KnownHostEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final host = json['host'];
    final port = json['port'];
    final type = json['keyType'];
    final fp = json['fingerprint'];
    if (host is! String || port is! int || type is! String || fp is! String) return null;
    return KnownHostEntry(
      host: host,
      port: port,
      keyType: type,
      fingerprint: fp,
      addedAt: DateTime.tryParse('${json['addedAt']}') ?? DateTime.now(),
    );
  }
}

/// Host key fingerprint as printed in an OpenSSH "authenticity of host"
/// prompt (used when hopping with the remote `ssh` command).
@immutable
class ParsedHostKeyPrompt {
  const ParsedHostKeyPrompt(this.keyType, this.fingerprint);
  final String keyType;
  final String fingerprint;
}

final _promptFingerprint = RegExp(
  r'([A-Za-z0-9-]+) key fingerprint is ((?:SHA256|MD5):[A-Za-z0-9+/=:]+|(?:[0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2})',
);

/// Extracts key type and fingerprint from OpenSSH's first-connection prompt.
ParsedHostKeyPrompt? parseOpenSshHostKeyPrompt(String text) {
  final m = _promptFingerprint.firstMatch(text);
  if (m == null) return null;
  var fp = m.group(2)!;
  // OpenSSH ends the sentence with a period, which is not base64.
  if (fp.endsWith('.')) fp = fp.substring(0, fp.length - 1);
  if (!fp.startsWith('SHA256:') && !fp.startsWith('MD5:')) fp = 'MD5:$fp';
  return ParsedHostKeyPrompt(m.group(1)!, fp);
}

/// Trust-on-first-use store of SSH host keys (`~/.nexus_fx/known_hosts.json`).
///
/// Every SSH connection the app makes asks [verify] before authenticating, so
/// a password is never sent to a server whose key the user has not accepted.
/// Unknown and changed keys go to [prompter] (the trust dialog); without one
/// they are rejected.
class KnownHostsService {
  KnownHostsService._(this._filePath);

  static final KnownHostsService instance = KnownHostsService._(null);

  @visibleForTesting
  factory KnownHostsService.forTesting({required String filePath}) =>
      KnownHostsService._(filePath);

  String? _filePath;
  final List<KnownHostEntry> _entries = [];
  final List<KnownHostEntry> _sessionEntries = [];
  final Map<String, Future<bool>> _inFlight = {};
  Future<void>? _loading;
  bool _loaded = false;

  /// Asks the user about an unknown or changed key. Set by the app shell.
  HostKeyPrompter? prompter;

  List<KnownHostEntry> get entries => List.unmodifiable(_entries);

  String get filePath => _filePath ??= _defaultFilePath();

  static String _defaultFilePath() {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    return '$home/.nexus_fx/known_hosts.json';
  }

  static String _normHost(String host) => host.trim().toLowerCase();

  /// Groups key algorithm names that share one key: `ssh-rsa`, `rsa-sha2-256`
  /// and `rsa-sha2-512` all sign with the same RSA key, and OpenSSH prompts
  /// say just "RSA" or "ED25519".
  static String _family(String keyType) {
    final t = keyType.toLowerCase();
    if (t.contains('ed25519')) return 'ed25519';
    if (t.contains('ed448')) return 'ed448';
    if (t.contains('rsa')) return 'rsa';
    if (t.contains('ecdsa')) {
      for (final size in ['256', '384', '521']) {
        if (t.contains(size)) return 'ecdsa$size';
      }
      return 'ecdsa';
    }
    if (t.contains('dss') || t.contains('dsa')) return 'dsa';
    return t;
  }

  static String _fpFormat(String fp) => fp.startsWith('SHA256:') ? 'sha256' : 'md5';

  bool _sameKind(KnownHostEntry e, String host, int port, String keyType, String fp) {
    if (e.host != host || e.port != port) return false;
    if (_fpFormat(e.fingerprint) != _fpFormat(fp)) return false;
    final a = _family(e.keyType);
    final b = _family(keyType);
    // A bare "ecdsa" (from an OpenSSH prompt) matches any ECDSA size.
    if (a == 'ecdsa' || b == 'ecdsa') return a.startsWith('ecdsa') && b.startsWith('ecdsa');
    return a == b;
  }

  Iterable<KnownHostEntry> get _all => _entries.followedBy(_sessionEntries);

  Future<void> load() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    _entries.clear();
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        final list = data is Map ? data['hosts'] : null;
        if (list is List) {
          _entries.addAll(list.map(KnownHostEntry.fromJson).whereType<KnownHostEntry>());
        }
      }
    } catch (e) {
      debugPrint('[KnownHosts] Could not read $filePath: $e');
      // Keep the unreadable file aside instead of overwriting it on next save.
      try {
        await File(filePath).rename('$filePath.corrupt');
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      final tmp = File('$filePath.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'hosts': _entries.map((e) => e.toJson()).toList(),
      }));
      if (await file.exists()) await file.delete();
      await tmp.rename(filePath);
    } catch (e) {
      debugPrint('[KnownHosts] Could not write $filePath: $e');
    }
  }

  HostKeyStatus check(String host, int port, String keyType, String fingerprint) {
    final h = _normHost(host);
    var sawSameKind = false;
    for (final e in _all) {
      if (!_sameKind(e, h, port, keyType, fingerprint)) continue;
      if (e.fingerprint == fingerprint) return HostKeyStatus.trusted;
      sawSameKind = true;
    }
    return sawSameKind ? HostKeyStatus.changed : HostKeyStatus.unknown;
  }

  /// Every fingerprint trusted for [host]:[port], for the native engine.
  List<String> fingerprintsFor(String host, int port) {
    final h = _normHost(host);
    return _all
        .where((e) => e.host == h && e.port == port)
        .map((e) => e.fingerprint)
        .toSet()
        .toList();
  }

  /// Trusts [fingerprint], replacing any other key of the same kind.
  Future<void> trust(
    String host,
    int port,
    String keyType,
    String fingerprint, {
    bool persist = true,
  }) async {
    if (!_loaded) await load();
    final h = _normHost(host);
    bool stale(KnownHostEntry e) => _sameKind(e, h, port, keyType, fingerprint);
    _sessionEntries.removeWhere(stale);
    final hadPersisted = _entries.any(stale);
    final entry = KnownHostEntry(
      host: h,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      addedAt: DateTime.now(),
    );
    if (persist) {
      _entries.removeWhere(stale);
      _entries.add(entry);
      await _save();
    } else {
      // Accepting a changed key for this session only still drops the old
      // one from memory, otherwise the next check would flag it again.
      if (hadPersisted) {
        _entries.removeWhere(stale);
        await _save();
      }
      _sessionEntries.add(entry);
    }
  }

  Future<void> remove(String host, int port) async {
    if (!_loaded) await load();
    final h = _normHost(host);
    _entries.removeWhere((e) => e.host == h && e.port == port);
    _sessionEntries.removeWhere((e) => e.host == h && e.port == port);
    await _save();
  }

  /// Returns whether to proceed with [host]:[port] presenting [fingerprint].
  Future<bool> verify(
    String host,
    int port,
    String keyType,
    String fingerprint, {
    String? via,
  }) async {
    if (!_loaded) await load();
    final status = check(host, port, keyType, fingerprint);
    if (status == HostKeyStatus.trusted) return true;

    // Several tabs opening the same server at once get one dialog.
    final key = '${_normHost(host)}:$port:$fingerprint';
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _ask(host, port, keyType, fingerprint, status, via);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<bool> _ask(
    String host,
    int port,
    String keyType,
    String fingerprint,
    HostKeyStatus status,
    String? via,
  ) async {
    final ask = prompter;
    if (ask == null) {
      debugPrint('[KnownHosts] No prompter; rejecting ${status.name} key for $host:$port');
      return false;
    }
    String? previous;
    if (status == HostKeyStatus.changed) {
      final h = _normHost(host);
      previous = _all
          .firstWhere((e) => _sameKind(e, h, port, keyType, fingerprint))
          .fingerprint;
    }
    HostKeyDecision decision;
    try {
      decision = await ask(HostKeyPromptRequest(
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
        status: status,
        previousFingerprint: previous,
        via: via,
      ));
    } catch (e) {
      debugPrint('[KnownHosts] Prompt failed for $host:$port: $e');
      return false;
    }
    switch (decision) {
      case HostKeyDecision.trustAlways:
        await trust(host, port, keyType, fingerprint);
        return true;
      case HostKeyDecision.trustOnce:
        await trust(host, port, keyType, fingerprint, persist: false);
        return true;
      case HostKeyDecision.reject:
        return false;
    }
  }

  /// A dartssh2 `onVerifyHostKey` callback for [host]:[port].
  FutureOr<bool> Function(String type, Uint8List fingerprint) handlerFor(
    String host,
    int port, {
    String? via,
  }) {
    return (type, fingerprint) => verify(
          host,
          port,
          type,
          utf8.decode(fingerprint, allowMalformed: true),
          via: via,
        );
  }

  @visibleForTesting
  void resetForTesting({String? filePath}) {
    _filePath = filePath;
    _entries.clear();
    _sessionEntries.clear();
    _inFlight.clear();
    _loading = null;
    _loaded = false;
    prompter = null;
  }
}
