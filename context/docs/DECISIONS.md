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

## ADR-007 · Plain-text editor, no Markdown rendering in v1 — **Inline styling added by ADR-016; lists and tasks by ADR-017**

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

---

## ADR-016 · The editor styles inline Markdown and hides its markers; notes stay plain Markdown (amends ADR-007) — **Lists and tasks added by ADR-017**

**Context.** The formatting shortcuts (`⌘B`, `⌘I`, `⇧⌘X`, `⌘E`, `⌘K`) put Markdown markers in a plain-text editor, so bolding a word shows `**word**` and nothing looks bold. The product owner wants bold to look bold, struck text struck through, and so on, with the markers out of sight. ADR-007 ruled out live rendering for latency, IME and undo reasons.

**Options.** Markers always visible but dimmed (simplest; what's on screen is what's saved) · hidden except near the caret, like Obsidian's live preview (relayout on every caret move) · **always hidden**.

**Decision.**
- The panel editor styles inline Markdown: bold, italic, bold italic, strikethrough, inline code and `[text](url)` links, whether typed, pasted, restored or added by a shortcut. Headings, lists, quotes and other block syntax aren't styled.
- A complete span's markers are always hidden, a link's URL included. An unclosed span shows as typed. A link shows raw only while the selection is in its destination (`⌘K`).
- Styling and hiding are display-only. The `NSTextView` stays plain text (`isRichText = false`); styles and hiding are text-storage attributes set by a delegate from the spans a pure OtterCore parser (`MarkdownStyling`) returns. The string, the draft, the outbox and the delivered file never change.
- Editing treats hidden markers as part of their span, never as characters on their own: the caret skips them, typing at an edge takes the style on its left, `⌫`/`⌦` never delete a lone marker, a partly deleted span keeps its markers, and copy writes balanced Markdown (UX_SPEC §1). These rules are pure OtterCore functions with tests.
- Each edit parses the whole note and re-attributes only the lines whose styling changed. Nothing restyles during IME composition. Attribute changes aren't undo steps.
- VoiceOver reads the saved Markdown, markers included.

**Consequences.** The editor looks like a rich-text editor for inline styles, so it has to behave like one: `EditorTextView` overrides caret movement, selection, deletion, typing over a selection, line breaks and copy, which is the riskiest part of the feature. ADR-007's concerns are handled rather than avoided: latency by the small, line-local re-attribution (budget in ARCHITECTURE §9), IME by waiting for composition to commit, undo by never touching characters outside the user's edit. Editing a link's URL needs `⌘K`. Emphasis doesn't span a line break, unlike Obsidian.

---

## ADR-017 · `-` bullets and `- [ ]` tasks show as bullets and checkboxes (amends ADR-016) — **Caret-line reveal and look replaced by ADR-018**

**Context.** ADR-016 styles inline Markdown only, so list markers show as typed. The product owner wants `- ` lists and `- [ ]` checkboxes to look and behave like lists, as they do in Obsidian. ADR-007 left `- [ ]` tinting open as a later addition.

**Options.** Tint the markers only, which keeps every character on screen · **hide the marker and draw a bullet or checkbox in its place**, the way ADR-016 hides inline markers · real rich-text lists (breaks "notes stay plain Markdown").

**Decision.**
- Outside a fence, a line made of indentation, `- ` and optionally `[ ] ` / `[x] ` / `[X] ` is a list item. Its indentation is always hidden, and the item is indented by its nesting level, with wrapped lines hanging under its text. Checked items are dimmed and struck through. `*`, `+` and numbered lists stay as typed.
- **The caret line shows the raw marker, as in Obsidian.** On the line with the caret, or any line a selection touches, `- ` / `- [ ] ` shows as dimmed text, hanging in a gutter wide enough for `- [x] ` so the text never moves. Every other line hides the marker and draws `•` or a checkbox. This deliberately differs from ADR-016, where inline markers are always hidden. The product owner wants to see and edit the list syntax on the line being written, as in Obsidian. Two things make that cheap here, where ADR-016 rejected it for inline markers: a list marker sits at a fixed place at the start of a line, so the reveal re-attributes two lines when the caret changes line, not on every caret move; and the gutter keeps the reveal from re-wrapping anything. Inline markers stay always hidden.
- A click on a drawn checkbox ticks it. On the caret line the raw `[ ]` is plain text: a click places the caret there, and `⌘L` toggles it.
- Nesting follows Markdown: an item is one level deeper than the nearest item above it with less indentation, so lists indented with 2 spaces, 4 spaces or tabs all nest. `Tab` indents with a tab character, Obsidian's default.
- This is still display-only (ADR-016). The string, draft, outbox and file keep the exact Markdown. Ticking a box changes `[ ]` ↔ `[x]` in the text, as one undo step.
- Arriving on an item line from another line puts the caret after the marker, so typing goes into the item. Once the marker is revealed, it's ordinary text. `↩` continues the list, or ends it on an empty item. `⌫` at the start of the text removes the marker. `Tab` / `⇧Tab` nest and un-nest. `⌘L` toggles a task (Obsidian's default shortcut) and `⇧⌘8` toggles a bullet. These rules are pure OtterCore functions (`MarkdownLists`, `HiddenMarkerEditing`) with tests.

