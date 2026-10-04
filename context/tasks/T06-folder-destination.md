# T06 — Folder destination

**Milestone:** M0 · **Depends on:** T04, T05 · **Estimate:** 1 day

## Goal

Write captures as Markdown into any folder the user picks, either one file per note or appended to a single inbox file. This is the universal fallback **and** the engine the Obsidian destination is built on. Completing it completes M0.

## Read first

- ARCHITECTURE §5.1
- OVERVIEW §6
- UX_SPEC §1 footer (destination pill)

## Scope

1. `FolderOptions`:
   ```swift
   struct FolderOptions: Codable {
       var bookmark: Data
       var displayPath: String              // for UI only
       var mode: Mode                       // .newFilePerNote | .appendToFile(name: String)
       var subfolder: String?               // relative, e.g. "Inbox"
       var filenameTemplate = "{date} {time} {title}"
       var frontmatter = true
       var appendTemplate: String = AppendTemplate.default
       var attachmentsFolder = "attachments"   // used by T09
   }
   ```
2. `FileNamer` (pure): title from first non-empty line, strip leading `#`, `-`, `* `, `> `, `[ ] `; remove `/ \ : * ? " < > | # ^ [ ]` and control chars; collapse whitespace; trim to 60 chars at a word boundary; fallback "Quick note". `{date}` = `yyyy-MM-dd`, `{time}` = `HHmm`. Collision suffix ` 2`, ` 3`….
3. `MarkdownWriter` (pure): renders new-file content (optional frontmatter + text, trailing newline) and append blocks via `AppendTemplate` (`{{time}}`, `{{date}}`, `{{text}}`, `{{attachments}}`, `{{#single_line}}…{{/single_line}}`, `{{#multi_line}}…{{/multi_line}}`).
4. `FolderDestination: Destination`:
   - Resolve bookmark (`URL(resolvingBookmarkData:options:bookmarkDataIsStale:)`); if stale, re-create it; if unresolvable → `.unreachable("Folder missing")`.
   - New file: write to `.<uuid>.tmp` in the target dir, then `FileManager.moveItem` → final name (atomic rename). Create subfolder if needed.
   - Append: `NSFileCoordinator().coordinate(writingItemAt:options: .forMerging)`; create if missing; if the file doesn't end with `\n`, write one; separate blocks with one blank line; `seekToEnd` + `write` + `synchronize`.
   - `healthCheck`: exists, is directory, writable (`FileManager.isWritableFile`).
   - Receipt `.file(URL)`.
5. Minimal app UI for M0: menu item "Choose Folder…" → `NSOpenPanel` (directories only, "Create Folder" allowed) → registers a folder destination as default. Panel footer shows its name.
6. Default destination if nothing is configured: `~/Documents/Otter Inbox/` (created on first save), new file per note.

## Implementation notes

- Never construct paths from note text without sanitizing; reject `..` and leading `/` in templates/subfolders.
- Line endings: always `\n`. Encoding: UTF-8 without BOM.
- Frontmatter:
  ```yaml
  ---
  created: 2026-10-02T22:07:13-04:00
  source: otter
  ---
  ```
- Format times with the capture's stored time zone (T05).
- First write into `~/Documents` or iCloud Drive may trigger a TCC prompt — that's expected; it happens on a background lane, and the outbox retries if denied.

## Acceptance criteria

- [x] Unit tests: `FileNamer` edge cases (emoji, only punctuation, very long line, leading `# `, path traversal attempts, collisions).
- [x] Unit tests: `MarkdownWriter` new-file and append rendering, single vs multi-line templates.
- [x] Integration test (temp dir): 50 concurrent appends from the delivery lane produce 50 intact blocks in order.
- [x] Manual: point at an Obsidian vault folder with Obsidian open → new notes appear in Obsidian within a second.
- [x] Manual: rename the chosen folder in Finder → next capture still lands in it (bookmark).
- [x] Manual: delete the folder → capture stays in outbox, error visible in logs; recreate/choose again → delivered.
- [x] **M0 demo:** hotkey → type → `⌘↩` → file exists, and you're back in your previous app.

## Out of scope

Obsidian specifics (T07). Attachments (T09). Full destination settings UI (T10).
