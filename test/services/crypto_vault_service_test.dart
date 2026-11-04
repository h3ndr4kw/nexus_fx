import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/crypto_vault_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CryptoVaultService Tests', () {
    late CryptoVaultService vault;

    setUp(() {
      vault = CryptoVaultService.instance;
    });

    test('Encrypting plain text produces prefixed format enc:v1:<iv>:<ciphertext>', () {
      final plain = 'super_secret_ssh_password_123!';
      final encrypted = vault.encrypt(plain);

      expect(encrypted, startsWith('enc:v1:'));
      final parts = encrypted.split(':');
      expect(parts.length, 4); // ['enc', 'v1', iv_b64, cipher_b64]
      expect(parts[2].isNotEmpty, isTrue);
      expect(parts[3].isNotEmpty, isTrue);
    });

    test('Decrypting ciphertext restores original plain text with Unicode support', () {
      final plain = 'P@ssw0rd_Kompilasi_🇮🇩_#992!';
      final encrypted = vault.encrypt(plain);
      final decrypted = vault.decrypt(encrypted);

      expect(decrypted, equals(plain));
    });

    test('Encrypting the same text twice generates different ciphertexts due to random IV', () {
      final plain = 'constant_password';
      final enc1 = vault.encrypt(plain);
      final enc2 = vault.encrypt(plain);

      expect(enc1, isNot(equals(enc2)));
      expect(vault.decrypt(enc1), equals(plain));
      expect(vault.decrypt(enc2), equals(plain));
    });

    test('Empty input returns empty string', () {
      expect(vault.encrypt(''), '');
      expect(vault.decrypt(''), '');
    });

    test('Legacy XOR 0x5A encoded string is automatically detected and decrypted', () {
      final raw = 'legacy-admin-pwd-2026';
      // Simulate legacy XOR 0x5A encoding
      final bytes = utf8.encode(raw);
      final xored = bytes.map((b) => b ^ 0x5A).toList();
      final legacyEncoded = base64.encode(xored);

      // Verify that decrypt seamlessly decodes the legacy string
      final decrypted = vault.decrypt(legacyEncoded);
      expect(decrypted, equals(raw));
    });

    test('Malformed string fallback returns the input safely without crashing', () {
      final malformed = 'not-valid-base64-or-encryption-%%%';
      expect(vault.decrypt(malformed), equals(malformed));
    });
  });
}
