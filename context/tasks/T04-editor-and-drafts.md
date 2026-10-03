# T04 — Editor, keyboard map, draft autosave

**Milestone:** M0 · **Depends on:** T03 · **Estimate:** 1 day

## Goal

A fast plain-text editor inside the panel that implements the full in-panel keyboard map and never loses an unfinished thought.

## Read first

- UX_SPEC §1 (states, footer), §2 (keyboard map)
- ARCHITECTURE §8 (storage), DECISIONS ADR-007

## Scope

1. `EditorView`: `NSTextView` in an `NSScrollView` (AppKit directly, or via `NSViewRepresentable` if the panel content is SwiftUI).
   - `isRichText = false`, `allowsUndo = true`, `isContinuousSpellCheckingEnabled = true`
   - Smart quotes/dashes/text replacement **off** by default (setting later)
   - System font 16 pt, 14 pt horizontal insets (left inset leaves room for the destination dot), placeholder "Jot something down…"
2. Auto-height: panel grows with content from the 56 pt compact bar to 420 pt (footer row appears once there is content), then the scroll view scrolls. Recompute on `textDidChange` using the layout manager's used rect; resize the panel keeping the **top edge fixed**.
3. Key commands (override `doCommand(by:)` / `performKeyEquivalent` on the panel):
   | Key | Action |
   |---|---|
   | `⌘↩` | `onSubmit(text, closeAfter: true)` |
   | `⇧⌘↩` | `onSubmit(text, closeAfter: false)` → clear editor, stay open |
   | `Esc` | hide, keep draft |
   | `⇧⌘⌫` | discard draft (and attachments), stay open |
   | `⌘1…⌘9` | `onSelectDestination(index)` (no-op until T05/T10 provide destinations) |
   | `⌘,` | open settings (stub) |
   Empty/whitespace-only submit = just close.
4. `DraftStore` (in OtterCore): `load() -> Draft?`, `save(Draft)` debounced 300 ms, `clear()`. File: `drafts/current.json` (`{text, attachmentRefs, updatedAt}`), atomic writes. Keep the latest draft in memory so `show()` doesn't hit disk.
5. On show: restore the draft, cursor at end, nothing selected.
6. Wire `onSubmit` to a temporary sink that logs the byte count (T05 replaces it).

## Implementation notes

- `⌘↩` arrives as `insertNewline:` with the command modifier — check `NSApp.currentEvent?.modifierFlags` in `doCommand(by:)`, or handle in `performKeyEquivalent`. Make sure plain `↩` still inserts a newline.
- Respect IME composition: don't submit or resize-thrash while `hasMarkedText()` is true.
- Save the draft also on `hide()` and on `applicationWillTerminate` (synchronously).
- Clear the draft only **after** the outbox accepts the capture (T05), not on keypress.

## Acceptance criteria

- [ ] Typing is visually instant; no dropped characters when typing fast right after the hotkey.
- [ ] `Esc` then the hotkey restores exactly what was there, cursor at end.
- [ ] `kill -9` the app while typing → relaunch → draft is restored (≤300 ms of typing lost at worst).
- [ ] Empty panel is a single-line bar; it grows to 420 pt then scrolls; top edge stays put.
- [ ] Japanese/Chinese IME input works; `↩` confirms composition rather than submitting.
- [ ] Undo/redo works; pasting rich text from Safari inserts plain text.
- [ ] Unit tests for `DraftStore` (save/load/clear, corrupt file → nil).

## Out of scope

Image/file paste (T09). Destination picker UI (T10). Actual delivery (T05/T06).
