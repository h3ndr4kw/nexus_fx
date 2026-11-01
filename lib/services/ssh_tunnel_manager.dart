import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import '../models/network_manager_config.dart';
import '../models/ssh_tunnel_models.dart';

/// Manages SSH master jump host connections and multiplexed port forwarding channels.
///
/// Prevents concurrent connection storms to Network Manager by pooling master
/// SSH clients and tracking active channel leases.
class SshTunnelManager {
  static SshTunnelManager? _instance;

  final Map<TunnelKey, SSHClient> _masterClients = {};
  final Map<TunnelKey, Future<SSHClient>> _inFlightConnections = {};
  final Map<String, SSHClient> _clusterClients = {};
  final Map<String, Future<SSHClient>> _inFlightClusterConnections = {};
  final Map<String, TunnelLease> _activeLeases = {};
  int _leaseCounter = 0;

  @visibleForTesting
  Future<SSHClient> Function(NetworkManagerConfig config)? customClientFactory;

  @visibleForTesting
  Future<SSHClient> Function(
    SSHSocket socket,
    String host,
    String username,
    String password,
  )? customClusterClientFactory;

  SshTunnelManager._();

  /// The singleton instance of [SshTunnelManager].
  static SshTunnelManager get instance {
    _instance ??= SshTunnelManager._();
    return _instance!;
  }

  @visibleForTesting
  static set instance(SshTunnelManager inst) {
    _instance = inst;
  }

  /// The number of currently active master SSHClient connections.
  int get activeMasterConnectionsCount {
    _masterClients.removeWhere((_, client) => client.isClosed);
    return _masterClients.length;
  }

  /// The number of currently active Cluster OAM SSHClient connections.
  int get activeClusterConnectionsCount {
    _clusterClients.removeWhere((_, client) => client.isClosed);
    return _clusterClients.length;
  }

  /// The number of currently active tunnel leases.
  int get activeLeaseCount {
    _activeLeases.removeWhere((_, lease) => !lease.isActive);
    return _activeLeases.length;
  }

  /// Returns an unmodifiable list of active leases.
  List<TunnelLease> get activeLeases =>
      List.unmodifiable(_activeLeases.values.where((l) => l.isActive));

  /// Gets a lease by its identifier, or null if not found.
  TunnelLease? getLease(String leaseId) => _activeLeases[leaseId];

  /// Obtains an authenticated master [SSHClient] for the given [NetworkManagerConfig].
  ///
  /// Reuses existing non-closed connections and deduplicates concurrent connection
  /// attempts to prevent connection storms.
  Future<SSHClient> getMasterClient(NetworkManagerConfig config) async {
    final key = TunnelKey(
      host: config.host,
      port: config.port,
      username: config.username,
    );

    final existing = _masterClients[key];
    if (existing != null && !existing.isClosed) {
      return existing;
    }
    if (existing != null && existing.isClosed) {
      _masterClients.remove(key);
    }

    if (_inFlightConnections.containsKey(key)) {
      return await _inFlightConnections[key]!;
    }

    final future = _connectMaster(config, key);
    _inFlightConnections[key] = future;
    try {
      return await future;
    } finally {
      _inFlightConnections.remove(key);
    }
  }

  Future<SSHClient> _connectMaster(
    NetworkManagerConfig config,
    TunnelKey key,
  ) async {
    try {
      final client = await (customClientFactory != null
          ? customClientFactory!(config)
          : _defaultClientFactory(config));

      // Listen for socket termination to purge stale connection
      client.done.then((_) {
        if (_masterClients[key] == client) {
          _masterClients.remove(key);
        }
      }).catchError((_) {
        if (_masterClients[key] == client) {
          _masterClients.remove(key);
        }
      });

      _masterClients[key] = client;
      return client;
    } catch (e) {
      _masterClients.remove(key);
      rethrow;
    }
  }

  Future<SSHClient> _defaultClientFactory(NetworkManagerConfig config) async {
    final socket = await SSHSocket.connect(
      config.host,
      config.port,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: config.username,
      onPasswordRequest: () => config.password,
      onUserInfoRequest: (r) => r.prompts.map((_) => config.password).toList(),
      keepAliveInterval: const Duration(seconds: 15),
    );
    await client.authenticated;
    return client;
  }

