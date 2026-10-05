# T09 — Paste handling and attachments

**Milestone:** M1 · **Depends on:** T04, T06 (T07 for Obsidian placement) · **Estimate:** 1 day

## Goal

"Paste something to save for later" works for more than text: screenshots, images and files pasted or dropped into the panel are saved alongside the note and linked from it.

## Read first

- UX_SPEC §1 (attachment chips, footer warning)
- ARCHITECTURE §3 (`Attachment`), §5.2 (Obsidian attachment rules), §8 (outbox files)

## Scope

1. Override `paste(_:)` and drag-and-drop in `EditorView`. Inspect `NSPasteboard` in this order:
   1. File URLs (`.fileURL`) → one attachment per file (copy, don't move).
   2. Image data (`.png`, `.tiff`, `public.jpeg`, `public.heic`) → convert TIFF to PNG, keep PNG/JPEG/HEIC as is → attachment.
   3. String → insert as plain text at the cursor.
   Pasting a screenshot copied with `⌃⇧⌘4` must become an image attachment.
2. Attachment chips row above the footer: thumbnail (images) or file icon + name + size, `✕` to remove. Keyboard: `⇧⌘⌫` discards all (from T04).
3. Staging: attachments are written to `drafts/files/` immediately (so drafts survive crashes) and moved into the outbox on submit (T05 `enqueue` already moves files).
4. Destination writing:
   - **Folder:** copy into `<folder>/<attachmentsFolder>/`, name `Pasted image yyyyMMddHHmmss.png` for clipboard images, original name for files (collision suffix). Append embeds at the end of the note body: `![](attachments/Pasted%20image%2020261002220713.png)` for images, `[spec.pdf](attachments/spec.pdf)` for files.
   - **Obsidian:** location from `attachmentFolderPath`, link style from `useMarkdownLinks` (T07 helpers). Wikilink form: `![[Pasted image 20261002220713.png]]`.
   - **Destinations that can't take attachments:** when the selected destination's `supportsAttachments` is `false`, the footer shows a warning before submit (UX_SPEC §1). Every v1 destination takes attachments, so build the check but there's no real destination to see it on until T08 adds Apple Notes.
5. Limits: warn at > 25 MB per attachment, refuse > 200 MB; max 10 attachments per note.

## Implementation notes

- `NSPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])` for files; `NSImage(pasteboard:)` is convenient but loses the original format — prefer reading the raw data type first.
- Generate thumbnails with `NSImage` at 48 pt on a background queue; release them on panel hide.
- Use the capture's timestamp for generated names so outbox retries don't change filenames.
- `{{attachments}}` in append templates expands to the embed lines.
- Respect concealed pasteboard types (see T11) — don't paste content from `org.nspasteboard.ConcealedType` as attachments.

## Acceptance criteria

- [ ] Screenshot to clipboard → hotkey → `⌘V` → chip appears → `⌘↩` → image file in the vault's attachment folder and embedded in today's daily note, rendering in Obsidian.
- [ ] Dragging a PDF from Finder attaches it.
- [ ] Copying text from a web page pastes plain text, not an attachment.
- [ ] Draft with an attachment survives `Esc` and app relaunch.
- [ ] With a destination whose `supportsAttachments` is `false` (a test double), an attached image shows the footer warning before submit. T08 repeats this check with Apple Notes.
- [ ] Unit tests: attachment naming, Obsidian attachment path resolution for `/`, `./`, `./assets`, `Assets/Images`.

## Out of scope

Rich-text → Markdown conversion (stretch `⇧⌥⌘V`). Link title fetching (network — ADR-009).
