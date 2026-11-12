import 'package:dartssh2/dartssh2.dart';

class SshAlgorithmHelper {
  static const List<String> availableMacOptions = [
    'auto',
    'hmac-sha1',
    'hmac-sha2-256',
    'hmac-sha2-512',
    'hmac-sha2-256-etm@openssh.com',
    'hmac-sha2-512-etm@openssh.com',
    'hmac-sha2-256-96',
    'hmac-sha2-512-96',
    'hmac-md5',
  ];

  static const List<SSHKexType> allKex = [
    SSHKexType.x25519Rfc,
    SSHKexType.x25519,
    SSHKexType.nistp521,
    SSHKexType.nistp384,
    SSHKexType.nistp256,
    SSHKexType.dhGexSha256,
    SSHKexType.dh14Sha256,
    SSHKexType.dhGexSha1,
    SSHKexType.dh14Sha1,
    SSHKexType.dh1Sha1,
  ];

  static const List<SSHHostkeyType> allHostkeys = [
    SSHHostkeyType.ed25519,
    SSHHostkeyType.rsaSha512,
    SSHHostkeyType.rsaSha256,
    SSHHostkeyType.ecdsa521,
    SSHHostkeyType.ecdsa384,
    SSHHostkeyType.ecdsa256,
    SSHHostkeyType.rsaSha1,
  ];

  static const List<SSHCipherType> allCiphers = [
    SSHCipherType.aes256gcm,
    SSHCipherType.aes128gcm,
    SSHCipherType.chacha20poly1305,
    SSHCipherType.aes256ctr,
    SSHCipherType.aes192ctr,
    SSHCipherType.aes128ctr,
    SSHCipherType.aes256cbc,
    SSHCipherType.aes192cbc,
    SSHCipherType.aes128cbc,
  ];

  static const List<SSHMacType> allMacs = [
    SSHMacType.hmacSha256Etm,
    SSHMacType.hmacSha512Etm,
    SSHMacType.hmacSha256,
    SSHMacType.hmacSha512,
    SSHMacType.hmacSha1,
    SSHMacType.hmacSha256_96,
    SSHMacType.hmacSha512_96,
    SSHMacType.hmacMd5,
  ];

  static Map<String, String> parseOptions(String customSshOptions) {
    final result = <String, String>{};
    if (customSshOptions.trim().isEmpty) return result;

    final regex = RegExp(r'(?:-o\s+)?([A-Za-z0-9_]+)\s*=\s*([^\s]+)');
    for (final match in regex.allMatches(customSshOptions)) {
      final key = match.group(1)!.toLowerCase();
      final val = match.group(2)!.trim();
      if (val.isNotEmpty) {
        result[key] = val;
      }
    }
    return result;
  }

  static List<T> _resolveList<T>(
    List<T> defaults,
    String? spec, {
    required String Function(T) nameOf,
    required bool prioritizeOnly,
  }) {
    if (spec == null || spec.trim().isEmpty) return defaults;
    final cleanSpec = spec.trim();
    final isAppendOrPrioritize = cleanSpec.startsWith('+') || prioritizeOnly;
    final rawNames = (cleanSpec.startsWith('+') ? cleanSpec.substring(1) : cleanSpec)
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final matched = <T>[];
    for (final name in rawNames) {
      final found = defaults.where((alg) => nameOf(alg).toLowerCase() == name.toLowerCase()).firstOrNull;
      if (found != null && !matched.contains(found)) {
        matched.add(found);
      }
    }

    if (matched.isEmpty) return defaults;

    if (isAppendOrPrioritize) {
      return [
        ...matched,
        ...defaults.where((alg) => !matched.contains(alg)),
      ];
    }
    return matched;
  }

  static SSHAlgorithms buildAlgorithms({
    String sshMacs = 'auto',
    String customSshOptions = '',
  }) {
    final parsed = parseOptions(customSshOptions);

    final customMacSpec = parsed['macs'];
    final effectiveMacSpec = (customMacSpec != null && customMacSpec.isNotEmpty)
        ? customMacSpec
        : (sshMacs.trim().isNotEmpty && sshMacs.trim().toLowerCase() != 'auto'
            ? sshMacs.trim()
            : null);
    final prioritizeMacOnly = customMacSpec == null && effectiveMacSpec != null;

    final resolvedMacs = _resolveList<SSHMacType>(
      allMacs,
      effectiveMacSpec,
      nameOf: (m) => m.name,
      prioritizeOnly: prioritizeMacOnly,
    );

    final resolvedKex = _resolveList<SSHKexType>(
      allKex,
      parsed['kexalgorithms'],
      nameOf: (k) => k.name,
      prioritizeOnly: false,
    );

    final resolvedHostkeys = _resolveList<SSHHostkeyType>(
      allHostkeys,
      parsed['hostkeyalgorithms'] ?? parsed['pubkeyacceptedalgorithms'] ?? parsed['pubkeyacceptedkeytypes'],
      nameOf: (h) => h.name,
      prioritizeOnly: false,
    );

    final customCipherSpec = parsed['ciphers'];
    List<SSHCipherType> resolvedCiphers;
    if (customCipherSpec != null && customCipherSpec.isNotEmpty) {
      resolvedCiphers = _resolveList<SSHCipherType>(
        allCiphers,
        customCipherSpec,
        nameOf: (c) => c.name,
        prioritizeOnly: false,
      );
    } else if (effectiveMacSpec != null) {
      // Non-AEAD ciphers must be negotiated first so the selected MAC is actually used
      // instead of being bypassed by AES-GCM or ChaCha20-Poly1305.
      resolvedCiphers = [
        ...allCiphers.where((c) => !c.isAead),
        ...allCiphers.where((c) => c.isAead),
      ];
    } else {
      resolvedCiphers = allCiphers;
    }

    return SSHAlgorithms(
      kex: resolvedKex,
      hostkey: resolvedHostkeys,
      cipher: resolvedCiphers,
      mac: resolvedMacs,
    );
  }

  static String buildCliOptionFlags({
    String sshMacs = 'auto',
    String customSshOptions = '',
  }) {
    final flags = <String>[];
    final parsed = parseOptions(customSshOptions);

    if (!parsed.containsKey('macs') &&
        sshMacs.trim().isNotEmpty &&
        sshMacs.trim().toLowerCase() != 'auto') {
      flags.add('-o MACs=${sshMacs.trim()}');
    }

    final rawTrimmed = customSshOptions.trim();
    if (rawTrimmed.isNotEmpty) {
      final regex = RegExp(r'(?:-o\s+)?([A-Za-z0-9_]+=[^\s]+)');
      final matches = regex.allMatches(rawTrimmed).toList();
      if (matches.isNotEmpty) {
        for (final m in matches) {
          flags.add('-o ${m.group(1)!}');
        }
      } else {
        flags.add(rawTrimmed);
      }
    }

    return flags.join(' ');
  }
}
