# Otter — UX Spec

## 1. The capture panel

A small sticky-note panel floating above everything (reference: `context/ui/box-ui.png`). It opens as a ready-to-type text box, narrower and taller than a search bar, so it reads as a place to write rather than a place to search. The user can drag it anywhere and it reopens where they left it. There is no title bar or traffic lights.

**Empty**

```
╭──────────────────────────────────────╮
│  ● Daily note · Obsidian             │  ← header: drag handle
│                                      │
│  Jot something down…                 │
│                                      │
│                                      │
│                                      │
│                                      │
│  ──────────────────────────────────  │
│              ⌘↩ Save · ⌘S Save as…   │
╰──────────────────────────────────────╯
```

**Typing, with attachments**

```
╭──────────────────────────────────────╮
│  ● Daily note · Obsidian ▾           │
│                                      │
│  Pick up oat milk + call Sam re: Q4  │
│  deck                                │
│  - ask about the revised budget      │
│    numbers▍                          │
│                                      │
│  [🖼 img.png ✕]  [📄 spec.pdf ✕]     │
│  ──────────────────────────────────  │
│              ⌘↩ Save · ⌘S Save as…   │
╰──────────────────────────────────────╯
```

**Save as (`⌘S`)**

```
   ╭─────────────────────────────────────╮  ← the native Save panel, in its own
   │ Save As: [2026-10-03 2051         ] │     window in the middle of the screen
   │ Tags:    [                        ] │
   │ Where:   [ Otter Inbox          ▾ ] │
   │                [Cancel]  [ Save ]   │
   ╰─────────────────────────────────────╯
```

The `●` in the header is the destination dot (colored per destination), next to the destination name. The footer is always shown. `⌘S` opens the native Save panel in its own window, centred on the screen the panel is on and above it. The name is pre-filled with the date and time and selected, and the folder starts at the destination's folder. Save writes the note to that file (`.md`), names it after the file, and clears the panel for a new note; Cancel or `Esc` goes back to the text (T16, ADR-014).

| Property | Value |
|---|---|
| Size | Opens at 380 × 300 pt. Resizable both ways (min 300 × 180, max 720 × 640, capped to the screen); size remembered |
| Height | Fixed at the user's size; text scrolls inside. The panel doesn't grow as you type |
| Corner radius | 12 pt |
| Position | Screen containing the mouse pointer. Wherever the user last dragged it on that display (remembered per display, across relaunches); otherwise horizontally centered with the top edge at ~22% of the visible frame. Always kept fully on-screen. Settings › General › "Reset panel position and size" restores the default |
| Background | Vibrancy (`NSVisualEffectView`, `.popover`/`.hudWindow` material), thin 0.5 pt separator-color border, system shadow |
| Stacking | Floats above all normal app windows, including full-screen apps, on whichever Space you're on |
| Font | System font, 15 pt (setting: system / monospaced, size) |
| Placeholder | "Jot something down…" |
| Chrome | No title bar, no traffic lights. Dragged by the header strip or footer background; dragging in the text selects text |
| Animation | 80 ms fade-in/out; none if Reduce Motion is on |

### Footer

- **Destination pill** (in the header): colored dot + destination name. For a folder destination the name is the folder's name, its tooltip is the full path, and it highlights on hover. Clicking it opens the destination menu (T10): every destination with its `⌘1…⌘9` number, the shown one ticked, and for a folder, "Change Folder… ⇧⌘O" last. Choosing a destination, or pressing `⌘1…⌘9`, switches it for *this note only*; the default comes back on the next open and after a save. "Change Folder…" (or `⇧⌘O`) opens a folder picker over the panel for the destination shown; the folder chosen becomes where that destination saves from then on, and the text being typed stays as it is (T17). The destination's name follows the folder unless it was renamed in Settings.
- **Attachment chips** (above the footer, T09): one per pasted or dropped file or image: a thumbnail for images or the file type's icon, the name ("Pasted image" for clipboard image data) and size, and `✕` to remove it. The row scrolls sideways when full and is hidden when empty. Up to 10 per note; a file over 200 MB is refused, one over 25 MB is kept with a warning.
- **Hint** (right): `⌘↩ Save · ⌘S Save as…`. Turns into an orange inline warning when relevant: why a paste wasn't attached (too many, too large, a folder), until the next edit; when the destination can't take attachments ("{Destination} can't take attachments — they'll be dropped." once T08 adds Apple Notes); or when an attachment is over 25 MB.
- **Pending badge**: if the outbox has failed deliveries, a small amber dot with count appears next to the destination pill. Click → menu with Retry / Show details.

