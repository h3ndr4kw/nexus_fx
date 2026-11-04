# NexusScreen Modular Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Modularize `nexus_screen.dart` (~3,900 lines) by extracting dedicated state controllers and reusable indicator widgets, establishing clean Separation of Concerns (SoC) for tab management, broadcast coordination, and visual pulse indicators while maintaining 100% test pass fidelity across the entire test suite.

---

## File Structure & Proposed Changes

| Action | Path | Description |
| :--- | :--- | :--- |
| **Create** | `lib/widgets/radar_pulse_indicator.dart` | Extract `RadarPulseIndicator`, `_RadarPulsePainter`, and `CyanPulseDot` out of `nexus_screen.dart`. |
| **Create** | `lib/controllers/terminal_tab_controller.dart` | Dedicated `ChangeNotifier` managing left/right tabs, active index, split pane state, tab relocation, and disconnect cleanup. |
| **Create** | `lib/controllers/broadcast_coordinator.dart` | Dedicated `ChangeNotifier` managing broadcast targeting, host multi-selection, command history navigation, and broadcast execution. |
| **Create** | `test/controllers/terminal_tab_controller_test.dart` | Comprehensive unit tests for `TerminalTabController`. |
| **Create** | `test/controllers/broadcast_coordinator_test.dart` | Comprehensive unit tests for `BroadcastCoordinator`. |
| **Modify** | `lib/screens/nexus_screen.dart` | Wire `TerminalTabController` and `BroadcastCoordinator` into `NexusScreenState`, delegating tab & broadcast state while preserving existing public API and test accessors. |

---

## Task 1: Extract Pulse Indicator Widgets to Dedicated Widget File

**Files:**
- Create: `lib/widgets/radar_pulse_indicator.dart`
- Modify: `lib/screens/nexus_screen.dart`

- [x] **Step 1.1**: Create `lib/widgets/radar_pulse_indicator.dart` containing `RadarPulseIndicator`, `_RadarPulsePainter`, and `CyanPulseDot`.
- [x] **Step 1.2**: Import `lib/widgets/radar_pulse_indicator.dart` into `lib/screens/nexus_screen.dart` and remove the duplicate inline classes.
- [x] **Step 1.3**: Run `flutter test test/services/pulse_settings_test.dart` to verify that existing pulse settings and radar tests continue to pass.

---

## Task 2: Create & Test `TerminalTabController`

**Files:**
- Create: `lib/controllers/terminal_tab_controller.dart`
- Create: `test/controllers/terminal_tab_controller_test.dart`

- [x] **Step 2.1**: Write unit tests in `test/controllers/terminal_tab_controller_test.dart` testing:
  - Initial state (empty left & right tabs, split view false).
  - Adding tabs to left pane and right pane.
  - Active tab index tracking and boundary clamps.
  - Toggling split view and closing tabs.
  - Auto-close callback triggers when connection is closed.
- [x] **Step 2.2**: Run `flutter test test/controllers/terminal_tab_controller_test.dart` (verify test failure before implementation).
- [x] **Step 2.3**: Implement `TerminalTabController` in `lib/controllers/terminal_tab_controller.dart` extending `ChangeNotifier`.
- [x] **Step 2.4**: Run `flutter test test/controllers/terminal_tab_controller_test.dart` (verify test passes).

---

## Task 3: Create & Test `BroadcastCoordinator`

**Files:**
- Create: `lib/controllers/broadcast_coordinator.dart`
- Create: `test/controllers/broadcast_coordinator_test.dart`

- [x] **Step 3.1**: Write unit tests in `test/controllers/broadcast_coordinator_test.dart` testing:
  - Setting broadcast target (`all`, `left`, `right`, `custom`).
  - Selection synchronization based on target and connected state.
  - Command history recording, deduplication, and Up/Down history navigation.
  - Resolving active target connections for execution.
- [x] **Step 3.2**: Run `flutter test test/controllers/broadcast_coordinator_test.dart` (verify test failure before implementation).
- [x] **Step 3.3**: Implement `BroadcastCoordinator` in `lib/controllers/broadcast_coordinator.dart` extending `ChangeNotifier`.
- [x] **Step 3.4**: Run `flutter test test/controllers/broadcast_coordinator_test.dart` (verify test passes).

---

## Task 4: Integrate Controllers into `NexusScreen` & Regression Verification

**Files:**
- Modify: `lib/screens/nexus_screen.dart`

- [x] **Step 4.1**: Wire `TerminalTabController` into `NexusScreenState` for managing tab collections, active tab indices, and split state.
- [x] **Step 4.2**: Wire `BroadcastCoordinator` into `NexusScreenState` for managing broadcast target, history navigation, and execution.
- [x] **Step 4.3**: Preserve all existing `@visibleForTesting` getters (`tabs`, `rightTabs`, `activeTabIndex`, `commandHistory`, `broadcastTarget`, `setBroadcastTargetForTesting`, etc.) via delegation to the new controllers to ensure backward compatibility.
- [x] **Step 4.4**: Run the entire Flutter test suite: `flutter test`. Verify all tests (61+ tests) pass without regression.