  /// Opens a local port forwarding channel through the master jump host to [targetHost]:[targetPort].
  ///
  /// Automatically registers a [TunnelLease] and closes the lease when the channel is closed.
  Future<SSHForwardChannel> openForwardChannel({
    required NetworkManagerConfig nmConfig,
    required String targetHost,
    int targetPort = 22,
    void Function(TunnelLease lease)? onLeaseCreated,
  }) async {
    final masterClient = await getMasterClient(nmConfig);
    final forwardChannel = await masterClient.forwardLocal(
      targetHost,
      targetPort,
    );

    final leaseId =
        'forward_${targetHost}_${targetPort}_${++_leaseCounter}_${DateTime.now().microsecondsSinceEpoch}';
    late final TunnelLease lease;
    lease = TunnelLease(
      id: leaseId,
      targetHost: targetHost,
      targetPort: targetPort,
      onRelease: () {
        _activeLeases.remove(leaseId);
        try {
          forwardChannel.close();
        } catch (_) {}
      },
    );

    _activeLeases[leaseId] = lease;
    onLeaseCreated?.call(lease);

    forwardChannel.done.then((_) {
      releaseLease(leaseId);
    }).catchError((_) {
      releaseLease(leaseId);
    });

    return forwardChannel;
  }

  /// Creates a mock [TunnelLease] for testing and tracking without opening a real channel.
  TunnelLease createMockLease({
    required String targetHost,
    int targetPort = 22,
    void Function()? onRelease,
  }) {
    final leaseId =
        'mock_lease_${++_leaseCounter}_${DateTime.now().microsecondsSinceEpoch}';
    late final TunnelLease lease;
    lease = TunnelLease(
      id: leaseId,
      targetHost: targetHost,
      targetPort: targetPort,
      onRelease: () {
        _activeLeases.remove(leaseId);
        onRelease?.call();
      },
    );
    _activeLeases[leaseId] = lease;
    return lease;
  }

  /// Creates a tracked [TunnelLease] for an active session or hop on a multiplexed client.
  TunnelLease createSessionLease({
    required String targetHost,
    int targetPort = 22,
    void Function()? onRelease,
  }) {
    final leaseId =
        'session_${targetHost}_${targetPort}_${++_leaseCounter}_${DateTime.now().microsecondsSinceEpoch}';
    late final TunnelLease lease;
    lease = TunnelLease(
      id: leaseId,
      targetHost: targetHost,
      targetPort: targetPort,
      onRelease: () {
        _activeLeases.remove(leaseId);
        onRelease?.call();
      },
    );
    _activeLeases[leaseId] = lease;
    return lease;
  }

  /// Releases the lease with the given [leaseId] and triggers its release callback.
  void releaseLease(String leaseId) {
    final lease = _activeLeases.remove(leaseId);
    if (lease != null && lease.isActive) {
      lease.release();
    }
  }

  /// Generates a cache key for a cluster OAM node based on its host and username.
  String getClusterKey(String oamHost, String username) => '$username@$oamHost';

  /// Obtains an authenticated [SSHClient] connected to the cluster OAM node.
  ///
  /// The connection is tunneled through the Network Manager master client:
  /// Local -> Network Manager -> Cluster OAM (port 22).
  ///
  /// If [fallbackOamHost] is provided and connection to [oamHost] fails,
  /// automatic failover connects to [fallbackOamHost] instead.
  Future<SSHClient> getClusterOamClient({
    required NetworkManagerConfig nmConfig,
    required String oamHost,
    String? fallbackOamHost,
    required String username,
    required String password,
  }) async {
    final primaryKey = getClusterKey(oamHost, username);
    final existingPrimary = _clusterClients[primaryKey];
    if (existingPrimary != null && !existingPrimary.isClosed) {
      return existingPrimary;
    }
    if (existingPrimary != null && existingPrimary.isClosed) {
      _clusterClients.remove(primaryKey);
    }

    if (fallbackOamHost != null && fallbackOamHost.isNotEmpty) {
      final fallbackKey = getClusterKey(fallbackOamHost, username);
      final existingFallback = _clusterClients[fallbackKey];
      if (existingFallback != null && !existingFallback.isClosed) {
        return existingFallback;
      }
      if (existingFallback != null && existingFallback.isClosed) {
        _clusterClients.remove(fallbackKey);
      }
    }

    if (_inFlightClusterConnections.containsKey(primaryKey)) {
      return await _inFlightClusterConnections[primaryKey]!;
    }

    final future = _connectClusterOam(
      nmConfig: nmConfig,
      oamHost: oamHost,
      fallbackOamHost: fallbackOamHost,
      username: username,
      password: password,
    );
    _inFlightClusterConnections[primaryKey] = future;
    try {
      return await future;
    } finally {
      _inFlightClusterConnections.remove(primaryKey);
    }
  }

  /// Obtains an authenticated [SSHClient] connected to a specific cluster OAM node.
  /// Does not attempt any fallback if connection fails.
  Future<SSHClient> getSpecificOamClient({
    required NetworkManagerConfig nmConfig,
    required String host,
    required String username,
    required String password,
  }) async {
    final key = getClusterKey(host, username);
    final existing = _clusterClients[key];
    if (existing != null && !existing.isClosed) {
      return existing;
    }
    if (existing != null && existing.isClosed) {
      _clusterClients.remove(key);
    }

    final masterClient = await getMasterClient(nmConfig);
    return await _connectToSingleOam(
      masterClient: masterClient,
      host: host,
      username: username,
      password: password,
    );
  }

