# T04 — Editor, keyboard map, draft autosave

**Milestone:** M0 · **Depends on:** T03, T15 · **Estimate:** 1 day

## Goal

A fast plain-text editor inside the panel that implements the full in-panel keyboard map and never loses an unfinished thought.

## Read first

- UX_SPEC §1 (states, footer), §2 (keyboard map)
- ARCHITECTURE §8 (storage), DECISIONS ADR-007

## Scope

1. `EditorView`: `NSTextView` in an `NSScrollView` (AppKit directly, or via `NSViewRepresentable` if the panel content is SwiftUI).
   - `isRichText = false`, `allowsUndo = true`, `isContinuousSpellCheckingEnabled = true`
   - Smart quotes/dashes/text replacement **off** by default (setting later)
   - System font 15 pt, 14 pt insets, placeholder "Jot something down…"
2. Fill T15's text area. The panel keeps its user-set size; the scroll view scrolls once the text is longer than it. No auto-height.
3. Key commands (override `doCommand(by:)` / `performKeyEquivalent` on the panel):
   | Key | Action |
   |---|---|
   | `⌘↩` | `onSubmit(text, closeAfter: true)` |
   | `⇧⌘↩` | `onSubmit(text, closeAfter: false)` → clear editor, stay open |
   | `Esc` | hide, keep draft |
   | `⇧⌘⌫` | discard draft (and attachments), stay open |
   | `⌘1…⌘9` | `onSelectDestination(index)` (no-op until T05/T10 provide destinations) |
   | `⌘,` | open settings (stub) |
   | `⌘S` | reserved: swallow it (no `saveDocument:`); T16 adds save-as |
   Empty/whitespace-only submit = just close.
4. `DraftStore` (in OtterCore): `load() -> Draft?`, `save(Draft)` debounced 300 ms, `clear()`. File: `drafts/current.json` (`{text, attachmentRefs, updatedAt}`), atomic writes. Keep the latest draft in memory so `show()` doesn't hit disk.
5. On show: restore the draft, cursor at end, nothing selected.
6. Wire `onSubmit` to a temporary sink that logs the byte count (T05 replaces it).

## Implementation notes

- `⌘↩` arrives as `insertNewline:` with the command modifier — check `NSApp.currentEvent?.modifierFlags` in `doCommand(by:)`, or handle in `performKeyEquivalent`. Make sure plain `↩` still inserts a newline.
- Respect IME composition: don't submit while `hasMarkedText()` is true.
- Save the draft also on `hide()` and on `applicationWillTerminate` (synchronously).
- Clear the draft only **after** the outbox accepts the capture (T05), not on keypress.

## Acceptance criteria

- [x] Typing is visually instant; no dropped characters when typing fast right after the hotkey.
- [x] `Esc` then the hotkey restores exactly what was there, cursor at end.
- [x] `kill -9` the app while typing → relaunch → draft is restored (≤300 ms of typing lost at worst).
- [x] Long text scrolls inside the panel; the panel's size and position don't change while typing.
- [ ] Japanese/Chinese IME input works; `↩` confirms composition rather than submitting.
- [x] Undo/redo works; pasting rich text from Safari inserts plain text.
- [x] Unit tests for `DraftStore` (save/load/clear, corrupt file → nil).

## Out of scope

Image/file paste (T09). Destination picker UI (T10). Actual delivery (T05/T06).
