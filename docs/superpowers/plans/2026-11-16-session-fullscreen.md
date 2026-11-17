# Session Fullscreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the focused SSH session take over the whole screen (OS
fullscreen, no app chrome) and return, via UI controls and Ctrl+Shift+Enter.

**Architecture:** A `SessionFullscreenController` (ChangeNotifier) owned by
`NexusScreenState` holds the target connection and drives
`WindowStateService`. `NexusScreen` swaps its terminal area to a chrome-less
layout. The existing `SshTabView`s keep their `GlobalObjectKey(conn)`, so they
are reparented rather than remounted. `MainScreen` hides the title bar and
sidebar while notified through an `onSessionFullscreenChanged` callback.

**Tech Stack:** Flutter (desktop), window_manager ^0.5.2, xterm, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-16-session-fullscreen-design.md`

## Global Constraints

- Shortcut: **Ctrl+Shift+Enter** (also numpad Enter). Meta counts as Ctrl, like the existing handlers. Alt must not be pressed.
- **Esc never exits fullscreen.**
- Exit hint copy: `Press Ctrl+Shift+Enter to exit fullscreen`, shown for about 2 s.
- Hover bar: hot zone 6 px at the top edge. It hides 1.5 s after the pointer leaves. Content: connection label, then `Exit fullscreen  Ctrl+Shift+Enter`.
- Tab bar button tooltip: `Fullscreen session (Ctrl+Shift+Enter)`. Menu labels: `Fullscreen` / `Exit Fullscreen`.
- Leaving session fullscreen calls `setFullScreen(false)` only if the window was **not** fullscreen before entering.
- `SshTabView` instances must keep `GlobalObjectKey(conn)`. Never construct a second `SshTabView` for the same connection.
- The working tree has unrelated uncommitted changes. Stage **only** the files each task lists.

## Review Focus

1. **Window reports "not fullscreen" mid-transition** (real `windowManager` settling after `setFullScreen(true)`). Expected: session fullscreen does not auto-exit. Covered by the `_settling` guard test in Task 1.
2. **Split view, target in the right pane.** Expected: only the right terminal is visible, and the left pane's terminals are offstage, not disposed, and not resized to 0 columns. Covered by the `split right target` test in Task 3.
3. **The fullscreen session disconnects and shows "Session stopped", then the user presses Enter (closes the tab).** Expected: fullscreen auto-exits and chrome returns. Covered by the `closeTab exits` test in Task 3.
4. **The user presses F11 while in session fullscreen.** Expected: window leaves fullscreen, session fullscreen ends, chrome returns. Covered by the `OS leave` test in Task 1.
5. **Ctrl+Shift+Enter while the terminal is focused.** Expected: toggles, and nothing is written to the remote. Covered by the matcher test (Task 1) and the `SshTabView` swallow test (Task 3).

---

### Task 1: Fullscreen controller, window API, shortcut matcher

**Files:**
- Modify: `lib/services/window_state_service.dart` (add `setFullScreen` next to `toggleFullScreen`, line 56)
- Create: `lib/controllers/session_fullscreen_controller.dart`
- Test: `test/controllers/session_fullscreen_controller_test.dart`

**Interfaces:**
- Produces:
  - `Future<void> WindowStateService.setFullScreen(bool value)`: same optimistic update and `checkWindowState` pattern as `toggleFullScreen`. Refactor `toggleFullScreen` to call `setFullScreen(!_isFullScreen)`.
  - `class SessionFullscreenController extends ChangeNotifier`
    - `SessionFullscreenController({WindowStateService? window})`, defaulting to `WindowStateService.instance`. It adds itself as a listener on `window`.
    - `SshConnection? get target`, `bool get isActive`
    - `Future<void> enter(SshConnection conn)`: no-op if already targeting `conn`. Records `_wasWindowFullscreen = window.isFullScreen`, sets the target, notifies, then sets `_settling = true` and awaits `window.setFullScreen(true)` if not already fullscreen, then sets `_settling = false`.
    - `Future<void> exit()`: no-op if inactive. Clears the target, notifies, and awaits `window.setFullScreen(false)` only if `!_wasWindowFullscreen`.
    - `Future<void> toggle(SshConnection? conn)`: exits if active, enters if `conn != null`.
    - `void onConnectionRemoved(String connectionId)`: calls `exit()` if `target?.id == connectionId`.
    - Window listener: if `isActive && !_settling && !window.isFullScreen`, clear the target and notify. It does not call `setFullScreen`.
  - `bool isSessionFullscreenShortcut(LogicalKeyboardKey key, {required bool ctrl, required bool shift, required bool alt})`: top-level function in the same file. True when `key` is `enter` or `numpadEnter`, `ctrl && shift && !alt`.

- [ ] **Step 1: Write the failing tests.** In `setUp`, call `WindowStateService.instance.resetForTesting()`. In tests, `windowManager` calls throw and are swallowed, so state comes from the optimistic update.

```dart
test('enter sets target and window fullscreen', () async {
  final c = SessionFullscreenController();
  final conn = SshConnection(id: 'a', host: '10.0.0.1', port: 22, label: 'A');
  await c.enter(conn);
  expect(c.isActive, isTrue);
  expect(c.target, same(conn));
  expect(WindowStateService.instance.isFullScreen, isTrue);
});
test('exit restores non-fullscreen window', () async { /* enter, exit → isActive false, isFullScreen false */ });
test('exit keeps window fullscreen if it was already F11 fullscreen', () async {
  WindowStateService.instance.setFullScreenForTesting(true);
  /* enter, exit → isActive false, isFullScreen true */
});
test('OS leave fullscreen ends session fullscreen', () async {
  /* enter; setFullScreenForTesting(false) → isActive false */
});
test('_settling guard: window false during enter does not exit', () async {
  /* start enter() without awaiting; setFullScreenForTesting(false) before the future completes;
     await it → isActive true */
});
test('onConnectionRemoved exits only for target', () async {
  /* enter(a); onConnectionRemoved('b') → active; onConnectionRemoved('a') → inactive */
});
test('isSessionFullscreenShortcut', () {
  expect(isSessionFullscreenShortcut(LogicalKeyboardKey.enter, ctrl: true, shift: true, alt: false), isTrue);
  expect(isSessionFullscreenShortcut(LogicalKeyboardKey.numpadEnter, ctrl: true, shift: true, alt: false), isTrue);
  expect(isSessionFullscreenShortcut(LogicalKeyboardKey.enter, ctrl: true, shift: false, alt: false), isFalse);
  expect(isSessionFullscreenShortcut(LogicalKeyboardKey.enter, ctrl: true, shift: true, alt: true), isFalse);
  expect(isSessionFullscreenShortcut(LogicalKeyboardKey.escape, ctrl: true, shift: true, alt: false), isFalse);
});
```

- [ ] **Step 2:** Run `flutter test test/controllers/session_fullscreen_controller_test.dart`. Expected: FAIL to compile, because the controller does not exist yet.
- [ ] **Step 3:** Implement `setFullScreen` and the controller per Interfaces.
- [ ] **Step 4:** Run the same command. Expected: all PASS. Then run `flutter test test/widgets/window_caption_buttons_test.dart`. Expected: PASS, since the `toggleFullScreen` refactor causes no regression.
- [ ] **Step 5: Commit**

```bash
git add lib/services/window_state_service.dart lib/controllers/session_fullscreen_controller.dart test/controllers/session_fullscreen_controller_test.dart
git commit -m "feat(fullscreen): session fullscreen controller and window setFullScreen"
```

---

### Task 2: Fullscreen overlay (exit hint and hover bar)

**Files:**
- Create: `lib/widgets/session_fullscreen_overlay.dart`
- Test: `test/widgets/session_fullscreen_overlay_test.dart`

**Interfaces:**
- Produces: `SessionFullscreenOverlay({Key? key, required String label, required VoidCallback onExit})`. This is a `StatefulWidget` meant to be placed as a `Positioned.fill` child over the terminal. Hit testing must only claim the 6 px hot zone and the visible pill. Everywhere else stays transparent to pointer events so terminal selection still works.
  - On mount it shows the hint pill (bottom-center) with the exact Global Constraints copy for 2 s, then fades it out.
  - A `MouseRegion` hot zone 6 px tall across the top edge shows the bar (top-center pill, `key: ValueKey('session_fullscreen_bar')`). The bar holds the label and a `TextButton` with `Icons.fullscreen_exit`, label `Exit fullscreen`, and trailing `Ctrl+Shift+Enter`. The bar stays while hovered and hides 1.5 s after exit. Tapping the button calls `onExit`.
  - Use `AppTheme.activePalette` colors. Respect the existing reduce-motion setting the way `test/widgets/reduce_motion_test.dart` exercises (zero-duration fades).

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('hint shows then disappears after 2s', (t) async {
  await t.pumpWidget(wrap(SessionFullscreenOverlay(label: 'root@db', onExit: () {})));
  expect(find.text('Press Ctrl+Shift+Enter to exit fullscreen'), findsOneWidget);
  await t.pump(const Duration(seconds: 2)); await t.pumpAndSettle();
  expect(find.text('Press Ctrl+Shift+Enter to exit fullscreen'), findsNothing);
});
testWidgets('hover top edge shows bar; exit button calls onExit', (t) async {
  // TestGesture(kind: PointerDeviceKind.mouse) moveTo(Offset(400, 2)) → bar finds 'root@db' and 'Exit fullscreen'
  // tap 'Exit fullscreen' → onExit called once
  // moveTo(Offset(400, 300)); pump 1.5s; pumpAndSettle → bar gone
});
testWidgets('pointer below hot zone does not show bar', (t) async { /* moveTo(400, 50) → no bar */ });
```

