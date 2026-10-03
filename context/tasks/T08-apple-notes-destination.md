# T08 — Apple Notes destination

**Milestone:** M1 · **Depends on:** T05 · **Estimate:** 1 day

## Goal

Send captures to Apple Notes as real notes in a chosen account and folder, safely and without ever blocking the UI.

## Read first

- ARCHITECTURE §5.3, §7 (permissions)
- DECISIONS ADR-003, ADR-004

## Scope

1. `OsascriptRunner` (OtterCore): runs `/usr/bin/osascript -` (script from stdin) with arguments, via `Process`, on a background task. Captures stdout/stderr and exit code; 20 s timeout (terminate on expiry). Parses AppleScript error numbers from stderr (`… (-1743)`).
2. Scripts (constants, never string-built with user content):
   ```applescript
   -- create-note.applescript
   on run argv
     set noteBody to item 1 of argv
     set accountName to item 2 of argv
     set folderName to item 3 of argv
     tell application "Notes"
       set acct to account accountName
       if not (exists folder folderName of acct) then
         make new folder at acct with properties {name:folderName}
       end if
       set newNote to make new note at folder folderName of acct with properties {body:noteBody}
       return id of newNote
     end tell
   end run
   ```
   Plus `list-accounts-and-folders` returning a simple delimited list for the settings picker, and `ping` (`tell application "Notes" to count accounts`) for health checks / triggering the permission prompt.
3. `NotesHTML.render(text)` (pure): escape `& < > "`; each line → `<div>…</div>`; empty line → `<div><br></div>`; preserve leading spaces as `&nbsp;`. Optionally append a small grey timestamp line (setting, default off).
4. `NotesOptions { accountName: String?, folderName = "Otter", mode: .newNote }`. `nil` account = default account (resolve via `default account` in script).
5. `AppleNotesDestination: Destination`, `supportsAttachments = false`. Receipt `.appleNote(id:)`.
6. Error mapping:
   | Code | Meaning | Health / message |
   |---|---|---|
   | `-1743` | Not authorized | `.needsPermission` → "Allow Otter to control Notes in System Settings › Privacy & Security › Automation" + button opening `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation` |
   | `-1728` | Account/folder not found | `.unreachable("Account ‘X’ not found")` |
   | timeout | Notes not responding | retryable |
7. Temporary menu item "Use Apple Notes" that runs `ping` (triggers the prompt) and registers the destination.

## Implementation notes

- Pass arguments as separate `Process.arguments` entries after `-` — no shell, no quoting issues, no injection.
- Notes may launch in the background on first call; that's fine. Don't activate it.
- If a capture contains attachments, the panel footer warns before submit (UX_SPEC §1); on delivery, text is sent and attachment names are listed at the bottom of the note as plain text.
- **Stretch — append mode** (`.appendToNote(name)`): `set body of n to (body of n) & noteBody`. Verify it doesn't mangle checklists/tables in the existing note before enabling; ship behind a flag if unsure.
- Verify the scripts against the current macOS release before relying on them; behavior of the Notes scripting dictionary should be re-checked on each major macOS update (add to T14's matrix).

## Acceptance criteria

- [ ] First use shows the Automation prompt naming **Otter**; after allowing, the note appears in Notes › Otter.
- [ ] Denying permission → capture stays in outbox, clear message with the System Settings button; allowing → retry delivers.
- [ ] Note text containing `"`, `\`, `<script>`, `end tell`, and emoji appears verbatim in Notes.
- [ ] Panel closes instantly even when Notes takes 3 s to launch.
- [ ] Unit tests for `NotesHTML` and stderr error-code parsing.

## Out of scope

Attachments/images in Notes. Shortcuts-based destination (future ADR).
