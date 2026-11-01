# NexusFX (`nexus_fx`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the standalone `nexus_fx` desktop application in `c:\Dev\projects\nexus_fx` featuring the Nexus Terminal + Nexus Notebook, Dual-Pane SFTP File Explorer, and an Xshell-style hierarchical Session Manager (supporting Direct SSH, Jump Host SSH, and Local Shell sessions) without Header Enrichment (HE) modules or Login screens.

**Architecture:** Extract the core UI theme, `NexusScreen`, `InteractiveRunbookSidebar`, `FileExplorerView`, and SSH/Tunneling services from `smart_e_he_app` into `c:\Dev\projects\nexus_fx`, replacing `NodeService`/`ClusterCredentialService`/`AuthService` with a unified local `SessionManagerService` (`lib/services/session_manager_service.dart`) and `SessionProfile`/`SessionFolder` models (`lib/models/session_models.dart`).

**Tech Stack:** Flutter Desktop (Windows/Linux/macOS, Dart SDK `^3.12.2`), `dartssh2: ^4.1.0`, `xterm: ^4.0.0`, `window_manager: ^0.5.2`, `file_selector: ^1.1.0`, `crypto: ^3.0.7`, `yaml: ^3.1.3`.

**Spec:** `docs/superpowers/specs/2026-10-30-nexus-fx-design.md` (copied into `c:\Dev\projects\nexus_fx\docs\superpowers\specs\2026-10-30-nexus-fx-design.md` in Task 1)

## Global Constraints

- **Target Directory:** `c:\Dev\projects\nexus_fx` (package name: `nexus_fx`, window title: `NexusFX`).
- **Searchable Dropdowns Rule (`GEMINI.md`):** Every selection dropdown (protocol, auth method, jump host mode, existing jump host session, terminal color scheme, file explorer target selector, notebook target selector) MUST use `FuzzySearchableDropdown` (`lib/widgets/fuzzy_searchable_dropdown.dart`) and never plain `DropdownButton` or `DropdownButtonFormField`.
- **No HE Modules or Firebase Auth:** Do not include `LoginScreen`, `AdminDashboardScreen`, `DeploymentScreen`, `HealthCheckScreen`, `CertificateManagementScreen`, `BulkFileTransferScreen`, `SslMulticertView`, `UnusedFilesView`, or `NodeMapView`.
- **Direct Startup:** Launch directly into `MainScreen` (with optional `SessionsDialog` popup on startup when `SettingsService.instance.showSessionDialogAtStartup` is true).

## Review Focus

1. **Circular Jump Host Chain (`A -> B -> A` or `A -> A`):** `SessionManagerService.resolveConnectionConfig` must track visited session IDs and throw `CircularJumpHostException` rather than entering an infinite recursion.
2. **Same-Folder Copy/Paste (Duplicate Session):** Copying a session and pasting into the same `parentId` must generate a new unique `id` and disambiguated name (`<Name> - Copy`, `<Name> - Copy (2)`) without overwriting the original session.
3. **Recursive Folder Copy & Delete:** Copying and pasting a folder must deep-clone all descendant folders and sessions with newly remapped `id` and `parentId` values; deleting a folder must remove all descendant folders and sessions.
4. **Deleting a Referenced Jump Host Session:** Deleting a session whose `id` is referenced by another session's `jumpSessionId` must reset the dependent session's `jumpHostMode` to `JumpHostMode.direct` (and `jumpSessionId` to `null`) after user confirmation so dependent sessions do not hold dangling IDs.
5. **Local Shell Process Cleanup on Tab Close:** Closing a `SessionProtocol.local` terminal tab must terminate the underlying local OS shell `Process` (`powershell.exe` / `bash`) to prevent orphaned background shell processes.

---

### Task 1: Project Scaffolding, Docs Migration & Core Models (`session_models.dart`)