### States

| State | What the user sees |
|---|---|
| Empty | Placeholder, header with default destination |
| Draft restored | Previous draft text, cursor at end, text **not** selected (so typing appends) |
| Typing | Text scrolls inside the panel once it's longer than the panel |
| Saving | Nothing — the panel closes immediately on `⌘↩` (optimistic) |
| Delivery failed | Menu bar icon gets an amber badge; macOS notification once per failure burst; badge in panel footer next open |

### Inline Markdown styling

The note stays plain Markdown. The editor styles inline Markdown as it's typed, pasted, restored from a draft or added by a shortcut, and hides the markers of every complete span (ADR-016). Styling and hiding are display-only: what's drafted, saved and delivered is exactly the text with its markers.

| Markdown | Shown as |
|---|---|
| `**bold**`, `__bold__` | **bold** |
| `*italic*`, `_italic_` | *italic* |
| `***both***`, `**_both_**` | bold italic |
| `~~struck~~` | struck through |
| `` `code` `` (any run of backticks) | `code` in the monospaced system font at the editor's size, faint background (`quaternarySystemFill`) over the code only |
| `[text](url)` | `text` in the link colour, underlined; the URL shows as a tooltip on hover. Not clickable: a click places the caret |

**What's styled**

- Styles combine: bold inside a link, struck-through italic. Nothing inside inline code is styled.
- Rules follow CommonMark/GFM as Obsidian renders them, within one line: a span never crosses a line break; `\*` is a literal `*` (the backslash stays visible); `_` doesn't open or close inside a word (`snake_case_name` stays plain); an unclosed marker, or one with a space just inside (`** x **`), is plain text.
- Lines inside a fenced code block (```` ``` ```` or `~~~`) aren't styled.
- Not styled, shown as typed: headings, `*` / `+` bullets and numbered lists, block quotes, tables, rules, highlights `==…==`, wikilinks `[[…]]`, images `![…](…)`, bare URLs, HTML. `- ` bullets and `- [ ]` tasks are covered under Lists and tasks below.
- Follows the Font setting (§5): bold and italic are faces of the chosen font; with Monospaced, inline code keeps only its background.

**When markers hide**

- Only a complete span's markers hide: `**`, `*`, `_`, `~~`, backticks, and a link's `[` and `](url)`. Hidden markers take no space.
- An unclosed span shows its markers as typed: `**abc` stays `**abc`. The moment the closing marker is typed, both hide and the caret sits after the span, so what's typed next is plain. (Typing `**abc**` shows `*`*abc* for a moment after the first closing `*`, as in Obsidian.)
- An empty pair (`****`, ` `` `) isn't a span and shows as typed, so `⌘B` with nothing to bold inserts a visible `****` with the caret between; the first character typed hides the markers and continues bold.
- A link's raw Markdown shows while the selection is inside its destination: after `⌘K` selects `url`, or after `⌘K` with the caret in an existing link, which selects its URL to type over. The markers and URL then show as typed, URL in `secondaryLabelColor`, until the selection leaves the link.

**Caret and typing**

- The caret never stops inside or beside a hidden marker as a separate position. `←` / `→` move one visible character, skipping hidden markers, so every press moves the caret. Clicks, `↑` / `↓`, word and line movement land on the nearest visible position.
- At a span's edge, typing takes the style of the visible character before the caret, as in a word processor: at the end of `**bold**` it continues bold; at its start it's plain.
- Two exceptions put the caret after a span's closing marker, so typing is plain: having just typed the closing marker, and pressing the span's shortcut (`⌘B`, `⌘I`, `⇧⌘X`, `⌘E`) with the caret at its end. Either lasts until the caret moves.
- `↩` (or a pasted line break) inside a span splits it: `**ab|c**` becomes `**ab**⏎**c**`. At a span's end, the line break goes after the closing marker.
- A non-empty selection never starts or ends inside hidden markers; its highlight covers visible characters only.

**Deleting, replacing, copying**

- `⌫` / `⌦` delete the visible character before / after the caret, never a hidden marker on its own, so ordinary editing can't half-break a style. Deleting a span's last visible character removes its markers too. A style is taken off with its shortcut, caret in the span or text selected.
- Deleting or cutting a selection removes every span whose visible text is all selected, markers included. A span only partly selected keeps its markers: deleting `x **ab` from `x **abc**` leaves `**c**`, still bold.
- Typing or pasting over a selection does the same, and the new text takes the style of the first selected character, so typing over a selected bold word keeps it bold.
- Copy, cut and drag put plain Markdown on the pasteboard, closing and reopening any partly selected span so it pastes looking the same: copying `ab` from `**abc**` gives `**ab**`. Paste is still plain text; pasted Markdown is styled and its markers hide.
- Select All, double-click and triple-click select as usual; the rules above decide which markers go with the selection.

**Undo, IME, spelling, VoiceOver**

- Styling and hiding are never undo steps. `⌘Z` brings back the text, and its styling follows; undoing the closing marker you just typed shows the markers again.
- While an input method is composing, nothing restyles or hides; the text restyles once it's committed.
- Spell checking works as before; hidden markers are punctuation and aren't checked. It still runs inside inline code.
- VoiceOver reads the saved Markdown, markers included (ADR-016).

### Lists and tasks

`- ` bullets and `- [ ]` tasks look like a list, and the note stays plain Markdown (ADR-017, ADR-018, T18). As in Obsidian, typing `- ` shows a bullet straight away and `- [ ] ` a circle, on the line you're on too; the raw marker shows only while the caret is in it.

| Markdown, at a line's start | Shown as |
|---|---|
| `- item` | `•` item |
| `- [ ] task` | ○ task |
| `- [x] done`, `- [X] done` | ✓ in an accent-filled circle; done, dimmed and struck through |

- A line counts when its indentation is followed by `-` and one space. A task also needs the space after `]`. These show as typed: a lone `-`, `---`, `*` / `+` / numbered lists, lists in a `>` quote, and lines inside a fence.
- Each nesting level indents 1.34 em, the same as from plain text to a bullet's text; a task's text starts at 1.75 em. The bullet is a grey dot 0.28 em across and the checkbox a grey ring 0.94 em across, both centred 0.87 em in (measured from Obsidian). Wrapped lines hang under the item's text. An item is one level deeper than the nearest item above it with less indentation, so lists indented with 2 spaces, 4 spaces or tabs all nest. The indentation characters are always hidden.
- While the caret is in an item's marker (`←` from the start of its text steps in), or a selection includes part of it, the marker shows as raw text (`- `, `- [ ] `, `- [x] `) in `tertiaryLabelColor`. `- ` hangs left of the text; `- [ ] ` pushes the text right, as in Obsidian. Otherwise the marker is hidden and a bullet or circle is drawn, including on the caret line, so after `↩` continues a list the new line shows a bullet straight away.
- Arriving on an item line from elsewhere (click, `↑` / `↓`, `→`, `⌘←`) puts the caret at the start of the item's text, so typing goes into the item. `←` from there steps into the marker, which then shows as ordinary text, and you can edit `- [ ]` directly. Hidden indentation is skipped, and a selection that includes the `-` takes the indentation with it (`⌘A` then `⌫` empties the note).
- `↩` continues the list with the same indentation. A new task is always unchecked, and text after the caret moves to the new item. `↩` on an empty item outdents it if it's nested, or otherwise removes the marker and ends the list.
- `⌫` at the start of an item's text removes its marker (all of `- [ ] ` for a task) and keeps the indentation. `⌦` at the end of an item joins the next item's text onto it.
- `Tab` / `⇧Tab` in an item indent it under the item above / outdent it back to its parent's indentation, using tab characters. Elsewhere `Tab` still inserts a tab.
- Clicking a drawn circle ticks or unticks it, writing `[x]` or `[ ]`, without moving the caret, on any line. A revealed raw `[ ]` is plain text: a click places the caret there, and `⌘L` toggles it. Each list action is one `⌘Z` step.
- Paste inserts text as it does now and never adds markers. Copying across lines includes the markers. While an input method is composing, `↩` and `Tab` go to it.

## 2. Keyboard map

| Shortcut | Scope | Action |
|---|---|---|
| `⌥Space` *(default; `⌘Space` optional, set up in onboarding — see ADR-010, ADR-011)* | Global | Toggle panel (show → focus → hide) |
| *unset (suggest `⌥⇧Space`)* | Global | Save clipboard as a note instantly, show HUD |
| `⌘↩` | Panel | Save and close |
| `⇧⌘↩` | Panel | Save and keep open (cleared, ready for the next note) |
| `⌘S` | Panel | Save as: the native Save panel picks the name (defaults to the date and time) and folder; save it there, keep the panel open for a new note |
| `Esc` | Panel | Close. Draft is kept and restored next time |
| `⇧⌘⌫` | Panel | Discard draft (and attachments) |
| `⌘1` … `⌘9` | Panel | Choose destination for this note |
| `⇧⌘O` | Panel | Change the save folder (same as clicking the folder name in the header) |
| `⌘V` | Panel | Paste as plain text; files, then images become attachments (formatted text with a picture of itself stays text; concealed or transient pasteboard content is never attached) |
| `⇧⌥⌘V` | Panel | Paste with original formatting converted to Markdown *(stretch)* |
| `⌘B` / `⌘I` | Panel | Bold `**…**` / italic `*…*` on the selection, or the word the caret is in; elsewhere inserts an empty pair with the caret between. Pressed again, removes it; with the caret at the end of a bold / italic span, moves it past the span so typing is plain |
| `⇧⌘X` | Panel | Strikethrough `~~…~~`, the same way |
| `⌘E` | Panel | Inline code `` `…` ``, the same way |
| `⌘K` | Panel | Link: `[selection](url)` with `url` selected to type over (the link shows raw while you do). A URL on the clipboard is used instead, caret after the link; a selected URL becomes `[](URL)` with the caret in the brackets. In an existing link, shows it raw and selects its URL |
| `⌘L` | Panel | Task: makes the line, or each selected line, a `- [ ]` task; on a task, checks or unchecks it (T18) |
| `⇧⌘8` | Panel | Bullet: adds `- ` to the line or selected lines; removes it if they're all list items already (T18) |
| `Tab` / `⇧Tab` | Panel | In a list item: indent / outdent it. Elsewhere `Tab` inserts a tab (T18) |
| `↩` | Panel | In a list item: continues the list. On an empty item, outdents it or ends the list (T18) |
| `⌘,` | Panel | Open Settings |
| `⌘Z` / `⇧⌘Z` | Panel | Undo / redo |

The formatting shortcuts only add or remove Markdown markers; the editor then styles the text and hides the markers, the same as typed Markdown (§1, Inline Markdown styling). Each is one `⌘Z` step. Surrounding spaces stay outside the markers, a selection across lines is done line by line (blank lines skipped, list and quote markers left outside), and bold and italic nest (`***both***`) rather than undoing each other.

Clicking outside the panel closes it (keeps the draft). Setting: "Keep panel open when clicking elsewhere".

## 3. Save-clipboard HUD

A small non-interactive pill near the bottom center of the screen with the pointer, visible ~1.2 s:

```
        ┌─────────────────────────────────┐
        │  ✓  Saved to Otter Inbox        │
        └─────────────────────────────────┘
