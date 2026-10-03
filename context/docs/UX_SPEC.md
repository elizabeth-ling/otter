# Otter — UX Spec

## 1. The capture panel

Modelled on the ChatGPT desktop overlay: a single rounded, translucent bar floating above everything, centered in the upper part of the screen. It starts as one line and grows downward as you type. There is no window chrome.

**Empty (compact bar)**

```
╭──────────────────────────────────────────────────────────────╮
│  ●  Jot something down…                                ⌘↩    │
╰──────────────────────────────────────────────────────────────╯
```

**Typing (expanded)**

```
╭──────────────────────────────────────────────────────────────╮
│  ●  Pick up oat milk + call Sam re: Q4 deck                  │
│     - ask about the revised budget numbers▍                  │
│                                                              │
│     [🖼 img.png ✕]  [📄 spec.pdf ✕]       ← attachment chips  │
│  ──────────────────────────────────────────────────────────  │
│     Daily note · Obsidian ▾                       ⌘↩ Save    │
╰──────────────────────────────────────────────────────────────╯
```

The `●` on the left is the destination dot (colored per destination). The footer row (destination name and save hint) appears once there is text or an attachment, so the empty state stays a clean one-line bar.

| Property | Value |
|---|---|
| Width | 640 pt (user-resizable horizontally, remembered) |
| Height | Compact bar 56 pt; grows with content to 420 pt, then scrolls |
| Corner radius | 16 pt (fully pill-like in the compact state) |
| Position | Screen containing the mouse pointer; horizontally centered; top edge at ~22% of the visible frame |
| Background | Vibrancy (`NSVisualEffectView`, `.popover`/`.hudWindow` material), thin 0.5 pt separator-color border, system shadow |
| Stacking | Floats above all normal app windows, including full-screen apps, on whichever Space you're on |
| Font | System font, 16 pt in the compact bar (setting: system / monospaced, size) |
| Placeholder | "Jot something down…" |
| Chrome | No title bar, no traffic lights. Draggable by background |
| Animation | 80 ms fade-in/out; none if Reduce Motion is on |

### Footer

- **Destination pill** (left): colored dot + destination name. Click or `⌘1…⌘9` switches destination for *this note only*. The default comes back on the next open.
- **Hint** (right): `⌘↩ Save`. Turns into an inline warning when relevant, e.g. "Apple Notes can't take images yet — they'll be dropped."
- **Pending badge**: if the outbox has failed deliveries, a small amber dot with count appears next to the pill. Click → menu with Retry / Show details.

### States

| State | What the user sees |
|---|---|
| Empty | Placeholder, footer with default destination |
| Draft restored | Previous draft text, cursor at end, text **not** selected (so typing appends) |
| Typing | Panel grows with content |
| Saving | Nothing — the panel closes immediately on `⌘↩` (optimistic) |
| Delivery failed | Menu bar icon gets an amber badge; macOS notification once per failure burst; badge in panel footer next open |

## 2. Keyboard map

| Shortcut | Scope | Action |
|---|---|---|
| `⌥Space` *(default; `⌘Space` optional, set up in onboarding — see ADR-010, ADR-011)* | Global | Toggle panel (show → focus → hide) |
| *unset (suggest `⌥⇧Space`)* | Global | Save clipboard as a note instantly, show HUD |
| `⌘↩` | Panel | Save and close |
| `⇧⌘↩` | Panel | Save and keep open (cleared, ready for the next note) |
| `Esc` | Panel | Close. Draft is kept and restored next time |
| `⇧⌘⌫` | Panel | Discard draft (and attachments) |
| `⌘1` … `⌘9` | Panel | Choose destination for this note |
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

Clicking a recent item opens it where it lives: reveal in Finder (Folder), `obsidian://open` (Obsidian), or activates Notes (Apple Notes).

## 5. Settings (one window, three tabs)

**General**
- Open-panel hotkey · Save-clipboard hotkey
- Launch at login
- Close panel when clicking elsewhere
- Font: System / Monospaced, size
- Smart quotes and dashes (off by default — notes often contain code)

**Destinations**
- List of destinations with drag-to-reorder (order = `⌘1…⌘9`), star = default
- Add: Obsidian vault (detected vaults listed) · Apple Notes · Folder
- Per-destination options (mode, target file/folder, template, frontmatter) and a **Test** button that writes a test note and reports success/failure

**Advanced**
- Outbox: pending count, last error, Retry now, Reveal outbox folder
- Remember recent captures (on/off) · Clear recents
- Reveal logs · Reset all settings

## 6. First run

Shown once, in the Settings window, three steps:

1. **Your hotkey.** Recommended: `⌥Space`, already active. "Use ⌘Space instead" starts the Spotlight handoff: if Spotlight still owns `⌘Space`, the step explains this in one sentence and shows an **Open Keyboard Shortcuts** button (System Settings › Keyboard › Keyboard Shortcuts › Spotlight) with "Uncheck *Show Spotlight search*, or change it to ⌥Space." The step re-checks when Otter regains focus and turns green once `⌘Space` is free; then it asks the user to press `⌘Space` once to confirm. "Use a different shortcut" opens the recorder; "Skip for now" keeps `⌥Space`. Either way, the step asks the user to press the shortcut once to confirm it reaches Otter (`⌥Space` may be taken by another app).
2. **Where should notes go?** Detected Obsidian vaults listed first, then Apple Notes, then "A folder…". One choice; sensible defaults for the rest (Obsidian → daily note append; Notes → "Otter" folder in the default account; Folder → new file per note). Picking Apple Notes immediately runs a test so the Automation prompt appears now, not mid-capture.
3. **Try it.** "Press ⌥Space, type anything, hit ⌘↩." (shows whichever hotkey step 1 ended on) The step completes itself when the first capture is delivered and shows where it went, with an "Open" button.

Launch at login is offered on the last step (default on).

## 7. Accessibility

- Text view and controls have VoiceOver labels; panel announces "Otter, note editor" on open.
- Respects Reduce Motion, Reduce Transparency (solid background), Increase Contrast.
- Every action is reachable by keyboard.