**Files:**
- Create: `c:\Dev\projects\nexus_fx\GEMINI.md`
- Create: `c:\Dev\projects\nexus_fx\docs\superpowers\specs\2026-10-30-nexus-fx-design.md`
- Create: `c:\Dev\projects\nexus_fx\docs\superpowers\plans\2026-10-30-nexus-fx-implementation-plan.md`
- Create: `c:\Dev\projects\nexus_fx\pubspec.yaml`
- Create: `c:\Dev\projects\nexus_fx\lib\models\session_models.dart`
- Create: `c:\Dev\projects\nexus_fx\test\models\session_models_test.dart`

**Interfaces:**
- Produces:
  - `enum SessionProtocol { ssh, local }`
  - `enum AuthMethod { password, privateKey }`
  - `enum JumpHostMode { direct, existingSession, customJumpHost }`
  - `class SessionFolder` (`id`, `parentId`, `name`, `description`, `modifiedAt`, `copyWith`, `toJson`, `fromJson`)
  - `class SessionProfile` (`id`, `parentId`, `name`, `protocol`, `host`, `port`, `fallbackHost`, `description`, `autoReconnect`, `reconnectIntervalSec`, `reconnectLimitMin`, `username`, `authMethod`, `password`, `privateKeyPath`, `privateKeyPassphrase`, `loginScript`, `jumpHostMode`, `jumpSessionId`, `customJumpHost`, `customJumpPort`, `customJumpFallbackHost`, `customJumpUsername`, `customJumpPassword`, `tunnelMode`, `customThemeName`, `customFontSize`, `scrollbackLines`, `enableSessionLogging`, `modifiedAt`, `copyWith`, `toJson`, `fromJson`)

- [ ] **Step 1: Scaffold `c:\Dev\projects\nexus_fx` and copy `GEMINI.md`, design spec, and implementation plan**
  Copy platform runners (`windows/`, `linux/`, `macos/`), `analysis_options.yaml`, `assets/`, and base non-HE shared files (`lib/theme/`, `lib/models/playbook_models.dart`, `lib/models/ssh_tunnel_models.dart`, `lib/widgets/fuzzy_searchable_dropdown.dart`, `lib/widgets/window_caption_buttons.dart`, `lib/widgets/sidebar_icon.dart`, `lib/widgets/shimmer_loading.dart`, `lib/widgets/animated_gradient_border.dart`, `lib/widgets/table_column_filter_header.dart`) from `c:\Dev\projects\header_enrichment\smart_e_he\smart_e_he_app` to `c:\Dev\projects\nexus_fx`, updating `pubspec.yaml` name to `nexus_fx` and package imports from `package:smart_e_he/` to `package:nexus_fx/`. Copy `GEMINI.md`, the spec, and this plan into `c:\Dev\projects\nexus_fx`.

- [ ] **Step 2: Write the failing test in `c:\Dev\projects\nexus_fx\test\models\session_models_test.dart`**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_fx/models/session_models.dart';
import 'package:nexus_fx/models/ssh_tunnel_models.dart';

