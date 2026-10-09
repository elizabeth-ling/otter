# Otter — Manual test matrix (T14)

Run before each release on a Release build, Apple silicon, current macOS. Record the build, the date and who ran it, then a result per row: **Pass**, **Fail** (with an issue), or **Not run**. A row stays open until it passes or its failure is accepted in writing here.

Rows marked *automated* are covered by a test that runs without a person; the cell says which. Everything else needs hands, eyes, a second display or a system setting changed, and is still to be done.

| Run | Build | Date | By |
|---|---|---|---|
| 1 | `feature/t14-performance-and-reliability`, Release with `OTTER_TEST_HOOKS` | 2026-10-08 | Claude (automated rows only) |

**Run 1 summary:** 14 rows pass or are fixed, all automated. Four of them pass only in part: the logic is tested, but the UI half (disk full, the two `⌘Space` rows, the duplicate-shortcut message) still needs a person. Every other row is not run yet and waits for the owner. No failures, but one known issue goes into the Focus return rows: focus comes back about 105 ms after `⌘↩`, at the end of the fade-out (PERF.md, "Open"). One bug was found and fixed along the way: a kill during a draft or recents save left a temp copy of note text behind (see Privacy audit).

## Spaces & windows

| Case | How | Run 1 |
|---|---|---|
| Multiple Spaces: panel opens on the current Space, and switching Spaces with it open brings it along | Open on Space 2, switch with `⌃→` | Not run |
| Over a full-screen app | Safari full screen, press the hotkey | Not run |
| Split View | Two apps in Split View; open over each side | Not run |
| Stage Manager on | Open, type, `⌘↩`; focus goes back to the staged app | Not run |
| Stage Manager off | As above | Not run |
| Mission Control open | Press the hotkey with Mission Control showing | Not run |

## Displays

| Case | How | Run 1 |
|---|---|---|
| Two displays, pointer on the main one | Panel opens on the pointer's display, at that display's saved position | Not run |
| Two displays, pointer on the other one | As above | Not run |
| Display unplugged while the panel is open | Panel moves to the remaining display, text kept, still typeable | Not run |
| Different scale factors (Retina + 1×) | Drag across; text and shadow stay sharp, size correct | Not run |

## Focus return

Type immediately after `Esc`, and immediately after `⌘↩`: every keystroke must land in the app, none in the panel. The fade-out takes 80 ms and the panel stays key until it ends (see PERF.md), so type fast for the `⌘↩` half.

| App | After `Esc` | After `⌘↩` |
|---|---|---|
| TextEdit | Not run | Not run |
| Safari address bar | Not run | Not run |
| Terminal | Not run | Not run |
| VS Code | Not run | Not run |
| Slack | Not run | Not run |
| A Java or Electron app (e.g. IntelliJ, Discord) | Not run | Not run |

## Input

| Case | How | Run 1 |
|---|---|---|
| Japanese IME | Type and convert, `⌘↩` mid-composition doesn't submit half a word | Not run |
| Chinese IME (Pinyin) | As above | Not run |
| Emoji picker (`⌃⌘Space`) | Opens over the panel; the emoji lands in the note; the panel doesn't hide | Not run |
| Dictation | Dictate a sentence into the panel | Not run |
| RTL text | Type Arabic or Hebrew; caret and styling behave; saved file is correct | Not run |
| 1 MB paste | Paste 1 MB of text; typing stays responsive; `⌘↩` saves it whole | Not run |

## Appearance

| Case | How | Run 1 |
|---|---|---|
| Light | Panel, chips, footer readable | Not run |
| Dark | As above | Not run |
| Reduce Motion | No fade in or out | Not run |
| Reduce Transparency | Opaque background | Not run |
| Increase Contrast | Borders and text meet contrast | Not run |
| VoiceOver walkthrough | Open, type, read back, change destination, `⌘↩`, menu bar menu, Settings | Not run |

## Destinations

