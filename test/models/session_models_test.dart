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

    test('SessionProfile ignores the legacy environment key in saved JSON', () {
      final legacyJson = {
        'id': 's1',
        'name': 'Old',
        'protocol': 'ssh',
        'host': '1.1.1.1',
        'environment': 'prod',
        'modifiedAt': '2026-01-01',
      };
      final restored = SessionProfile.fromJson(legacyJson);
      expect(restored.name, 'Old');
      expect(restored.toJson().containsKey('environment'), isFalse);
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

  group('SessionProfile web URL', () {
    SessionProfile p({
      String host = '10.89.100.11',
      String webUrl = '',
      SessionProtocol protocol = SessionProtocol.ssh,
      JumpHostMode jump = JumpHostMode.direct,
      bool enabled = true,
    }) =>
        SessionProfile(
          id: 's',
          name: 'n',
          host: host,
          webEnabled: enabled,
          webUrl: webUrl,
          protocol: protocol,
          jumpHostMode: jump,
          modifiedAt: DateTime(2026),
        );

    test('is off unless enabled, even with a Web URL set', () {
      expect(p(enabled: false).resolvedWebUrl, isNull);
      expect(p(enabled: false, webUrl: 'https://x').canOpenWeb, isFalse);
      expect(SessionProfile(id: 's', name: 'n', host: 'h', modifiedAt: DateTime(2026)).webEnabled, isFalse);
    });

    test('defaults to https://<host>', () {
      expect(p().resolvedWebUrl, 'https://10.89.100.11');
      expect(p().canOpenWeb, isTrue);
    });

    test('uses an explicit Web URL, adding https when no scheme is given', () {
      expect(p(webUrl: 'https://10.0.0.5:8443/ui').resolvedWebUrl, 'https://10.0.0.5:8443/ui');
      expect(p(webUrl: 'http://10.0.0.5').resolvedWebUrl, 'http://10.0.0.5');
      expect(p(webUrl: '10.0.0.5:8443').resolvedWebUrl, 'https://10.0.0.5:8443');
    });

    test('has no URL for local shells or an empty host', () {
      expect(p(protocol: SessionProtocol.local).resolvedWebUrl, isNull);
      expect(p(host: '').resolvedWebUrl, isNull);
    });

    test('jump host sessions need an explicit Web URL to open', () {
      expect(p(jump: JumpHostMode.existingSession).canOpenWeb, isFalse);
      expect(p(jump: JumpHostMode.customJumpHost).canOpenWeb, isFalse);
      expect(
        p(jump: JumpHostMode.existingSession, webUrl: 'https://127.0.0.1:9443').canOpenWeb,
        isTrue,
      );
    });

    test('round-trips through JSON and defaults to empty for old data', () {
      final restored = SessionProfile.fromJson(p(webUrl: 'https://x:8443').toJson());
      expect(restored.webUrl, 'https://x:8443');
      expect(restored.webEnabled, isTrue);
      final json = p().toJson()
        ..remove('webUrl')
        ..remove('webEnabled');
      final old = SessionProfile.fromJson(json);
      expect(old.webUrl, '');
      expect(old.webEnabled, isFalse);
    });
  });
}
