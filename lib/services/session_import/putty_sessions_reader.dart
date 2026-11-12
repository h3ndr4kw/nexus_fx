import 'dart:io';

import 'imported_host.dart';

/// Reads PuTTY's saved sessions from the Windows registry
/// (`HKCU\Software\SimonTatham\PuTTY\Sessions`).
///
/// Only SSH sessions are imported. PuTTY does not store passwords, so none
/// are imported. PuTTY's SSH proxy (Connection > Proxy, type "SSH") becomes
/// the jump host.
class PuttySessionsReader {
  PuttySessionsReader._();

  static const registryKey = r'HKCU\Software\SimonTatham\PuTTY\Sessions';

  static bool get supported => Platform.isWindows;

  static Future<ImportScan> readRegistry() async {
    if (!supported) return const ImportScan([], ['PuTTY sessions are only read on Windows.']);
    final ProcessResult r;
    try {
      r = await Process.run('reg', ['query', registryKey, '/s']);
    } on ProcessException catch (e) {
      return ImportScan(const [], ['Could not run reg.exe: ${e.message}']);
    }
    if (r.exitCode != 0) {
      return const ImportScan([], ['No PuTTY saved sessions were found in the registry.']);
    }
    return parseRegQuery(r.stdout as String);
  }

  /// Parses the output of `reg query <registryKey> /s`.
  static ImportScan parseRegQuery(String output) {
    final sessions = <String, Map<String, String>>{};
    Map<String, String>? current;
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      if (raw.trim().isEmpty) continue;
      if (raw.startsWith('HKEY_')) {
        final i = raw.toLowerCase().indexOf(r'\sessions\');
        current = i < 0 ? null : (sessions[raw.substring(i + r'\sessions\'.length)] = {});
        continue;
      }
      final m = RegExp(r'^\s+(\S+)\s+(REG_\w+)\s*(.*)$').firstMatch(raw);
      if (m == null || current == null) continue;
      var value = m.group(3)!;
      if (m.group(2) == 'REG_DWORD') {
        value = (int.tryParse(value.replaceFirst(RegExp('^0x', caseSensitive: false), ''), radix: 16) ?? 0)
            .toString();
      }
      current[m.group(1)!] = value;
    }

    final hosts = <ImportedHost>[];
    final warnings = <String>[];
    for (final e in sessions.entries) {
      final name = Uri.decodeComponent(e.key);
      if (name == 'Default Settings') continue;
      final v = e.value;
      final protocol = v['Protocol'] ?? 'ssh';
      if (protocol != 'ssh') {
        warnings.add('"$name" uses $protocol, not SSH; skipped.');
        continue;
      }

      var host = v['HostName'] ?? '';
      var user = v['UserName'] ?? '';
      final at = host.lastIndexOf('@');
      if (at >= 0) {
        if (user.isEmpty) user = host.substring(0, at);
        host = host.substring(at + 1);
      }
      if (host.isEmpty) {
        warnings.add('"$name" has no host name; skipped.');
        continue;
      }

      final notes = <String>[];
      final key = v['PublicKeyFile'] ?? '';
      if (key.toLowerCase().endsWith('.ppk')) {
        notes.add('Key is a PuTTY .ppk file; convert it in PuTTYgen (Conversions > Export OpenSSH key) '
            'and point the session at the exported file.');
      }

      ImportedJump? jump;
      final proxyMethod = int.tryParse(v['ProxyMethod'] ?? '') ?? 0;
      final proxyHost = v['ProxyHost'] ?? '';
      if (proxyMethod == 6 && proxyHost.isNotEmpty) {
        jump = ImportedJump(
          host: proxyHost,
          port: int.tryParse(v['ProxyPort'] ?? '') ?? 22,
          username: v['ProxyUsername'] ?? '',
        );
      } else if (proxyMethod != 0) {
        notes.add('PuTTY proxy type $proxyMethod is not supported and was ignored.');
      }

      hosts.add(ImportedHost(
        name: name,
        host: host,
        port: int.tryParse(v['PortNumber'] ?? '') ?? 22,
        username: user,
        identityFile: key.isEmpty ? null : key,
        jump: jump,
        notes: notes,
      ));
    }
    hosts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ImportScan(hosts, warnings);
  }
}
