# T14 — Performance and reliability hardening

**Milestone:** M2 · **Depends on:** T13 (can start informally after M1) · **Estimate:** 1–1.5 days

## Goal

Prove the two promises with numbers before release: **it feels instant** and **it never loses a note**.

## Read first

- OVERVIEW §7 (success criteria)
- ARCHITECTURE §9 (performance budget), §11 (testing strategy)

## Scope

### 1. Performance measurements

Add/verify `os_signpost` intervals and record results in `context/docs/PERF.md` (release build, Apple silicon, current macOS):

| Interval | Budget | Result |
|---|---|---|
| Cold launch → hotkey registered | < 300 ms | |
| Hotkey → panel key | p95 < 100 ms (target 50) | |
| `⌘↩` → panel hidden | < 50 ms | |
| Enqueue → delivered (Folder/Obsidian) | p95 < 50 ms | |
| Idle memory after 100 captures | < 40 MB | |
| Idle wakeups/s (Activity Monitor) | ~0 | |

Fix anything over budget (common culprits: SwiftUI body recomputation on show, synchronous disk reads, thumbnail retention, timers).

### 2. Reliability soak test

A debug-only test hook (`--otter-soak N`) that submits N synthetic captures (random sizes up to 100 KB, 10% with attachments) across all destinations while a script randomly `kill -9`s and relaunches the app. Afterward, a verifier checks every capture ID appears in a destination at least once.

- [ ] 1,000 captures, ≥20 random kills → **0 lost**, duplicates counted and reported (expected ≈0).

### 3. Manual test matrix

| Area | Cases |
|---|---|
| Spaces & windows | Multiple Spaces; full-screen app; Split View; Stage Manager on/off; Mission Control open |
| Displays | Two displays, pointer on each; display unplugged while panel open; different scale factors |
| Focus return | TextEdit, Safari address bar, Terminal, VS Code, Slack, a Java/Electron app — type immediately after `Esc` and after `⌘↩` |
| Input | Japanese/Chinese IME; emoji picker (`⌃⌘Space`); dictation; RTL text; 1 MB paste |
| Appearance | Light/Dark; Reduce Motion; Reduce Transparency; Increase Contrast; VoiceOver walkthrough |
| Destinations | Vault in iCloud Drive with "Optimize Mac Storage" (file evicted); vault on external drive unplugged; folder renamed/deleted; disk full |
| Time | Capture at 23:59, deliver after midnight; time zone change between capture and delivery; DST transition |
| Lifecycle | Sleep/wake with pending outbox; logout/login; Sparkle update with pending outbox and an open draft |
| Hotkeys | `⌘Space` with Spotlight enabled (falls back to `⌥Space`, reminder shown); Spotlight shortcut disabled while Otter is running (Otter picks up `⌘Space` without relaunch); Spotlight moved to `⌥Space` (no clash with fallback); `⌥Space` taken by another app; shortcut cleared; same key for both shortcuts (must be prevented) |

Record pass/fail per row in `context/docs/TEST_MATRIX.md`; file issues for failures.

### 4. Privacy audit

- [ ] Grep logs from a full session: no note contents.
- [ ] Little Snitch / `nettop`: no network traffic except Sparkle's appcast check.
- [ ] Outbox and recents are the only places note text is stored by Otter; both cleared after delivery / on "Clear recents".

## Acceptance criteria

- [ ] All budgets met or explicitly accepted with a note in `context/docs/PERF.md`.
- [ ] Soak test: 0 lost captures.
- [ ] Test matrix fully executed; no open P0/P1 issues.
- [ ] Privacy audit passes.
