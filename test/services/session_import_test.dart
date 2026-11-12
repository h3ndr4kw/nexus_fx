import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/services/session_import/imported_host.dart';
import 'package:nexus_fx/services/session_import/putty_sessions_reader.dart';
import 'package:nexus_fx/services/session_import/ssh_config_parser.dart';
import 'package:nexus_fx/services/session_manager_service.dart';

void main() {
  group('SshConfigParser', () {
    ImportScan parse(String text) => SshConfigParser.parse(text, home: '/home/me');
    ImportedHost host(ImportScan s, String name) => s.hosts.singleWhere((h) => h.name == name);

    test('reads HostName, Port, User and expands IdentityFile', () {
      final s = parse('''
# comment
Host web
    HostName 10.0.0.5
    Port 2222
    User deploy
    IdentityFile ~/.ssh/id_web
''');
      final h = host(s, 'web');
      expect(h.host, '10.0.0.5');
      expect(h.port, 2222);
      expect(h.username, 'deploy');
      expect(h.identityFile, '/home/me/.ssh/id_web');
      expect(s.warnings, isEmpty);
    });

    test('alias without HostName connects to the alias itself on port 22', () {
      final h = host(parse('Host box.example.com\n'), 'box.example.com');
      expect(h.host, 'box.example.com');
      expect(h.port, 22);
      expect(h.identityFile, isNull);
    });

    test('wildcard blocks give defaults but are not hosts; first value wins', () {
      final s = parse('''
Host a b
    User alice
Host *.internal
    Port 2200
Host *
    User nobody
    Port 22
    IdentityFile "~/keys/default key"
Host db.internal
''');
      expect(s.hosts.map((h) => h.name), ['a', 'b', 'db.internal']);
      expect(host(s, 'a').username, 'alice');
      expect(host(s, 'a').identityFile, '/home/me/keys/default key');
      expect(host(s, 'db.internal').username, 'nobody');
      expect(host(s, 'db.internal').port, 2200);
    });

    test('negated patterns exclude a host from a block', () {
      final s = parse('''
Host * !bastion
    User app
Host bastion
Host api
''');
      expect(host(s, 'bastion').username, '');
      expect(host(s, 'api').username, 'app');
    });

    test('ProxyJump to another alias takes that alias\'s settings', () {
      final s = parse('''
Host bastion
    HostName 203.0.113.9
    User jump
    Port 2022
Host app
    HostName 10.1.1.1
    ProxyJump bastion
''');
      final j = host(s, 'app').jump!;
      expect(j.alias, 'bastion');
      expect(j.host, '203.0.113.9');
      expect(j.port, 2022);
      expect(j.username, 'jump');
    });

    test('ProxyJump as user@host:port, keyword=value form', () {
      final j = host(parse('Host app\n  ProxyJump=ops@gw.example.com:2201\n'), 'app').jump!;
      expect(j.alias, isNull);
      expect(j.host, 'gw.example.com');
      expect(j.port, 2201);
      expect(j.username, 'ops');
    });

    test('multi-hop ProxyJump and ProxyCommand are noted, not guessed', () {
      final s = parse('''
Host far
    ProxyJump a,b
Host cmd
    ProxyCommand nc -X 5 -x proxy:1080 %h %p
''');
      expect(host(s, 'far').jump, isNull);
      expect(host(s, 'far').notes.single, contains('2 hops'));
      expect(host(s, 'cmd').notes.single, contains('ProxyCommand'));
    });

    test('Include and Match are reported and Match options are not applied', () {
      final s = parse('''
Include config.d/*
Host app
    User real
Match host app
    User fromMatch
    Port 9999
''');
      expect(host(s, 'app').username, 'real');
      expect(host(s, 'app').port, 22);
      expect(s.warnings, hasLength(2));
      expect(s.warnings.first, contains('Include'));
      expect(s.warnings.last, contains('Match'));
    });

    test('readFile reports a missing file', () async {
      final s = await SshConfigParser.readFile('${Directory.systemTemp.path}/no_such_ssh_config_xyz');
      expect(s.hosts, isEmpty);
      expect(s.warnings.single, contains('does not exist'));
    });
  });

  group('PuttySessionsReader.parseRegQuery', () {
    const output = '\r\n'
        r'HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Default%20Settings' '\r\n'
        '    HostName    REG_SZ    \r\n'
        '\r\n'
        r'HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\prod%20web' '\r\n'
        '    HostName    REG_SZ    admin@10.2.3.4\r\n'
        '    PortNumber    REG_DWORD    0x8ae\r\n'
        '    UserName    REG_SZ    \r\n'
        '    Protocol    REG_SZ    ssh\r\n'
        r'    PublicKeyFile    REG_SZ    C:\keys\prod.ppk' '\r\n'
        '    ProxyMethod    REG_DWORD    0x6\r\n'
        '    ProxyHost    REG_SZ    gw.example.com\r\n'
        '    ProxyPort    REG_DWORD    0x16\r\n'
        '    ProxyUsername    REG_SZ    ops\r\n'
        '\r\n'
        r'HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\router' '\r\n'
        '    HostName    REG_SZ    192.168.1.1\r\n'
        '    Protocol    REG_SZ    telnet\r\n'
        '\r\n'
        r'HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\blank' '\r\n'
        '    HostName    REG_SZ    \r\n'
        '    Protocol    REG_SZ    ssh\r\n'
        '\r\n'
        r'HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Alpha' '\r\n'
        '    HostName    REG_SZ    alpha.local\r\n'
        '    UserName    REG_SZ    root\r\n'
        '    ProxyMethod    REG_DWORD    0x2\r\n'
        '    ProxyHost    REG_SZ    socks.local\r\n';

    test('imports SSH sessions with decoded names, user@host and SSH proxy', () {
      final s = PuttySessionsReader.parseRegQuery(output);
      expect(s.hosts.map((h) => h.name), ['Alpha', 'prod web']);

      final prod = s.hosts.last;
      expect(prod.host, '10.2.3.4');
      expect(prod.username, 'admin');
      expect(prod.port, 2222);
      expect(prod.identityFile, r'C:\keys\prod.ppk');
      expect(prod.notes.single, contains('.ppk'));
      expect(prod.jump!.host, 'gw.example.com');
      expect(prod.jump!.port, 22);
      expect(prod.jump!.username, 'ops');

      final alpha = s.hosts.first;
      expect(alpha.port, 22);
      expect(alpha.username, 'root');
      expect(alpha.jump, isNull);
      expect(alpha.notes.single, contains('proxy type 2'));
    });

    test('skips Default Settings, non-SSH and host-less sessions with warnings', () {
      final s = PuttySessionsReader.parseRegQuery(output);
      expect(s.warnings, hasLength(2));
      expect(s.warnings.any((w) => w.contains('"router" uses telnet')), isTrue);
      expect(s.warnings.any((w) => w.contains('"blank" has no host name')), isTrue);
    });
  });

  group('SessionImporter', () {
    late Directory tempDir;
    late SessionManagerService mgr;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nexus_fx_import_test_');
      mgr = SessionManagerService.forTesting();
      await mgr.loadSessions(customFilePath: '${tempDir.path}/sessions.json');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('isDuplicate matches host (case-insensitive), port and user', () {
      final saved = [
        SessionProfile(id: 's', name: 's', host: 'Web.Example', port: 22, username: 'a', modifiedAt: DateTime.now()),
      ];
      expect(SessionImporter.isDuplicate(const ImportedHost(name: 'x', host: 'web.example', username: 'a'), saved), isTrue);
      expect(SessionImporter.isDuplicate(const ImportedHost(name: 'x', host: 'web.example', username: 'b'), saved), isFalse);
      expect(SessionImporter.isDuplicate(const ImportedHost(name: 'x', host: 'web.example', port: 2, username: 'a'), saved), isFalse);
    });

    test('saves into a new folder, uses key auth and links jumps', () async {
      final existingGw = await mgr.createSession(SessionProfile(
        id: 'gw',
        name: 'gateway',
        host: 'gw.example.com',
        username: 'ops',
        modifiedAt: DateTime.now(),
      ));

      final created = await SessionImporter.commit(
        mgr,
        const [
          ImportedHost(name: 'bastion', host: '203.0.113.9', username: 'jump', identityFile: '/k/bastion'),
          ImportedHost(
            name: 'app',
            host: '10.1.1.1',
            jump: ImportedJump(alias: 'bastion', host: '203.0.113.9', username: 'jump'),
          ),
          ImportedHost(
            name: 'behind-gw',
            host: '10.9.9.9',
            jump: ImportedJump(host: 'gw.example.com', username: 'ops'),
          ),
          ImportedHost(
            name: 'elsewhere',
            host: '10.8.8.8',
            jump: ImportedJump(host: 'other.example.com', port: 2201, username: 'x'),
          ),
        ],
        folderName: 'Imported from OpenSSH',
      );

      final folder = mgr.folders.singleWhere((f) => f.name == 'Imported from OpenSSH');
      expect(created, hasLength(4));
      expect(created.every((s) => s.parentId == folder.id), isTrue);

      final bastion = created[0];
      expect(bastion.authMethod, AuthMethod.privateKey);
      expect(bastion.privateKeyPath, '/k/bastion');
      expect(created[1].authMethod, AuthMethod.password);

      expect(created[1].jumpHostMode, JumpHostMode.existingSession);
      expect(created[1].jumpSessionId, bastion.id);

      expect(created[2].jumpHostMode, JumpHostMode.existingSession);
      expect(created[2].jumpSessionId, existingGw.id);

      expect(created[3].jumpHostMode, JumpHostMode.customJumpHost);
      expect(created[3].customJumpHost, 'other.example.com');
      expect(created[3].customJumpPort, 2201);
      expect(created[3].customJumpUsername, 'x');

      // The linked jump resolves like any hand-made session.
      final route = mgr.resolveSshRoute(created[1]);
      expect(route.jumpHost, '203.0.113.9');
      expect(route.jumpPrivateKey?.path, '/k/bastion');
    });

    test('PuTTY proxy that matches another imported session links to it', () async {
      final created = await SessionImporter.commit(
        mgr,
        const [
          ImportedHost(name: 'gw', host: 'gw.example.com', username: 'ops'),
          ImportedHost(name: 'inner', host: '10.0.0.2', jump: ImportedJump(host: 'gw.example.com', username: 'ops')),
        ],
        folderName: 'Imported from PuTTY',
      );
      expect(created[1].jumpHostMode, JumpHostMode.existingSession);
      expect(created[1].jumpSessionId, created[0].id);
    });

    test('nothing chosen creates nothing', () async {
      final before = mgr.folders.length;
      expect(await SessionImporter.commit(mgr, const [], folderName: 'X'), isEmpty);
      expect(mgr.folders.length, before);
    });
  });
}
