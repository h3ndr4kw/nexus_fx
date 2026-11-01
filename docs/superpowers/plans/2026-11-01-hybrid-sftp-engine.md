# Hybrid SFTP Transfer Engine (>= 500 MB Rust Engine, < 500 MB Dart) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an automatic hybrid SFTP file transfer engine in NexusFX that routes transfers >= 500 MB to a high-performance Rust native dynamic library (`dart:ffi`) using hardware-accelerated crypto, while preserving pure Dart (`dartssh2`) for files < 500 MB and directory navigation.

**Architecture:** A Rust `cdylib` crate (`native/sftp_engine`) handles high-speed SFTP streaming via `russh` and `tokio` on a dedicated OS worker thread. It communicates progress back to Dart via thread-safe `dart:ffi` (`NativeCallable.listener`). `FileExplorerService` inspects file sizes before transfer and transparently delegates to the Rust worker when threshold is met, with graceful fallback to `dartssh2`.

**Tech Stack:** 
- Flutter / Dart 3.13 (`dart:ffi`, `NativeCallable.listener`)
- Rust 1.99 (`russh`, `russh-sftp`, `tokio`, `cdylib`)
- Existing `dartssh2: ^4.1.0`

**Spec:** [docs/superpowers/specs/2026-10-30-nexus-fx-design.md](file:///c:/Dev/projects/nexus_fx/docs/superpowers/specs/2026-10-30-nexus-fx-design.md) (Section 4 & 5.3)

---

## Global Constraints

- **Threshold:** Exactly `500 * 1024 * 1024` bytes (500 MB) trigger native transfer.
- **Pure Rust Dependencies:** Use `russh` and `russh-sftp` (pure Rust, no C-OpenSSL or `libclang` dependencies, compatible with Windows MSVC/GNU toolchain).
- **Zero UI Blocking:** Native transfer must run on Tokio background threads in Rust; Dart UI must maintain 60 FPS while reporting byte progress.
- **Fail-safe Fallback:** If the native DLL is not loaded or fails initialization, transfer must gracefully fallback to `dartssh2` with a warning log, without crashing the app.
- **OOM Protection:** Shell fallback (`cat`, `base64`) in `dartssh2` must be capped at 50 MB to prevent process out-of-memory crashes on large files.

## Review Focus

1. **Missing or Uncompiled DLL:** App boots and transfers files < 500 MB or >= 500 MB using `dartssh2` without throwing uncaught platform exceptions.
2. **Cancellation / Abort:** User cancelling a 5 GB transfer terminates the Rust stream and closes remote file descriptors cleanly without memory or socket leaks.
3. **Progress Reporting Consistency:** Progress callbacks from Rust thread map correctly to Dart UI progress bars (`sentBytes`, `totalBytes`) at 60Hz rate limiting.
4. **Symlinks and Directory Edge Cases:** Uploading and downloading single large files vs directory recursion routes individual large files appropriately.
5. **Jump Host / Bastion Proxy:** If target session requires a jump host, routing handles credentials/tunnels or falls back safely to tunnelled `dartssh2`.

---

## Tasks

### Task 1: Create Native Rust SFTP Crate (`native/sftp_engine`)

**Files:**
- Create: `native/sftp_engine/Cargo.toml`
- Create: `native/sftp_engine/src/lib.rs`
- Create: `native/sftp_engine/src/transfer.rs`
- Create: `native/sftp_engine/src/ffi.rs`

- [x] **Step 1.1:** Create `native/sftp_engine/Cargo.toml` configured with `crate-type = ["cdylib"]` and dependencies:
  - `russh = "0.65"`
  - `russh-sftp = "3.0"`
  - `tokio = { version = "1", features = ["full"] }`
  - `futures = "0.3"`
- [x] **Step 1.2:** Write `transfer.rs` implementing async chunked upload and download with high-buffer pipelining (128 KB - 256 KB chunk size) and progress callback.
- [x] **Step 1.3:** Write `ffi.rs` exposing C ABI functions:
  - `nexus_sftp_is_available() -> i32`
  - `nexus_sftp_upload(...) -> i32`
  - `nexus_sftp_download(...) -> i32`
  - Accepting function pointer `typedef void (*ProgressCallback)(int64_t transferred, int64_t total);`
- [x] **Step 1.4:** Build release DLL with `cargo build --release` inside `native/sftp_engine/` and verify generation of `sftp_engine.dll`.

---

### Task 2: Implement Dart FFI Bridge (`RustSftpBridge`)

**Files:**
- Create: `lib/services/rust_sftp_bridge.dart`
- Create: `test/services/rust_sftp_bridge_test.dart`

- [x] **Step 2.1:** Write unit test in `test/services/rust_sftp_bridge_test.dart` testing library loader availability check and threshold evaluation.
- [x] **Step 2.2:** Implement `RustSftpBridge`:
  - Locate `sftp_engine.dll` in executable directory, `windows/runner`, or local development build folder.
  - Bind C functions with `dart:ffi`.
  - Implement `NativeCallable.listener` for thread-safe asynchronous progress updates from Rust to Dart isolate.
  - Implement `uploadFile` and `downloadFile` methods returning `Future<bool>`.
- [x] **Step 2.3:** Run `flutter test test/services/rust_sftp_bridge_test.dart` and confirm tests pass.

---

### Task 3: Integrate Adaptive Routing & OOM Guard in `FileExplorerService`

**Files:**
- Modify: `lib/services/file_explorer_service.dart:650-770`
- Modify: `test/services/file_explorer_service_test.dart` (or add new test file)

- [x] **Step 3.1:** Add `kRustTransferThreshold = 500 * 1024 * 1024` (500 MB) constant in `file_explorer_service.dart`.
- [x] **Step 3.2:** In `uploadLocalToRemote`:
  - Query local file size `await entity.length()`.
  - If `entity is File` and `size >= kRustTransferThreshold` and `RustSftpBridge.isAvailable`:
    - Invoke `RustSftpBridge.uploadFile(...)`.
  - Otherwise, fallback to existing `dartssh2` stream upload.
  - Guard shell fallback with maximum 50 MB check (`if (size > 50 * 1024 * 1024) throw Exception("File too large for shell fallback");`).
- [x] **Step 3.3:** In `downloadRemoteToLocal`:
  - Query remote file size via `session.sftp!.stat(remotePath)`.
  - If `!isDir` and `totalBytes >= kRustTransferThreshold` and `RustSftpBridge.isAvailable`:
    - Invoke `RustSftpBridge.downloadFile(...)`.
  - Otherwise, use existing `dartssh2` stream download.
- [x] **Step 3.4:** Run `flutter test` across all services to ensure no regressions.

---

### Task 4: Automation Script & Windows Build Integration

**Files:**
- Create: `scripts/build_native.ps1`
- Modify: `windows/CMakeLists.txt` (to copy `sftp_engine.dll` to output bundle directory)

- [x] **Step 4.1:** Create `scripts/build_native.ps1` to compile `native/sftp_engine` with `cargo build --release` and copy the `.dll` to `build/windows/x64/runner/Release/` and `Debug/`.
- [x] **Step 4.2:** Update `windows/CMakeLists.txt` so `flutter build windows` automatically bundles `sftp_engine.dll`.
- [x] **Step 4.3:** Verify full project compilation with `flutter analyze`.
