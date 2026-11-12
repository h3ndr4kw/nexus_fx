import 'dart:io';

import 'imported_host.dart';

/// Reads the `Host` entries of an OpenSSH client config (`~/.ssh/config`).
///
/// Every concrete alias becomes a host; wildcard blocks (`Host *`) only
/// contribute defaults. Options follow OpenSSH's rule that the first value
/// obtained wins. `Include` and `Match` are not followed; they are reported
/// as warnings instead.
class SshConfigParser {
  SshConfigParser._();

  /// Default location: `%USERPROFILE%\.ssh\config` or `$HOME/.ssh/config`.
  static String defaultPath() => '${_home()}${Platform.pathSeparator}.ssh${Platform.pathSeparator}config';

  static String _home() => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';

  static Future<ImportScan> readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return ImportScan(const [], ['$path does not exist.']);
    }
    return parse(await file.readAsString(), home: _home());
  }

  static ImportScan parse(String text, {required String home}) {
    final warnings = <String>[];
    final blocks = <_Block>[_Block(const ['*'], global: true)];
    final aliases = <String>[];
    var inMatch = false;

    final lines = text.split(RegExp(r'\r?\n'));
    for (var n = 0; n < lines.length; n++) {
      final line = lines[n].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final m = RegExp(r'^(\S+?)(?:\s*=\s*|\s+)(.*)$').firstMatch(line);
      if (m == null) continue;
      final keyword = m.group(1)!.toLowerCase();
      final args = _splitArgs(m.group(2)!);
      if (args.isEmpty) continue;

      switch (keyword) {
        case 'host':
          inMatch = false;
          blocks.add(_Block(args));
          for (final p in args) {
            if (!_isPattern(p) && !aliases.contains(p)) aliases.add(p);
          }
        case 'match':
          inMatch = true;
          warnings.add('Line ${n + 1}: "Match" blocks are not supported; their options were ignored.');
        case 'include':
          warnings.add('Line ${n + 1}: "Include ${args.join(' ')}" was not followed; import that file separately.');
        default:
          if (!inMatch) blocks.last.options.putIfAbsent(keyword, () => args);
      }
    }

    String? opt(String alias, String key) {
      for (final b in blocks) {
        if (b.matches(alias) && b.options.containsKey(key)) return b.options[key]!.first;
      }
      return null;
    }

    final hosts = <ImportedHost>[];
    for (final alias in aliases) {
      final notes = <String>[];
      final user = opt(alias, 'user') ?? '';
      final hostName = (opt(alias, 'hostname') ?? alias).replaceAll('%h', alias);
      final port = int.tryParse(opt(alias, 'port') ?? '') ?? 22;
      final identity = opt(alias, 'identityfile');

      ImportedJump? jump;
      final proxyJump = opt(alias, 'proxyjump');
      if (proxyJump != null && proxyJump.toLowerCase() != 'none') {
        final hops = proxyJump.split(',');
        if (hops.length > 1) {
          notes.add('ProxyJump has ${hops.length} hops; NexusFX supports one, so no jump host was set.');
        } else {
          jump = _parseHop(hops.single.trim(), aliases, opt);
        }
      }
      if (opt(alias, 'proxycommand') case final cmd? when cmd.toLowerCase() != 'none') {
        notes.add('ProxyCommand is not supported and was ignored.');
      }

      hosts.add(ImportedHost(
        name: alias,
        host: hostName,
        port: port,
        username: user,
        identityFile: identity == null ? null : _expandPath(identity, home: home, user: user, host: hostName),
        jump: jump,
        notes: notes,
      ));
    }
    return ImportScan(hosts, warnings);
  }

  /// `[user@]host[:port]` or `ssh://[user@]host[:port]`; a host that names
  /// another alias in the file takes that alias's HostName, Port and User.
  static ImportedJump _parseHop(
    String hop,
    List<String> aliases,
    String? Function(String alias, String key) opt,
  ) {
    var s = hop.startsWith('ssh://') ? hop.substring(6) : hop;
    String? user;
    final at = s.lastIndexOf('@');
    if (at >= 0) {
      user = s.substring(0, at);
      s = s.substring(at + 1);
    }
    int? port;
    final colon = s.lastIndexOf(':');
    if (colon > 0 && !s.contains(']')) {
      port = int.tryParse(s.substring(colon + 1));
      if (port != null) s = s.substring(0, colon);
    }
    if (aliases.contains(s)) {
      return ImportedJump(
        alias: s,
        host: (opt(s, 'hostname') ?? s).replaceAll('%h', s),
        port: port ?? int.tryParse(opt(s, 'port') ?? '') ?? 22,
        username: user ?? opt(s, 'user') ?? '',
      );
    }
    return ImportedJump(host: s, port: port ?? 22, username: user ?? '');
  }

  static String _expandPath(String path, {required String home, required String user, required String host}) {
    var p = path.replaceAll('%d', home).replaceAll('%u', user).replaceAll('%h', host).replaceAll('%%', '%');
    if (p == '~' || p.startsWith('~/') || p.startsWith('~\\')) p = home + p.substring(1);
    return p;
  }

  static bool _isPattern(String p) => p.contains('*') || p.contains('?') || p.startsWith('!');

  static List<String> _splitArgs(String s) {
    final out = <String>[];
    for (final m in RegExp(r'"([^"]*)"|(\S+)').allMatches(s)) {
      out.add(m.group(1) ?? m.group(2)!);
    }
    return out;
  }
}

class _Block {
  final List<String> patterns;
  final bool global;
  final Map<String, List<String>> options = {};

  _Block(this.patterns, {this.global = false});

  bool matches(String alias) {
    if (global) return true;
    var hit = false;
    for (final p in patterns) {
      if (p.startsWith('!')) {
        if (_glob(p.substring(1), alias)) return false;
      } else if (_glob(p, alias)) {
        hit = true;
      }
    }
    return hit;
  }

  static bool _glob(String pattern, String s) {
    final re = RegExp(
      '^${RegExp.escape(pattern).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
      caseSensitive: false,
    );
    return re.hasMatch(s);
  }
}
