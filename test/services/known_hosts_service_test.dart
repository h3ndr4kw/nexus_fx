import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/known_hosts_service.dart';

const _fpA = 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _fpB = 'SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late Directory dir;
  late String path;
  late KnownHostsService svc;
  late List<HostKeyPromptRequest> prompts;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('known_hosts_test_');
    path = '${dir.path}${Platform.pathSeparator}known_hosts.json';
    svc = KnownHostsService.forTesting(filePath: path);
    prompts = [];
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  void answer(HostKeyDecision d) {
    svc.prompter = (req) async {
      prompts.add(req);
      return d;
    };
  }

  group('check', () {
    test('unknown host', () {
      expect(svc.check('10.0.0.1', 22, 'ssh-ed25519', _fpA), HostKeyStatus.unknown);
    });

    test('trusted, matching case-insensitively on host', () async {
      await svc.trust('Server.Example', 22, 'ssh-ed25519', _fpA);
      expect(svc.check('server.example', 22, 'ssh-ed25519', _fpA), HostKeyStatus.trusted);
    });

    test('different key of the same family is a change', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA);
      expect(svc.check('h', 22, 'ssh-ed25519', _fpB), HostKeyStatus.changed);
    });

    test('rsa signature variants are the same key family', () async {
      await svc.trust('h', 22, 'rsa-sha2-512', _fpA);
      expect(svc.check('h', 22, 'ssh-rsa', _fpA), HostKeyStatus.trusted);
      expect(svc.check('h', 22, 'rsa-sha2-256', _fpB), HostKeyStatus.changed);
    });

    test('a key of another family is unknown, not changed', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA);
      expect(svc.check('h', 22, 'ecdsa-sha2-nistp256', _fpB), HostKeyStatus.unknown);
    });

    test('ports are separate hosts', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA);
      expect(svc.check('h', 2222, 'ssh-ed25519', _fpB), HostKeyStatus.unknown);
    });

    test('an MD5 fingerprint is not compared against a SHA256 one', () async {
      await svc.trust('h', 22, 'ssh-rsa', _fpA);
      expect(
        svc.check('h', 22, 'RSA', 'MD5:12:34:56:78:9a:bc:de:f0:12:34:56:78:9a:bc:de:f0'),
        HostKeyStatus.unknown,
      );
    });
  });

  group('persistence', () {
    test('trusted keys survive a reload', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA);
      final again = KnownHostsService.forTesting(filePath: path);
      await again.load();
      expect(again.check('h', 22, 'ssh-ed25519', _fpA), HostKeyStatus.trusted);
      expect(again.fingerprintsFor('h', 22), [_fpA]);
    });

    test('session-only trust is not written to disk', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA, persist: false);
      expect(svc.check('h', 22, 'ssh-ed25519', _fpA), HostKeyStatus.trusted);
      final again = KnownHostsService.forTesting(filePath: path);
      await again.load();
      expect(again.check('h', 22, 'ssh-ed25519', _fpA), HostKeyStatus.unknown);
    });

    test('a corrupt file loads as empty instead of throwing', () async {
      await File(path).writeAsString('{not json');
      final again = KnownHostsService.forTesting(filePath: path);
      await again.load();
      expect(again.entries, isEmpty);
      expect(File('$path.corrupt').existsSync(), isTrue);
    });

    test('remove forgets a host', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA);
      await svc.remove('h', 22);
      expect(svc.check('h', 22, 'ssh-ed25519', _fpA), HostKeyStatus.unknown);
    });
  });

  group('verify', () {
    test('trusted key passes without a prompt', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA);
      answer(HostKeyDecision.reject);
      expect(await svc.verify('h', 22, 'ssh-ed25519', _fpA), isTrue);
      expect(prompts, isEmpty);
    });

    test('unknown key with no prompter is rejected', () async {
      expect(await svc.verify('h', 22, 'ssh-ed25519', _fpA), isFalse);
    });

    test('trustAlways stores the key', () async {
      answer(HostKeyDecision.trustAlways);
      expect(await svc.verify('h', 22, 'ssh-ed25519', _fpA, via: 'jump'), isTrue);
      expect(prompts.single.status, HostKeyStatus.unknown);
      expect(prompts.single.via, 'jump');
      final again = KnownHostsService.forTesting(filePath: path);
      await again.load();
      expect(again.check('h', 22, 'ssh-ed25519', _fpA), HostKeyStatus.trusted);
    });

    test('trustOnce allows this session only', () async {
      answer(HostKeyDecision.trustOnce);
      expect(await svc.verify('h', 22, 'ssh-ed25519', _fpA), isTrue);
      expect(await svc.verify('h', 22, 'ssh-ed25519', _fpA), isTrue);
      expect(prompts, hasLength(1));
      expect(File(path).existsSync(), isFalse);
    });

    test('reject does not store anything', () async {
      answer(HostKeyDecision.reject);
      expect(await svc.verify('h', 22, 'ssh-ed25519', _fpA), isFalse);
      expect(svc.check('h', 22, 'ssh-ed25519', _fpA), HostKeyStatus.unknown);
    });

    test('changed key reports the previous fingerprint and replacing drops it', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA);
      answer(HostKeyDecision.trustAlways);
      expect(await svc.verify('h', 22, 'ssh-ed25519', _fpB), isTrue);
      expect(prompts.single.status, HostKeyStatus.changed);
      expect(prompts.single.previousFingerprint, _fpA);
      expect(svc.fingerprintsFor('h', 22), [_fpB]);
    });

    test('concurrent connections to one host share a single prompt', () async {
      var calls = 0;
      svc.prompter = (req) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return HostKeyDecision.trustOnce;
      };
      final results = await Future.wait([
        svc.verify('h', 22, 'ssh-ed25519', _fpA),
        svc.verify('h', 22, 'ssh-ed25519', _fpA),
        svc.verify('H', 22, 'ssh-ed25519', _fpA),
      ]);
      expect(results, [true, true, true]);
      expect(calls, 1);
    });

    test('a throwing prompter rejects', () async {
      svc.prompter = (_) async => throw StateError('no navigator');
      expect(await svc.verify('h', 22, 'ssh-ed25519', _fpA), isFalse);
    });

    test('handlerFor decodes dartssh2 fingerprint bytes', () async {
      await svc.trust('h', 22, 'ssh-ed25519', _fpA);
      final handler = svc.handlerFor('h', 22);
      expect(await handler('ssh-ed25519', _bytes(_fpA)), isTrue);
      expect(await handler('ssh-ed25519', _bytes(_fpB)), isFalse);
    });
  });

  group('parseOpenSshPrompt', () {
    test('modern OpenSSH prompt', () {
      const text = "The authenticity of host '10.1.2.3 (10.1.2.3)' can't be established.\r\n"
          'ED25519 key fingerprint is SHA256:abcDEF123+/xyz.\r\n'
          'This key is not known by any other names.\r\n'
          'Are you sure you want to continue connecting (yes/no/[fingerprint])? ';
      final p = parseOpenSshHostKeyPrompt(text)!;
      expect(p.keyType, 'ED25519');
      expect(p.fingerprint, 'SHA256:abcDEF123+/xyz');
    });

    test('old OpenSSH prints MD5 hex', () {
      const text = "RSA key fingerprint is 12:34:56:78:9a:bc:de:f0:12:34:56:78:9a:bc:de:f0.\n"
          'Are you sure you want to continue connecting (yes/no)? ';
      final p = parseOpenSshHostKeyPrompt(text)!;
      expect(p.keyType, 'RSA');
      expect(p.fingerprint, 'MD5:12:34:56:78:9a:bc:de:f0:12:34:56:78:9a:bc:de:f0');
    });

    test('returns null without a fingerprint line', () {
      expect(parseOpenSshHostKeyPrompt('Are you sure you want to continue connecting?'), isNull);
    });
  });
}
