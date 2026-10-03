# T12 — Menu bar item, recents, launch at login

**Milestone:** M2 · **Depends on:** T05 (T10 for settings link) · **Estimate:** 0.5–1 day

## Goal

A quiet, useful menu bar presence: start a note, see and reopen recent captures, notice failed deliveries, and start automatically at login.

## Read first

- UX_SPEC §4 (menu bar)
- ARCHITECTURE §4 rules 4–6 (status, failures)

## Scope

1. `StatusItemController` builds the menu from UX_SPEC §4, rebuilt in `menuNeedsUpdate(_:)` (no polling). Shortcut hints mirror the user's configured hotkeys.
   While `HotkeyService.needsSpotlightHandoff` is true, show "Finish setting up ⌘Space…" (opens onboarding step 1).
2. **Recent ▸** submenu from `RecentStore` (last 10): first line (truncated), destination, relative time. Click opens:
   - `.file(URL)` → `NSWorkspace.shared.activateFileViewerSelecting([url])`
   - `.obsidian` → `obsidian://open?…` (T07 helper)
   - `.appleNote` → open Notes (`NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))`)
3. Pending/failing state: icon variant with amber dot (`square.and.pencil` + badge, template-safe); menu row "N notes waiting to deliver… Retry"; one `UNUserNotification` per failure burst (request authorization lazily on first failure).
4. Launch at login: `SMAppService.mainApp.register()` / `unregister()`; reflect `status` in Settings (handle `.requiresApproval` → show "Approve in System Settings › General › Login Items").
5. `applicationShouldHandleReopen` (user double-clicks Otter.app while running) → open Settings.
6. `applicationWillTerminate`: flush draft synchronously.

## Implementation notes

- Keep the status item image a template image so it adapts to light/dark and tinted menu bars.
- Notification content must not include note text — "1 note couldn't be delivered to Daily note" only.

## Acceptance criteria

- [ ] Recent items open the right note for each destination type.
- [ ] Unplugging the drive a folder destination lives on → amber badge + one notification; reconnect + Retry → badge clears.
- [ ] Login item survives reboot and is listed in System Settings › Login Items.
- [ ] Opening Otter.app from Finder while it's running opens Settings.

## Out of scope

Hiding the menu bar icon (stretch). Dock icon.