void main() {
  test('SessionProfile serializes and deserializes with obfuscated password and jump host fields', () {
    final profile = SessionProfile(
      id: 'sess_1',
      parentId: 'folder_1',
      name: 'DOCKER_SERVER',
      protocol: SessionProtocol.ssh,
      host: '192.168.1.146',
      port: 22,
      username: 'docker-server',
      password: 'secret-password',
      jumpHostMode: JumpHostMode.existingSession,
      jumpSessionId: 'sess_jump_1',
      tunnelMode: TunnelMode.multiplexed,
      modifiedAt: DateTime.utc(2026, 8, 13, 13, 31, 10),
    );

    final json = profile.toJson();
    expect(json['password'], isNot(equals('secret-password')));

    final restored = SessionProfile.fromJson(json);
    expect(restored.id, 'sess_1');
    expect(restored.parentId, 'folder_1');
    expect(restored.name, 'DOCKER_SERVER');
    expect(restored.host, '192.168.1.146');
    expect(restored.password, 'secret-password');
    expect(restored.jumpHostMode, JumpHostMode.existingSession);
    expect(restored.jumpSessionId, 'sess_jump_1');
  });
}
```

- [ ] **Step 3: Run test to verify it fails**
  Run: `flutter test test/models/session_models_test.dart` (in `c:\Dev\projects\nexus_fx`)
  Expected: FAIL (`session_models.dart` not found)

- [ ] **Step 4: Implement `c:\Dev\projects\nexus_fx\lib\models\session_models.dart`**
  Implement `SessionProtocol`, `AuthMethod`, `JumpHostMode`, `SessionFolder`, and `SessionProfile` with reversible credential obfuscation for `password`, `privateKeyPassphrase`, and `customJumpPassword` in `toJson`/`fromJson`.

- [ ] **Step 5: Run test to verify it passes**
  Run: `flutter test test/models/session_models_test.dart`
  Expected: PASS

---

### Task 2: `SessionManagerService` (CRUD, Hierarchy, Cut/Copy/Paste, Jump Host Resolution & Persistence)

**Files:**
- Create: `c:\Dev\projects\nexus_fx\lib\services\session_manager_service.dart`
- Create: `c:\Dev\projects\nexus_fx\test\services\session_manager_service_test.dart`

**Interfaces:**
- Consumes: `SessionFolder`, `SessionProfile`, `JumpHostMode`, `SessionProtocol` from `lib/models/session_models.dart`
- Produces:
  - `class CircularJumpHostException implements Exception`
  - `class ResolvedSshRoute` (`targetSession`, `jumpHost`, `jumpPort`, `jumpFallbackHost`, `jumpUsername`, `jumpPassword`)
  - `class SessionManagerService extends ChangeNotifier`:
    - `List<SessionFolder> get folders`
    - `List<SessionProfile> get sessions`
    - `List<SessionFolder> getChildFolders(String? parentId)`
    - `List<SessionProfile> getChildSessions(String? parentId)`
    - `List<SessionFolder> getBreadcrumbPath(String? folderId)`
    - `String getFullPathLabel(SessionProfile session)`
    - `Future<void> loadSessions({String? customFilePath})`
    - `Future<void> saveSessions()`
    - `Future<SessionFolder> createFolder({required String name, String? parentId, String description = ''})`
    - `Future<SessionProfile> createSession(SessionProfile profile)`
    - `Future<void> updateSession(SessionProfile profile)`
    - `Future<void> updateFolder(SessionFolder folder)`
    - `List<SessionProfile> getDependentSessions(String jumpSessionId)`
    - `Future<void> deleteSession(String sessionId)`
    - `Future<void> deleteFolder(String folderId)`
    - `void copyItem({String? sessionId, String? folderId})`
    - `void cutItem({String? sessionId, String? folderId})`
    - `bool get hasClipboardItem`
    - `Future<void> pasteInto(String? targetFolderId)`
    - `Future<SessionProfile> duplicateSession(String sessionId)`
    - `ResolvedSshRoute resolveSshRoute(SessionProfile session)`
    - `Future<void> exportToFile(File file)`
    - `Future<void> importFromFile(File file, {bool merge = true})`

- [ ] **Step 1: Write the failing unit tests in `c:\Dev\projects\nexus_fx\test\services\session_manager_service_test.dart`**
  Cover:
  1. Default `LOCAL` session seeded when storage file does not exist.
  2. Folder & Session creation, `getChildFolders`, `getChildSessions`, and `getBreadcrumbPath`.
  3. Same-folder Copy & Paste (`duplicateSession`) generating `<Name> - Copy` and `<Name> - Copy (2)`.
  4. Recursive folder Copy & Paste deep-cloning child folders and sessions with remapped `parentId`s.
  5. Cut & Paste moving a session or folder to a new `parentId` (and preventing cutting a folder into its own descendant).
  6. `resolveSshRoute` for `direct`, `customJumpHost`, and `existingSession`, plus throwing `CircularJumpHostException` on `A -> B -> A` or `A -> A`.
  7. Deleting a session referenced as `jumpSessionId` resets dependent sessions to `JumpHostMode.direct`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/services/session_manager_service_test.dart`
  Expected: FAIL (`session_manager_service.dart` not found)

