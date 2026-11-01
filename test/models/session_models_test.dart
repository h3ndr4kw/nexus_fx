import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/models/ssh_tunnel_models.dart';

void main() {
  group('Session models', () {
    test('SessionProfile serializes and deserializes with obfuscated password and jump host fields', () {
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
  });
}