- [ ] **Step 2:** Run `flutter test test/widgets/session_fullscreen_overlay_test.dart`. Expected: FAIL, because the widget does not exist yet.
- [ ] **Step 3:** Implement per Interfaces.
- [ ] **Step 4:** Run the same command. Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/widgets/session_fullscreen_overlay.dart test/widgets/session_fullscreen_overlay_test.dart
git commit -m "feat(fullscreen): exit hint and top-edge hover bar overlay"
```

---

### Task 3: NexusScreen and SshTabView integration

**Files:**
- Modify: `lib/screens/nexus_screen.dart`. Add a widget param, a controller field and the public API near `toggleCommandPane` (line 259). Add a guard in `_handleGlobalKeyEvent` before the tab navigation block (around line 388). Dispose the controller.
- Modify: `lib/screens/nexus_screen_view.dart`. Add the fullscreen branch at the top of `_buildTerminalMainArea` (line 36). Extract the pane `IndexedStack` builder. Add the tab bar button next to `_buildSplitButton()` (lines 113 and 132).
- Modify: `lib/screens/nexus_screen_command_pane.dart`. Add `_buildFullscreenButton()` modeled on `_buildSplitButton` (line 737).
- Modify: `lib/screens/nexus_screen_tabs.dart`. In `_closeTab`, `_closeAllTabs` and `_closeOtherTabs`, call `_fullscreen.onConnectionRemoved(id)` for each removed connection. Add a `fullscreen` item to `_showTabContextMenu` (line 302).
- Modify: `lib/widgets/ssh_tab_view.dart`. Add new params, the shortcut swallow at the top of `_handleKeyEvent` (line 314, before the `_isSessionStopped` block), and a context menu item.
- Test: `test/screens/nexus_screen_fullscreen_test.dart`

**Interfaces:**
- Consumes: `SessionFullscreenController` and `isSessionFullscreenShortcut` (Task 1), `SessionFullscreenOverlay` (Task 2).
- Produces:
  - `NexusScreen({..., ValueChanged<bool>? onSessionFullscreenChanged})`
  - `NexusScreenState`:
    - `bool get isSessionFullscreen`
    - `Future<void> toggleSessionFullscreen([SshConnection? conn])`, where `conn` defaults to `_activeConnection`
    - `Future<void> exitSessionFullscreen()`
    - `@visibleForTesting SessionFullscreenController get fullscreenController`
    - `@visibleForTesting void debugAddTab(SshConnection conn, {bool isRightPane = false})`, which calls `_tabController.addTab` and `setState`
  - Entering on a connection selects its tab and pane first (`_activeTab` / `_activeRightTab`, `_lastActivePaneIsRight`). The controller listener calls `setState`, `widget.onSessionFullscreenChanged?.call(isActive)` and `_focusActiveTerminal()`.
  - `SshTabView({..., bool isFullscreen = false, VoidCallback? onToggleFullscreen})`. On the matcher, `_handleKeyEvent` returns `KeyEventResult.handled` without writing. The context menu gets a new item after `Save Output to File`: `Fullscreen` / `Exit Fullscreen` with `Icons.fullscreen` / `Icons.fullscreen_exit` and trailing `Ctrl+Shift+Enter`. It is shown only when `onToggleFullscreen != null`.
- **Fullscreen layout** (`_buildFullscreenArea()`): a `Stack` with
  - left pane `IndexedStack` and right pane `IndexedStack` as `Positioned.fill`, the non-target pane wrapped in `Offstage` + `ExcludeFocus`. Use one extracted `_buildPaneStack({required bool isRightPane})` for both normal and fullscreen layouts, so each `SshTabView` is constructed in exactly one place.
  - the floating command pane when `_showCommandPane`, positioned as in the normal layout
  - `SessionFullscreenOverlay(label: target.currentLabel, onExit: exitSessionFullscreen)`
  - No tab bar and no prod banner. The right runbook sidebar is `Offstage` while fullscreen (in `build`, line 607: `offstage: !_isRightSidebarVisible || isSessionFullscreen`), and the `Material` card wrapper is skipped.
- **Global key handler:** while `isSessionFullscreen`, return `false` early for Ctrl+Tab, Ctrl+T, Ctrl+PageUp/PageDown and Ctrl+Shift+Tab/T. These are then swallowed by `SshTabView` as they are today. Also handle `isSessionFullscreenShortcut` here when `widget.onSessionFullscreenChanged == null` (standalone NexusScreen, same pattern as Ctrl+Shift+Space at line 317).

- [ ] **Step 1: Write failing widget tests.** Pump `MaterialApp(home: NexusScreen(onSessionFullscreenChanged: log.add))` with `WindowStateService.instance.resetForTesting()`. Add tabs with `debugAddTab(SshConnection(id:'a', host:'127.0.0.1', port: 1, label:'A'))`. Port 1 fails fast. If the connect attempt is still noisy, use `tester.runAsync` around pump.

```dart
testWidgets('enter hides tab bar and shows overlay; exit restores', ...);
  // tab label 'A' visible in tab strip → toggleSessionFullscreen() → pump
  // expect(find.byTooltip('Fullscreen session (Ctrl+Shift+Enter)'), findsNothing)
  // expect(find.byType(SessionFullscreenOverlay), findsOneWidget); expect(log, [true])
  // exitSessionFullscreen() → tooltip back, overlay gone, log == [true, false]