```

The hotkey and the menu bar's "Save Clipboard" save what's on the clipboard to the default destination, read in the same order as `⌘V` in the panel: files, then an image, then text. ✓ shows once the outbox has the note; delivery is in the background, as for the panel.

| Message | When |
|---|---|
| ✓ Saved to {destination} | Saved. "· 2 files skipped" is added when some copied files couldn't be attached (a folder, over 200 MB, past 10) |
| ✓ Already saved | The same clipboard (`changeCount`) was saved less than 10 s ago |
| ✕ Clipboard is empty | No file, no image Otter attaches, no text that isn't only whitespace |
| ✕ Skipped — copied from a password manager | The clipboard is marked `org.nspasteboard.ConcealedType` or `TransientType`; it's never read |
| ✕ {reason} | None of the files or the image could be attached, e.g. "“talk.mov” is over 200 MB, so it can't be attached." |
| ✕ Not saved — no destination set up / disk is full / couldn't write to Otter's outbox | The outbox didn't take the note |

| Property | Value |
|---|---|
| Size | 40 pt tall, as wide as the message (truncated 16 pt from the screen's sides); fully rounded ends |
| Position | Centred, its bottom 72 pt above the bottom of the visible frame (above the Dock) |
| Content | SF Symbol `checkmark.circle.fill` (green) or `xmark.circle.fill` (secondary), then the message in the 14 pt medium system font |
| Background | `.hudWindow` vibrancy; solid with Reduce Transparency |
| Animation | 150 ms fade-in, 300 ms fade-out; none with Reduce Motion |
| Repeat | A new message replaces the one showing, moves to the pointer's screen and restarts the 1.2 s |
| VoiceOver | The message is announced (high priority), without the symbol |

## 4. Menu bar

Template icon (monochrome, adapts to light/dark). Amber dot when deliveries are failing.

```
New Note                          ⌥Space
Finish setting up ⌘Space…                   (only if the user chose ⌘Space and Spotlight still owns it)
Save Clipboard                    ⌥⇧Space
──────────────────────────────────────────
Recent                                  ▸   (last 10: first line · destination · time)
──────────────────────────────────────────
2 notes waiting to deliver… Retry           (only when non-zero)
──────────────────────────────────────────
Settings…                             ⌘,
Quit Otter                              ⌘Q
```

Clicking a recent item opens it where it lives: reveal in Finder (Folder) or `obsidian://open` (Obsidian). After v1, Apple Notes items activate Notes (T08).

