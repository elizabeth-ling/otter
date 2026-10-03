# otter

 otter is a FOS macOS menu-bar utility for capturing notes. what quick notes should've been. press a hotkey from anywhere, a small floating panel appears, type, hit `⌘↩`, and the note is filed into the notes system of your choice

 currently, there is support for Obsidian and Apple Notes

Otter is NOT a notes app.
No account. No backend. Your data stays on your Mac by default.

## docs

| Doc | What's in it |
|---|---|
| [docs/OVERVIEW.md](docs/OVERVIEW.md) | Problem, principles, scope, non-goals, success criteria, milestones, open questions |
| [docs/UX_SPEC.md](docs/UX_SPEC.md) | Panel anatomy, states, keyboard map, menu bar, settings, first run |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, data flow, capture pipeline, destinations, permissions, storage, performance budget |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Architecture decision records (why Swift, why files, why not the App Store, etc.) |
| [tasks/README.md](tasks/README.md) | Build plan: milestones, dependency graph, task conventions |

## build tasks

| # | Task | Milestone |
|---|---|---|
| T01 | [Project scaffold](tasks/T01-project-scaffold.md) | M0 |
| T02 | [Global hotkey](tasks/T02-global-hotkey.md) | M0 |
| T03 | [Floating capture panel](tasks/T03-floating-panel.md) | M0 |
| T04 | [Editor, keyboard map, draft autosave](tasks/T04-editor-and-drafts.md) | M0 |
| T05 | [Capture pipeline and outbox](tasks/T05-capture-pipeline-outbox.md) | M0 |
| T06 | [Folder destination](tasks/T06-folder-destination.md) | M0 |
| T07 | [Obsidian destination](tasks/T07-obsidian-destination.md) | M1 |
| T08 | [Apple Notes destination](tasks/T08-apple-notes-destination.md) | M1 |
| T09 | [Paste handling and attachments](tasks/T09-paste-and-attachments.md) | M1 |
| T10 | [Settings and first-run onboarding](tasks/T10-settings-and-onboarding.md) | M2 |
| T11 | [Save-clipboard hotkey and HUD](tasks/T11-clipboard-capture-hud.md) | M1 |
| T12 | [Menu bar item, recents, launch at login](tasks/T12-menubar-and-lifecycle.md) | M2 |
| T13 | [Packaging, notarization, updates](tasks/T13-packaging-and-distribution.md) | M2 |
| T14 | [Performance and reliability hardening](tasks/T14-performance-and-reliability.md) | M2 |
