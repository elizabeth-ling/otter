# T07 — Obsidian destination

**Milestone:** M1 · **Depends on:** T06 · **Estimate:** 1–1.5 days

## Goal

First-class Obsidian support with zero configuration for the common case: pick a detected vault, and quick notes append to today's daily note exactly where Obsidian itself would put it.

## Read first

- ARCHITECTURE §5.2
- DECISIONS ADR-002
- OVERVIEW §10 open question 5 (append format)

## Scope

1. `VaultDiscovery`: read `~/Library/Application Support/obsidian/obsidian.json`; return `[Vault(id, name: lastPathComponent, path, lastOpened)]` sorted by last opened; skip paths that don't exist. Also `isVault(url)` = contains `.obsidian/`.
2. `ObsidianOptions`:
   ```swift
   struct ObsidianOptions: Codable {
       var vaultBookmark: Data
       var vaultName: String
       var mode: Mode            // .dailyNote | .appendToNote(path) | .newNoteIn(folder)
       var dailyOverride: DailyOverride?   // folder/format/template override if user sets one
       var underHeading: String?           // stretch: append under "## Inbox"
       var appendTemplate: String
   }
   ```
3. `DailyNoteResolver`: read `.obsidian/daily-notes.json` (`folder`, `format`, `template`); defaults: root folder, `YYYY-MM-DD`, no template. Produce the vault-relative path for the capture's date. If the daily note doesn't exist: create it from the template file (substitute `{{date}}`, `{{title}}`, `{{time}}`; `{{date:FORMAT}}` with Moment format) or empty.
4. `MomentFormat.toDateFormatter(_:)` supporting at least: `YYYY YY M MM MMM MMMM D DD Do d dd ddd dddd H HH h hh m mm s ss A a W WW gggg [literal]`. `Do` → day + English ordinal suffix (post-process). Unsupported token → return `nil`, fall back to `YYYY-MM-DD`, and surface a warning in settings.
5. `ObsidianDestination: Destination` delegating file I/O to the T06 writer. Receipt `.obsidian(vault: name, path: relative)`.
6. Attachment placement (consumed by T09): parse `.obsidian/app.json` `attachmentFolderPath` (`/`, `./`, `./sub`, or vault-relative) and `useMarkdownLinks` → embed syntax `![[file.png]]` or `![](relative/path.png)` with spaces percent-encoded.
7. "Open in Obsidian" helper: `obsidian://open?vault=<urlencoded name>&file=<urlencoded vault-relative path without .md>`.
8. Temporary menu: "Use Obsidian Vault ▸" listing detected vaults (T10 replaces it with real settings).

## Implementation notes

- Use the Periodic Notes plugin config (`.obsidian/plugins/periodic-notes/data.json`, `daily.enabled/folder/format/template`) **if** present and enabled, since it overrides core Daily Notes. Parse defensively; if the shape doesn't match, ignore it.
- Default append template (single-line → bullet, multi-line → `### HH:mm` block). Make sure the appended block is separated by a blank line from existing content.
- `underHeading` (stretch): find the heading line; insert at the end of that section (before the next heading of the same or higher level); if missing, append the heading + content at the end.
- Don't touch `.obsidian/` other than reading.
- Fixture vaults in `Tests/Fixtures/` covering: no config, core daily notes with folder+format, template with `{{date:dddd, MMMM Do}}`, periodic notes, attachments `./assets`, markdown links.

## Acceptance criteria

- [ ] Detected vaults listed with the most recently opened first.
- [ ] With daily notes configured as `Journal/YYYY/YYYY-MM-DD`, a capture creates/appends `Journal/2026/2026-10-02.md`.
- [ ] Daily note created from the vault's template with variables substituted.
- [ ] Works with Obsidian closed; Obsidian shows the change immediately when open.
- [ ] Capture made at 23:59 and delivered at 00:01 goes to the **capture's** day.
- [ ] `MomentFormat` unit tests for every supported token and the fallback path.
- [ ] "Open in Obsidian" opens the exact note.

## Out of scope

Writing into `.obsidian/`. Templater plugin syntax (`<% %>`) — leave untouched. Canvas files.
