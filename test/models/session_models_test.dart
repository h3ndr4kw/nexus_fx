import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/models/ssh_tunnel_models.dart';

void main() {
  group('Session models', () {
    test('SessionProfile serializes and deserializes with AES-256 encrypted password and jump host fields', () {
      final profile = SessionProfile(
        id: 'sess_1',
        parentId: 'folder_1',
        name: 'DOCKER_SERVER',
        protocol: SessionProtocol.ssh,
        host: '192.168.1.146',
        port: 22,
        username: 'docker-server',
        password: 'secret-password',
        jumpHostMode: JumpHostMode.existingSession,
        jumpSessionId: 'sess_jump_1',
        tunnelMode: TunnelMode.multiplexed,
        modifiedAt: DateTime.utc(2026, 8, 13, 13, 31, 10),
      );

      final json = profile.toJson();
      expect(json['password'], isNot(equals('secret-password')));
      expect(json['password'], startsWith('enc:v1:'));

      final restored = SessionProfile.fromJson(json);
      expect(restored.id, 'sess_1');
      expect(restored.parentId, 'folder_1');
      expect(restored.name, 'DOCKER_SERVER');
      expect(restored.host, '192.168.1.146');
      expect(restored.password, 'secret-password');
      expect(restored.jumpHostMode, JumpHostMode.existingSession);
      expect(restored.jumpSessionId, 'sess_jump_1');
      expect(restored.protocol, SessionProtocol.ssh);
      expect(restored.enableSessionLogging, isTrue);
    });

    test('SessionProfile deserializes legacy XOR 0x5A passwords seamlessly', () {
      // Simulate a JSON file saved by an older version of NexusFX with XOR 0x5A
      final legacyRawPassword = 'old-legacy-password-123';
      final bytes = utf8.encode(legacyRawPassword);
      final xored = bytes.map((b) => b ^ 0x5A).toList();
      final legacyEncoded = base64.encode(xored);

      final legacyJson = {
        'id': 'sess_legacy',
        'name': 'LEGACY_NODE',
        'protocol': 'ssh',
        'host': '10.20.30.40',
        'port': 22,
        'username': 'legacy-user',
        'password': legacyEncoded,
        'jumpHostMode': 'direct',
        'tunnelMode': 'multiplexed',
        'modifiedAt': DateTime.utc(2025, 1, 1).toIso8601String(),
      };

      final restored = SessionProfile.fromJson(legacyJson);
      expect(restored.password, equals(legacyRawPassword));

      // When saved again, it will be upgraded to AES-256 enc:v1 format
      final upgradedJson = restored.toJson();
      expect(upgradedJson['password'], startsWith('enc:v1:'));
    });

    test('SessionProfile handles SessionEnvironment dev, staging, and prod serialization', () {
      final devProfile = SessionProfile(
        id: 'sess_dev',
        name: 'Dev Node',
        protocol: SessionProtocol.ssh,
        host: '127.0.0.1',
        environment: SessionEnvironment.dev,
        modifiedAt: DateTime.utc(2026, 1, 1),
      );
      expect(devProfile.environment, SessionEnvironment.dev);
      expect(devProfile.environment.isProduction, isFalse);
      expect(devProfile.toJson()['environment'], 'dev');

      final prodProfile = devProfile.copyWith(environment: SessionEnvironment.prod);
      expect(prodProfile.environment, SessionEnvironment.prod);
      expect(prodProfile.environment.isProduction, isTrue);
      expect(prodProfile.toJson()['environment'], 'prod');

      final restoredProd = SessionProfile.fromJson(prodProfile.toJson());
      expect(restoredProd.environment, SessionEnvironment.prod);

      // Sesi lama tanpa field environment otomatis default ke dev
      final oldJsonWithoutEnv = {'id': 's1', 'name': 'Old', 'protocol': 'ssh', 'host': '1.1.1.1', 'modifiedAt': '2026-01-01'};
      final restoredOld = SessionProfile.fromJson(oldJsonWithoutEnv);
      expect(restoredOld.environment, SessionEnvironment.dev);
    });

    test('SessionFolder serializes and deserializes correctly', () {
      final folder = SessionFolder(
        id: 'folder_1',
        parentId: null,
        name: 'TSEL_PS',
        description: 'Telkomsel PS nodes',
        modifiedAt: DateTime.utc(2026, 8, 28, 9, 52, 20),
      );

      final json = folder.toJson();
      final restored = SessionFolder.fromJson(json);

      expect(restored.id, 'folder_1');
      expect(restored.parentId, isNull);
      expect(restored.name, 'TSEL_PS');
      expect(restored.description, 'Telkomsel PS nodes');
    });

    test('SessionProfile serializes and deserializes sshMacs and customSshOptions', () {
      final profile = SessionProfile(
        id: 'sess_mac',
        name: 'LEGACY_MAC_HOST',
        protocol: SessionProtocol.ssh,
        host: '10.89.100.11',
        username: '21339656',
        sshMacs: 'hmac-sha1',
        customSshOptions: '-o MACs=hmac-sha1 -o KexAlgorithms=+diffie-hellman-group1-sha1',
        modifiedAt: DateTime.utc(2026, 11, 6),
      );

      final json = profile.toJson();
      expect(json['sshMacs'], 'hmac-sha1');
      expect(json['customSshOptions'], '-o MACs=hmac-sha1 -o KexAlgorithms=+diffie-hellman-group1-sha1');

      final restored = SessionProfile.fromJson(json);
      expect(restored.sshMacs, 'hmac-sha1');
      expect(restored.customSshOptions, '-o MACs=hmac-sha1 -o KexAlgorithms=+diffie-hellman-group1-sha1');

      final legacyJson = {
        'id': 's_old',
        'name': 'Old',
        'protocol': 'ssh',
        'host': '1.2.3.4',
        'modifiedAt': '2026-01-01',
      };
      final restoredOld = SessionProfile.fromJson(legacyJson);
      expect(restoredOld.sshMacs, 'auto');
      expect(restoredOld.customSshOptions, '');
    });
  });
}
