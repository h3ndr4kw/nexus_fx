import 'package:flutter/material.dart';
import 'ssh_tunnel_models.dart';
import '../services/crypto_vault_service.dart';

enum SessionProtocol {
  ssh,
  local,
}

enum SessionEnvironment {
  dev,
  staging,
  prod;

  String get label {
    switch (this) {
      case SessionEnvironment.dev:
        return 'DEV';
      case SessionEnvironment.staging:
        return 'STAGING';
      case SessionEnvironment.prod:
        return 'PROD';
    }
  }

  bool get isProduction => this == SessionEnvironment.prod;

  Color get color {
    switch (this) {
      case SessionEnvironment.dev:
        return const Color(0xFF06B6D4); // Cyan
      case SessionEnvironment.staging:
        return const Color(0xFFF59E0B); // Amber
      case SessionEnvironment.prod:
        return const Color(0xFFEF4444); // Crimson Red
    }
  }
}

enum AuthMethod {
  password,
  privateKey,
}

enum JumpHostMode {
  direct,
  existingSession,
  customJumpHost,
}

/// Secure credential encoder/decoder delegating to AES-256 CryptoVaultService
/// with seamless backward-compatible decoding of legacy XOR payloads.
class _Obfuscator {
  static String encode(String raw) => CryptoVaultService.instance.encrypt(raw);
  static String decode(String encoded) => CryptoVaultService.instance.decrypt(encoded);
}

class SessionFolder {
  final String id;
  final String? parentId;
  final String name;
  final String description;
  final DateTime modifiedAt;

  const SessionFolder({
    required this.id,
    this.parentId,
    required this.name,
    this.description = '',
    required this.modifiedAt,
  });

