# Session Security & AES-256 Password Encryption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Upgrade session credential protection from reversible XOR `0x5A` obfuscation to AES-256-CBC with PKCS7 padding, secure per-cipher random IVs, and automatic legacy migration for backward compatibility.

---

## File Structure & Proposed Changes

| Action | Path | Description |
| :--- | :--- | :--- |
| **Create** | `lib/services/crypto_vault_service.dart` | `CryptoVaultService` providing AES-256 encryption/decryption, random IV generation, and legacy XOR fallback decoder. |
| **Create** | `test/services/crypto_vault_service_test.dart` | Comprehensive unit tests for AES-256 encryption, decryption, round-trip fidelity, random IV uniqueness, and legacy XOR auto-migration. |
| **Modify** | `lib/models/session_models.dart` | Upgrade `_Obfuscator` to delegate to `CryptoVaultService`, applying `enc:v1:` prefix to new ciphertexts and seamlessly decrypting both new AES and legacy XOR stored passwords. |
| **Modify** | `test/models/session_models_test.dart` | Update and expand session serialization tests to assert `enc:v1:` encryption format and legacy payload compatibility. |

---

## Task 1: Create & Test `CryptoVaultService` (TDD)

**Files:**
- Create: `test/services/crypto_vault_service_test.dart`
- Create: `lib/services/crypto_vault_service.dart`

- [x] **Step 1.1**: Write failing unit tests in `test/services/crypto_vault_service_test.dart` for:
  - Encrypting plain text returns format `enc:v1:<base64_iv>:<base64_ciphertext>`.
  - Decrypting `enc:v1:...` recovers the original plain text with exact Unicode fidelity.
  - Two encryptions of the same plain text produce different ciphertexts (due to unique random IVs).
  - Decrypting legacy XOR `0x5A` base64 string seamlessly decodes the original string.
  - Empty strings or malformed inputs are handled gracefully without exceptions.
- [x] **Step 1.2**: Run `flutter test test/services/crypto_vault_service_test.dart` (confirm test fails because service does not exist yet).
- [x] **Step 1.3**: Implement `CryptoVaultService` in `lib/services/crypto_vault_service.dart` using `pointycastle` (`CBCBlockCipher(AESEngine())` with `PKCS7Padding`).
- [x] **Step 1.4**: Run `flutter test test/services/crypto_vault_service_test.dart` (verify all tests pass).

---

## Task 2: Integrate `CryptoVaultService` into `SessionProfile` & Verify Migration

**Files:**
- Modify: `lib/models/session_models.dart`
- Modify: `test/models/session_models_test.dart`

- [x] **Step 2.1**: Update `_Obfuscator` in `lib/models/session_models.dart` to delegate `encode` and `decode` to `CryptoVaultService.instance`.
- [x] **Step 2.2**: Update `test/models/session_models_test.dart` to assert that `profile.toJson()['password']` starts with `enc:v1:`, and add a test verifying that legacy JSON with XOR-obfuscated passwords correctly deserializes into `SessionProfile`.
- [x] **Step 2.3**: Run `flutter test test/models/session_models_test.dart` to verify session profile serialization passes.

---

## Task 3: Full Regression Verification

**Files:**
- Test across whole codebase: `flutter analyze` & `flutter test`

- [x] **Step 3.1**: Run `flutter analyze` to verify zero static analysis errors or warnings.
- [x] **Step 3.2**: Run the entire Flutter test suite: `flutter test`. Verify all tests (74+ tests) pass without regression.
