# Otter — Performance and reliability results (T14)

The two promises, with numbers: **it feels instant** (OVERVIEW §7, ARCHITECTURE §9) and **it never loses a note**. Re-run both before each release and replace the tables.

| Run | Build | Machine | Date |
|---|---|---|---|
| 1, 2 | `feature/t14-performance-and-reliability`: Release, `OTTER_TEST_HOOKS`, ad-hoc signed, Hardened Runtime off | MacBook, Apple M2, 16 GB, macOS 27.0.1 | 2026-10-08 |

## How to measure

```sh
scripts/perf.sh          # ≈ 3 min; the panel keeps taking focus, so don't type
scripts/soak.sh          # ≈ 1 min; nothing on screen
```

- **`scripts/perf.sh`** builds Release with the test hooks compiled in and records Otter's signposts with `log stream --signpost`. It launches 10 times with `--otter-bench launch`, then runs `--otter-bench full` (`App/TestHooks/BenchRunner.swift`). The full bench shows and hides the panel 30 times through the hotkey's closure and takes 100 notes through the panel with a real `⌘↩` key event. It then sends 50 notes each straight to a folder and to an Obsidian vault, and finally sits idle for 60 s while it reads its own memory footprint and wakeups. `scripts/perf_report.py` turns the run into the table below. Everything lives in a temporary folder with its own preferences suite, so your notes and settings are never touched.
- **`scripts/soak.sh`** runs `--otter-soak` (`App/TestHooks/SoakRunner.swift`) and `kill -9`s it at random until it finishes.
- **Instruments:** the same intervals are in Points of Interest (`Signpost` in OtterCore): `hotkey ready` (an event, in ms since the process started), `hotkey→visible`, `submit→hidden`, `enqueue→delivered` (per capture, with the destination ID as its message) and `restyle`.
- The test hooks are compiled only with `OTTER_TEST_HOOKS`: on in Debug, added to Release by `perf.sh`, and never in a shipped build.
- Without a Developer ID, the perf build runs with Hardened Runtime off. With it on, library validation refuses Sparkle.framework, whose Team ID an ad-hoc signature can't match. Hardened Runtime only changes how libraries are checked at load, so expect launch to be a few ms slower in a shipped build. Check that with a Developer ID build before release.

## Results

