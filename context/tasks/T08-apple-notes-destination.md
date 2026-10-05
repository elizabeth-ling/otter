# T08 — Apple Notes destination

**Milestone:** M3 (after v1) · **Depends on:** T05; builds on T10 and T14 · **Estimate:** 1 day for the destination, 2–4 days with the pieces below

> **Deferred (ADR-015).** v1 ships with Folder and Obsidian only. The other tasks were written so they don't need this one, and their Apple Notes parts moved here: see [Picking this back up](#picking-this-back-up).

## Goal

Send captures to Apple Notes as real notes in a chosen account and folder, safely and without ever blocking the UI.

## Read first

- ARCHITECTURE §5.3, §7 (permissions)
- DECISIONS ADR-003, ADR-004, ADR-014 (`fileURL` captures), ADR-015

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

## Picking this back up

These were taken out of other tasks when T08 was deferred. Each is part of this task now.

- **Before starting:** run `ping` and `create-note` by hand on the current macOS release, and check whether Notes calls need the `com.apple.security.automation.apple-events` entitlement under Hardened Runtime (T01's follow-up). `NSAppleEventsUsageDescription` is already in the Info.plist. If an entitlement is needed, add it to the signing setup T13 built.
- **Registry and model:** add `DestinationKind.appleNotes` and `DestinationConfig.Options.appleNotes(NotesOptions)`, decoding settings saved without them, and register the builder. `DeliveryReceipt.Location.appleNote(id:)` already exists.
- **Named notes and save-as (T16, ADR-014):** a capture with a `title` sends it as a bold first `<div>`, followed by the body. A capture that carries a `fileURL` (from the `⌘S` Save panel) is a file, so it goes to the default *folder* destination, or `⌘S` is unavailable while Apple Notes is the panel's destination. Pick one and record it in this spec.
- **Attachments (T09):** the footer warning before submit is driven by `supportsAttachments`, which T09 already checks. Confirm it shows with Apple Notes selected and an image attached.
- **Settings and onboarding (T10):**
  - Add Apple Notes to the Destinations tab's Add menu, with account and folder pickers filled by `list-accounts-and-folders`.
  - The Test button shows the `-1743` permission error with its System Settings button.
  - Onboarding step 2 lists Apple Notes between the detected vaults and "A folder…", and choosing it runs `ping` straight away so the Automation prompt appears while the user is paying attention.
  - Remove this task's temporary "Use Apple Notes" menu item.
- **Recent menu (T12):** a `.appleNote` receipt opens Notes (`NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))`).
- **Packaging (T13):** the README's permissions section explains Notes automation.
- **Performance and reliability (T14):** add "Enqueue → delivered (Apple Notes, warm / cold)" with a target of < 1 s / < 4 s to `PERF.md`, and the rows "Notes permission revoked mid-session" and "Notes iCloud account signed out" to `TEST_MATRIX.md`. Re-check the Notes scripting dictionary on each major macOS update.
- **Tests:** Apple Notes integration tests run only locally, behind an env flag, because they need TCC (ARCHITECTURE §11).

## Acceptance criteria

- [ ] First use shows the Automation prompt naming **Otter**; after allowing, the note appears in Notes › Otter.
- [ ] Denying permission → capture stays in outbox, clear message with the System Settings button; allowing → retry delivers.
- [ ] Note text containing `"`, `\`, `<script>`, `end tell`, and emoji appears verbatim in Notes.
- [ ] Panel closes instantly even when Notes takes 3 s to launch.
- [ ] Unit tests for `NotesHTML` and stderr error-code parsing.
- [ ] A named capture creates a note titled after its name (T16's "Groceries" check), and a `fileURL` capture is handled as decided above.
- [ ] Choosing Apple Notes in onboarding shows the Automation prompt at that step, and the Test button surfaces a denied permission with a working fix.
- [ ] Clicking an Apple Notes item in Recent opens Notes.

## Out of scope

Attachments/images in Notes. Shortcuts-based destination (future ADR).
