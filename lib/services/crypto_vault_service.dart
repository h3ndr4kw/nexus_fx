import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// Cryptographic vault service for encrypting and decrypting sensitive credentials
/// using AES-256-CBC with PKCS7 padding and random IVs, with seamless legacy XOR migration.
class CryptoVaultService {
  static final CryptoVaultService _instance = CryptoVaultService._internal();
  static CryptoVaultService get instance => _instance;

  static const String prefix = 'enc:v1:';
  static const int _legacyXorKey = 0x5A;

  // 256-bit derived key for AES encryption
  late final Uint8List _aesKey;
  final Random _secureRandom = Random.secure();

  CryptoVaultService._internal() {
    // Derive a fixed 32-byte (256-bit) encryption key
    final seed = utf8.encode('NexusFX::VaultSecretSalt::v1::2026::DesktopSSH');
    final hash = crypto.sha256.convert(seed);
    _aesKey = Uint8List.fromList(hash.bytes);
  }

  /// Encrypts plain text string using AES-256-CBC with random 16-byte IV.
  /// Resulting string is prefixed with `enc:v1:<base64_iv>:<base64_ciphertext>`.
  String encrypt(String plainText) {
    if (plainText.isEmpty) return '';

    // Generate random 16-byte IV
    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      iv[i] = _secureRandom.nextInt(256);
    }

    final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
    final params = PaddedBlockCipherParameters(
      ParametersWithIV(KeyParameter(_aesKey), iv),
      null,
    );
    cipher.init(true, params);

    final inputBytes = Uint8List.fromList(utf8.encode(plainText));
    final encryptedBytes = cipher.process(inputBytes);

    final ivB64 = base64.encode(iv);
    final cipherB64 = base64.encode(encryptedBytes);

    return '$prefix$ivB64:$cipherB64';
  }

  /// Decrypts ciphertext.
  /// Automatically detects `enc:v1:` AES format vs legacy XOR 0x5A format,
  /// falling back gracefully to the raw input if decryption fails.
  String decrypt(String encoded) {
    if (encoded.isEmpty) return '';

    if (encoded.startsWith(prefix)) {
      try {
        final raw = encoded.substring(prefix.length);
        final parts = raw.split(':');
        if (parts.length != 2) return encoded;

        final iv = base64.decode(parts[0]);
        final ciphertext = base64.decode(parts[1]);

        final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
        final params = PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(_aesKey), Uint8List.fromList(iv)),
          null,
        );
        cipher.init(false, params);

        final decryptedBytes = cipher.process(Uint8List.fromList(ciphertext));
        return utf8.decode(decryptedBytes);
      } catch (_) {
        return encoded;
      }
    }

    // Legacy XOR 0x5A fallback auto-migration
    try {
      final bytes = base64.decode(encoded);
      final unxored = bytes.map((b) => b ^ _legacyXorKey).toList();
      return utf8.decode(unxored);
    } catch (_) {
      return encoded;
    }
  }
}