- [ ] **Step 3: Implement `c:\Dev\projects\nexus_fx\lib\services\session_manager_service.dart`**
  Implement all methods defined in the Interfaces block with atomic JSON persistence to `sessions.json`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/services/session_manager_service_test.dart`
  Expected: PASS

---

### Task 3: Xshell-Style `SessionPropertiesDialog` & `SessionsScreen` (View + Startup/Modal Dialog)

**Files:**
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\session_properties_dialog.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\screens\sessions_screen.dart`
- Create: `c:\Dev\projects\nexus_fx\test\widgets\sessions_screen_test.dart`

**Interfaces:**
- Consumes: `SessionManagerService`, `SessionProfile`, `SessionFolder`, `FuzzySearchableDropdown`
- Produces:
  - `class SessionPropertiesDialog extends StatefulWidget` (`static Future<SessionPropertiesResult?> show(BuildContext context, {SessionProfile? initialSession, String? parentFolderId})`)
  - `class SessionsScreen extends StatefulWidget` (`onConnectSessions: void Function(List<SessionProfile> sessions, {bool openInRightSplit})`, `onOpenInFileExplorer: void Function(SessionProfile session)`, `isDialogMode: bool`)
  - `class SessionsDialog` (`static Future<void> show(BuildContext context, {required void Function(List<SessionProfile>, {bool openInRightSplit}) onConnectSessions, required void Function(SessionProfile) onOpenInFileExplorer})`)

- [ ] **Step 1: Write widget tests in `c:\Dev\projects\nexus_fx\test\widgets\sessions_screen_test.dart`**
  Verify:
  1. `SessionsScreen` renders folders (`TSEL_PS`) and sessions (`LOCAL`, `DOCKER_SERVER`) with columns `Name`, `Host`, `User Name`, `Protocol`, `Port`, `Route`, `Description`, `Modified`.
  2. Double-clicking a folder navigates into it and updates the breadcrumb bar (`All Sessions > TSEL_PS`).
  3. Toolbar Copy + Paste duplicates the selected session in the table.
  4. `SessionPropertiesDialog` renders the left Category tree (`Connection`, `Authentication`, `SSH`, `Tunneling`, `Terminal`, `Appearance`, `Logging`), uses `FuzzySearchableDropdown` for Protocol, Auth Method, and Connection Mode (Direct / Via Existing Session / Via Custom Jump Host), and blocks circular jump host selection.

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/widgets/sessions_screen_test.dart`
  Expected: FAIL

- [ ] **Step 3: Implement `session_properties_dialog.dart` and `sessions_screen.dart`**
  Ensure every dropdown in `SessionPropertiesDialog` uses `FuzzySearchableDropdown` per `GEMINI.md`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/widgets/sessions_screen_test.dart`
  Expected: PASS

---

### Task 4: Terminal Engine (`SshService` + Local Shell Support) & `NexusScreen` + `InteractiveRunbookSidebar` Integration

**Files:**
- Create: `c:\Dev\projects\nexus_fx\lib\services\settings_service.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\services\ssh_log_service.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\services\ssh_tunnel_manager.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\services\ssh_service.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\services\playbook_parser.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\ssh_tab_view.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\script_cell_widget.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\interactive_runbook_sidebar.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\floating_send_progress_dialog.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\command_palette.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\screens\nexus_screen.dart`
- Create: `c:\Dev\projects\nexus_fx\test\services\ssh_service_session_test.dart`

**Interfaces:**
- Consumes: `SessionProfile`, `SessionManagerService`, `ResolvedSshRoute`
- Produces:
  - `SshConnection` updated to support `SessionProtocol.local` (spawning local OS shell via `Process.start` and killing it on `disconnect()`) alongside `SessionProtocol.ssh` (Direct & Jump Host via `ResolvedSshRoute`, plus `loginScript` execution and `autoReconnect`).
  - `NexusScreenState.connectSessionProfile(SessionProfile profile, {bool toRightPane = false})`

