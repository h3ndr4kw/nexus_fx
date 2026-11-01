class NetworkManagerConfig {
  final String host;
  final int port;
  final String username;
  final String password;

  const NetworkManagerConfig({
    this.host = '10.52.19.24',
    this.port = 22,
    this.username = 'vmridwan',
    this.password = '',
  });

  NetworkManagerConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
  }) {
    return NetworkManagerConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
    };
  }

  factory NetworkManagerConfig.fromMap(Map<String, dynamic> map) {
    return NetworkManagerConfig(
      host: map['host'] as String? ?? '10.52.19.24',
      port: (map['port'] is int)
          ? map['port'] as int
          : int.tryParse(map['port']?.toString() ?? '22') ?? 22,
      username: map['username'] as String? ?? 'vmridwan',
      password: map['password'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkManagerConfig &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          password == other.password;

  @override
  int get hashCode =>
      host.hashCode ^ port.hashCode ^ username.hashCode ^ password.hashCode;
}
