import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/file_explorer_models.dart';
import 'app_log.dart';
import 'ssh_tunnel_manager.dart';

/// An SSH connection to a file explorer target, with the SFTP client when
/// the server offers one and shell commands as the fallback.
class RemoteSession {
  final SSHClient client;
  SftpClient? sftp;
  final SSHClient? jumpClient;
  final String? leaseId;
  final bool isSharedClient;
  final bool isSharedJumpClient;
  final String? feHostname;
  final ExplorerNodeTarget? target;

  RemoteSession({
    required this.client,
    this.sftp,
    this.jumpClient,
    this.leaseId,
    this.isSharedClient = false,
    this.isSharedJumpClient = true,
    this.feHostname,
    this.target,
  });

  Future<Uint8List> run(String cmd) async {
    if (feHostname != null && feHostname!.isNotEmpty) {
      final escaped = cmd.replaceAll("'", "'\\''");
      final feCmd =
          "ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $feHostname '$escaped'";
      return await client.run(feCmd, stderr: false);
    }
    if (await detectTmshShell()) {
      return await _runViaTmshBash(cmd);
    }
    return await client.run(cmd);
  }

  /// Starts [cmd] on an exec channel and returns the live session, so callers
  /// can stream stdin/stdout (for byte-level progress). Applies the same
  /// FE-hop and tmsh wrapping as [run].
  Future<SSHSession> execute(String cmd) async {
    if (feHostname != null && feHostname!.isNotEmpty) {
      final escaped = cmd.replaceAll("'", "'\\''");
      return await client.execute(
        "ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $feHostname '$escaped'",
      );
    }
    if (await detectTmshShell()) {
      await ensureShellAccess();
      final encoded = base64.encode(utf8.encode(cmd));
      return await client.execute(
        'run util bash -c "echo $encoded | base64 -d | bash"',
      );
    }
    return await client.execute(cmd);
  }

  /// Total size in bytes of [path] (file or directory), or -1 if unknown.
  Future<int> sizeOf(String path) async {
    try {
      final out = utf8.decode(
        await run('du -sb "$path" 2>/dev/null | cut -f1'),
        allowMalformed: true,
      );
      return int.tryParse(out.trim().split('\n').last.trim()) ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// Whether the remote login shell is F5 tmsh (null = not probed yet).
  bool? isTmshShell;

  static const _shellProbeMarker = '__NEXUS_SHELL_OK__';
  static final _tmshErrorPattern = RegExp(r'^\s*Syntax Error:', multiLine: true);

  /// Probes the login shell once. F5 BIG-IP users whose shell is tmsh cannot
  /// run POSIX commands (or SFTP) directly; commands must go through
  /// `run util bash -c`.
  Future<bool> detectTmshShell() async {
    final known = isTmshShell;
    if (known != null) return known;
    var tmsh = false;
    try {
      final out = utf8.decode(
        await client.run('echo $_shellProbeMarker'),
        allowMalformed: true,
      );
      tmsh = !out.contains(_shellProbeMarker) && _tmshErrorPattern.hasMatch(out);
    } catch (e, st) {
      AppLog.warning('FileExplorer: tmsh shell probe', e, st);
    }
    isTmshShell = tmsh;
    if (tmsh) {
      // The SFTP subsystem is unusable under tmsh (the channel carries tmsh
      // text instead of SFTP packets), so stop trying it for this session.
      sftp?.close();
      sftp = null;
    }
    return tmsh;
  }

  bool _shellAccessVerified = false;

  /// Under tmsh, verifies that this user may run `run util bash` (F5 roles
  /// without advanced-shell access may not). Throws a clear error instead of
  /// letting callers treat tmsh's refusal text as command output.
  Future<void> ensureShellAccess() async {
    if (_shellAccessVerified || !await detectTmshShell()) return;
    final out = utf8.decode(
      await client
          .run('run util bash -c "echo $_shellProbeMarker"')
          .timeout(const Duration(seconds: 20)),
      allowMalformed: true,
    );
    if (!out.contains(_shellProbeMarker)) {
      final firstLine = out.trim().isEmpty
          ? 'no output'
          : out.trim().split('\n').first.trim();
      throw ShellAccessDeniedException(
        'Bash access denied on this node: the tmsh user is not allowed to '
        'run "run util bash" ($firstLine). File transfer needs bash or SFTP '
        'access.',
      );
    }
    _shellAccessVerified = true;
  }

  Future<Uint8List> _runViaTmshBash(String cmd) async {
    await ensureShellAccess();
    // Base64 keeps the command free of quoting issues in tmsh's parser.
    final encoded = base64.encode(utf8.encode(cmd));
    final out = await client.run(
      'run util bash -c "echo $encoded | base64 -d | bash"',
    );
    final text = utf8.decode(out, allowMalformed: true);
    if (_tmshErrorPattern.hasMatch(text)) {
      final firstLine = text.trim().split('\n').first;
      throw Exception(
        'tmsh shell rejected "run util bash" (bash access required): $firstLine',
      );
    }
    return out;
  }

  void close() {
    if (!isSharedClient) {
      try {
        client.close();
      } catch (e, st) {
        AppLog.warning('FileExplorer: closing SSH client', e, st);
      }
    }
    if (!isSharedJumpClient) {
      try {
        jumpClient?.close();
      } catch (e, st) {
        AppLog.warning('FileExplorer: closing jump client', e, st);
      }
    }
    if (leaseId != null) {
      SshTunnelManager.instance.releaseLease(leaseId!);
    }
  }
}

/// Thrown when a tmsh user may not run `run util bash`.
class ShellAccessDeniedException implements Exception {
  const ShellAccessDeniedException(this.message);
  final String message;
  @override
  String toString() => message;
}