  Future<SSHClient> _connectClusterOam({
    required NetworkManagerConfig nmConfig,
    required String oamHost,
    String? fallbackOamHost,
    required String username,
    required String password,
  }) async {
    final masterClient = await getMasterClient(nmConfig);

    try {
      return await _connectToSingleOam(
        masterClient: masterClient,
        host: oamHost,
        username: username,
        password: password,
      );
    } catch (primaryError) {
      if (fallbackOamHost != null &&
          fallbackOamHost.isNotEmpty &&
          fallbackOamHost != oamHost) {
        try {
          return await _connectToSingleOam(
            masterClient: masterClient,
            host: fallbackOamHost,
            username: username,
            password: password,
          );
        } catch (fallbackError) {
          throw Exception(
            'Failed to connect to cluster OAM at $oamHost ($primaryError) and fallback $fallbackOamHost ($fallbackError)',
          );
        }
      }
      rethrow;
    }
  }

  Future<SSHClient> _connectToSingleOam({
    required SSHClient masterClient,
    required String host,
    required String username,
    required String password,
  }) async {
    final key = getClusterKey(host, username);
    final channel = await masterClient.forwardLocal(host, 22);
    try {
      final client = await (customClusterClientFactory != null
          ? customClusterClientFactory!(channel, host, username, password)
          : _defaultClusterClientFactory(channel, username, password));

      client.done.then((_) {
        if (_clusterClients[key] == client) {
          _clusterClients.remove(key);
        }
      }).catchError((_) {
        if (_clusterClients[key] == client) {
          _clusterClients.remove(key);
        }
      });

      _clusterClients[key] = client;
      return client;
    } catch (e) {
      try {
        channel.close();
      } catch (_) {}
      _clusterClients.remove(key);
      rethrow;
    }
  }

  Future<SSHClient> _defaultClusterClientFactory(
    SSHSocket socket,
    String username,
    String password,
  ) async {
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
      onUserInfoRequest: (r) => r.prompts.map((_) => password).toList(),
      keepAliveInterval: const Duration(seconds: 15),
    );
    await client.authenticated;
    return client;
  }

  /// Opens a chained local port forwarding channel to an FE node through NM and Cluster OAM:
  /// Local -> Network Manager -> Cluster OAM -> FE Node ([feHost]:[fePort]).
  ///
  /// Automatically registers a [TunnelLease] and closes the lease when the channel is closed.
  Future<SSHForwardChannel> openChainedFeChannel({
    required NetworkManagerConfig nmConfig,
    required String oamHost,
    String? fallbackOamHost,
    required String oamUsername,
    required String oamPassword,
    required String feHost,
    int fePort = 22,
    void Function(TunnelLease lease)? onLeaseCreated,
  }) async {
    final oamClient = await getClusterOamClient(
      nmConfig: nmConfig,
      oamHost: oamHost,
      fallbackOamHost: fallbackOamHost,
      username: oamUsername,
      password: oamPassword,
    );

    final forwardChannel = await oamClient.forwardLocal(
      feHost,
      fePort,
    );

    final leaseId =
        'chained_${feHost}_${fePort}_${++_leaseCounter}_${DateTime.now().microsecondsSinceEpoch}';
    late final TunnelLease lease;
    lease = TunnelLease(
      id: leaseId,
      targetHost: feHost,
      targetPort: fePort,
      onRelease: () {
        _activeLeases.remove(leaseId);
        try {
          forwardChannel.close();
        } catch (_) {}
      },
    );

    _activeLeases[leaseId] = lease;
    onLeaseCreated?.call(lease);

    forwardChannel.done.then((_) {
      releaseLease(leaseId);
    }).catchError((_) {
      releaseLease(leaseId);
    });

    return forwardChannel;
  }

  /// Disconnects and purges all pooled master clients, cluster clients, in-flight handshakes, and active leases.
  Future<void> disconnectAll() async {
    customClientFactory = null;
    customClusterClientFactory = null;

    final leases = _activeLeases.values.toList();
    _activeLeases.clear();
    for (final lease in leases) {
      try {
        lease.release();
      } catch (_) {}
    }

    final clusterClients = _clusterClients.values.toList();
    _clusterClients.clear();
    _inFlightClusterConnections.clear();
    for (final client in clusterClients) {
      try {
        client.close();
      } catch (_) {}
    }

    final clients = _masterClients.values.toList();
    _masterClients.clear();
    _inFlightConnections.clear();

    for (final client in clients) {
      try {
        client.close();
      } catch (_) {}
    }
  }
}