testWidgets('SshTabView state preserved across enter/exit', ...);
  // final s1 = tester.state<SshTabViewState>(find.byKey(GlobalObjectKey(conn)));
  // enter + exit → expect(tester.state(...), same(s1))
testWidgets('split right target: left pane offstage, not disposed', ...);
  // debugAddTab(a); debugAddTab(b, isRightPane: true); toggleSplitView(); toggleSessionFullscreen(b)
  // expect(find.byKey(GlobalObjectKey(a), skipOffstage: false), findsOneWidget)
  // expect(find.byKey(GlobalObjectKey(a)), findsNothing)  // offstage
  // expect(find.byKey(GlobalObjectKey(b)), findsOneWidget)
testWidgets('closeTab exits fullscreen', ...);
  // enter(a) → state.closeTab... via tab context menu 'close' or public close path → isSessionFullscreen false
testWidgets('Ctrl+Shift+Enter in terminal toggles and writes nothing', ...);
  // record conn.terminal output listener / onOutput; focus SshTabView; send Ctrl+Shift+Enter
  // expect(state.isSessionFullscreen, isTrue); expect(writtenToRemote, isEmpty)
testWidgets('Ctrl+Tab ignored while fullscreen', ...);
  // two tabs, enter(a); send Ctrl+Tab → activeTabIndex unchanged
