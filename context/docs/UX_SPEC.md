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
| Position | Screen containing the mouse pointer. Wherever the user last dragged it on that display (remembered per display, across relaunches); otherwise horizontally centered with the top edge at ~22% of the visible frame. Always kept fully on-screen. Menu bar "Reset Panel Position" restores the default |
| Background | Vibrancy (`NSVisualEffectView`, `.popover`/`.hudWindow` material), thin 0.5 pt separator-color border, system shadow |
| Stacking | Floats above all normal app windows, including full-screen apps, on whichever Space you're on |
| Font | System font, 15 pt (setting: system / monospaced, size) |
| Placeholder | "Jot something down…" |
| Chrome | No title bar, no traffic lights. Dragged by the header strip or footer background; dragging in the text selects text |
| Animation | 80 ms fade-in/out; none if Reduce Motion is on |

### Footer

- **Destination pill** (in the header): colored dot + destination name. For a folder destination the name is the folder's name, its tooltip is the full path, and it highlights on hover. Clicking it (or `⇧⌘O`) opens a folder picker over the panel; the folder chosen becomes where notes are saved from then on, and the text being typed stays as it is (T17). `⌘1…⌘9` switches destination for *this note only*; the default comes back on the next open.
- **Hint** (right): `⌘↩ Save · ⌘S Save as…`. Turns into an inline warning when relevant, e.g. when the destination can't take attachments ("Apple Notes can't take images yet — they'll be dropped." once T08 adds Apple Notes).
- **Pending badge**: if the outbox has failed deliveries, a small amber dot with count appears next to the destination pill. Click → menu with Retry / Show details.

### States

| State | What the user sees |
|---|---|
| Empty | Placeholder, header with default destination |
| Draft restored | Previous draft text, cursor at end, text **not** selected (so typing appends) |
| Typing | Text scrolls inside the panel once it's longer than the panel |
| Saving | Nothing — the panel closes immediately on `⌘↩` (optimistic) |
| Delivery failed | Menu bar icon gets an amber badge; macOS notification once per failure burst; badge in panel footer next open |

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
| `⌘V` | Panel | Paste as plain text; images/files become attachments |
| `⇧⌥⌘V` | Panel | Paste with original formatting converted to Markdown *(stretch)* |
| `⌘,` | Panel | Open Settings |
| `⌘Z` / `⇧⌘Z` | Panel | Undo / redo |

Clicking outside the panel closes it (keeps the draft). Setting: "Keep panel open when clicking elsewhere".

## 3. Save-clipboard HUD

A small non-interactive pill near the bottom center of the active screen, visible ~1.2 s:

```
        ┌─────────────────────────────────┐
        │  ✓  Saved to Daily note         │
        └─────────────────────────────────┘
```

Error variant: "✕ Clipboard is empty" / "✕ Skipped — clipboard came from a password manager".

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
- Reveal logs · Reset all settings

## 6. First run

Shown once, in the Settings window, three steps:

1. **Your hotkey.** Recommended: `⌥Space`, already active. "Use ⌘Space instead" starts the Spotlight handoff: if Spotlight still owns `⌘Space`, the step explains this in one sentence and shows an **Open Keyboard Shortcuts** button (System Settings › Keyboard › Keyboard Shortcuts › Spotlight) with "Uncheck *Show Spotlight search*, or change it to ⌥Space." The step re-checks when Otter regains focus and turns green once `⌘Space` is free; then it asks the user to press `⌘Space` once to confirm. "Use a different shortcut" opens the recorder; "Skip for now" keeps `⌥Space`. Either way, the step asks the user to press the shortcut once to confirm it reaches Otter (`⌥Space` may be taken by another app).
2. **Where should notes go?** Detected Obsidian vaults listed first, then "A folder…". One choice; sensible defaults for the rest (a vault or folder → new file per note, ADR-013). After v1, T08 adds Apple Notes between the two ("Otter" folder in the default account), and picking it runs a test right away so the Automation prompt appears now, not mid-capture.
3. **Try it.** "Press ⌥Space, type anything, hit ⌘↩." (shows whichever hotkey step 1 ended on) The step completes itself when the first capture is delivered and shows where it went, with an "Open" button.

Launch at login is offered on the last step (default on).

## 7. Accessibility

- Text view and controls have VoiceOver labels; panel announces "Otter, note editor" on open.
- Respects Reduce Motion, Reduce Transparency (solid background), Increase Contrast.
- Every action is reachable by keyboard.
