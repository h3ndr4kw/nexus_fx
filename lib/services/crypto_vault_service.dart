import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// A stored `enc:v1:` credential that cannot be decrypted (the file was
/// edited, truncated or corrupted). Never carries the stored value.
class VaultDecryptException implements Exception {
  final String reason;
  const VaultDecryptException(this.reason);

  @override
  String toString() => 'VaultDecryptException: $reason';
}

/// Cryptographic vault service for encrypting and decrypting sensitive credentials
/// using AES-256-CBC with PKCS7 padding and random IVs, supporting legacy XOR migration.
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
  /// Automatically detects `enc:v1:` AES format vs legacy XOR 0x5A format.
  ///
  /// Throws [VaultDecryptException] when an `enc:v1:` payload cannot be
  /// decrypted: returning it unchanged would hand the ciphertext to callers
  /// as if it were the password. Input without the prefix that is not legacy
  /// XOR is returned as is, since old files may hold plain text.
  String decrypt(String encoded) {
    if (encoded.isEmpty) return '';

    if (encoded.startsWith(prefix)) {
      final parts = encoded.substring(prefix.length).split(':');
      if (parts.length != 2) {
        throw const VaultDecryptException('expected <iv>:<ciphertext>');
      }
      try {
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
      } on VaultDecryptException {
        rethrow;
      } catch (e) {
        // pointycastle reports bad padding, block sizes and IVs as a mix of
        // ArgumentError, StateError and RangeError.
        throw VaultDecryptException(e.runtimeType.toString());
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
