import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/network_manager_config.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/models/ssh_tunnel_models.dart';
import 'package:nexus_fx/services/session_manager_service.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/services/ssh_log_service.dart';

void main() {
  group('SshService & SessionProfile', () {
    test('creates SshConnection from SessionProfile for local shell', () {
      final localProfile = SessionProfile(
        id: 'sess_loc',
        name: 'LOCAL',
        protocol: SessionProtocol.local,
        modifiedAt: DateTime.now(),
      );

      final conn = SshConnection.fromSessionProfile(
        localProfile,
        route: ResolvedSshRoute(targetSession: localProfile),
      );

      expect(conn.isLocalShell, isTrue);
      expect(conn.currentLabel, 'LOCAL');
      expect(conn.terminal, isNotNull);
    });

    test('creates SshConnection from SessionProfile for SSH session with jump host', () {
      final targetProfile = SessionProfile(
        id: 'sess_target',
        name: 'SERVER_A',
        protocol: SessionProtocol.ssh,
        host: '10.10.0.5',
        port: 22,
        username: 'admin',
        password: 'pass',
        modifiedAt: DateTime.now(),
      );

      final route = ResolvedSshRoute(
        targetSession: targetProfile,
        jumpHost: 'jump.example.com',
        jumpPort: 2222,
        jumpUsername: 'jumpuser',
        jumpPassword: 'jumppass',
      );

      final conn = SshConnection.fromSessionProfile(
        targetProfile,
        route: route,
      );

      expect(conn.isLocalShell, isFalse);
      expect(conn.host, '10.10.0.5');
      expect(conn.port, 22);
      expect(conn.jumpClusterHost, 'jump.example.com');
      expect(conn.jumpClusterPort, 2222);
      expect(conn.enableLogging, isTrue);
    });

    test('initializes logger with session name when enableSessionLogging is true', () async {
      final tempDir = await Directory.systemTemp.createTemp('session_log_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final logService = SshLogService(baseDir: tempDir.path);
      final profile = SessionProfile(
        id: 'sess_prod',
        name: 'PROD_DB',
        protocol: SessionProtocol.ssh,
        host: '10.0.0.1',
        enableSessionLogging: true,
        modifiedAt: DateTime.now(),
      );

      final conn = SshConnection.fromSessionProfile(
        profile,
        route: ResolvedSshRoute(targetSession: profile),
        logService: logService,
      );

      expect(conn.enableLogging, isTrue);
      await conn.initLogger();
      expect(conn.logFile, isNotNull);
      expect(conn.logFile!.path, contains('session_PROD_DB_'));
      expect(conn.logFile!.existsSync(), isTrue);

      conn.recordLogOutput('Hello Production Database\r\n');
      await conn.flushLogger();
      await conn.closeLogger();

      final content = await conn.logFile!.readAsString();
      expect(content, contains('Hello Production Database'));
    });

    test('does not initialize logger when enableSessionLogging is false', () async {
      final tempDir = await Directory.systemTemp.createTemp('session_log_disabled_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final logService = SshLogService(baseDir: tempDir.path);
      final profile = SessionProfile(
        id: 'sess_disabled',
        name: 'DEV_TEST',
        protocol: SessionProtocol.local,
        enableSessionLogging: false,
        modifiedAt: DateTime.now(),
      );

      final conn = SshConnection.fromSessionProfile(
        profile,
        route: ResolvedSshRoute(targetSession: profile),
        logService: logService,
      );

      expect(conn.enableLogging, isFalse);
      await conn.initLogger();
      expect(conn.logFile, isNull);
    });

    test('connect() uses instance targetUsername and targetPassword when none provided in arguments', () async {
      String? capturedUser;
      String? capturedPass;

      final conn = SshConnection(
        id: 'test_conn',
        host: '10.0.0.1',
        label: 'TEST',
        targetUsername: 'myuser',
        targetPassword: 'mypassword',
        jumpClusterHost: 'jump.example.com',
        tunnelMode: TunnelMode.legacyInteractive,
      );

      conn.customJumpHostConnector = ({
        required String targetUsername,
        required String targetPassword,
        required NetworkManagerConfig nmConfig,
      }) async {
        capturedUser = targetUsername;
        capturedPass = targetPassword;
        return true;
      };

      final result = await conn.connect(
        nmConfig: const NetworkManagerConfig(
          host: 'jump.example.com',
          port: 22,
          username: 'juser',
          password: 'jpass',
        ),
      );

      expect(result, isTrue);
      expect(capturedUser, 'myuser');
      expect(capturedPass, 'mypassword');
    });

    test('connect() prevents concurrent re-entrant connection attempts', () async {
      final conn = SshConnection(
        id: 'test_conn_concurrent',
        host: '10.0.0.1',
        label: 'TEST',
        targetUsername: 'myuser',
        targetPassword: 'mypassword',
        jumpClusterHost: 'jump.example.com',
        tunnelMode: TunnelMode.legacyInteractive,
      );

      final completer = Completer<bool>();
      int connectAttempts = 0;

      conn.customJumpHostConnector = ({
        required String targetUsername,
        required String targetPassword,
        required NetworkManagerConfig nmConfig,
      }) async {
        connectAttempts++;
        return await completer.future;
      };

      final nmConfig = const NetworkManagerConfig(
        host: 'jump.example.com',
        port: 22,
        username: 'juser',
        password: 'jpass',
      );

      final future1 = conn.connect(nmConfig: nmConfig);
      expect(conn.isConnecting, isTrue);

      final future2 = conn.connect(nmConfig: nmConfig);

      await pumpEventQueue();
      expect(connectAttempts, 1);

      completer.complete(true);
      final r1 = await future1;
      final r2 = await future2;
      expect(r1, isTrue);
      expect(r2, isFalse);
      expect(conn.isConnecting, isFalse);
    });

    test('local shell write converts CR to CRLF on Windows without throwing', () {
      final localProfile = SessionProfile(
        id: 'sess_loc_test',
        name: 'LOCAL',
        protocol: SessionProtocol.local,
        modifiedAt: DateTime.now(),
      );

      final conn = SshConnection.fromSessionProfile(
        localProfile,
        route: ResolvedSshRoute(targetSession: localProfile),
      );

      String? writtenData;
      conn.onDataWritten = (data) {
        writtenData = data;
      };

      // Calling write('\r') should call onDataWritten without throwing even if process not started
      expect(() => conn.write('\r'), returnsNormally);
      expect(writtenData, '\r');

      // Writing characters then DEL (\x7f)
      conn.write('abc');
      expect(() => conn.write('\x7f'), returnsNormally);
      expect(writtenData, '\x7f');
    });

    test('isShellPrompt accurately detects various modern shell prompts and complex escape sequences', () {
      final conn = SshConnection(
        id: 'sess_prompt_test',
        host: '10.0.0.1',
        label: 'TEST',
      );

      // Standard Unix / Root / Windows / Routers
      expect(conn.isShellPrompt('user@host:~\$ '), isTrue);
      expect(conn.isShellPrompt('root@server:~# '), isTrue);
      expect(conn.isShellPrompt('PS C:\\Dev\\projects> '), isTrue);
      expect(conn.isShellPrompt('C:\\Users\\Admin>'), isTrue);
      expect(conn.isShellPrompt('Router# '), isTrue);
      expect(conn.isShellPrompt('[admin@MikroTik] > '), isTrue);

      // OSC titles and Bracketed Paste
      expect(conn.isShellPrompt('\x1b]0;user@host: ~\x07user@host:~\$ '), isTrue);
      expect(conn.isShellPrompt('user@host:~\$ \x1b]0;user@host: ~\x07'), isTrue);
      expect(conn.isShellPrompt('\x1b[?2004huser@host:~\$ '), isTrue);

      // Starship & Powerlevel10k & Oh-My-Zsh prompts
      expect(conn.isShellPrompt('user on main via \u{e718} v18.0.0 \n❯ '), isTrue);
      expect(conn.isShellPrompt('\x1b[38;5;2m~/myproject\x1b[0m \x1b[38;5;4m▶\x1b[0m '), isTrue);
      expect(conn.isShellPrompt('\x1b[01;32m➜\x1b[00m \x1b[01;34mrepo\x1b[00m \x1b[01;31mgit:(main)\x1b[00m '), isTrue);
      expect(conn.isShellPrompt('\x1b[01;32m➜\x1b[00m \x1b[01;34m~/\x1b[00m '), isTrue);

      // Shell Integration (FTCS / OSC 133)
      expect(conn.isShellPrompt('\x1b]133;A\x1b\\user@host:~\$ \x1b]133;B\x1b\\'), isTrue);

      // Password and non-prompts should return false
      expect(conn.isShellPrompt('user@host password: '), isFalse);
      expect(conn.isShellPrompt('Password for admin:'), isFalse);
      expect(conn.isShellPrompt('Enter passphrase: '), isFalse);
      expect(conn.isShellPrompt('Running apt-get update...'), isFalse);
    });

    test('sendCommandAndWaitForPrompt on local shell finishes immediately without 20s hang', () async {
      final localProfile = SessionProfile(
        id: 'sess_local_cmd',
        name: 'LOCAL',
        protocol: SessionProtocol.local,
        modifiedAt: DateTime.now(),
      );

      final conn = SshConnection.fromSessionProfile(
        localProfile,
        route: ResolvedSshRoute(targetSession: localProfile),
      );
      conn.setConnectedForTesting(true);

      final stopwatch = Stopwatch()..start();
      final result = await conn.sendCommandAndWaitForPrompt(
        command: 'echo "hello from nxnb"',
      );
      stopwatch.stop();

      expect(result, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });
}
