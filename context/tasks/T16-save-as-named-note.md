# T16 — `⌘S`: save as a named note and start a new one

**Milestone:** M1 · **Depends on:** T04, T06, T15 · **Estimate:** 1 day

## Goal

`⌘S` saves the current note under a name the user chooses, then clears the panel for the next note and keeps it open. The name prompt is pre-filled with the date and time of the save, so pressing `⌘S` then `↩` saves without typing anything.

## Read first

- UX_SPEC §1 (save-as row), §2 (keyboard map)
- ARCHITECTURE §3 (core model), §5 (destinations)
- T04 (key commands, draft store), T06 (`FileNamer`)

## Scope

1. **Model**: add `title: String?` to `Capture` (ARCHITECTURE §3). `nil` means unnamed, which is every `⌘↩`/`⇧⌘↩` save and every clipboard save. Decoding must accept outbox JSON written before this field existed (missing key → `nil`).
2. **Key command** (`EditorView` / panel `performKeyEquivalent`):
   - `⌘S` with non-empty text opens the save-as row. With empty or whitespace-only text it does nothing, apart from a beep.
   - `⌘S` while the row is open does the same as `↩`.
3. **Save-as row** (UX_SPEC §1): an inline row that slides in above the footer. It is part of the panel, not a sheet, alert or separate window, because those would activate Otter and break focus return.
   - Label "Save as", a text field filled with the default name and fully selected, and hints `↩ Save · Esc Cancel`.
   - Default name: the date and time when the row opened, in the user's time zone, formatted `yyyy-MM-dd HHmm` (e.g. `2026-10-03 2051`). The format is filename-safe and matches the folder destination's `{date} {time}`.
   - `↩`: build a `Capture` with `title` set to the trimmed field text, or the default if it's empty. `createdAt` is the moment of confirming. Submit it through `onSubmit(text, closeAfter: false, title:)`, then clear the editor and the draft (after the outbox accepts it, as T04 does) and put the caret back in the editor. The panel stays open.
   - `Esc`: close the row, return focus to the editor, change nothing. A second `Esc` closes the panel as usual.
   - Clicking outside the panel while the row is open: hide the panel as usual and keep the draft; the row is closed next time.
4. **Destinations use the title** when present:
   | Destination / mode | Unnamed (`title == nil`) | Named |
   |---|---|---|
   | Folder · new file per note | `{date} {time} {title-from-first-line}.md` (T06) | `{title}.md`, cleaned up by `FileNamer`'s character rules, collision suffix ` 2`, ` 3`… |
   | Folder / Obsidian · append (incl. daily note) | Append template as now | Append template gets `{{title}}`. Default multi-line block heading becomes `### {{time}} {{title}}`; a single-line named note renders as a multi-line block so the name shows |
   | Obsidian · new note in folder | Same as Folder | Same as Folder |
   | Apple Notes | First line is the Notes title | `title` is sent as the first `<div>` (bold), body follows |
5. Add `{{title}}` to `AppendTemplate` and `MarkdownWriter`, and add a `title` frontmatter field on new files when named.
6. Footer hint: `⌘↩ Save · ⌘S Save as…` (T15 puts both in the footer).

## Implementation notes

- Read the default name's clock when the row opens and set `createdAt` when the user confirms. If the two land in different minutes, keep the name the user saw.
- IME: don't treat `↩` in the name field as confirm while `hasMarkedText()` is true.
- The name field's `Esc` must go to the row's cancel handler, not `CapturePanel.cancelOperation`. Use the same delegate routing T03 used for the placeholder field.
- `FileNamer` gets a `name(forTitle:)` path next to its existing first-line path, reusing the same sanitizing. A title that sanitizes to empty falls back to the default timestamp name.
- `⌘S` must not reach the responder chain's default `saveDocument:`.
- Drafts: the open/closed state of the row is not saved. Only the editor text is.

## Acceptance criteria

- [ ] Type a note, `⌘S`, `↩`: a file named like `2026-10-03 2051.md` appears in the folder destination; the panel stays open, empty, caret in the editor.
- [ ] Type a note, `⌘S`, type "Groceries", `↩`: `Groceries.md` appears. Doing it again gives `Groceries 2.md`.
- [ ] `⌘S` then `Esc`: back in the editor with the text untouched, nothing saved.
- [ ] `⌘S` on an empty panel does nothing.
- [ ] Obsidian daily note: a named capture appends under `### HH:mm Groceries`.
- [ ] Apple Notes: a named capture creates a note titled "Groceries".
- [ ] Previous app never activates and Otter never shows in `⌘⇥` during the flow.
- [ ] Unit tests: `Capture` decodes old JSON without `title`; `FileNamer` titles (illegal characters, empty after cleanup, collisions); `MarkdownWriter` with `{{title}}`; default-name formatting across time zones.

## Out of scope

Renaming or overwriting an existing note. Picking a folder or destination in the save-as row (`⌘1…⌘9` still works before `⌘S`). A setting for the default name format; add one in T10 if needed.
