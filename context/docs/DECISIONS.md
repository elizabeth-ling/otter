# Otter — Architecture Decision Records

Short ADRs. Status is **Accepted** unless noted. To change one, add a new ADR that supersedes it rather than editing history.

---

## ADR-001 · Native Swift (AppKit panel + SwiftUI settings)

**Context.** The whole product is "feels instant, weighs nothing." The critical piece is a Spotlight-style non-activating floating panel that returns focus to the previous app.

**Options.** Electron (150 MB+, 100 MB+ RAM idle, poor non-activating panel support) · Tauri (light, but the panel/focus behavior still needs native code and two languages) · **Swift/AppKit**.

**Decision.** Swift. AppKit for the panel, editor (`NSTextView`) and status item, where precise control matters. SwiftUI for Settings and Onboarding, where it's faster to build.

**Consequences.** macOS-only forever (fine — it's a non-goal to be cross-platform). Small binary, tiny memory, first-class focus handling.

---

## ADR-002 · Files are the integration layer; Obsidian = folder + vault awareness — **Daily notes dropped by ADR-013**

**Context.** The brief: don't build another notes app; plug into Obsidian or Apple Notes, fall back to a folder.

**Options for Obsidian.**
1. Write Markdown files directly into the vault.
2. `obsidian://new` URI — brings Obsidian to the front (steals focus), requires Obsidian installed and the vault registered.
3. A companion Obsidian plugin or the community Local REST API plugin — requires Obsidian running and an extra install.

**Decision.** Option 1. Obsidian watches the vault and picks up file changes immediately, works whether Obsidian is open or not, and syncs through whatever the user already uses (Obsidian Sync, iCloud, git). Otter reads the vault's own config to place daily notes and attachments where Obsidian would.

**Consequences.** Folder and Obsidian share one writer and one test suite. Otter depends on Obsidian's config file formats (`daily-notes.json`, `app.json`), so parsing must be defensive with user overrides. The URI scheme is still used, but only for "Open in Obsidian."

---

## ADR-003 · Apple Notes via AppleScript run with `osascript`, treated as best-effort — **Deferred to after v1 by ADR-015**

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

## ADR-010 · `⌘Space` is the primary hotkey, with a guided Spotlight handoff (supersedes ADR-006) — **Default changed by ADR-011**

**Context.** The product owner wants `⌘Space`, the most reachable chord on a Mac. macOS reserves it for Spotlight, and while Spotlight's shortcut is enabled the system intercepts the keypress before any app hotkey sees it. Apps such as Raycast and Alfred solve this by asking the user to turn off or move Spotlight's shortcut during setup.

**Decision.**
- Onboarding step 1 offers `⌘Space` as the recommended choice.
- Otter checks whether Spotlight's shortcut is enabled by reading `com.apple.symbolichotkeys` → `AppleSymbolicHotKeys` → key `64` (`enabled`). If it is, onboarding explains the conflict and opens System Settings › Keyboard › Keyboard Shortcuts › Spotlight so the user can uncheck "Show Spotlight search" or move it (e.g. to `⌥Space`).
- Otter registers `⌘Space` only once Spotlight's binding is off. Until then it falls back to `⌥Space` and shows a "Finish setting up ⌘Space" row in Settings and the menu bar menu.
- Otter **never** edits `com.apple.symbolichotkeys` itself. Writing another system preference domain is fragile, only takes effect after logout, and is the kind of thing users rightly distrust.

**Consequences.** One extra step in onboarding for users who pick `⌘Space`. Users who rely on Spotlight keep it on another shortcut. The symbolic-hotkey key number and plist shape are undocumented, so the check is best-effort: if it can't be read, Otter attempts registration and asks the user to press the shortcut once to confirm it works.

---

## ADR-011 · `⌥Space` is the default hotkey; `⌘Space` is opt-in (amends ADR-010)

**Context.** ADR-010 made `⌘Space` the first choice. Because Spotlight owns `⌘Space` on a fresh Mac, that meant every new user started on a fallback, with a "finish setup" reminder and a System Settings detour before the recommended shortcut worked.

**Decision.**
- The toggle-panel shortcut defaults to `⌥Space`, and onboarding step 1 recommends it. It works on first launch with no handoff.
- `⌘Space` stays one click away ("Use ⌘Space"). Picking it keeps ADR-010's handoff unchanged: probe Spotlight, fall back to `⌥Space` while Spotlight holds `⌘Space`, show the "Finish setting up ⌘Space" row, and never write `com.apple.symbolichotkeys`.
- The save-clipboard shortcut still ships unset (suggest `⌥⇧Space`).

**Consequences.** Most users never see the Spotlight step. `⌥Space` may already be taken by ChatGPT or Raycast, so onboarding's press-to-confirm check and recorder matter more (ADR-006's concern). macOS 15.0–15.1 reject hotkeys whose only modifier is `⌥`, and KeyboardShortcuts swallows that error, so the default may silently fail there; T14 should check it.

---

## ADR-012 · The panel is a movable sticky note, not a Spotlight-style bar

