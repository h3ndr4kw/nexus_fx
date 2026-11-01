# NexusFX (`nexus_fx`) — Design Specification

**Date:** 2026-10-30
**Target Project Directory:** `c:\Dev\projects\nexus_fx`
**Base Reference Project:** `c:\Dev\projects\header_enrichment\smart_e_he\smart_e_he_app`

---

## 1. Overview & Goals

**NexusFX (`nexus_fx`)** is a standalone desktop application built with Flutter, derived from the UI and terminal/SFTP core of `smart_e_he`. Unlike `smart_e_he`, which is tailored for Telco Header Enrichment (HE) operations with a rigid `Cluster (OAM) -> Site -> FE Node` hierarchy, **NexusFX** is a general-purpose **SSH & Local Terminal Workspace + SFTP File Explorer + Interactive Notebook** featuring an **Xshell-style Session Manager**.

### In-Scope Features
1. **Identical Visual Identity & Theme:** Reuses `AppTheme`, custom window frame (`WindowCaptionButtons`), keyboard shortcuts, command palette, and mandatory [`FuzzySearchableDropdown`](file:///c:/Dev/projects/header_enrichment/smart_e_he/smart_e_he_app/lib/widgets/fuzzy_searchable_dropdown.dart) for all searchable selection dropdowns.
2. **Xshell-Style Session Manager:**
   - Accessible both as a primary left-sidebar tab (**Sessions**) and as a modal dialog (**Sessions Dialog** with a *"Show this dialog box at startup"* toggle).
   - Hierarchical folder organization (nested folders and sessions).
   - Full CRUD & clipboard actions: **Create New Session**, **Create New Folder**, **Modify (Properties)**, **Delete**, **Cut**, **Copy**, and **Paste / Duplicate Session**.
   - **Properties of Session Dialog** with a left category tree (`Connection`, `Authentication`, `SSH -> Tunneling`, `Terminal & Appearance`, `Logging`) and right configuration form with `OK`, `Connect`, and `Cancel` actions.
   - Flexible connection routing per SSH session: **Direct Connection**, **Via Existing Session (Jump Host)**, or **Via Custom Jump Host**.
   - Local JSON persistence (`sessions.json`) with credential obfuscation, plus **Export / Import** support and a default **`LOCAL`** shell session out of the box.
3. **Nexus Terminal & Nexus Notebook:**
   - Multi-tab terminal supporting both **SSH Sessions** (via `dartssh2` + `xterm`) and **LOCAL Shell Sessions** (`powershell.exe` / `cmd.exe` on Windows, `bash` / `zsh` on Linux/macOS via `Pty` / `Process.start` piped to `xterm`).
   - Split View (Left/Right panes), Multi-Tab Broadcast Bar, and Command History.
   - Integrated **Nexus Notebook** (`InteractiveRunbookSidebar` + `ScriptCellWidget` + `PlaybookParser`) on the right sidebar, able to execute script cells into active or broadcasted SSH/Local terminal tabs.
4. **Dual-Pane File Explorer (Local & SFTP):**
   - Multi-tab Dual-Pane File Explorer (`FileExplorerView`) supporting local filesystem operations and remote SFTP transfers (including transparent SFTP over Jump Host when a session configures a Jump Host).
5. **Direct Startup (No Login Screen):**
   - Boots directly into `MainScreen` without Firebase Auth, `LoginScreen`, or `AdminDashboardScreen`.

### Out-of-Scope (Removed from `smart_e_he`)
- All Header Enrichment (HE) specific modules: *Cluster & Node Deployment*, *Health Check*, *Certificate Management / Audit*, *SSL Multicert*, *Bulk File Transfer HE*, *Unused Files*, *Indonesia GeoJSON Site Map*, and *Firebase/Firestore Auth & User Management*.

---

## 2. Architecture & Module Structure

```
c:\Dev\projects\nexus_fx\
├── pubspec.yaml
├── assets/
│   ├── icon/
│   └── scripts/ (default sample notebook/runbook files)
└── lib/
    ├── main.dart
    ├── models/
    │   ├── file_explorer_models.dart
    │   ├── playbook_models.dart
    │   ├── session_models.dart          # NEW: SessionFolder, SessionProfile, JumpHostConfig, etc.
    │   └── ssh_tunnel_models.dart
    ├── services/
    │   ├── fe_remote_executor.dart
    │   ├── file_explorer_service.dart
    │   ├── local_shell_service.dart     # NEW: Local OS shell process bridge to Terminal
    │   ├── playbook_parser.dart
    │   ├── session_manager_service.dart # NEW: CRUD, clipboard (Cut/Copy/Paste), JSON persistence, Export/Import
    │   ├── settings_service.dart
    │   ├── ssh_log_service.dart
    │   ├── ssh_service.dart             # UPDATED: Supports SessionProfile + LocalShell + JumpHost resolution
    │   ├── ssh_tunnel_manager.dart
    │   └── window_state_service.dart
    ├── theme/
    │   ├── app_theme.dart
    │   └── terminal_theme_helper.dart
    ├── screens/
    │   ├── main_screen.dart             # Left Sidebar: Sessions, Nexus, File Explorer, Settings
    │   ├── nexus_screen.dart            # Terminal tabs + Split View + Broadcast + Nexus Notebook
    │   └── sessions_screen.dart         # NEW: Reusable Session Manager View (Full Tab & Modal Dialog)
    └── widgets/
        ├── animated_gradient_border.dart
        ├── command_palette.dart
        ├── file_explorer_dialogs.dart
        ├── file_explorer_view.dart
        ├── floating_send_progress_dialog.dart
        ├── fuzzy_searchable_dropdown.dart
        ├── interactive_runbook_sidebar.dart
        ├── keyboard_shortcuts_dialog.dart
        ├── script_cell_widget.dart
        ├── session_properties_dialog.dart # NEW: Xshell-style Properties of Session dialog
        ├── shimmer_loading.dart
        ├── sidebar_icon.dart
        ├── ssh_tab_view.dart
        ├── table_column_filter_header.dart
        └── window_caption_buttons.dart
```

---

## 3. Data Models (`lib/models/session_models.dart`)

### 3.1 `SessionProtocol` & `JumpHostMode`
```dart
enum SessionProtocol {
  ssh,
  local,
}

enum AuthMethod {
  password,
  privateKey,
}

enum JumpHostMode {
  direct,
  existingSession,
  customJumpHost,
}
```

### 3.2 `SessionEntry` (Folder or Session Node)
To support an arbitrary folder hierarchy (`All Sessions > TSEL_PS > ...`), both folders and sessions share a parent folder reference (`parentId`, where `null` represents the root `All Sessions` directory):

```dart
class SessionFolder {
  final String id;
  final String? parentId; // null = root ("All Sessions")
  final String name;
  final String description;
  final DateTime modifiedAt;
  ...
}

class SessionProfile {
  final String id;
  final String? parentId; // null = root ("All Sessions")
  final String name;
  final SessionProtocol protocol; // ssh or local

  // Connection (General)
  final String host;
  final int port;
  final String? fallbackHost;
  final String description;
  final bool autoReconnect;
  final int reconnectIntervalSec;
  final int reconnectLimitMin;

  // Authentication
  final String username;
  final AuthMethod authMethod;
  final String password;
  final String? privateKeyPath;
  final String? privateKeyPassphrase;
  final String loginScript; // Startup commands separated by newline

  // SSH -> Tunneling (Direct vs Jump Host)
  final JumpHostMode jumpHostMode;
  final String? jumpSessionId; // Used when jumpHostMode == existingSession
  final String? customJumpHost; // Used when jumpHostMode == customJumpHost
  final int customJumpPort;
  final String? customJumpFallbackHost;
  final String? customJumpUsername;
  final String? customJumpPassword;
  final TunnelMode tunnelMode; // multiplexed or dedicated

  // Terminal & Appearance
  final String? customThemeName; // null = follow global terminal theme
  final double? customFontSize;  // null = follow global terminal font size
  final int scrollbackLines;

  // Logging
  final bool enableSessionLogging;

  final DateTime modifiedAt;
  ...
}
```

---

## 4. Session Manager & Properties UI Design

### 4.1 Session Manager View & Modal Dialog (`lib/screens/sessions_screen.dart`)
- **Dual Presentation:**
  - Rendered inside `MainScreen` when the **Sessions** sidebar item is active.
  - Rendered inside `SessionsDialog.show(context)` when triggered from Startup, from the Nexus toolbar **"Sessions"** button, or via keyboard shortcut (`Ctrl+Shift+O` / `Alt+S`).
- **Top Action Toolbar:**
  - `New` split/dropdown button: **New Session** (`Ctrl+N`) and **New Folder** (`Ctrl+Shift+N`).
  - Clipboard actions: **Cut** (`Ctrl+X`), **Copy** (`Ctrl+C`), **Paste / Duplicate** (`Ctrl+V`), **Delete** (`Del`).
    - Copying and pasting a session in the same folder automatically duplicates it with an incremented name (e.g., `DOCKER_SERVER - Copy` or `DOCKER_SERVER (2)`).
    - Copying and pasting a folder deep-clones the folder and all nested child folders/sessions.
  - **Properties** (`Alt+Enter`): Opens `SessionPropertiesDialog` for the selected item.
  - **Search Bar**: Real-time fuzzy/substring filtering across session names, hosts, usernames, and descriptions.
- **Breadcrumb Bar:**
  - Displays current folder path (`All Sessions > TSEL_PS`) with clickable segments, an **Up Folder** button, and a **Refresh** button.
- **Session Table Columns:**
  - `Name` (with folder icon, SSH icon, or LOCAL shell icon)
  - `Host`
  - `User Name`
  - `Protocol` (`SSH`, `LOCAL`)
  - `Port`
  - `Route / Jump Host` (`Direct`, `Via: <SessionName>`, or `Via: <CustomHost>`)
  - `Description`
  - `Modified` (`YYYY-MM-DD HH:mm:ss`)
- **Interactions & Context Menu:**
  - Double-clicking a folder navigates into that folder.
  - Double-clicking a session (or selecting it and clicking **Connect**) opens the session in **Nexus** and switches focus to the Nexus tab.
  - Right-click context menu on a session:
    - *Connect in Terminal*
    - *Connect in Split Pane (Right)*
    - *Open in File Explorer (SFTP)* (enabled for `SSH` sessions)
    - *Duplicate Session*
    - *Cut* / *Copy*
    - *Delete*
    - *Properties*
- **Bottom Footer (in Dialog mode):**
  - Checkbox: `[x] Show this dialog box at startup` (persisted in `SettingsService`).
  - Buttons: `Connect` (primary action for selected session(s)) and `Close`.

### 4.2 Properties of Session Dialog (`lib/widgets/session_properties_dialog.dart`)
Modeled directly after the Xshell "Properties of Session" layout:
- **Left Pane (`Category:` TreeView):**
  - `Connection`
    - `Authentication`
    - `SSH`
      - `Tunneling`
  - `Terminal`
    - `Appearance`
  - `Logging`
- **Right Center Pane (Dynamic Category Form):**
  - **Category: `Connection`**
    - `Name`, `Protocol` (`FuzzySearchableDropdown`: `SSH`, `LOCAL`), `Host`, `Port Number` (numeric spinner/input, default `22`), `Fallback Host` (optional), `Description` (multi-line text box), and `Reconnect` group (`[ ] Reconnect automatically if connection is terminated unexpectedly`, `Interval (sec)`, `Limit (min)`).
  - **Category: `Authentication`**
    - `User Name`, `Authentication Method` (`FuzzySearchableDropdown`: `Password`, `Public Key / PEM File`), `Password` (with show/hide toggle), `Private Key File` (with file picker), and `Login Scripts` (commands automatically sent after shell prompt is ready).
  - **Category: `SSH -> Tunneling`**
    - `Connection Mode` (`FuzzySearchableDropdown`):
      1. `Direct Connection (No Jump Host)`
      2. `Via Existing SSH Session (Jump Host)` → Shows a `FuzzySearchableDropdown` listing all other `SSH` sessions in `SessionManagerService`.
      3. `Via Custom Jump Host` → Shows input fields for `Jump Host IP/Hostname`, `Jump Port` (`22`), `Fallback Jump Host`, `Jump Username`, and `Jump Password`.
    - `Tunnel Multiplexing Mode` (`FuzzySearchableDropdown`: `Multiplexed (Shared Master Connection)`, `Dedicated Connection`).
  - **Category: `Terminal -> Appearance`**
    - `Color Scheme` (`FuzzySearchableDropdown`: `Use Global Theme` + built-in terminal themes), `Font Size` (`Use Global Font Size` or custom `10..24`), `Scrollback Buffer Lines` (default `5000`).
  - **Category: `Logging`**
    - `[ ] Enable automatic session logging on connect` + preview of log directory path from `SettingsService`.
- **Rightmost Action Column:**
  - `OK` (validates & saves changes)
  - `Connect` (validates, saves changes, and immediately launches the session in Nexus Terminal)
  - `Cancel` (discards changes)

---

## 5. Data Flow & Service Integration

### 5.1 Resolving Jump Hosts & Circular Reference Protection
When connecting to a `SessionProfile` (either in `SshService` for Terminal or `FileExplorerService` for SFTP):
1. `SessionManagerService.resolveConnectionConfig(SessionProfile session)` inspects `session.jumpHostMode`:
   - **`JumpHostMode.direct`**: Returns a direct connection config (`jumpClusterHost: null`).
   - **`JumpHostMode.customJumpHost`**: Populates `jumpClusterHost`, `jumpClusterFallback`, `jumpClusterUsername`, and `jumpClusterPassword` from the session's custom jump fields.
   - **`JumpHostMode.existingSession`**: Looks up `jumpSessionId` in `SessionManagerService`.
     - **Cycle Detection:** Maintains a `visitedIds` set (`{session.id}`). If `jumpSessionId` is already in `visitedIds`, throws a descriptive `CircularJumpHostException` (and blocks saving in `SessionPropertiesDialog`).
     - Copies the target jump session's `host`, `fallbackHost`, `username`, and `password` into the resolved jump parameters.

### 5.2 Local Shell Integration (`LocalShellService` / `SshConnection`)
- To allow `NexusScreen` to treat `LOCAL` and `SSH` tabs uniformly (tab bar, split view, broadcast commands, Nexus Notebook execution, logging):
  - `SshConnection` supports `isLocalShell: true` (or `protocol == SessionProtocol.local`).
  - When `isLocalShell` is true, calling `connect()` spawns a local shell process (`powershell.exe` on Windows, `$SHELL` or `/bin/bash` on Linux/macOS) and wires `stdout`/`stderr` to `terminal.write()` and `terminal.onOutput` to the process `stdin`.

### 5.3 File Explorer SFTP Integration
- In `FileExplorerView`, the target selector dropdown (`FuzzySearchableDropdown`) lists:
  1. `Local Filesystem`
  2. All saved `SSH` sessions from `SessionManagerService` formatted as `<FolderPath> / <SessionName> (<Host>)`.
- Selecting an `SSH` session constructs an `ExplorerNodeTarget` carrying both the target session credentials and any resolved Jump Host credentials so `FileExplorerService` can open SFTP either directly or over the SSH jump tunnel.

---

## 6. Error Handling & Testing Strategy

1. **Validation & Safeguards:**
   - Prevent saving an `SSH` session with an empty `Host` or invalid `Port` (`1..65535`).
   - Prevent selecting the session itself (or a cycle of sessions) as its `Jump Host Session`.
   - Warn the user before deleting a session that is currently referenced as a `jumpSessionId` by other sessions, offering to switch dependent sessions back to `Direct` or cancel deletion.
2. **Automated Tests (`flutter test`):**
   - **Unit Tests (`session_manager_service_test.dart`):** Folder & session CRUD, nested folder deletion, Cut/Copy/Paste (including duplicate naming & deep folder cloning), JSON serialization/deserialization, Export/Import, and Jump Host resolution + cycle detection.
   - **Widget Tests (`sessions_screen_test.dart` & `session_properties_dialog_test.dart`):** Rendering session table, navigating folders via breadcrumbs, searching sessions, creating/editing/duplicating a session via `SessionPropertiesDialog`, and verifying `FuzzySearchableDropdown` usage across all dropdowns.