```

- [ ] **Step 2:** Run `flutter test test/screens/nexus_screen_fullscreen_test.dart`. Expected: FAIL (missing API).
- [ ] **Step 3:** Implement per Interfaces.
- [ ] **Step 4:** Run the same command. Expected: PASS. Then run `flutter test test/controllers test/widgets/interactive_runbook_sidebar_test.dart`. Expected: PASS (no regression).
- [ ] **Step 5: Commit**

```bash
git add lib/screens/nexus_screen.dart lib/screens/nexus_screen_view.dart lib/screens/nexus_screen_command_pane.dart lib/screens/nexus_screen_tabs.dart lib/widgets/ssh_tab_view.dart test/screens/nexus_screen_fullscreen_test.dart
git commit -m "feat(fullscreen): session fullscreen layout, button, menus and shortcut in Nexus"
```

---

### Task 4: MainScreen chrome, global shortcut, palette, help

**Files:**
- Modify: `lib/screens/main_screen.dart`. Add a `_isSessionFullscreen` field, the `NexusScreen(onSessionFullscreenChanged: ...)` hookup at line 1427, the chrome hiding in `build` (line 973), the shortcut in `_handleKeyEvent` before the F11 block (line 390), auto-exit in `_selectTab` (line 461) / `_toggleSettings` / `_openStartupSessionsDialog`, and the palette case near `CommandAction.toggleSplitView` (line 675).
- Modify: `lib/widgets/command_palette.dart`. Add the enum value `toggleSessionFullscreen` and an item after `Toggle Split View` (line 108). Label `Toggle Session Fullscreen`, subtitle `Fill the screen with the active SSH session`, icon `Icons.fullscreen`.
- Modify: `lib/widgets/keyboard_shortcuts_dialog.dart`. Add a `ShortcutEntry(command: 'Toggle Session Fullscreen', keys: ['Ctrl', 'Shift', 'Enter'], when: 'terminalFocused', source: 'Smart-E HE')` after the F11 entry (line 310). Match the `when` value used by existing terminal entries in that file.
- Test: `test/screens/main_screen_test.dart` (append)

**Interfaces:**
- Consumes: `NexusScreenState.isSessionFullscreen`, `toggleSessionFullscreen()`, `exitSessionFullscreen()`, `fullscreenController`, `debugAddTab` (Task 3).
- Behavior:
  - While `_isSessionFullscreen`, `build` omits `_buildTitleBar()`, `_buildSidebar()` and `_buildResizeHandle()`, and renders `_buildBodyContent()` with no margin, shadow, border or rounded `Material`. The `IndexedStack` that holds `NexusScreen` must remain the same element, so `NexusScreen` state is not lost. Keep it at the same tree position and change only its wrappers' properties, or give the body a `GlobalKey`.
  - Global shortcut: if `isSessionFullscreenShortcut(...)` and `_isNexusActive`, call `_nexusKey.currentState?.toggleSessionFullscreen()` and return `true`.
  - Before switching away from Nexus (`_selectTab` to a non-Nexus tab, `_toggleSettings`, `_openStartupSessionsDialog`, `_selectCustomTool`), call `_nexusKey.currentState?.exitSessionFullscreen()`.

- [ ] **Step 1: Append failing tests**

```dart
testWidgets('session fullscreen hides title bar and sidebar, exit restores', (tester) async {
  // pump createTestWidget(); final nexus = tester.state<NexusScreenState>(find.byType(NexusScreen));
  // nexus.debugAddTab(SshConnection(id:'a', host:'127.0.0.1', port:1, label:'A'));
  // await nexus.toggleSessionFullscreen(); pump
  // expect(find.byTooltip('Session Manager'), findsNothing); expect(find.text('File Explorer'), findsNothing)
  // await nexus.exitSessionFullscreen(); pump → both found again
});
testWidgets('Ctrl+Shift+Enter toggles session fullscreen globally on Nexus', ...);
testWidgets('switching to File Explorer (Alt+3) exits session fullscreen', ...);
  // enter → Alt+3 → nexus.isSessionFullscreen false, sidebar visible
