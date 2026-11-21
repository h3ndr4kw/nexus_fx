import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/services/ssh_service.dart';
import 'package:nexus_fx/theme/app_theme.dart';
import 'package:nexus_fx/widgets/ssh_tab_view.dart';
import 'package:nexus_fx/widgets/terminal_find_bar.dart';

SshConnection _conn() {
  final c = SshConnection(
      id: 'find', host: '10.0.0.1', label: 'find', enableLogging: false);
  c.setConnectedForTesting(true);
  return c;
}

Widget _app(SshConnection c) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: SshTabView(connection: c, onClose: () {})),
    );

Future<void> _ctrlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

String _status(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('terminal-find-status')))
    .data!;

void main() {
  testWidgets('Ctrl+F opens the find bar, counts hits and Escape closes it',
      (tester) async {
    final c = _conn();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump();
    c.terminal.write('alpha error\r\nbeta\r\ngamma error\r\n');
    await tester.pump();

    expect(find.byType(TerminalFindBar), findsNothing);
    await _ctrlF(tester);
    expect(find.byType(TerminalFindBar), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('terminal-find-field')), 'error');
    await tester.pump(const Duration(milliseconds: 200));
    // Starts at the newest hit.
    expect(_status(tester), '2 of 2');
    // Two dim hits plus the current one.
    expect(c.terminalController.highlights, hasLength(3));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_status(tester), '1 of 2');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_status(tester), '2 of 2', reason: 'wraps around');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(TerminalFindBar), findsNothing);
    expect(c.terminalController.highlights, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows no results and invalid regex states', (tester) async {
    final c = _conn();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump();
    c.terminal.write('hello\r\n');
    await _ctrlF(tester);

    final field = find.byKey(const ValueKey('terminal-find-field'));
    await tester.enterText(field, 'missing');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_status(tester), 'No results');

    await tester.tap(find.text('.*'));
    await tester.enterText(field, '(');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_status(tester), 'Invalid regex');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the context menu offers Find', (tester) async {
    final c = _conn();
    addTearDown(c.dispose);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    await tester.tapAt(tester.getCenter(find.byType(SshTabView)),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Find...'), findsOneWidget);

    await tester.tap(find.text('Find...'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(TerminalFindBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  group('scrollback', () {
    test('defaults to 10000 lines', () {
      final c = SshConnection(
          id: 'sb', host: 'h', label: 'sb', enableLogging: false);
      addTearDown(c.dispose);
      expect(c.terminal.maxLines, 10000);
      expect(SessionProfile.fromJson({'id': '1', 'name': 'x', 'host': 'h'}).scrollbackLines,
          10000);
    });

    test('a stored legacy 5000 reads as the new default', () {
      expect(
          SessionProfile.fromJson(
              {'id': '1', 'name': 'x', 'host': 'h', 'scrollbackLines': 5000}).scrollbackLines,
          10000);
      expect(
          SessionProfile.fromJson(
              {'id': '1', 'name': 'x', 'host': 'h', 'scrollbackLines': 20000}).scrollbackLines,
          20000);
    });

    test('the session value reaches the terminal, clamped', () {
      final big = SshConnection(
          id: 'a', host: 'h', label: 'a', enableLogging: false,
          scrollbackLines: 50000);
      final tiny = SshConnection(
          id: 'b', host: 'h', label: 'b', enableLogging: false,
          scrollbackLines: 1);
      addTearDown(big.dispose);
      addTearDown(tiny.dispose);
      expect(big.terminal.maxLines, 50000);
      expect(tiny.terminal.maxLines, kMinScrollbackLines);
    });
  });
}