**Context.** T03 built a 640 pt wide, one-line bar that grows downward as you type, modelled on the ChatGPT/Spotlight overlay. In use it reads as a search box, not a place to write, and it always opens in the same spot whatever the user prefers. The product owner wants it closer to a sticky note (reference: `context/ui/box-ui.png`).

**Decision.**
- The panel opens as a multi-line text box at 380 × 300 pt, resizable in both directions, with a header strip (drag handle and destination) and an always-visible footer. It doesn't auto-grow; text scrolls.
- The user can drag it, and it reopens where it was left: one remembered position per display, stored as an offset from that display's visible frame and keyed by display UUID. It still opens on the display with the pointer, and is always clamped fully on-screen.
- The non-activating focus behavior from ADR-001 is unchanged.

**Consequences.** T04 loses its auto-height work; T15 replaces T03's layout and placement. A remembered position can be far from the pointer on a large display, which is the trade-off the user asked for; "Reset Panel Position" undoes it.

---

## ADR-013 · No daily notes; an Obsidian vault is a folder destination (amends ADR-002)

**Context.** The original plan had a separate Obsidian destination that appended each capture to the vault's daily note, located through `.obsidian/daily-notes.json` with its Moment.js filename format. But tasks often span several days, so filing captures by date isn't useful.

**Decision.**
- Drop daily notes. No Periodic Notes or note templates either.
- No Obsidian destination kind. A vault is a folder: any folder destination inside a vault (found by walking up to a `.obsidian/` directory) follows the vault's attachment folder and link style from `app.json`, and its notes open in Obsidian.
- Receipts stay `.file(URL)`. Whether a note is in a vault is decided when it's opened, not stored.
- Anyone who wants one running file uses T06's append mode.

**Consequences.** ADR-002's consequences no longer include `daily-notes.json`: the only Obsidian files Otter reads are `app.json` and `obsidian.json`, and it needs no `MomentFormat`. Picking a vault (T10's Add menu, onboarding) just sets a folder destination to the vault root, and the user can pick a subfolder from the panel header. Other specs that still mention daily notes (OVERVIEW, UX_SPEC, T09, T11, T12, T16, the tasks README) are updated separately.

---

## ADR-014 · `⌘S` uses the native Save panel

**Context.** T16 specified an inline "Save as" row inside the panel, so naming a note never activated Otter. In use the product owner wants the real macOS Save As: a separate window in the middle of the screen, with its folder browser.

**Decision.**
- `⌘S` shows `NSSavePanel` as its own window, centred on the capture panel's screen and above it (the capture panel floats), not as a sheet. It offers `yyyy-MM-dd HHmm` as the name and starts in the default folder destination's folder; the file is Markdown (`.md`).
- The Save panel only picks the file. The note still goes through the outbox (ADR-005): the capture carries `fileURL` and its `title` (the file name), and the folder destination writes exactly that file, replacing one that's there since the Save panel asked first. The destination's mode, subfolder and filename template don't apply; its frontmatter setting does, plus a `title` field.
- Showing the Save panel activates Otter. The panel stays up while it's open, and the next hide hands activation back to the app the user came from, as for T17's folder picker.

**Consequences.** Notes can be saved anywhere, not only in the destination's folder. A name that's taken gets the Save panel's "Replace?" prompt rather than a ` 2` suffix. Otter is briefly the active app (it has no Dock icon, so it still doesn't show in `⌘⇥`). A future non-folder default destination (T08's Apple Notes) has to handle or refuse captures that carry a `fileURL`.

---

## ADR-015 · v1 ships without Apple Notes; T08 moves after the first release

**Context.** Folder and Obsidian share one writer: put a `.md` file on disk. Apple Notes is the only destination that drives another app (ADR-003). It brings an Automation (TCC) prompt and denial recovery into onboarding, `osascript` timeouts and stderr error codes, a possible Hardened Runtime entitlement, and a scripting dictionary that can change in any macOS release and can't be tested in CI. It also reaches into other tasks: T09's attachment warning, T10's pickers, Test button and onboarding step, and T16's named notes and `fileURL` captures. The developer dogfoods with Obsidian, so it would be built without daily use.

**Decision.**
- v1 (M0–M2) ships with Folder and Obsidian only. T08 moves to **M3 — After v1**, together with the Apple Notes parts of other tasks, which T08 now lists under "Picking this back up".
- Nothing in M1/M2 depends on T08. Those tasks don't build Apple Notes UI, scripts or permission flows.
- Keep the seams that cost nothing: `Destination.supportsAttachments`, `DestinationHealth.needsPermission`, `DeliveryReceipt.Location.appleNote`, the factory's per-kind builders and `NSAppleEventsUsageDescription`. ADR-003's approach stands for when T08 is built.

**Consequences.** The primary user (OVERVIEW §4) is someone who lives in Obsidian; Apple Notes users get the Folder destination until M3. Onboarding is simpler: step 2 picks a vault or a folder, with no permission prompt beyond Files & Folders. ADR-004's App Store concern about Apple Events no longer applies to v1, though the Obsidian-config reason for staying unsandboxed still does.
