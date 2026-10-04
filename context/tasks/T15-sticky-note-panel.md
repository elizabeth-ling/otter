# T15 — Sticky-note panel: shape, dragging, remembered position

**Milestone:** M0 · **Depends on:** T03 · **Estimate:** 1 day

## Goal

Turn the T03 panel from a one-line Spotlight-style bar into a small sticky-note panel: narrower, taller, a real multi-line text box from the moment it opens. The user can drag it anywhere, and it comes back where they left it.

Reference: `context/ui/box-ui.png` (the ChatGPT desktop window). Take its compact window shape, header strip, roomy text area and rounded translucent look. Leave out its chat content.

## Read first

- UX_SPEC §1 (panel anatomy, sizing, position)
- ARCHITECTURE §6 (panel mechanics)
- DECISIONS ADR-012
- T03 history in `context/current-feature.md`, which covers the focus rules and fade handling this task must keep

## Scope

1. **Layout** (UX_SPEC §1), replacing the T03 56 pt bar:
   - **Header strip** (32 pt): the drag handle. Holds the destination dot and name on the left. It has no title text and no traffic lights.
   - **Text area**: fills the space between header and footer, 14 pt insets. T04's `NSTextView` goes here; until then the T03 placeholder control goes here, made multi-line (an `NSTextView` in an `NSScrollView` with a placeholder is fine).
   - **Footer** (28 pt): hints on the right (`⌘↩ Save · ⌘S Save as…`), shown at all times rather than only once there is text.
2. **Size**:
   - The panel opens at 380 × 300 pt.
   - The user can resize both ways (min 300 × 180 pt, max 720 × 640 pt, also capped to the screen's `visibleFrame`).
   - Store the size in `UserDefaults` as `panelSize`, replacing T03's `panelWidth`. Read the old key once if present and use it as the width, clamped.
   - The panel no longer grows as you type. Text scrolls inside it.
3. **Dragging**: drag by the header strip and the footer background. Dragging inside the text area selects text as usual, so it must not move the window. Keep `isMovableByWindowBackground = true`, and make the text view and controls return `mouseDownCanMoveWindow = false`.
4. **Remembered position**:
   - Save the panel's top-left as an offset from its screen's `visibleFrame` top-left, keyed by display UUID (`CGDisplayCreateUUIDFromDisplayID` on `deviceDescription["NSScreenNumber"]`). Store it in `UserDefaults` as `panelPositions: [displayUUID: {x, y}]`.
   - Save when a drag or resize ends (`windowDidMove` / `windowDidEndLiveResize`). Ignore moves made by Otter's own placement code.
   - On `show()`, use the screen with the pointer, as T03 does. If that display has a saved offset, place the panel there. If not, use the default placement: horizontally centered, top edge 22% down `visibleFrame`.
   - Always clamp so the whole panel stays inside `visibleFrame`, which covers changed resolution, the Dock moving or a smaller display.
   - Add a "Reset Panel Position" item to the menu bar menu that clears `panelPositions` and `panelSize`. T10 moves it into Settings › General.
5. **Look**: keep T03's material, border, shadow, Reduce Transparency and Reduce Motion handling. Use a 12 pt corner radius (no pill shape). The header strip has no separator line; a thin separator sits above the footer.
6. Move the placement maths into OtterCore `PanelPlacement` so it stays pure and testable: default frame, restore from offset, clamp, and size migration.

## Implementation notes

- All T03 focus behavior stays: non-activating, never `NSApp.activate`, hides on resign key, created once at launch. Re-run T03's focus acceptance checks after the layout change.
- The panel style mask already includes `.resizable` (ARCHITECTURE §6). Drop T03's `minSize`/`maxSize` height pin.
- `windowDidMove` also fires during the show fade if the frame is set then. Set the frame before ordering in, and use a flag so only user moves are saved.
- Display UUIDs survive reboots and reconnects. `NSScreenNumber` alone does not, so don't key on it.
- The hotkey→visible budget doesn't change. Reading two `UserDefaults` values on show is fine; cache them in memory after the first read anyway.

## Acceptance criteria

- [ ] First open (no saved state): a 380 × 300 pt panel, centered, top edge 22% down the pointer's screen, caret in a multi-line text area.
- [ ] Dragging the header moves the panel. Dragging in the text selects text and doesn't move it.
- [ ] Move it, close it, reopen it: it opens in the same place. This holds after quitting and relaunching too.
- [ ] Resize it, close it, reopen it: same size. An existing `panelWidth` is migrated on first launch.
- [ ] Two displays: a position saved on each display is restored on that display. A display with no saved position uses the default placement.
- [ ] Lower the resolution, or move the Dock, so a saved position would be off-screen: the panel opens fully visible.
- [ ] "Reset Panel Position" puts it back to the default size and placement.
- [ ] All T03 focus criteria still pass (TextEdit focus return, no `⌘⇥` entry, full-screen Space, click-outside closes).
- [ ] Unit tests for `PanelPlacement`: restore, clamp on smaller screen, missing display, size migration.

## Out of scope

Editor behavior and draft saving (T04). `⌘S` naming flow (T16). Per-destination dot colors and the Settings UI (T10). Snapping to screen edges, pinning or multiple panels open at once.
