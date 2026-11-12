import '../../models/session_models.dart';
import '../session_manager_service.dart';

/// The hop a host is reached through, as written in the source config.
class ImportedJump {
  /// Name of another host in the same source, when the hop refers to one.
  final String? alias;
  final String host;
  final int port;
  final String username;

  const ImportedJump({this.alias, required this.host, this.port = 22, this.username = ''});

  String get label => '${username.isEmpty ? '' : '$username@'}$host${port == 22 ? '' : ':$port'}';
}

/// One host read from an OpenSSH config or a PuTTY saved session.
class ImportedHost {
  final String name;
  final String host;
  final int port;
  final String username;
  final String? identityFile;
  final ImportedJump? jump;

  /// Things the user should know about this host (e.g. a .ppk key).
  final List<String> notes;

  const ImportedHost({
    required this.name,
    required this.host,
    this.port = 22,
    this.username = '',
    this.identityFile,
    this.jump,
    this.notes = const [],
  });

  String get target => '${username.isEmpty ? '' : '$username@'}$host${port == 22 ? '' : ':$port'}';
}

/// What a source yielded: the hosts plus warnings that apply to the whole
/// source (unsupported directives, unreadable registry, ...).
class ImportScan {
  final List<ImportedHost> hosts;
  final List<String> warnings;

  const ImportScan(this.hosts, [this.warnings = const []]);
}

/// Turns imported hosts into saved sessions.
class SessionImporter {
  SessionImporter._();

  /// True when a session with the same host, port and user is already saved.
  static bool isDuplicate(ImportedHost h, Iterable<SessionProfile> existing) => existing.any(
        (s) =>
            s.protocol == SessionProtocol.ssh &&
            s.host.toLowerCase() == h.host.toLowerCase() &&
            s.port == h.port &&
            s.username == h.username,
      );

  /// Saves [hosts] into a new folder named [folderName] and returns the
  /// created sessions.
  ///
  /// A jump hop that names another host in this batch, or matches a session
  /// that is already saved, links to that session so its key and password
  /// are reused; any other hop becomes a custom jump host.
  static Future<List<SessionProfile>> commit(
    SessionManagerService mgr,
    List<ImportedHost> hosts, {
    required String folderName,
    String? parentId,
  }) async {
    if (hosts.isEmpty) return const [];
    final existing = List<SessionProfile>.of(mgr.sessions);
    final folder = await mgr.createFolder(
      name: folderName,
      parentId: parentId,
      description: 'Imported ${DateTime.now().toIso8601String().substring(0, 10)}',
    );

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ids = <String, String>{
      for (var i = 0; i < hosts.length; i++) hosts[i].name: 'sess_import_${stamp}_$i',
    };

    final created = <SessionProfile>[];
    for (final h in hosts) {
      final key = h.identityFile;
      var profile = SessionProfile(
        id: ids[h.name]!,
        parentId: folder.id,
        name: h.name,
        host: h.host,
        port: h.port,
        username: h.username,
        authMethod: key != null ? AuthMethod.privateKey : AuthMethod.password,
        privateKeyPath: key,
        description: h.notes.join(' '),
        modifiedAt: DateTime.now(),
      );

      final jump = h.jump;
      if (jump != null) {
        final hop = ImportedHost(name: '', host: jump.host, port: jump.port, username: jump.username);
        bool sameTarget(ImportedHost o) =>
            o.host.toLowerCase() == hop.host.toLowerCase() && o.port == hop.port && o.username == hop.username;
        final inBatch = jump.alias != null
            ? ids[jump.alias]
            : ids[hosts.where((o) => o != h && sameTarget(o)).firstOrNull?.name];
        final saved = existing.where((s) => isDuplicate(hop, [s]));
        final linkId = inBatch ?? saved.firstOrNull?.id;
        profile = linkId != null
            ? profile.copyWith(jumpHostMode: JumpHostMode.existingSession, jumpSessionId: linkId)
            : profile.copyWith(
                jumpHostMode: JumpHostMode.customJumpHost,
                customJumpHost: jump.host,
                customJumpPort: jump.port,
                customJumpUsername: jump.username.isEmpty ? null : jump.username,
              );
      }
      created.add(await mgr.createSession(profile));
    }
    return created;
  }
}
