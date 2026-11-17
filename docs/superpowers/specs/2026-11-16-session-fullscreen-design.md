# Session Fullscreen — Design

Date: 2026-11-16
Status: Approved

## Intent

Let one open SSH session take over the whole screen (OS fullscreen, no app
chrome) and return to the normal layout, each with a visible UI control and a
keyboard shortcut.

## Goals

- Toggle fullscreen for the focused SSH session from the tab bar, the terminal
  and tab context menus, the command palette, and **Ctrl+Shift+Enter**.
- In fullscreen the window goes OS-fullscreen and only that terminal is shown.
- Exit with the same shortcut, a hover bar at the top edge, or the context menu.

## Non-goals

- Fullscreen for the File Explorer or Settings views.
- Multiple sessions visible in fullscreen (split stays hidden).

## Anti-goals

- **Esc must not exit.** vim, less and htop need it.
- Terminal state (per-tab zoom, scroll, focus) must not be lost: the existing
  `SshTabView` must not be remounted.
- Leaving session fullscreen must not un-fullscreen a window the user had
  already put in F11 fullscreen.
- The UI must never get stuck with chrome hidden while the window is no longer
  fullscreen.

## Approaches

1. **Hide surrounding chrome in place (chosen).** Same widget tree, chrome is
   conditionally omitted. Keeps the `SshTabView` instance and its state.
2. **Overlay/route with the terminal on top.** Remounts the terminal view (zoom,
   scroll, focus lost) and risks two `TerminalView`s on one `Terminal`. Rejected.

Picked: 1. OS fullscreen included (user choice "B").

## Design

- **State:** `NexusScreenState._fullscreenConnection` (`SshConnection?`), exposed
  as `isSessionFullscreen` plus `enterSessionFullscreen()`,
  `exitSessionFullscreen()` and `toggleSessionFullscreen()`. `MainScreen` reads it
  through `_nexusKey` and an `onSessionFullscreenChanged` callback.
- **Enter:** remember `_wasWindowFullscreen = WindowStateService.isFullScreen`.
  If not already fullscreen, call `setFullScreen(true)`. `MainScreen` hides the
  title bar, left sidebar and resize handle, and drops the card margin/border.
  `NexusScreen` hides the tab bar, runbook sidebar, warning banner and the other
  split pane, and renders only the fullscreen connection's `SshTabView` in its
  existing slot. A hint reading "Press Ctrl+Shift+Enter to exit fullscreen"
  shows for about 2 s.
- **Exit:** restore the chrome. Call `setFullScreen(false)` only if
  `_wasWindowFullscreen` was false.
- **Hover bar:** a pill at top-center that appears when the pointer is within
  about 6 px of the top edge and hides about 1.5 s after the pointer leaves it.
  Content: connection label, then "Exit fullscreen  Ctrl+Shift+Enter".
- **Sync with OS:** if the window leaves fullscreen (F11, Win+arrow,
  `onWindowLeaveFullScreen`), session fullscreen ends too.
- **Auto-exit:** the fullscreen session is closed or removed, the user switches
  away from the Nexus tab, or the Sessions dialog / Settings opens via shortcut.
- **Still works in fullscreen:** command pane (Ctrl+Shift+Space), zoom,
  copy/paste, and the command palette. Ctrl+Tab and Ctrl+PageUp/PageDown tab
  switching are disabled while in fullscreen.
- **Shortcut plumbing:** `SshTabView._handleKeyEvent` swallows Ctrl+Shift+Enter
  (and numpad Enter) so the remote does not receive it. `MainScreen`'s global
  handler toggles it while Nexus is active. It is listed in the F1 shortcuts
  dialog.
- **UI entry points:** a ⛶ button next to the split button (tooltip "Fullscreen
  session (Ctrl+Shift+Enter)"). The terminal right-click menu has "Fullscreen" or
  "Exit Fullscreen". The tab context menu has "Fullscreen". A
  `CommandAction.toggleSessionFullscreen` entry is added to the palette.

## Tests

- Enter: title bar, sidebar and tab bar are gone and the terminal is present;
  exit restores them.
- Pre-existing F11 fullscreen: exiting session fullscreen leaves the window
  fullscreen (via `WindowStateService` testing hooks).
- Closing the fullscreen session auto-exits.
- Ctrl+Shift+Enter is handled and not written to the terminal.

## Left to the builder

- Exact animation and timing of the hint and hover bar.
- Icon choice (`Icons.fullscreen` / `Icons.fullscreen_exit`).
