/// Represents the operation mode of an SSH connection.
enum TunnelMode {
  /// Uses SSH port forwarding channels over an existing master connection.
  multiplexed,

  /// Uses legacy interactive shell hopping (ssh -tt).
  legacyInteractive,
}

/// Identifies a unique master SSH tunnel connection based on host, port, and username.
class TunnelKey {
  final String host;
  final int port;
  final String username;

  const TunnelKey({
    required this.host,
    this.port = 22,
    required this.username,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TunnelKey &&
        other.host == host &&
        other.port == port &&
        other.username == username;
  }

  @override
  int get hashCode => Object.hash(host, port, username);

  @override
  String toString() => 'TunnelKey(host: $host, port: $port, username: $username)';
}

/// Represents an active lease on a forwarded tunnel channel.
class TunnelLease {
  final String id;
  final String targetHost;
  final int targetPort;
  final DateTime createdAt;
  final void Function()? onRelease;

  bool _isActive = true;

  TunnelLease({
    required this.id,
    required this.targetHost,
    this.targetPort = 22,
    DateTime? createdAt,
    this.onRelease,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whether this lease is currently active.
  bool get isActive => _isActive;

  /// Releases this lease and triggers the [onRelease] callback if still active.
  void release() {
    if (!_isActive) return;
    _isActive = false;
    onRelease?.call();
  }

  @override
  String toString() =>
      'TunnelLease(id: $id, targetHost: $targetHost, targetPort: $targetPort, isActive: $_isActive)';
}