## 5. Settings (one window, three tabs)

**General**
- Open-panel hotkey · Save-clipboard hotkey
- Launch at login
- Close panel when clicking elsewhere
- Font: System / Monospaced, size
- Smart quotes and dashes (off by default — notes often contain code)
- Reset panel position and size

**Destinations**
- List of destinations with drag-to-reorder (order = `⌘1…⌘9`), star = default
- Add: Obsidian vault (detected vaults listed) · Folder. Apple Notes joins this menu after v1 (T08).
- Per-destination options (mode, target file/folder, template, frontmatter) and a **Test** button that writes a test note and reports success/failure

**Advanced**
- Outbox: pending count, last error, Retry now, Reveal outbox folder
- Remember recent captures (on/off) · Clear recents
- Reveal logs (saves this run's log, which never holds note text, to `logs/` and shows it in Finder) · Reset all settings (after a confirmation: preferences, shortcuts, panel position and destinations go back to a fresh install's; waiting notes go to the Otter Inbox; onboarding isn't shown again)

Every setting applies as it changes; there's no Save button. A destination with notes waiting can be deleted only after confirming they move to the default; the last destination can't be deleted. Health dots: green working, amber needs access, red folder missing; checked when the tab appears and after edits. A failed Test says what's wrong and offers the fix ("Choose Folder…" for a missing folder, "Grant Access…" to re-pick one Otter can't write to). `⌘W` closes the window.

