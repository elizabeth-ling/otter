# otter

[![Download Otter for macOS](https://img.shields.io/github/v/release/elizabeth-ling/otter?label=Download%20.dmg&logo=apple&style=for-the-badge&color=black)](https://github.com/elizabeth-ling/otter/releases/latest)

otter is a free, open-source macOS menu-bar utility for capturing notes. what quick notes should've been. press a hotkey from anywhere, a small floating panel appears, type, hit `⌘↩`, and the note is filed into the notes system of your choice.

saves to plain folders and Obsidian vaults, as Markdown files.

No account. No backend. Your data stays on your Mac by default.

![otter display](images/example.png)
![otter display on top of full screen app](images/overlay-ex.png)

## install

Needs macOS 14 Sonoma or later.

- **Download:** get `Otter-<version>.dmg` from the [latest release](https://github.com/elizabeth-ling/otter/releases/latest), open it, drag Otter to Applications, and open it from there. Otter is signed and notarized by Apple, so it opens without a Gatekeeper warning.
- **Homebrew:** `brew install --cask elizabeth-ling/tap/otter`

The first time it opens, Otter walks you through picking a shortcut and where your notes go. By default they land in `~/Documents/Otter Inbox/`, one file per note.

Otter updates itself. Once a day it checks for a new version and, when there is one, shows "Update Available…" in its menu bar menu. You can also pick "Check for Updates…" yourself.

## using otter

Press `⌥Space` from any app to open the panel, and again to hide it. You can change the shortcut, or use `⌘Space` instead of Spotlight, in Settings.

| Shortcut | What it does |
|---|---|
| `⌘↩` | Save and close |
| `⇧⌘↩` | Save and keep the panel open for the next note |
| `⌘S` | Save as a named note, in a folder you pick |
| `Esc` | Close. Your draft is kept for next time |
| `⇧⌘⌫` | Discard the draft |
| `⌘1` … `⌘9` | Pick where this note goes |
| `⇧⌘O` | Change the save folder |
| `⌘B` `⌘I` `⇧⌘X` `⌘E` | Bold, italic, strikethrough, inline code |
| `⌘K` | Link |
| `⌘L` | Checkbox, or check it off |
| `⇧⌘8` | Bulleted list |
| `⌘,` | Settings |

Notes are Markdown. Paste an image or a file and it's saved alongside the note as an attachment.

There's also an optional shortcut (set it in Settings) that saves whatever is on your clipboard as a note without opening the panel. Your recent notes are in the menu bar menu.

## permissions

- **No Accessibility permission.** The global shortcuts don't need it.
- **Files & Folders.** macOS asks the first time Otter saves to a protected location such as Documents, Desktop or iCloud Drive, which is where the Otter Inbox and most Obsidian vaults live. Otter writes only to the folders you choose. It also reads Obsidian's list of vaults and each vault's `.obsidian/app.json`, so notes and attachments follow the vault's settings. It never changes them.
- **Notifications.** macOS asks the first time a note can't be delivered, so Otter can tell you. If you say no, the menu bar icon still shows an amber dot.

## privacy

- No account, no telemetry, no analytics, no crash reporting.
- **The update check is Otter's only network access.** Once a day it fetches `appcast.xml` from this repo's GitHub releases. The request carries Otter's version number and nothing about you or your notes. Turn it off in Settings › Advanced › "Automatically check for updates" and Otter makes no network requests at all.
- Your notes go only to the folders you pick. Until a note is delivered, it waits in `~/Library/Application Support/Otter/`. Logs never contain note text.

## contributing

Design docs, the build plan and release instructions are in [DEVELOPMENT.md](DEVELOPMENT.md). Changes in each version are in the [CHANGELOG](CHANGELOG.md).

## license

[MIT](LICENSE)
