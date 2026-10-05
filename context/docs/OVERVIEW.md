# Otter — Project Overview

> Named Otter: it floats on top of everything and holds onto things for you.

## 1. Problem

Jotting down a thought or saving something you just copied should cost about two seconds on a Mac. Today it costs a context switch: find the notes app, wait for it, pick a folder, make a new note, paste, then find your way back to what you were doing. That friction is enough that most quick thoughts never get written down, or get dumped in a random text editor tab and lost.

The ChatGPT desktop overlay (hotkey → floating bar → type) accidentally proved the pattern: people used it as a scratchpad because it was the fastest text box on the machine. Raycast Notes does something similar, but notes live inside Raycast and it requires adopting Raycast. Apple's Quick Note only goes to Apple Notes and opens a full Notes window.

## 2. The product in one sentence

**A hotkey-summoned floating text box that files whatever you type or paste into the notes system you already use, then gets out of the way.**

## 3. Principles

These are the tie-breakers for every decision.

1. **Capture, not organize.** Otter has one job: get text out of your head and into your notes system. Browsing, searching, editing, tagging and linking are your notes app's job.
2. **It must feel instant.** Hotkey to typing in under 100 ms, every time. Saving never makes you wait — the panel closes the moment you hit `⌘↩`; delivery happens in the background.
3. **Never lose a note.** Every keystroke is drafted to disk; every submitted note is journaled before the panel closes; failed deliveries retry until they succeed.
4. **Your notes, your system.** Otter writes plain Markdown files (and, after v1, real Apple Notes). Uninstalling Otter leaves nothing stranded.
5. **Free, local, private.** No account, no telemetry, no network calls. Ever, in v1.
6. **Return focus.** Closing the panel must leave you exactly where you were, with the previous app still focused and typeable.

## 4. Who it's for

- Primary: someone who lives in Obsidian and wants a frictionless inbox. Apple Notes users follow after v1 (ADR-015).
- Secondary: someone with no notes system who just wants "a folder of quick notes" they can grep later.
- Not for: people who want a full notes app, sync service, or AI assistant.

## 5. Scope

### In (v1)

- Menu-bar agent app (no Dock icon), launches at login.
- Global hotkey **`⌥Space`** (fully configurable; onboarding offers `⌘Space` and walks you through moving Spotlight off it) toggles a small floating sticky-note panel above any app, Space or full-screen window. It can be dragged anywhere and reopens where you left it.
- Plain-text editor with draft autosave; `⌘↩` to save and close; `⌘S` to save under a name (defaults to the date and time) and start a new note; `Esc` to close and keep the draft.
- Destinations:
  - **Folder** — new file per note, or append to a single inbox file.
  - **Obsidian** — vault auto-discovery; append to today's daily note (default), append to an inbox note, or new note in a folder. Respects the vault's daily-note and attachment settings.
- Multiple destinations configured, one default, switch per note with `⌘1…⌘9`.
- Paste images/files as attachments.
- Optional second hotkey: save clipboard instantly without opening the panel.
- Outbox with background delivery, retry, and a visible failure state.
- Recent captures list in the menu bar (click to open the note).

### Out (non-goals, deliberately)

- Viewing, searching or editing existing notes (beyond the current draft).
- Its own storage format, database, or sync.
- Rich text editing or live Markdown rendering.
- iOS / iPadOS / Windows.
- AI features, tagging suggestions, link previews that fetch from the network.
- Capturing the current selection from other apps (needs Accessibility permission; revisit post-v1).
- Mac App Store distribution in v1 (see ADR-004).
- Apple Notes in v1. It's planned for after the first release (T08, ADR-015).

## 6. Destinations at a glance

The key insight: **an Obsidian vault is just a folder of Markdown files.** Obsidian watches the vault and picks up new or changed files immediately. So "Folder" and "Obsidian" share one writer; Obsidian adds vault-awareness on top (daily-note path, attachment folder, link style). Apple Notes is the only true app integration, and the most fragile one, so it comes after v1 (ADR-015).