## 6. First run

Shown once, in the Settings window, three steps:

1. **Your hotkey.** Recommended: `⌥Space`, already active. "Use ⌘Space instead" starts the Spotlight handoff: if Spotlight still owns `⌘Space`, the step explains this in one sentence and shows an **Open Keyboard Shortcuts** button (System Settings › Keyboard › Keyboard Shortcuts › Spotlight) with "Uncheck *Show Spotlight search*, or change it to ⌥Space." The step re-checks when Otter regains focus and turns green once `⌘Space` is free; then it asks the user to press `⌘Space` once to confirm. "Use a different shortcut" opens the recorder; "Skip for now" keeps `⌥Space`. Either way, the step asks the user to press the shortcut once to confirm it reaches Otter (`⌥Space` may be taken by another app).
2. **Where should notes go?** Detected Obsidian vaults listed first (the one opened most recently pre-selected), then the Otter Inbox in Documents, then "A folder…". One choice; sensible defaults for the rest (a vault or folder → new file per note, ADR-013). After v1, T08 adds Apple Notes between the two ("Otter" folder in the default account), and picking it runs a test right away so the Automation prompt appears now, not mid-capture.
3. **Try it.** "Press ⌥Space, type anything, hit ⌘↩." (shows whichever hotkey step 1 ended on) The step completes itself when the first capture is delivered and shows where it went, with an "Open" button.

Launch at login is offered on the last step (default on). In step 1 a press of the toggle shortcut confirms it rather than opening the panel; from step 3 it opens the panel. Closing the window counts as done.

## 7. Accessibility

- Text view and controls have VoiceOver labels; panel announces "Otter, note editor" on open.
- Respects Reduce Motion, Reduce Transparency (solid background), Increase Contrast.
- Every action is reachable by keyboard.