| Case | How | Run 1 |
|---|---|---|
| Vault in iCloud Drive, "Optimize Mac Storage" on, note file evicted | Append to an evicted file; it downloads and the block is added, nothing lost | Not run |
| Vault on an external drive, unplugged | Notes wait in the outbox, amber dot after 5 failures, delivered on replug | Not run |
| Folder renamed | Next note follows the rename | Pass (automated: `renamedFolderIsFollowedAndRebookmarked`, `healthCheckRebookmarksARenamedFolder`) |
| Folder deleted | Notes wait in the outbox; the folder isn't silently recreated | Pass (automated: `deletedFolderIsMissingAndNotRecreated`, `folderInTheTrashCountsAsMissing`) |
| Disk full | Panel stays open with "your disk is full", text kept | Pass (automated, the message: `diskFullIsRecognisedHoweverItIsReported`); the panel's behaviour on a really full disk: Not run |
| Kill at any point, 1,000 captures | Nothing lost | Pass (automated: `scripts/soak.sh`, see PERF.md) |

## Time

| Case | How | Run 1 |
|---|---|---|
| Capture at 23:59, deliver after midnight | Dated the capture's day | Pass (automated: `aNoteCapturedAt2359IsDatedThatDayWhenDeliveredAfterMidnight`) |
| Time zone change between capture and delivery | Dated in the capture's time zone | Pass (automated: `aNoteKeepsTheTimeZoneItWasCapturedInAfterAMove`, `captureKeepsItsTimeZoneThroughTheOutbox`) |
| DST transition | Repeated hour keeps both offsets; skipped hour jumps | Pass (automated: `theRepeatedHourWhenClocksGoBack…`, `theSkippedHourWhenClocksGoForward…`, `appendedBlocksAreTimedInTheCaptureTimeZone`) |

## Lifecycle

| Case | How | Run 1 |
|---|---|---|
| Sleep/wake with a pending outbox | Unplug the vault drive, capture, sleep, replug, wake: delivered on wake | Not run |
| Logout/login | Draft and outbox survive; login item relaunches Otter | Not run |
| Sparkle update with a pending outbox and an open draft | `scripts/release.sh --local` 0.1.0 and 0.1.1 (see below); both survive the update | Not run |

`release.sh --local` builds ad-hoc signed with Hardened Runtime on. When the perf build was made the same way, macOS refused to load Sparkle.framework, which keeps its own Team ID ("different Team IDs"). Check that the `--local` app launches before testing updates with it; if it doesn't, the update test needs Developer ID–signed builds.

## Hotkeys

| Case | How | Run 1 |
|---|---|---|
| `⌘Space` chosen while Spotlight has it | Falls back to `⌥Space`, reminder shown | Pass (automated, the decision: `commandSpaceWithSpotlightOnFallsBackToOptionSpace`); the reminder in the UI: Not run |
| Spotlight's shortcut turned off while Otter runs | Otter takes `⌘Space` without a relaunch | Pass (automated, the decision: `commandSpaceWithSpotlightOffRegistersCommandSpace`); live, from System Settings: Not run |
| Spotlight moved to `⌥Space` | No clash with the fallback | Not run |
| `⌥Space` taken by another app | Onboarding's press-to-confirm catches it | Not run |
| Shortcut cleared | Nothing registered; menu shows no shortcut; New Note still works | Not run |
| Same key for both shortcuts | Refused, the previous one put back | Pass (automated: `sameShortcutForBothActionsIsRefused`); the recorder's message: Not run |

## Privacy audit

| Check | How | Run 1 |
|---|---|---|
| No note text in the logs from a full session | `log show --info --debug` over a 1,000-capture soak (≈30,000 lines from Otter): searched for the notes' marker, filler words, file names and paths | Pass: none. Otter logs IDs, byte counts and error codes; system frameworks log paths as `<private>` |
| No network traffic except Sparkle's appcast check | Little Snitch or `nettop -p Otter` over a session that includes a manual "Check for Updates…" | Not run. The code's only network client is Sparkle (ADR-009, ARCHITECTURE §12); a live check is still to do |
| Note text is stored only in the outbox, the draft and recents | Searched Otter's folder after the soak | **Fixed.** A kill during a save left `recent.json.sb-…` (Foundation's temp file for an atomic write) holding the start of notes, and "Clear recents" didn't remove it; the draft had the same risk. Both stores now delete these leftovers on first read and on clear (`AtomicWriteLeftovers`). The draft (`drafts/current.json`) is a third place by design (T04): it holds the note being written, and is deleted once that note is in the outbox |
| Outbox cleared after delivery | Soak: outbox empty at the end, no files left | Pass |
| Recents cleared on "Clear recents" | `disabledStoreRecordsNothingAndDisablingDeletesTheFile`, `leftoverTempFilesOfAKilledSaveAreDeletedOnFirstReadAndOnClear` | Pass (automated) |