**Consequences.** `EditorTextView` takes on custom drawing and a mouse hit-test for checkboxes. Hidden leading tabs need care: a tab advances to the next tab stop whatever its font (T18 spikes a fix). A hidden prefix snaps forward on arrival while inline runs snap back, so `HiddenMarkerEditing` must keep them apart and know which lines are revealed. Other bullets, numbering and lists in quotes can follow the same pattern later.

## ADR-018 · Lists render on the caret line too; Obsidian's spacing, circles for tasks (amends ADR-017)

**Context.** ADR-017 showed the raw marker on the caret line and drew a bullet or box only once the caret left, with the text in a gutter wide enough for `- [x] `. In Obsidian itself, typing `- ` shows a bullet straight away, and the product owner wants that, plus circular checkboxes, bigger bullets and Obsidian's spacing (reference: `context/ui/obsidian-reference.png`).

**Decision.**
- Bullets and circles are drawn on every line, the caret line included. An item's marker shows raw (dimmed) only while the caret is in its prefix, before the start of its text, or a selection has a character of it (`MarkdownListItem.revealsMarker(for:)`). `←` from the start of an item's text steps into the marker, which reveals it. Arriving on an item still puts the caret at the start of its text, where nothing is revealed.
- Spacing and sizes in em of the editor font, measured from the reference: a level is 1.34 em; a bullet's text starts 1.34 em past its level, a task's 1.75 em; the bullet is a solid `tertiaryLabelColor` dot 0.28 em across on the x-height's middle; a task is a 0.94 em circle on the capitals' middle, a `tertiaryLabelColor` ring or filled with the accent colour and a white check. Both are centred 0.87 em past the level's start.
- A revealed `- ` hangs left of the text, which doesn't move; a revealed `- [ ] ` doesn't fit, so it starts at the level and pushes the first line's text right, as in Obsidian.
- A click on a circle toggles it on any line, since it's drawn on the caret line too.

**Consequences.** Revealing a task's marker can re-wrap its first line. The gutter is gone, so items sit as close to plain text as in Obsidian. ADR-017's other rules (keys, nesting, paste, undo, display-only) stand.

---

## ADR-019 · Releases come from a `v*` tag; GitHub hosts the DMG and the appcast; the build number is the commit count

**Context.** ADR-004 settles how Otter is distributed (Developer ID, notarized DMG, Sparkle, Homebrew). T13 has to choose where the update feed lives, how versions are numbered, and how much of a release is manual. The product owner decided OVERVIEW §10's open questions 1–3: the name stays Otter, the bundle ID is `io.github.elizabeth-ling.otter`, and the code is MIT-licensed in a public repo.

**Decision.**
- **Tag to release.** Pushing `vX.Y.Z` runs `.github/workflows/release.yml`. It calls `scripts/release.sh X.Y.Z`, which archives, exports with Developer ID, notarizes and staples the app, builds the DMG, then signs, notarizes and staples it, checks both with `codesign` and `spctl`, and writes the appcast. The workflow then publishes the GitHub release and commits the new cask to `elizabeth-ling/homebrew-tap`. Nothing is uploaded or edited by hand. The same script runs locally with `--local` (ad-hoc signed, not notarized) to test it and to test updates.
- **Versions.** The tag sets `CFBundleShortVersionString` (SemVer, digits only). `CFBundleVersion`, which Sparkle compares, is `git rev-list --count HEAD`. It only goes up as long as releases are tagged on `main`'s history, and nobody has to bump it. The project file keeps `0.1.0` / `1` for Debug builds.
- **Feed.** `SUFeedURL` is `…/releases/latest/download/appcast.xml`. Each release uploads an appcast holding only itself; Sparkle needs only the newest item. There are no GitHub Pages and no deltas.
- **Release notes** are the version's `## [X.Y.Z]` section of `CHANGELOG.md`. It becomes both the GitHub release body and the Markdown notes Sparkle shows. A tag without a section fails before anything is built.
- **Secrets** live only in GitHub Actions: the Developer ID certificate (.p12 and password), the App Store Connect API key, Sparkle's EdDSA private key and a token for the tap repo. The public EdDSA key is in the project file (`SPARKLE_PUBLIC_ED_KEY`).
- **Updates in the app.** A daily check (on by default, Settings › Advanced) uses Sparkle's gentle reminders: an agent app must not bring a window up over the user's work, so the menu bar item changes to "Update Available…". Debug builds don't start the updater.

**Consequences.** A release needs a clean `main` and a changelog entry, and nothing else. Changing the bundle ID reset the `UserDefaults` of existing development installs (shortcuts, settings, destinations); `~/Library/Application Support/Otter/` is keyed by name, so drafts and the outbox stayed. Rebasing `main` after a release could lower the commit count; don't. A prerelease channel would need Sparkle channels and a different feed; it's not needed for v1.
