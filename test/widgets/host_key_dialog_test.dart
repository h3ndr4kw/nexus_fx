import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/known_hosts_service.dart';
import 'package:nexus_fx/widgets/host_key_dialog.dart';

const _fp = 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _old = 'SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Future<HostKeyDecision?> _open(WidgetTester tester, HostKeyPromptRequest req, String tap) async {
  HostKeyDecision? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => result = await showHostKeyDialog(context, req),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text(_fp), findsOneWidget);
  await tester.tap(find.text(tap));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  const unknown = HostKeyPromptRequest(
    host: '10.0.0.5',
    port: 22,
    keyType: 'ssh-ed25519',
    fingerprint: _fp,
    status: HostKeyStatus.unknown,
  );
  const changed = HostKeyPromptRequest(
    host: '10.0.0.5',
    port: 2222,
    keyType: 'ssh-ed25519',
    fingerprint: _fp,
    status: HostKeyStatus.changed,
    previousFingerprint: _old,
  );

  testWidgets('first contact: trust, once, or cancel', (tester) async {
    expect(await _open(tester, unknown, 'Trust & connect'), HostKeyDecision.trustAlways);
    expect(await _open(tester, unknown, 'Connect once'), HostKeyDecision.trustOnce);
    expect(await _open(tester, unknown, 'Cancel'), HostKeyDecision.reject);
  });

  testWidgets('changed key shows both fingerprints and defaults to cancel', (tester) async {
    expect(await _open(tester, changed, 'Cancel connection'), HostKeyDecision.reject);
    expect(await _open(tester, changed, 'Replace key & connect'), HostKeyDecision.trustAlways);
  });

  testWidgets('changed key lists the previously trusted fingerprint', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HostKeyDialog(request: changed))));
    expect(find.text('Host key has changed'), findsOneWidget);
    expect(find.text(_old), findsOneWidget);
    expect(find.textContaining('10.0.0.5:2222', findRichText: true), findsOneWidget);
  });
}
