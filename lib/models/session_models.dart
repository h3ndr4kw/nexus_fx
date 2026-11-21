import 'ssh_tunnel_models.dart';
import '../services/app_log.dart';
import '../services/crypto_vault_service.dart';

enum SessionProtocol {
  ssh,
  local,
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
/// with backward-compatible decoding of legacy XOR payloads.
class _Obfuscator {
  static String encode(String raw) => CryptoVaultService.instance.encrypt(raw);

  /// Decodes the stored [field] of a session. A value that cannot be
  /// decrypted becomes empty, so the rest of the session still loads and the
  /// ciphertext is never offered to a server as the password.
  static String decode(String encoded, {required String field}) {
    try {
      return CryptoVaultService.instance.decrypt(encoded);
    } on VaultDecryptException catch (e) {
      AppLog.error('SessionProfile.$field', e);
      return '';
    }
  }
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

/// Terminal scrollback for a session when the profile does not override it.
const int kDefaultScrollbackLines = 10000;

/// Bounds applied when a terminal is created, so a typo cannot exhaust memory.
const int kMinScrollbackLines = 500;
const int kMaxScrollbackLines = 200000;

/// The default before 10000. The value was saved with every profile while it
/// had no effect, so a stored 5000 means "default", not a user choice.
const int _legacyDefaultScrollbackLines = 5000;

class SessionProfile {
  final String id;
  final String? parentId;
  final String name;
  final SessionProtocol protocol;

  // Connection
  final String host;
  final int port;
  final String? fallbackHost;
  final String sshMacs;
  final String customSshOptions;
  final String description;
  /// Shows the "WEB" action for this session in the quick-connect palette.
  final bool webEnabled;
  /// Management web UI address. Empty means `https://<host>`.
  final String webUrl;
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

  /// URL opened by the "WEB" action, or null when there is nothing to open.
  /// A bare host or `host:port` in [webUrl] is given an `https://` scheme.
  String? get resolvedWebUrl {
    if (isLocal || !webEnabled) return null;
    final raw = webUrl.trim().isNotEmpty ? webUrl.trim() : host.trim();
    if (raw.isEmpty) return null;
    final withScheme = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.toString();
  }

  /// [resolvedWebUrl] followed by the same URL pointed at [fallbackHost],
  /// tried in order like the SSH fallback. A Web URL that names a different
  /// host than [host] gets no fallback, since the swap would be a guess.
  List<String> get webUrlCandidates {
    final primary = resolvedWebUrl;
    if (primary == null) return const [];
    final fb = fallbackHost?.trim() ?? '';
    final uri = Uri.parse(primary);
    if (fb.isEmpty || uri.host != host.trim()) return [primary];
    final alt = uri.replace(host: fb).toString();
    return alt == primary ? [primary] : [primary, alt];
  }

  /// The browser runs on this PC, so a target only reachable through a jump
  /// host cannot be opened directly unless an explicit [webUrl] is set.
  bool get canOpenWeb =>
      resolvedWebUrl != null &&
      (jumpHostMode == JumpHostMode.direct || webUrl.trim().isNotEmpty);

  const SessionProfile({
    required this.id,
    this.parentId,
    required this.name,
    this.protocol = SessionProtocol.ssh,
    this.host = '',
    this.port = 22,
    this.fallbackHost,
    this.sshMacs = 'auto',
    this.customSshOptions = '',
    this.description = '',
    this.webEnabled = false,
    this.webUrl = '',
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
    this.scrollbackLines = kDefaultScrollbackLines,
    this.enableSessionLogging = true,
    required this.modifiedAt,
  });

  SessionProfile copyWith({
    String? id,
    String? parentId,
    bool clearParentId = false,
    String? name,
    SessionProtocol? protocol,
    String? host,
    int? port,
    String? fallbackHost,
    bool clearFallbackHost = false,
    String? sshMacs,
    String? customSshOptions,
    String? description,
    bool? webEnabled,
    String? webUrl,
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
      host: host ?? this.host,
      port: port ?? this.port,
      fallbackHost: clearFallbackHost ? null : (fallbackHost ?? this.fallbackHost),
      sshMacs: sshMacs ?? this.sshMacs,
      customSshOptions: customSshOptions ?? this.customSshOptions,
      description: description ?? this.description,
      webEnabled: webEnabled ?? this.webEnabled,
      webUrl: webUrl ?? this.webUrl,
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
      'host': host,
      'port': port,
      'fallbackHost': fallbackHost,
      'sshMacs': sshMacs,
      'customSshOptions': customSshOptions,
      'description': description,
      'webEnabled': webEnabled,
      'webUrl': webUrl,
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
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      fallbackHost: json['fallbackHost'] as String?,
      sshMacs: json['sshMacs'] as String? ?? 'auto',
      customSshOptions: json['customSshOptions'] as String? ?? '',
      description: json['description'] as String? ?? '',
      webEnabled: json['webEnabled'] as bool? ?? false,
      webUrl: json['webUrl'] as String? ?? '',
      autoReconnect: json['autoReconnect'] as bool? ?? false,
      reconnectIntervalSec: (json['reconnectIntervalSec'] as num?)?.toInt() ?? 30,
      reconnectLimitMin: (json['reconnectLimitMin'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      authMethod: AuthMethod.values.firstWhere(
        (e) => e.name == json['authMethod'],
        orElse: () => AuthMethod.password,
      ),
      password: _Obfuscator.decode(json['password'] as String? ?? '', field: 'password'),
      privateKeyPath: json['privateKeyPath'] as String?,
      privateKeyPassphrase: json['privateKeyPassphrase'] != null
          ? _Obfuscator.decode(json['privateKeyPassphrase'] as String, field: 'privateKeyPassphrase')
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
          ? _Obfuscator.decode(json['customJumpPassword'] as String, field: 'customJumpPassword')
          : null,
      tunnelMode: TunnelMode.values.firstWhere(
        (e) => e.name == json['tunnelMode'],
        orElse: () => TunnelMode.multiplexed,
      ),
      customThemeName: json['customThemeName'] as String?,
      customFontSize: (json['customFontSize'] as num?)?.toDouble(),
      scrollbackLines: switch ((json['scrollbackLines'] as num?)?.toInt()) {
        null || _legacyDefaultScrollbackLines => kDefaultScrollbackLines,
        final int n => n,
      },
      enableSessionLogging: json['enableSessionLogging'] as bool? ?? true,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.tryParse(json['modifiedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
