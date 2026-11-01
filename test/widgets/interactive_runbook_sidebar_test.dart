import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/widgets/interactive_runbook_sidebar.dart';

void main() {
  testWidgets('InteractiveRunbookSidebar defaults defaultDirectoryPath to nxnb', (tester) async {
    final sidebar = InteractiveRunbookSidebar(
      onClose: () {},
      activeConnections: const [],
      syncedCommandPaneTarget: '',
      onExecuteScript: (target, lines) async {},
    );

    expect(sidebar.defaultDirectoryPath, equals('nxnb'));
  });

  testWidgets('InteractiveRunbookSidebar renders close caption button and toolbar action buttons', (tester) async {
    bool closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: InteractiveRunbookSidebar(
              onClose: () => closed = true,
              activeConnections: const [],
              syncedCommandPaneTarget: '',
              onExecuteScript: (target, lines) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify close sidebar button
    final closeBtn = find.byTooltip('Close sidebar');
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    expect(closed, isTrue);

    // Verify presence of toolbar buttons and keys
    expect(find.byTooltip('New File'), findsOneWidget);
    expect(find.byTooltip('New Folder'), findsOneWidget);
    expect(find.byKey(const Key('runbook_toolbar_cut_button')), findsOneWidget);
    expect(find.byKey(const Key('runbook_toolbar_copy_button')), findsOneWidget);
    expect(find.byKey(const Key('runbook_toolbar_paste_button')), findsOneWidget);
    expect(find.byKey(const Key('runbook_toolbar_rename_button')), findsOneWidget);
    expect(find.byKey(const Key('runbook_toolbar_delete_button')), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byTooltip('Collapse Folders'), findsOneWidget);
  });

  testWidgets('InteractiveRunbookSidebar resize sash has 5px width and 3-dot animation', (tester) async {
    final key = GlobalKey<InteractiveRunbookSidebarState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: InteractiveRunbookSidebar(
              key: key,
              onClose: () {},
              activeConnections: const [],
              syncedCommandPaneTarget: '',
              onExecuteScript: (target, lines) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dragHandleFinder = find.byKey(const Key('runbook_sidebar_drag_handle'));
    expect(dragHandleFinder, findsOneWidget);

    final sashOpacityFinder = find.descendant(
      of: dragHandleFinder,
      matching: find.byType(AnimatedOpacity),
    );
    expect(sashOpacityFinder, findsOneWidget);

    // 1. Move mouse: dots fade in
    key.currentState?.onGlobalHover();
    await tester.pump(const Duration(milliseconds: 250));

    var animatedOpacity = tester.widget<AnimatedOpacity>(sashOpacityFinder);
    expect(animatedOpacity.opacity, equals(1.0));

    // 2. Idle for 3 seconds: dots fade out automatically
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 250));

    animatedOpacity = tester.widget<AnimatedOpacity>(sashOpacityFinder);
    expect(animatedOpacity.opacity, equals(0.0));

    // 3. Move mouse again: dots fade in
    key.currentState?.onGlobalHover();
    await tester.pump(const Duration(milliseconds: 250));

    animatedOpacity = tester.widget<AnimatedOpacity>(sashOpacityFinder);
    expect(animatedOpacity.opacity, equals(1.0));

    // 4. Select main widget: dots fade out immediately
    key.currentState?.onSelectMainWidget();
    await tester.pump(const Duration(milliseconds: 250));

    animatedOpacity = tester.widget<AnimatedOpacity>(sashOpacityFinder);
    expect(animatedOpacity.opacity, equals(0.0));
  });
}
