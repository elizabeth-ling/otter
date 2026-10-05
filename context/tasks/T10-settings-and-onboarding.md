# T10 — Settings and first-run onboarding

**Milestone:** M2 · **Depends on:** T07, T16, T17 · **Estimate:** 1.5 days

## Goal

Replace the temporary menu items with a real Settings window, and get a new user from install to first delivered note in under a minute.

## Read first

- UX_SPEC §5 (settings), §6 (first run), §7 (accessibility)

## Scope

1. Settings window (SwiftUI, hosted in an `NSWindow` you control; opening it calls `NSApp.activate()` since Otter is an agent app). Three tabs per UX_SPEC §5.
2. **General**: two `KeyboardShortcuts.Recorder`s (with reserved-shortcut warning from T02), Launch at login toggle (wired in T12), close-on-click-away, font family/size, smart quotes/dashes, and a "Reset panel position and size" button (moved from T15's menu item).
3. **Destinations**:
   - List with icon, name, mode summary, health dot (green/amber/red from `healthCheck()`), star for default, drag to reorder (order = `⌘1…⌘9`).
   - Add menu: detected Obsidian vaults (from `VaultDiscovery`) · Folder…. Picking a vault adds a folder destination at the vault root (ADR-013).
   - Detail form per type (mode, target note/folder, append template with a live preview of what will be appended, frontmatter toggle). Build the list and form around `DestinationKind` so T08 can add an Apple Notes row and form later without reworking them.
   - **Test** button: delivers a real test capture ("Otter test — you can delete this") and shows the result or the actionable error.
   - Deleting a destination with pending outbox items prompts to re-route them to the default.
4. **Advanced**: outbox status + Retry now + Reveal outbox; recents on/off + Clear; Reveal logs; Reset all settings (confirmation).
5. Panel header destination pill becomes a real menu (click) listing destinations with `⌘` numbers. When the destination shown is a folder, the menu ends with "Change Folder…" (`⇧⌘O`), which opens T17's folder picker for that destination.
6. **First run** (when no `hasOnboarded` flag): opens Settings in an onboarding mode with the 3 steps from UX_SPEC §6. Step 1 shows the `⌥Space` default with a "press it now" confirmation, plus "Use ⌘Space instead", which runs the handoff (ADR-011): show Spotlight's status from `SpotlightShortcutProbe` (T02), the **Open Keyboard Shortcuts** button, re-check on app activation, then a "press ⌘Space now" confirmation that completes when the hotkey fires. Step 3 listens to `DeliveryService` and completes on the first successful delivery, showing an **Open** button for the note.
7. Remove the temporary menu items from T02/T06/T07.

## Implementation notes

- Keep settings state in an `@Observable` `SettingsModel` backed by `UserDefaults` and `DestinationRegistry`. Changes apply live (no Save button).
- Health checks run when the Destinations tab appears and after edits, never on a timer.
- No Apple Notes in v1 (ADR-015): no Add-menu entry, pickers, onboarding option or Automation prompt. T08 adds them after v1.
- Pre-select the Obsidian vault opened most recently if one exists.

## Acceptance criteria

- [ ] Fresh install (`defaults delete com.yourname.otter`, remove App Support dir) → onboarding → first note delivered in < 60 s.
- [ ] Every setting persists across relaunch and applies without restart.
- [ ] Test button surfaces each error state with a working fix action (folder missing, folder access denied).
- [ ] `⌘1…⌘9` in the panel matches the order shown in Settings.
- [ ] On a fresh Mac, `⌥Space` works at step 1 with no System Settings visit.
- [ ] On a Mac with Spotlight's default shortcut, choosing `⌘Space` in step 1 gets the user to a working `⌘Space` in under 30 s, and "Skip for now" leaves `⌥Space` working.
- [ ] Settings › General shows the effective hotkey and, while Spotlight still owns `⌘Space`, a "Finish setting up ⌘Space" row (only if the user chose `⌘Space`).
- [ ] Full keyboard navigation and VoiceOver labels in Settings.

## Out of scope

Menu bar recents and login item mechanics (T12). Theming beyond font.
