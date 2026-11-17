import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/ssh_tab_view.dart';

SshConnection _conn(String id) {
  final c = SshConnection(id: id, host: '10.0.0.1', label: id, enableLogging: false);
  c.setConnectedForTesting(true);
  return c;
}

Widget _stack(List<SshConnection> conns, int index) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            for (final c in conns)
              SshTabView(key: ValueKey(c.id), connection: c, onClose: () {}),
          ],
        ),
      ),
    );

void main() {
  testWidgets('only the tab shown by the stack is a foreground terminal',
      (tester) async {
    final a = _conn('tab-a');
    final b = _conn('tab-b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    await tester.pumpWidget(_stack([a, b], 0));
    await tester.pump();
    expect(a.isForeground, isTrue);
    expect(b.isForeground, isFalse);

    await tester.pumpWidget(_stack([a, b], 1));
    await tester.pump();
    expect(a.isForeground, isFalse);
    expect(b.isForeground, isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
