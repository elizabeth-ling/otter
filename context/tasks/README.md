# Build Plan

Each task is sized to be one focused PR (roughly half a day to a day and a half). Each file is self-contained enough to hand to a coding agent or pick up cold: goal, required reading, scope, implementation notes, acceptance criteria, and what's explicitly out of scope.

## Milestones

| Milestone | Done when | Tasks |
|---|---|---|
| **M0 — Walking skeleton** | You can press the hotkey (`⌥Space` by default, or `⌘Space` once Spotlight is moved off it) anywhere, type, hit `⌘↩`, and the note lands in a folder you chose. Point it at your Obsidian vault and start dogfooding. | T01 → T02 → T03 → T15 → T04 → T05 → T06 |
| **M1 — Integrations** | Obsidian vault awareness, pasted images, save-clipboard hotkey, `⌘S` save-as, change the save folder from the panel header | T07, T09, T11, T16, T17 |
| **M2 — Ship it** | A stranger can download a notarized DMG, onboard in under a minute, and auto-update | T10, T12, T13, T14 |
| **M3 — After v1** | Captures can go to Apple Notes, including onboarding, settings and the Recent menu (ADR-015) | T08 |

## Dependency graph

```mermaid
flowchart LR
  T01[T01 Scaffold] --> T02[T02 Hotkey]
  T01 --> T05[T05 Pipeline + outbox]
  T02 --> T03[T03 Panel]
  T03 --> T15[T15 Sticky-note panel]
  T15 --> T04[T04 Editor + drafts]
  T05 --> T06[T06 Folder]
  T04 --> T06
  T06 --> T07[T07 Obsidian]
  T05 -.-> T08[T08 Apple Notes · after v1]
  T10 -.-> T08
  T14 -.-> T08
  T04 --> T09[T09 Paste + attachments]
  T06 --> T09
  T04 --> T16[T16 Save as ⌘S]
  T06 --> T16
  T05 --> T11[T11 Clipboard hotkey + HUD]
  T02 --> T11
  T07 --> T10[T10 Settings + onboarding]
  T16 --> T10
  T06 --> T17[T17 Change folder from panel]
  T15 --> T17
  T17 --> T10
  T05 --> T12[T12 Menu bar + lifecycle]
  T10 --> T13[T13 Packaging]
  T12 --> T13
  T13 --> T14[T14 Perf + reliability]
```

Parallelizable: **T11** can start as soon as T02 + T05 are in.

T08 (Apple Notes) is deferred to after v1 (ADR-015), and no M0–M2 task depends on it. Dotted edges show what it builds on once picked up: T05's pipeline, and T10/T14, whose Apple Notes parts it adds (see T08's "Picking this back up").

## Task file format

```
# Txx — Title
Milestone · Depends on · Estimate
## Goal                 — one paragraph, the outcome
## Read first           — which docs/sections matter
## Scope                — what to build
## Implementation notes — the non-obvious parts, decisions already made
## Acceptance criteria  — checkboxes; the PR is done when all are ticked
## Out of scope         — so the task doesn't sprawl
```

## Definition of done (every task)

- [ ] Acceptance criteria all met and demonstrated (short screen recording for UI tasks).
- [ ] OtterCore logic has unit tests; `xcodebuild test` is green in CI.
- [ ] No note contents in logs.
- [ ] No new third-party dependency without a new ADR.
- [ ] If the implementation contradicts a doc, the doc is updated in the same PR.

## Handing a task to a coding agent

Something like:

> Read `context/docs/OVERVIEW.md`, `context/docs/ARCHITECTURE.md` and `context/docs/DECISIONS.md`, then implement `context/tasks/T06-folder-destination.md`. Follow the task's implementation notes and stay within its scope. Before finishing, check every acceptance criterion and list how each was verified.
