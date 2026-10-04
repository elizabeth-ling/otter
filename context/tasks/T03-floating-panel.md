# T03 — Floating capture panel

**Milestone:** M0 · **Depends on:** T02 · **Estimate:** 1 day

## Goal

The Spotlight-style floating panel: appears instantly over anything, takes keyboard focus without activating Otter, and on close leaves the user typing in the app they came from.

This is the task that makes or breaks the "frictionless" feel. Spend the time to get focus behavior exactly right.

## Read first

- ARCHITECTURE §6 (panel mechanics), §9 (performance budget)
- UX_SPEC §1 (panel anatomy, sizing, position)

## Scope

1. `CapturePanel: NSPanel` configured exactly as in ARCHITECTURE §6.
2. Content: `NSVisualEffectView` (material `.popover`, blending `.behindWindow`, state `.active`), 16 pt corner radius via `layer.cornerRadius` + `masksToBounds`, 0.5 pt `separatorColor` border, `hasShadow = true`. Layout per UX_SPEC §1: compact 56 pt bar with the destination dot on the left, a placeholder text field (T04 replaces it) and a "⌘↩" hint on the right. The footer row (destination name + "⌘↩ Save") is built now but only shown once there is content.
3. `PanelController`:
   - Creates the panel **once** at launch; never re-creates it.
   - `show()`: compute frame (below), `makeKeyAndOrderFront(nil)`, focus the editor. **No `NSApp.activate`.**
   - `hide()`: `orderOut(nil)`. Previous app regains focus automatically.
   - `toggle()` per the table in T02.
   - Hide on `windowDidResignKey` unless the "keep open when clicking elsewhere" setting is on (setting can be a hard-coded `false` until T10).
4. Positioning: screen = the one containing `NSEvent.mouseLocation` (fallback `NSScreen.main`). Center horizontally in `visibleFrame`; top edge at 22% from the top. Width 640 pt (remember user-resized width in `UserDefaults`). Clamp fully on-screen.
5. Fade in/out 80 ms via `animator().alphaValue`; skip if `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
6. Reduce Transparency: if `accessibilityDisplayShouldReduceTransparency`, use a solid `windowBackgroundColor` background.
7. End the `hotkey→visible` signpost when the panel becomes key.

## Implementation notes

- `.nonactivatingPanel` must be in the style mask **at init**; toggling it later has known quirks.
- Override `canBecomeKey` → `true` and `canBecomeMain` → `false`.
- `.fullScreenAuxiliary` + `.canJoinAllSpaces` lets it appear over full-screen apps and on the current Space instead of yanking the user to another Space.
- `Esc` is handled in T04 via `cancelOperation(_:)`; for now, close on `Esc` by overriding `cancelOperation` on the panel.
- Do not use `NSPopover` or a SwiftUI `Window` scene — neither gives this focus behavior.

## Acceptance criteria

- [x] From TextEdit: press the hotkey, type, `Esc` → you can immediately keep typing in TextEdit without clicking.
- [x] Otter never appears in `⌘⇥` and never becomes the active app (menu bar still shows the previous app's name while the panel is open).
- [x] Appears on the current Space and over a full-screen Safari window.
- [ ] With two displays, appears on the display with the pointer.
- [x] Clicking outside closes it.
- [x] Hotkey → visible measured < 100 ms (Instruments signpost), target 50 ms.
- [x] Works in Light and Dark mode; respects Reduce Motion and Reduce Transparency.

## Out of scope

Real editor, key commands beyond `Esc`, saving.