- [ ] **Step 1: Write test in `c:\Dev\projects\nexus_fx\test\services\ssh_service_session_test.dart`**
  Test creating an `SshConnection` from a `SessionProfile` (both `SessionProtocol.local` shell lifecycle and `SessionProtocol.ssh` route mapping from `SessionManagerService.resolveSshRoute`).

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/services/ssh_service_session_test.dart`
  Expected: FAIL

- [ ] **Step 3: Adapt `SshService`, `NexusScreen`, and `InteractiveRunbookSidebar` for `nexus_fx`**
  Remove `Cluster`/`FeNode`/`AuthService` dependencies, wire `NexusScreen`'s session picker (`FuzzySearchableDropdown`) and toolbar **"Sessions"** button to `SessionManagerService` and `SessionsDialog`, and support `SessionProtocol.local` processes in `SshConnection`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/services/ssh_service_session_test.dart`
  Expected: PASS

---

### Task 5: Dual-Pane `FileExplorerView` Integrated with `SessionManagerService`

**Files:**
- Create: `c:\Dev\projects\nexus_fx\lib\models\file_explorer_models.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\services\fe_remote_executor.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\services\file_explorer_service.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\file_explorer_dialogs.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\file_explorer_view.dart`
- Create: `c:\Dev\projects\nexus_fx\test\widgets\file_explorer_session_target_test.dart`

**Interfaces:**
- Consumes: `SessionManagerService`, `SessionProfile`, `ResolvedSshRoute`
- Produces:
  - `ExplorerNodeTarget.fromSessionProfile(SessionProfile profile, ResolvedSshRoute route)`
  - `FileExplorerView` using `FuzzySearchableDropdown` populated with `ExplorerNodeTarget.local` + all `SessionProtocol.ssh` sessions from `SessionManagerService`.

- [ ] **Step 1: Write test in `c:\Dev\projects\nexus_fx\test\widgets\file_explorer_session_target_test.dart`**
  Verify `ExplorerNodeTarget.fromSessionProfile` maps both direct SSH sessions and Jump Host SSH sessions (carrying jump host credentials) and that `FileExplorerView` lists saved SSH sessions in its target `FuzzySearchableDropdown`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/widgets/file_explorer_session_target_test.dart`
  Expected: FAIL

- [ ] **Step 3: Implement `file_explorer_models.dart`, `file_explorer_service.dart`, and `file_explorer_view.dart`**
  Replace `NodeService` / `ClusterCredentialService` lookups with `SessionManagerService` SSH sessions and route SFTP through Jump Host when `jumpHost != null`.

- [ ] **Step 4: Run test to verify it passes**
  Run: `flutter test test/widgets/file_explorer_session_target_test.dart`
  Expected: PASS

---

### Task 6: `MainScreen`, `main.dart`, Settings & Full Verification

**Files:**
- Create: `c:\Dev\projects\nexus_fx\lib\services\window_state_service.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\widgets\keyboard_shortcuts_dialog.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\screens\main_screen.dart`
- Create: `c:\Dev\projects\nexus_fx\lib\main.dart`
- Create: `c:\Dev\projects\nexus_fx\test\screens\main_screen_test.dart`

**Interfaces:**
- Consumes: `SessionsScreen`, `SessionsDialog`, `NexusScreen`, `FileExplorerView`, `SessionManagerService`, `SettingsService`
- Produces: Complete `NexusFX` application entrypoint with 4 left-sidebar tabs (`Sessions`, `Nexus`, `File Explorer`, `Settings`) and optional startup `SessionsDialog`.

- [ ] **Step 1: Write widget test in `c:\Dev\projects\nexus_fx\test\screens\main_screen_test.dart`**
  Verify `MainScreen` boots directly without login, displays `Sessions`, `Nexus`, `File Explorer`, and `Settings` in the left navigation rail, switches views cleanly, and opens a session from `SessionsScreen` into `NexusScreen`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `flutter test test/screens/main_screen_test.dart`
  Expected: FAIL

- [ ] **Step 3: Implement `main_screen.dart` and `main.dart`**
  Wire `SessionManagerService.instance.loadSessions()` on startup, trigger `SessionsDialog.show` after first frame if `SettingsService.instance.showSessionDialogAtStartup` is enabled, and run `flutter analyze` + `flutter test`.

- [ ] **Step 4: Run full test suite and static analysis**
  Run: `flutter analyze` and `flutter test` in `c:\Dev\projects\nexus_fx`
  Expected: 0 analyzer issues, all tests PASS.
