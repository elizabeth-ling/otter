# T02 — Global hotkey

**Milestone:** M0 · **Depends on:** T01 · **Estimate:** 0.5 day

## Goal

`⌘Space` opens the panel from any app, Space or full-screen window, with no Accessibility permission. Because Spotlight owns `⌘Space` by default, the service detects that, falls back to `⌥Space`, and switches to `⌘Space` by itself as soon as the user frees it.

## Read first

- UX_SPEC §2 (keyboard map), §6 step 1 (onboarding hotkey step)
- DECISIONS ADR-010 (supersedes ADR-006)
- ARCHITECTURE §7 (permissions)

## Scope

1. `HotkeyService` wrapping `KeyboardShortcuts`:
   ```swift
   extension KeyboardShortcuts.Name {
       static let togglePanel   = Self("togglePanel", default: .init(.space, modifiers: [.command]))
       static let saveClipboard = Self("saveClipboard")   // no default
   }
   static let fallbackToggle = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
   ```
2. `SpotlightShortcutProbe` (app target): returns `.enabled`, `.disabled` or `.unknown` for Spotlight's "Show Spotlight search" shortcut by reading `UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")?["64"]` → `enabled`. Missing key = macOS default = enabled. Unreadable shape = `.unknown`. Read-only; never write to that domain.
3. Effective toggle hotkey:
   | User's chosen shortcut | Spotlight probe | Registered |
   |---|---|---|
   | `⌘Space` | `.disabled` | `⌘Space` |
   | `⌘Space` | `.enabled` | `⌥Space` fallback; `needsSpotlightHandoff = true` |
   | `⌘Space` | `.unknown` | `⌘Space`; onboarding asks the user to press it once to confirm |
   | anything else | — | the user's shortcut |
4. Re-probe on `NSWorkspace.didActivateApplicationNotification` (fires whenever *any* app comes to the front, e.g. the user leaving System Settings; Otter itself is rarely active) and when the panel or Settings opens. No polling. When the probe flips to `.disabled`, unregister the fallback and register `⌘Space` immediately, without a relaunch.
5. Expose `needsSpotlightHandoff` (observable) for onboarding (T10) and the menu bar row (T12), plus `openSpotlightShortcutSettings()` which opens System Settings › Keyboard (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`; fall back to opening System Settings if the URL fails).
6. Publish two events: `onTogglePanel`, `onSaveClipboard` (closures or `AsyncStream`). Until T03 lands, `onTogglePanel` just logs and beeps.
7. Toggle semantics, implemented here as a small state function the panel controller will call:
   | Panel state | Hotkey does |
   |---|---|
   | Hidden | Show + make key |
   | Visible and key | Hide |
   | Visible but not key (user clicked elsewhere and the "keep open" setting is on) | Make key |
8. A temporary "Hotkey…" menu item opening a tiny window with `KeyboardShortcuts.Recorder` for both shortcuts (replaced by Settings in T10).
9. Conflict detection: if the user records a shortcut macOS reserves (`⌃Space` input source switching, `⌘⇥`, `⌃⌘Space` emoji), show a warning in the recorder UI. `⌘Space` is **not** warned about; it gets the Spotlight handoff instead. Prevent both shortcuts being the same. Log registration problems.

## Implementation notes

- KeyboardShortcuts uses Carbon `RegisterEventHotKey` under the hood — no Accessibility or Input Monitoring prompt. Do **not** use `NSEvent.addGlobalMonitorForEvents` (needs Accessibility and can't consume the event).
- Use `KeyboardShortcuts.onKeyDown(for:)`, not `onKeyUp` — keydown feels faster.
- Separate the **preference** from the **registration**: `togglePanel` holds what the user chose (it backs the recorder); the service registers the *effective* shortcut from the table above. Keep the library from also registering `togglePanel` directly when it would clash (e.g. `KeyboardShortcuts.disable(.togglePanel)` and register the effective one under an internal name), so `⌘Space` and the fallback are never both live.
- While Spotlight owns `⌘Space`, macOS delivers the key to Spotlight and an app registration simply never fires. That's why detection is via the probe, not via registration errors.
- The `64` symbolic-hotkey ID and the plist shape are undocumented. Verify on the current macOS release; if it changes, the `.unknown` path (press-to-confirm) still works.
- Add an `os_signpost` begin event `hotkey→visible` here; T03 ends it when the panel is key.

## Acceptance criteria

- [ ] With Spotlight's shortcut turned off, `⌘Space` opens the panel from Safari, Terminal, a full-screen app, and the desktop.
- [ ] With Spotlight's shortcut on (fresh macOS default), `⌥Space` works and `needsSpotlightHandoff` is `true`; `⌘Space` still opens Spotlight.
- [ ] Unchecking "Show Spotlight search" in System Settings, then switching back to any app, makes `⌘Space` open Otter with no relaunch, and `⌥Space` stops working.
- [ ] Re-enabling Spotlight's shortcut flips Otter back to the fallback on next probe.
- [ ] Changing the shortcut in the recorder takes effect immediately and persists across relaunch.
- [ ] Clearing the shortcut disables it.
- [ ] No permission prompt appears at any point.
- [ ] Recording `⌃Space` shows a warning; recording the same shortcut for both actions is refused.
- [ ] Otter never writes to `com.apple.symbolichotkeys` (grep the codebase).

## Out of scope

The panel itself (T03). Clipboard capture behavior (T11). Final settings UI (T10).