| Interval | Budget | Run 1 | Run 2 | Verdict |
|---|---|---|---|---|
| Cold launch → hotkey registered | < 300 ms | first 262, then p50 154 ms (n=10) | first 288, then p50 157 ms (n=10) | Met, with little margin when cold (below) |
| Hotkey → panel key | p95 < 100 ms (target 50) | p50 4.1 · p95 6.7 · max 15.0 ms (n=130) | p50 5.1 · p95 6.0 · max 6.2 ms (n=130) | Met, and under the 50 ms target |
| `⌘↩` → panel hides | < 50 ms | p50 3.4 · p95 5.6 · max 7.6 ms (n=98) | p50 4.2 · p95 6.3 · max 10.4 ms (n=100) | Met |
| `⌘↩` → previous app has keyboard focus again | < 50 ms (OVERVIEW §7) | p50 105 · p95 113 ms | p50 110 · p95 117 ms | **Over. Open, needs a decision (below)** |
| Enqueue → delivered, default inbox (folder) | p95 < 50 ms | p50 6.9 · p95 13.9 · max 19.1 ms (n=98) | p50 7.7 · p95 15.9 · max 19.2 ms (n=100) | Met |
| Enqueue → delivered, folder | p95 < 50 ms | p50 6.5 · p95 10.9 · max 15.4 ms (n=50) | p50 6.3 · p95 9.6 · max 10.8 ms (n=50) | Met |
| Enqueue → delivered, Obsidian vault | p95 < 50 ms | p50 6.9 · p95 10.3 · max 12.6 ms (n=50) | p50 6.6 · p95 10.5 · max 12.8 ms (n=50) | Met |
| Idle memory after 100 captures | < 40 MB | 31.8 MB | 29.3 MB | Met (`phys_footprint`, Activity Monitor's Memory column) |
| Idle wakeups/s, 60 s, panel hidden, outbox empty | ~0 | 0.00 idle, 0.07 interrupt | 0.00 idle, 0.05 interrupt | Met: no timers while idle |
| Inline restyle, per edit | < 1 ms for a 10 KB note | p50 0.1 · p95 0.3 · max 1.3 ms (n=409) | p50 0.1 · p95 0.3 · max 0.6 ms (n=419) | Met (bench notes are up to 5 KB) |
| App size | < 15 MB | 10 MB (7.6 MB binary, 2.5 MB Sparkle) | | Met |

Nothing needed fixing for speed. The usual suspects were checked:
- **Show path:** the panel is built once. The draft is read off the main thread at launch, the destination check runs after the show, and nothing in SwiftUI is rebuilt.
- **Submit path:** an `fsync`ed outbox write, then a kick of the delivery actor. The note is written in the background.
- **Hide:** thumbnails are released on hide.
- **Idle:** there are no timers when the outbox is empty, and the retry sleep exists only while something is waiting.

### Notes on the numbers

- **Cold vs warm launch.** The first launch of each run came after several idle minutes, and took 262 ms and 288 ms. Back-to-back launches take 130–180 ms. The slow first launch is the one a login item gets, so it's the one that counts. It's within budget, but the margin is small. If it creeps up, the first places to look are what loads before `applicationDidFinishLaunching`: the SwiftUI `App` lifecycle (used only for the empty Settings scene), Sparkle.framework and KeyboardShortcuts.
- **First run of a new binary: ≈ 530 ms.** The first launch after a build, install or update takes about 370 ms more, while macOS checks an executable it hasn't seen before. Copying the app and launching the copy reproduced it: 533 ms, then 164, 163, 153 ms. Users see it once per install or update. It isn't Otter's code, so it isn't counted against the budget.
- **Hotkey → panel key** starts where the hotkey's handler starts. The Carbon event's trip from the keyboard to that handler happens before it and can't be measured in-process.
- **Enqueue → delivered** starts once the outbox has the note on disk. Counting the outbox write too, from just before `enqueue`: p50 10.0 · p95 16.2 ms for a folder and p50 10.5 · p95 13.8 ms for a vault.
- **In run 1, two of the 100 bench `⌘↩`s didn't submit** (captures 1 and 86). Neither produced a `submit→hidden` interval or a capture, so those notes were never sent; nothing was lost. The panel was key with the note in it, and the text-input system was generating candidates for the text just set. Run 2 submitted 100 of 100. So it's most likely the synthetic key event racing the text-input system, though that's not proven. The Focus return rows in TEST_MATRIX.md check `⌘↩` by hand. If a real `⌘↩` ever does nothing, start here.

### Open: focus comes back after the fade, not at `⌘↩`

`⌘↩` starts hiding the panel within 6 ms. But UX_SPEC's 80 ms fade-out keeps the panel on screen, and key, until it ends. Keyboard focus goes back to the previous app only when the panel is ordered out, about 105 ms after `⌘↩`. OVERVIEW §7 asks for under 50 ms. Keys typed during the fade go into the empty panel and become the start of the next draft instead of reaching the app. `Esc` behaves the same way.

The behind-window blur can't be snapshotted without Screen Recording permission, so a fading copy of the panel isn't an option. The choices are:
1. **Hide at once on `⌘↩` and `Esc`, and keep the 80 ms fade-in.** Focus is back in under 10 ms. This needs a UX_SPEC change. Recommended: it's what "the panel closes immediately on `⌘↩`" (UX_SPEC §1) and principle 6 (return focus) ask for.
2. Keep the fade, and change OVERVIEW §7 to "panel starts hiding < 50 ms; focus back < 120 ms".
3. Shorten the fade-out to about 30 ms. Focus is back in about 50 ms; it's a compromise on both.

## Reliability soak

`scripts/soak.sh` (defaults: 1,000 captures, killed with `kill -9` at random 0.2–2 s intervals until the run is complete, at least 20 kills). Each capture's text starts with a soak ID and is padded to a random size up to 100 KB, mostly under 2 KB. One in ten has a 1–64 KB attachment. Captures go to five destinations at random: the default inbox, a folder, an Obsidian vault (new file per note), and a file in each that notes are appended to. A capture counts as *acknowledged* once `enqueue` returns, which is the point where the panel would close. The verifier then looks for every acknowledged ID in the destinations' files.

| | Run 1 |
|---|---|
| Captures acknowledged | 1,000 |
| Kills | 34, spread over the whole run, including during the final drain |
| **Lost** | **0** |
| Duplicate copies | 0 |
| Delivered but never acknowledged | 2: killed after the outbox write but before the ack was recorded; delivered once each |
| Attachments delivered | 127 of 127 |
| Left in the outbox | 0 |

An earlier run (20 kills, all in the first half of the run) also lost 0 with 0 duplicates. After that run the script was changed to keep killing until the run is complete.

### Found and fixed

A kill during an atomic save leaves Foundation's temp file (`recent.json.sb-…`) beside the file. For the recents and the draft, that temp file holds note text, and nothing ever removed it, not even "Clear Recents". Both stores now delete these leftovers on first read and on clear (`AtomicWriteLeftovers`, with tests). The outbox already swept its own temp files.
