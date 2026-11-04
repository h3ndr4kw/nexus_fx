# CI/CD Pipeline & Modern UX/UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Implement the automated GitHub Actions CI/CD pipeline for Windows desktop releases and elevate the UX/UI with Active Island border glow and Environment Tagging guardrails (Dev, Staging, Production) with visual danger auras.

---

## File Structure & Proposed Changes

| Action | Path | Description |
| :--- | :--- | :--- |
| **Create** | `.github/workflows/build-and-release.yml` | GitHub Actions workflow for automated testing, Rust FFI compilation, and Windows Release binary packaging. |
| **Modify** | `lib/models/session_models.dart` | Introduce `SessionEnvironment` enum (`dev`, `staging`, `prod`) with color/badge attributes and serialize into `SessionProfile`. |
| **Modify** | `lib/services/ssh_service.dart` | Pass `SessionEnvironment` to `SshConnection` on session profile instantiation. |
| **Modify** | `lib/screens/main_screen.dart` | Implement Active Island border highlight & subtle elevation glow on the focused island. |
| **Modify** | `lib/screens/nexus_screen.dart` | Display environment badge on tabs and render top aura/banner for `prod` sessions to prevent critical operator mistakes. |
| **Modify** | `lib/widgets/session_properties_dialog.dart` | Add `SessionEnvironment` selector using `FuzzySearchableDropdown` (mandated by `GEMINI.md`). |
| **Modify** | `test/models/session_models_test.dart` | Add serialization & deserialization tests for `SessionEnvironment`. |
| **Create** | `test/widgets/environment_guardrails_test.dart` | Widget test verifying environment badges and production aura cues. |

---

## Task 1: GitHub Actions CI/CD Workflow Setup

**Files:**
- Create: `.github/workflows/build-and-release.yml`

- [x] **Step 1.1**: Create `.github/workflows/build-and-release.yml` configured for `windows-latest`.
- [x] **Step 1.2**: Define steps:
  - Checkout repository.
  - Setup Rust `stable` toolchain.
  - Setup Flutter SDK (`3.x`, channel `stable`).
  - Cache Cargo dependencies and Flutter pub cache.
  - Run `flutter pub get`.
  - Compile native SFTP engine via `powershell -ExecutionPolicy Bypass -File .\scripts\build_native.ps1`.
  - Run `flutter analyze`.
  - Run `flutter test`.
  - Build Windows executable `flutter build windows --release`.
  - Archive `build/windows/x64/runner/Release` into release zip.
  - Upload GitHub Actions artifact.

---

## Task 2: Model & Service Integration for `SessionEnvironment` (TDD)

**Files:**
- Modify: `lib/models/session_models.dart`
- Modify: `lib/services/ssh_service.dart`
- Modify: `test/models/session_models_test.dart`

- [x] **Step 2.1**: Write tests in `test/models/session_models_test.dart` for `SessionEnvironment` (`dev`, `staging`, `prod`) default values, serialization, and deserialization.
- [x] **Step 2.2**: Implement `SessionEnvironment` enum in `lib/models/session_models.dart` with `label`, `badgeColor`, and `isProduction` getters, and wire it into `SessionProfile` with fallback to `dev` for older sessions.
- [x] **Step 2.3**: Update `SshConnection` in `lib/services/ssh_service.dart` to store and expose `final SessionEnvironment environment`.
- [x] **Step 2.4**: Run `flutter test test/models/session_models_test.dart` to verify tests pass.

---

## Task 3: UX/UI Active Island Glow & Environment Guardrails

**Files:**
- Modify: `lib/screens/main_screen.dart`
- Modify: `lib/screens/nexus_screen.dart`
- Modify: `lib/widgets/session_properties_dialog.dart`
- Create: `test/widgets/environment_guardrails_test.dart`

- [x] **Step 3.1**: In `lib/screens/main_screen.dart`, apply an active island border highlight & ambient glow on the main canvas card when focused.
- [x] **Step 3.2**: In `lib/screens/nexus_screen.dart`, add environment badges to terminal tabs and a crimson warning top border aura when the active session is `prod`.
- [x] **Step 3.3**: In `lib/widgets/session_properties_dialog.dart`, integrate `FuzzySearchableDropdown<SessionEnvironment>` for configuring session environment.
- [x] **Step 3.4**: Create `test/widgets/environment_guardrails_test.dart` to test environment indicator rendering.
- [x] **Step 3.5**: Run `flutter test test/widgets/environment_guardrails_test.dart` (verify pass).

---

## Task 4: Regression Verification & Analysis

**Files:**
- Global: `flutter analyze` & `flutter test`

- [x] **Step 4.1**: Run `flutter analyze` to ensure zero warnings or errors.
- [x] **Step 4.2**: Run full test suite `flutter test` to ensure 100% pass across all tests.
