# NexusFX (`nexus_fx`)

> **Next-Generation Desktop SSH & Local Terminal Workspace, Dual-Pane SFTP Explorer, and Interactive Runbook Runner.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Rust](https://img.shields.io/badge/Rust-Native_FFI-black?logo=rust&logoColor=white)](https://www.rust-lang.org)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue?logo=windows&logoColor=white)](https://microsoft.com/windows)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-97%20Passed-brightgreen)](test/)

---

## 📌 Overview

**NexusFX** is a modern, high-performance desktop application engineered for sysadmins, DevOps engineers, and network operators. Built with Flutter Desktop and boosted by a native Rust engine, NexusFX combines the battle-tested ergonomics of classic tools like Xshell with modern fluid design, keyboard-driven navigation, multi-tab terminal broadcast, transparent Jump Host routing, and interactive executable runbooks (`.nxnb`).

---

## ✨ Key Features

### 🖥️ 1. Nexus Terminal & Multi-Tab Workspace
- **Hybrid Terminal Support**: Seamlessly launch remote **SSH Sessions** (powered by `dartssh2` & `xterm`) or **Local Shells** (`powershell.exe`, `cmd.exe` on Windows; `bash`, `zsh` on Unix).
- **Split View**: Work on multiple systems simultaneously with side-by-side or stacked split panes.
- **Broadcast Bar**: Send keystrokes and shell commands to multiple terminal tabs at once for synchronized fleet operations.
- **Command History & Search**: Quick-access floating search island, scrollback search, and execution logs.

### 📁 2. Xshell-Style Session Manager
- **Hierarchical Management**: Organize hundreds of servers in customizable folder trees.
- **Clipboard & Batch Operations**: Quick `Cut`, `Copy`, `Paste`, `Duplicate`, and inline search.
- **Comprehensive Session Properties**:
  - **Connection**: Host, port, protocol, keepalive, and timeout.
  - **Authentication**: Password (obfuscated in storage) or Private Key authentication.
  - **Jump Host / ProxyJump Routing**: Direct connection, via existing session profile, or via custom jump hosts.
  - **SSH Tunneling**: Local and remote port forwarding configurations.
  - **Appearance & Logging**: Font size, custom color palettes, and automated local session logging.
- **Portable Persistence**: Export and import session profiles in JSON format with credential security.

### ⚡ 3. Dual-Pane File Explorer & Hybrid SFTP Engine
- **Dual-Pane Interface**: Side-by-side local filesystem and remote SFTP file browsers.
- **Transparent Jump Host Transfers**: Access internal servers through intermediate bastion/jump hosts seamlessly.
- **Rust Native Acceleration (`native/sftp_engine`)**: High-throughput file transfers via Rust FFI with automatic fallback to pure Dart implementation.
- **Multi-Tab File Explorer**: Manage file transfers across multiple remote servers independently.

### 📓 4. Nexus Notebook (`.nxnb`)
- **Interactive Runbooks**: Markdown-based runbooks with embedded executable script cells.
- **Direct Terminal Injection**: Execute playbook steps sequentially or batch-run commands directly into active or broadcasted terminals.
- **Variable Interpolation**: Dynamic prompt variables, step validation, and real-time execution status tracking.

### 🎨 5. Modern Desktop Experience
- **Sleek Themes**: Dark Antigravity, Cyberpunk, Obsidian, and Midnight palettes.
- **Neon Sonar Indicators**: Subtle visual pulse indicators showing active SSH and execution states.
- **Command Palette (`Ctrl+K` / `Ctrl+P`)**: Fast navigation and action triggering.
- **Fuzzy Searchable Dropdowns**: Rapid item selection with fuzzy string matching and highlight filtering.

---

## 🏗️ Architecture & Tech Stack

```
nexus_fx/
├── assets/                  # Icons, bundled scripts, and presets
├── config/                  # App configuration (settings.yaml)
├── docs/                    # Design specifications and implementation plans
├── lib/
│   ├── models/              # Data models (Session, Playbook, File Explorer, SSH Tunnel)
│   ├── screens/             # Top-level views (MainScreen, NexusScreen, SessionsScreen)
│   ├── services/            # Core business logic (SSH, Local Shell, SFTP, Sessions, Settings)
│   ├── theme/               # Application & Terminal theme palettes
│   └── widgets/             # Reusable UI components (Fuzzy Dropdowns, Runbook Sidebar, Dialogs)
├── native/sftp_engine/      # High-performance native Rust SFTP engine (FFI)
├── nxnb/                    # Default executable notebook examples (.nxnb)
├── scripts/                 # Build & development automation scripts
├── test/                    # Comprehensive unit and widget test suite
└── windows/                 # Windows desktop runner & CMake configurations
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: `^3.12` or later
- **Dart SDK**: `^3.12.2`
- **Rust Toolchain**: `cargo` & `rustc` (required for building the native SFTP accelerator)
- **C++ Compiler**: Visual Studio 2022 with C++ desktop workload (for Windows builds)

### 1. Clone the Repository
```bash
git clone git@github.com:h3ndr4kw/nexus_fx.git
cd nexus_fx
```

### 2. Install Flutter Dependencies
```bash
flutter pub get
```

### 3. Build Native SFTP Engine (Optional / Recommended)
To compile the high-speed Rust SFTP FFI library:
```powershell
.\scripts\build_native.ps1
```

### 4. Run the Application
```bash
flutter run -d windows
```

---

## 🧪 Testing

Run the test suite:
```bash
flutter test
```

All 49 unit and widget tests verify:
- Session serialization, obfuscation, and folder hierarchy.
- Main navigation and tab persistence.
- Session screen interactions and keyboard shortcuts.
- Sidebar animations, sash resizing, and custom widgets.

---

## ⌨️ Useful Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl + K` / `Ctrl + P` | Open Command Palette |
| `Ctrl + B` | Toggle Left Sidebar |
| `Alt + 1` | Switch to Sessions View |
| `Alt + 2` | Switch to Nexus Terminal Workspace |
| `Alt + 3` | Switch to Dual-Pane File Explorer |
| `Alt + 4` | Switch to Settings |
| `Ctrl + T` | New Terminal Tab |
| `Ctrl + W` | Close Active Terminal Tab |

---

## 📄 License

This project is licensed under the terms of the [GNU General Public License v3.0](LICENSE).