| | Folder | Obsidian | Apple Notes (after v1) |
|---|---|---|---|
| Mechanism | Write `.md` files | Write `.md` files into the vault | Apple Events (AppleScript via `osascript`) |
| Needs Obsidian/Notes running | — | No | Launched automatically in the background |
| Permission prompt | Only for protected folders (Documents, iCloud Drive) | Same as Folder | Automation: "Otter wants to control Notes" |
| Typical latency | < 10 ms | < 10 ms | 0.2–3 s (hidden by the outbox) |
| Attachments | Yes | Yes, in the vault's attachment folder | No (v1) |
| Modes | New file · Append to file | Daily note · Inbox note · New note | New note (append is a stretch goal) |
| Fragility | Low | Low–medium (config formats can change) | Medium–high (scripting dictionary, TCC) |

## 7. Success criteria

| Metric | Target |
|---|---|
| Hotkey → panel visible and accepting keystrokes | p95 < 100 ms (target 50 ms) |
| `⌘↩` → panel gone and previous app focused | < 50 ms |
| Folder/Obsidian delivery after `⌘↩` | p95 < 50 ms |
| Idle memory | < 40 MB |
| Idle CPU | 0% (no polling timers while idle) |
| App size | < 15 MB |
| Notes lost in a 1,000-capture soak test with random kills | 0 |
| Dogfooding | You reach for it daily for two straight weeks without opening a notes app to capture |

## 8. Milestones

| Milestone | Outcome | Tasks | Rough effort (solo + coding agent) |
|---|---|---|---|
| **M0 — Walking skeleton** | Usable daily: hotkey → panel → saves to a folder you pick | T01–T06 | 4–6 days |
| **M1 — Integrations** | Obsidian vault awareness, paste images, clipboard hotkey, save-as, change folder from the panel | T07, T09, T11, T16, T17 | 4–6 days |
| **M2 — Ship it** | Onboarding, settings, menu bar polish, notarized DMG with auto-update | T10, T12, T13, T14 | 4–6 days |
| **M3 — After v1** | Apple Notes destination | T08 | 2–4 days |

Point a folder destination at your Obsidian vault after M0 and you're already dogfooding the core loop.

## 9. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Apple Notes scripting is slow or breaks in a macOS update | Medium | Deferred to M3 (ADR-015), so it can't hold up v1. Then: async outbox hides latency; clear error + "Test connection"; Folder fallback always available |
| `⌘Space` (opt-in) is owned by Spotlight until the user moves it | Certain | `⌥Space` default (ADR-011); guided handoff in onboarding (ADR-010), `⌥Space` fallback, persistent "finish setup" reminder |
| Default `⌥Space` already taken by ChatGPT/Raycast | Medium | Configurable; press-to-confirm check in onboarding |
| Obsidian config formats change (daily notes, Periodic Notes plugin) | Medium | Parse defensively; fall back to defaults; let the user override folder/format manually |
| Non-activating panel focus edge cases (full-screen, Stage Manager, IME) | Medium | Dedicated test matrix in T14 |
| iCloud Drive vault not downloaded / offline | Low | Coordinated writes; outbox retries; surface the error |
| Notarization requires a paid Apple Developer account ($99/yr) | Certain | Decide before T13 (see open questions) |

## 10. Open questions

1. ~~Name~~ **Decided: Otter.** Note: Otter.ai is an established note-taking/transcription product. Before T13, check the Mac App Store, GitHub and USPTO for conflicts, and consider a distinguishing full name for the listing and bundle ID (e.g. "Otter Quick Notes") if needed.
2. **Apple Developer Program.** Needed for a Gatekeeper-friendly free download. Pay the $99/yr, or ship unsigned with "right-click → Open" instructions?
3. **Open source?** Recommended (MIT) — builds trust for an app that writes into people's vaults, and invites destination contributions.
4. **Default destination when nothing is configured.** Proposal: `~/Documents/Otter Inbox/` folder, so the app works the second it's installed.
5. **Append format.** Timestamp heading (`## 22:07`) vs bullet (`- 22:07 text`) for daily-note appends. Proposal: bullet for single-line notes, heading block for multi-line, configurable template.
