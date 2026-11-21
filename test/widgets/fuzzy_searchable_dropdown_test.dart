import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/fuzzy_searchable_dropdown.dart';

/// Hosts the dropdown the way the settings screen does: the selection lives
/// in the parent and [onPick] decides how it is applied.
class _Host extends StatefulWidget {
  const _Host({required this.onPick});

  final void Function(_HostState state, String value) onPick;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String selected = 'Attached';

  void select(String value) => setState(() => selected = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: FuzzySearchableDropdown<String>(
              items: const ['Pill', 'Classic', 'Attached'],
              selectedItem: selected,
              itemLabel: (s) => s,
              onChanged: (val) {
                if (val != null) widget.onPick(this, val);
              },
            ),
          ),
        ),
      ),
    );
  }
}

Finder _checkInRow(String label) => find.descendant(
      of: find.ancestor(of: find.text(label).last, matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.check),
    );

void main() {
  testWidgets('picking an item closes the menu and moves the check', (tester) async {
    await tester.pumpWidget(_Host(
      onPick: (state, val) => state.select(val),
    ));

    await tester.tap(find.text('Attached'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Classic').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    expect(_checkInRow('Classic'), findsOneWidget);
    expect(_checkInRow('Attached'), findsNothing);
  });

  testWidgets('the menu still closes when onChanged throws', (tester) async {
    await tester.pumpWidget(_Host(
      onPick: (state, val) {
        state.selected = val;
        throw StateError('caller failed');
      },
    ));

    await tester.tap(find.text('Attached'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Classic').last);
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
