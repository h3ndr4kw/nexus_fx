import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/ssh_key_loader.dart';

/// Generates keys with the system ssh-keygen; tests skip without it.
String? _keygenSkip() {
  try {
    final r = Process.runSync('ssh-keygen', ['-?']);
    // ssh-keygen prints usage and exits non-zero; reaching here means it ran.
    return r.exitCode == 127 ? 'ssh-keygen not available' : null;
  } catch (_) {
    return 'ssh-keygen not available';
  }
}

Future<String> _keygen(Directory dir, String name, String type, String passphrase,
    {List<String> extra = const []}) async {
  final path = '${dir.path}${Platform.pathSeparator}$name';
  final r = await Process.run('ssh-keygen', [
    '-q', '-t', type, '-N', passphrase, '-f', path, '-C', 'test', ...extra,
  ]);
  if (r.exitCode != 0) fail('ssh-keygen failed: ${r.stderr}');
  return path;
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('ssh_key_loader_'));
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('SshPrivateKeyRef.of only when the session uses a key file', () {
    expect(SshPrivateKeyRef.of(usesKey: false, path: '/k'), isNull);
    expect(SshPrivateKeyRef.of(usesKey: true, path: '  '), isNull);
    expect(SshPrivateKeyRef.of(usesKey: true, path: ' /k ', passphrase: 'p')!.path, '/k');
  });

  test('expands ~ to the home folder', () {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    expect(expandKeyPath('~/.ssh/id_ed25519'), '$home/.ssh/id_ed25519');
    expect(expandKeyPath('/abs/key'), '/abs/key');
  });

  test('missing file has a clear message', () async {
    await expectLater(
      loadSshIdentities(SshPrivateKeyRef('${dir.path}/nope')),
      throwsA(isA<SshKeyLoadException>().having((e) => e.message, 'message', contains('not found'))),
    );
  });

  test('PuTTY and PKCS#8 keys are refused with a conversion hint', () async {
    await expectLater(
      parseSshIdentities('PuTTY-User-Key-File-3: ssh-ed25519\n', null),
      throwsA(isA<SshKeyLoadException>().having((e) => e.message, 'message', contains('PuTTYgen'))),
    );
    await expectLater(
      parseSshIdentities('-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n', null),
      throwsA(isA<SshKeyLoadException>().having((e) => e.message, 'message', contains('ssh-keygen -p'))),
    );
    await expectLater(parseSshIdentities('hello', null), throwsA(isA<SshKeyLoadException>()));
  });

  group('with ssh-keygen', () {
    test('loads an unencrypted ed25519 key', () async {
      final path = await _keygen(dir, 'ed', 'ed25519', '');
      final keys = await loadSshIdentities(SshPrivateKeyRef(path));
      expect(keys, hasLength(1));
      expect(keys.single.type, 'ssh-ed25519');
    });

    test('loads an encrypted key with its passphrase, off the UI isolate', () async {
      final path = await _keygen(dir, 'enc', 'ed25519', 'hunter2');
      final keys = await loadSshIdentities(SshPrivateKeyRef(path, 'hunter2'));
      expect(keys.single.type, 'ssh-ed25519');
    });

    test('encrypted key without or with a wrong passphrase', () async {
      final path = await _keygen(dir, 'enc2', 'ed25519', 'hunter2');
      await expectLater(
        loadSshIdentities(SshPrivateKeyRef(path)),
        throwsA(isA<SshKeyLoadException>().having((e) => e.message, 'message', contains('passphrase'))),
      );
      await expectLater(
        loadSshIdentities(SshPrivateKeyRef(path, 'wrong')),
        throwsA(isA<SshKeyLoadException>().having((e) => e.message, 'message', contains('Wrong passphrase'))),
      );
    });

    test('loads a legacy PEM RSA key', () async {
      final path = await _keygen(dir, 'rsa', 'rsa', '', extra: ['-b', '2048', '-m', 'PEM']);
      final keys = await loadSshIdentities(SshPrivateKeyRef(path));
      expect(keys, hasLength(1));
    });
  }, skip: _keygenSkip());
}