  SessionFolder copyWith({
    String? id,
    String? parentId,
    bool clearParentId = false,
    String? name,
    String? description,
    DateTime? modifiedAt,
  }) {
    return SessionFolder(
      id: id ?? this.id,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      name: name ?? this.name,
      description: description ?? this.description,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'name': name,
      'description': description,
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }

  factory SessionFolder.fromJson(Map<String, dynamic> json) {
    return SessionFolder(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      name: json['name'] as String? ?? 'New Folder',
      description: json['description'] as String? ?? '',
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.tryParse(json['modifiedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class SessionProfile {
  final String id;
  final String? parentId;
  final String name;
  final SessionProtocol protocol;
  final SessionEnvironment environment;

  // Connection
  final String host;
  final int port;
  final String? fallbackHost;
  final String sshMacs;
  final String customSshOptions;
  final String description;
  final bool autoReconnect;
  final int reconnectIntervalSec;
  final int reconnectLimitMin;

  // Authentication
  final String username;
  final AuthMethod authMethod;
  final String password;
  final String? privateKeyPath;
  final String? privateKeyPassphrase;
  final String loginScript;

  // SSH -> Tunneling
  final JumpHostMode jumpHostMode;
  final String? jumpSessionId;
  final String? customJumpHost;
  final int customJumpPort;
  final String? customJumpFallbackHost;
  final String? customJumpUsername;
  final String? customJumpPassword;
  final TunnelMode tunnelMode;

  // Terminal & Appearance
  final String? customThemeName;
  final double? customFontSize;
  final int scrollbackLines;

  // Logging
  final bool enableSessionLogging;

  final DateTime modifiedAt;

  bool get isLocal => protocol == SessionProtocol.local;

  const SessionProfile({
    required this.id,
    this.parentId,
    required this.name,
    this.protocol = SessionProtocol.ssh,
    this.environment = SessionEnvironment.dev,
    this.host = '',
    this.port = 22,
    this.fallbackHost,
    this.sshMacs = 'auto',
    this.customSshOptions = '',
    this.description = '',
    this.autoReconnect = false,
    this.reconnectIntervalSec = 30,
    this.reconnectLimitMin = 0,
    this.username = '',
    this.authMethod = AuthMethod.password,
    this.password = '',
    this.privateKeyPath,
    this.privateKeyPassphrase,
    this.loginScript = '',
    this.jumpHostMode = JumpHostMode.direct,
    this.jumpSessionId,
    this.customJumpHost,
    this.customJumpPort = 22,
    this.customJumpFallbackHost,
    this.customJumpUsername,
    this.customJumpPassword,
    this.tunnelMode = TunnelMode.multiplexed,
    this.customThemeName,
    this.customFontSize,
    this.scrollbackLines = 5000,
    this.enableSessionLogging = true,
    required this.modifiedAt,
  });

  SessionProfile copyWith({
    String? id,
    String? parentId,
    bool clearParentId = false,
    String? name,
    SessionProtocol? protocol,
    SessionEnvironment? environment,
    String? host,
    int? port,
    String? fallbackHost,
    bool clearFallbackHost = false,
    String? sshMacs,
    String? customSshOptions,
    String? description,
    bool? autoReconnect,
    int? reconnectIntervalSec,
    int? reconnectLimitMin,
    String? username,
    AuthMethod? authMethod,
    String? password,
    String? privateKeyPath,
    String? privateKeyPassphrase,
    String? loginScript,
    JumpHostMode? jumpHostMode,
    String? jumpSessionId,
    bool clearJumpSessionId = false,
    String? customJumpHost,
    int? customJumpPort,
    String? customJumpFallbackHost,
    String? customJumpUsername,
    String? customJumpPassword,
    TunnelMode? tunnelMode,
    String? customThemeName,
    double? customFontSize,
    int? scrollbackLines,
    bool? enableSessionLogging,
    DateTime? modifiedAt,
  }) {
    return SessionProfile(
      id: id ?? this.id,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      environment: environment ?? this.environment,
      host: host ?? this.host,
      port: port ?? this.port,
      fallbackHost: clearFallbackHost ? null : (fallbackHost ?? this.fallbackHost),
      sshMacs: sshMacs ?? this.sshMacs,
      customSshOptions: customSshOptions ?? this.customSshOptions,
      description: description ?? this.description,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      reconnectIntervalSec: reconnectIntervalSec ?? this.reconnectIntervalSec,
      reconnectLimitMin: reconnectLimitMin ?? this.reconnectLimitMin,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      password: password ?? this.password,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      privateKeyPassphrase: privateKeyPassphrase ?? this.privateKeyPassphrase,
      loginScript: loginScript ?? this.loginScript,
      jumpHostMode: jumpHostMode ?? this.jumpHostMode,
      jumpSessionId: clearJumpSessionId ? null : (jumpSessionId ?? this.jumpSessionId),
      customJumpHost: customJumpHost ?? this.customJumpHost,
      customJumpPort: customJumpPort ?? this.customJumpPort,
      customJumpFallbackHost: customJumpFallbackHost ?? this.customJumpFallbackHost,
      customJumpUsername: customJumpUsername ?? this.customJumpUsername,
      customJumpPassword: customJumpPassword ?? this.customJumpPassword,
      tunnelMode: tunnelMode ?? this.tunnelMode,
      customThemeName: customThemeName ?? this.customThemeName,
      customFontSize: customFontSize ?? this.customFontSize,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
      enableSessionLogging: enableSessionLogging ?? this.enableSessionLogging,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'name': name,
      'protocol': protocol.name,
      'environment': environment.name,
      'host': host,
      'port': port,
      'fallbackHost': fallbackHost,
      'sshMacs': sshMacs,
      'customSshOptions': customSshOptions,
      'description': description,
      'autoReconnect': autoReconnect,
      'reconnectIntervalSec': reconnectIntervalSec,
      'reconnectLimitMin': reconnectLimitMin,
      'username': username,
      'authMethod': authMethod.name,
      'password': _Obfuscator.encode(password),
      'privateKeyPath': privateKeyPath,
      'privateKeyPassphrase': privateKeyPassphrase != null ? _Obfuscator.encode(privateKeyPassphrase!) : null,
      'loginScript': loginScript,
      'jumpHostMode': jumpHostMode.name,
      'jumpSessionId': jumpSessionId,
      'customJumpHost': customJumpHost,
      'customJumpPort': customJumpPort,
      'customJumpFallbackHost': customJumpFallbackHost,
      'customJumpUsername': customJumpUsername,
      'customJumpPassword': customJumpPassword != null ? _Obfuscator.encode(customJumpPassword!) : null,
      'tunnelMode': tunnelMode.name,
      'customThemeName': customThemeName,
      'customFontSize': customFontSize,
      'scrollbackLines': scrollbackLines,
      'enableSessionLogging': enableSessionLogging,
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }

  factory SessionProfile.fromJson(Map<String, dynamic> json) {
    return SessionProfile(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      name: json['name'] as String? ?? 'New Session',
      protocol: SessionProtocol.values.firstWhere(
        (e) => e.name == json['protocol'],
        orElse: () => SessionProtocol.ssh,
      ),
      environment: json['environment'] != null
          ? SessionEnvironment.values.firstWhere(
              (e) => e.name == json['environment'],
              orElse: () => SessionEnvironment.dev,
            )
          : SessionEnvironment.dev,
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      fallbackHost: json['fallbackHost'] as String?,
      sshMacs: json['sshMacs'] as String? ?? 'auto',
      customSshOptions: json['customSshOptions'] as String? ?? '',
      description: json['description'] as String? ?? '',
      autoReconnect: json['autoReconnect'] as bool? ?? false,
      reconnectIntervalSec: (json['reconnectIntervalSec'] as num?)?.toInt() ?? 30,
      reconnectLimitMin: (json['reconnectLimitMin'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      authMethod: AuthMethod.values.firstWhere(
        (e) => e.name == json['authMethod'],
        orElse: () => AuthMethod.password,
      ),
      password: _Obfuscator.decode(json['password'] as String? ?? ''),
      privateKeyPath: json['privateKeyPath'] as String?,
      privateKeyPassphrase: json['privateKeyPassphrase'] != null
          ? _Obfuscator.decode(json['privateKeyPassphrase'] as String)
          : null,
      loginScript: json['loginScript'] as String? ?? '',
      jumpHostMode: JumpHostMode.values.firstWhere(
        (e) => e.name == json['jumpHostMode'],
        orElse: () => JumpHostMode.direct,
      ),
      jumpSessionId: json['jumpSessionId'] as String?,
      customJumpHost: json['customJumpHost'] as String?,
      customJumpPort: (json['customJumpPort'] as num?)?.toInt() ?? 22,
      customJumpFallbackHost: json['customJumpFallbackHost'] as String?,
      customJumpUsername: json['customJumpUsername'] as String?,
      customJumpPassword: json['customJumpPassword'] != null
          ? _Obfuscator.decode(json['customJumpPassword'] as String)
          : null,
      tunnelMode: TunnelMode.values.firstWhere(
        (e) => e.name == json['tunnelMode'],
        orElse: () => TunnelMode.multiplexed,
      ),
      customThemeName: json['customThemeName'] as String?,
      customFontSize: (json['customFontSize'] as num?)?.toDouble(),
      scrollbackLines: (json['scrollbackLines'] as num?)?.toInt() ?? 5000,
      enableSessionLogging: json['enableSessionLogging'] as bool? ?? true,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.tryParse(json['modifiedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