testWidgets('command palette lists Toggle Session Fullscreen', ...);
  // Ctrl+Shift+P → find.text('Toggle Session Fullscreen') findsOneWidget
```

- [ ] **Step 2:** Run `flutter test test/screens/main_screen_test.dart`. Expected: the new tests FAIL and the existing ones PASS.
- [ ] **Step 3:** Implement per Behavior.
- [ ] **Step 4:** Run `flutter test` (full suite) and `flutter analyze`. Expected: all tests PASS and analyze reports no new issues.
- [ ] **Step 5: Manual check on Windows.** Run `flutter run -d windows`, open an SSH session, then check:
  - Ctrl+Shift+Enter makes the window fullscreen with only the terminal visible, and the hint shows.
  - Hovering the top edge shows the bar, and Exit restores.
  - F11, then Ctrl+Shift+Enter twice, leaves the window fullscreen.
  - In fullscreen, F11 restores everything.
  - vim Esc still works in fullscreen.
- [ ] **Step 6: Commit**

```bash
git add lib/screens/main_screen.dart lib/widgets/command_palette.dart lib/widgets/keyboard_shortcuts_dialog.dart test/screens/main_screen_test.dart
git commit -m "feat(fullscreen): hide app chrome, global shortcut, palette and help entry"
```

Note: `test/screens/main_screen_test.dart` already has uncommitted changes in the working tree. Before staging, ask the user whether to include them, or stage only the new hunks with a patch.
