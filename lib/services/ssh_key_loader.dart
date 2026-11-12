import 'dart:io';
import 'dart:isolate';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// A private key a session logs in with: where it is and how to unlock it.
@immutable
class SshPrivateKeyRef {
  const SshPrivateKeyRef(this.path, [this.passphrase]);

  final String path;
  final String? passphrase;

  /// The key to use for a session, or null when it logs in with a password
  /// or has no key file set.
  static SshPrivateKeyRef? of({
    required bool usesKey,
    String? path,
    String? passphrase,
  }) {
    if (!usesKey || path == null || path.trim().isEmpty) return null;
    return SshPrivateKeyRef(path.trim(), passphrase);
  }
}

/// A key file that cannot be used, with a message meant for the user.
class SshKeyLoadException implements Exception {
  const SshKeyLoadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Expands a leading `~` to the user's home folder.
String expandKeyPath(String path) {
  final p = path.trim();
  if (p == '~' || p.startsWith('~/') || p.startsWith(r'~\')) {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    return home + p.substring(1);
  }
  return p;
}

/// Reads and decrypts [key] for dartssh2's `identities`.
///
/// Decryption runs on a background isolate: OpenSSH keys use bcrypt, which
/// takes long enough with a passphrase to freeze the UI.
Future<List<SSHKeyPair>> loadSshIdentities(SshPrivateKeyRef key) async {
  final path = expandKeyPath(key.path);
  final file = File(path);
  if (!await file.exists()) {
    throw SshKeyLoadException('Private key file not found: $path');
  }
  final String pem;
  try {
    pem = await file.readAsString();
  } catch (e) {
    throw SshKeyLoadException('Cannot read private key $path: $e');
  }
  return parseSshIdentities(pem, key.passphrase, source: path);
}

/// Parses [pem] (see [loadSshIdentities]). [source] names it in errors.
Future<List<SSHKeyPair>> parseSshIdentities(
  String pem,
  String? passphrase, {
  String source = 'private key',
}) async {
  if (pem.contains('PuTTY-User-Key-File')) {
    throw SshKeyLoadException(
      '$source is a PuTTY .ppk key. In PuTTYgen choose Conversions > '
      'Export OpenSSH key and use that file instead.',
    );
  }
  if (!pem.contains('-----BEGIN ')) {
    throw SshKeyLoadException('$source is not a PEM/OpenSSH private key.');
  }
  if (pem.contains('-----BEGIN PRIVATE KEY-----') ||
      pem.contains('-----BEGIN ENCRYPTED PRIVATE KEY-----')) {
    throw SshKeyLoadException(
      '$source is in PKCS#8 format, which is not supported. Convert it with '
      '"ssh-keygen -p -f <file>" (rewrites it as an OpenSSH key).',
    );
  }

  final pass = (passphrase == null || passphrase.isEmpty) ? null : passphrase;
  final bool encrypted;
  try {
    encrypted = SSHKeyPair.isEncryptedPem(pem);
  } catch (e) {
    throw SshKeyLoadException('$source could not be parsed: $e');
  }
  if (encrypted && pass == null) {
    throw SshKeyLoadException('$source is protected by a passphrase; enter it in the session properties.');
  }

  try {
    return await Isolate.run(() => SSHKeyPair.fromPem(pem, pass));
  } on SSHKeyDecryptError catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('passphrase')) {
      throw SshKeyLoadException('Wrong passphrase for $source.');
    }
    throw SshKeyLoadException('$source could not be decrypted: $e');
  } on SshKeyLoadException {
    rethrow;
  } catch (e) {
    throw SshKeyLoadException('$source is not a supported key type: $e');
  }
}
