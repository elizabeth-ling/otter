# Otter — Architecture Decision Records

Short ADRs. Status is **Accepted** unless noted. To change one, add a new ADR that supersedes it rather than editing history.

---

## ADR-001 · Native Swift (AppKit panel + SwiftUI settings)

**Context.** The whole product is "feels instant, weighs nothing." The critical piece is a Spotlight-style non-activating floating panel that returns focus to the previous app.

**Options.** Electron (150 MB+, 100 MB+ RAM idle, poor non-activating panel support) · Tauri (light, but the panel/focus behavior still needs native code and two languages) · **Swift/AppKit**.

**Decision.** Swift. AppKit for the panel, editor (`NSTextView`) and status item, where precise control matters. SwiftUI for Settings and Onboarding, where it's faster to build.

**Consequences.** macOS-only forever (fine — it's a non-goal to be cross-platform). Small binary, tiny memory, first-class focus handling.

---

## ADR-002 · Files are the integration layer; Obsidian = folder + vault awareness

**Context.** The brief: don't build another notes app; plug into Obsidian or Apple Notes, fall back to a folder.

**Options for Obsidian.**
1. Write Markdown files directly into the vault.
2. `obsidian://new` URI — brings Obsidian to the front (steals focus), requires Obsidian installed and the vault registered.
3. A companion Obsidian plugin or the community Local REST API plugin — requires Obsidian running and an extra install.

**Decision.** Option 1. Obsidian watches the vault and picks up file changes immediately, works whether Obsidian is open or not, and syncs through whatever the user already uses (Obsidian Sync, iCloud, git). Otter reads the vault's own config to place daily notes and attachments where Obsidian would.

**Consequences.** Folder and Obsidian share one writer and one test suite. Otter depends on Obsidian's config file formats (`daily-notes.json`, `app.json`), so parsing must be defensive with user overrides. The URI scheme is still used, but only for "Open in Obsidian."

---

## ADR-003 · Apple Notes via AppleScript run with `osascript`, treated as best-effort

**Context.** Apple Notes has no public API for third-party writes on macOS. The options are Apple Events (AppleScript/JXA) or Shortcuts.

**Decision.** Apple Events, executed out-of-process with `/usr/bin/osascript`, constant script on stdin, user content passed only as `argv`. Text-only in v1.

**Why not `NSAppleScript`?** Not safe off the main thread, and Notes calls can block for seconds.
**Why not Shortcuts (`shortcuts run`)?** Requires the user to build a Shortcut first — too much setup for the default path. Worth adding later as a generic **"Run a Shortcut"** destination, which would also cover Things, Drafts, Bear, Reminders, etc. for free.

**Consequences.** One-time Automation permission prompt. Latency of 0.2–3 s, hidden by the outbox. Scripting behavior can change across macOS releases, so this destination gets a visible health check and a Test button.

---

## ADR-004 · Distribute outside the Mac App Store, not sandboxed (v1)

**Context.** The App Store requires the App Sandbox. Sending Apple Events to Notes from a sandboxed app needs a temporary-exception entitlement that App Review may reject, and the sandbox complicates reading Obsidian's config in `~/Library/Application Support/obsidian/`.

**Decision.** Developer ID–signed, hardened runtime, notarized, **not sandboxed**. Distributed as a DMG via GitHub Releases + a Homebrew cask, updated with Sparkle. Folder locations are still stored as security-scoped bookmarks so a later move to the sandbox is cheap.

**Consequences.** Needs an Apple Developer Program membership ($99/yr) for a Gatekeeper-friendly experience. Not discoverable in the App Store. Revisit if there's demand (it would likely mean shipping a reduced App Store build without Apple Notes or with the Shortcuts route instead).

---

## ADR-005 · Outbox journal with at-least-once delivery; close the panel optimistically

**Context.** "Instant" and "never lose a note" pull against each other when a destination is slow (Notes) or unavailable (iCloud vault offline, external drive unplugged).

**Decision.** On submit, the capture is written to a local outbox (atomic + fsync, ~ms), the panel closes immediately, and a background actor delivers it with retries. Delivery is at-least-once.

**Alternatives rejected.** Synchronous delivery (Notes would freeze the panel for seconds). Exactly-once with dedupe markers embedded in notes (pollutes the user's notes for a crash window measured in microseconds).

**Consequences.** Rare duplicate after a crash mid-delivery is possible and accepted. Failures must be visible (badge + notification), since the user has already moved on.

---

## ADR-006 · Default hotkey `⌥Space`, never `⌘Space` — **Superseded by ADR-010**

**Context.** The ChatGPT-style overlay was the inspiration. `⌘Space` belongs to Spotlight; hijacking it is hostile and breaks muscle memory.

**Decision.** Default `⌥Space`, fully configurable, chosen in onboarding. The save-clipboard hotkey ships unset (suggest `⌥⇧Space`).

**Consequences.** `⌥Space` may already be taken by ChatGPT or Raycast; onboarding must make changing it obvious and warn when registration fails.

---

## ADR-007 · Plain-text editor, no Markdown rendering in v1

**Context.** Capture is about speed. Live Markdown rendering adds complexity, keystroke latency risk and edge cases (IME, undo).

**Decision.** Plain `NSTextView`, plain-text paste by default. The user's notes app does the rendering. Light syntax tinting (headings, `- [ ]`) can be added later if wanted.

---

## ADR-008 · Minimum macOS 14 (Sonoma)

**Context.** Want `@Observable`, modern `SMAppService` for login items, and the current SwiftUI `Settings` APIs, without availability checks everywhere.

**Decision.** `MACOSX_DEPLOYMENT_TARGET = 14.0`. Test on the current macOS release and one prior.

---

## ADR-009 · No network access in v1

**Decision.** Otter makes no network requests other than Sparkle's update check (which the user can disable). No analytics, no crash reporting service, no link-title fetching. Stated plainly in the README. Any future network feature must be opt-in.

---

## ADR-010 · `⌘Space` is the primary hotkey, with a guided Spotlight handoff (supersedes ADR-006)

**Context.** The product owner wants `⌘Space`, the most reachable chord on a Mac. macOS reserves it for Spotlight, and while Spotlight's shortcut is enabled the system intercepts the keypress before any app hotkey sees it. Apps such as Raycast and Alfred solve this by asking the user to turn off or move Spotlight's shortcut during setup.

**Decision.**
- Onboarding step 1 offers `⌘Space` as the recommended choice.
- Otter checks whether Spotlight's shortcut is enabled by reading `com.apple.symbolichotkeys` → `AppleSymbolicHotKeys` → key `64` (`enabled`). If it is, onboarding explains the conflict and opens System Settings › Keyboard › Keyboard Shortcuts › Spotlight so the user can uncheck "Show Spotlight search" or move it (e.g. to `⌥Space`).
- Otter registers `⌘Space` only once Spotlight's binding is off. Until then it falls back to `⌥Space` and shows a "Finish setting up ⌘Space" row in Settings and the menu bar menu.
- Otter **never** edits `com.apple.symbolichotkeys` itself. Writing another system preference domain is fragile, only takes effect after logout, and is the kind of thing users rightly distrust.

**Consequences.** One extra step in onboarding for users who pick `⌘Space`. Users who rely on Spotlight keep it on another shortcut. The symbolic-hotkey key number and plist shape are undocumented, so the check is best-effort: if it can't be read, Otter attempts registration and asks the user to press the shortcut once to confirm it works.
