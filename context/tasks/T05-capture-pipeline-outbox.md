# T05 — Capture pipeline and outbox

**Milestone:** M0 · **Depends on:** T01 · **Estimate:** 1 day

## Goal

The durable, asynchronous delivery engine behind "instant and never lose a note": submit writes to a local journal in milliseconds; a background actor delivers to destinations with retries.

## Read first

- ARCHITECTURE §3 (model), §4 (pipeline + rules), §8 (storage)
- DECISIONS ADR-005

## Scope

All in OtterCore unless noted.

1. Models: `Capture`, `Attachment`, `DestinationID`, `DestinationConfig`, `DeliveryReceipt`, `DestinationHealth`, `Destination` protocol — as in ARCHITECTURE §3.
2. `DestinationRegistry`: holds configured destinations, the default, and order (for `⌘1…⌘9`). Persists `[DestinationConfig]` to `UserDefaults` as JSON. Builds concrete `Destination`s from configs via a factory (folder only for now; T07/T08 register more).
3. `Outbox` (actor):
   - `enqueue(_ capture: Capture, attachmentFiles: [URL]) throws` — moves attachment files into `outbox/<id>/files/`, writes `outbox/<id>.json` atomically, then `fsync`s the file and directory. Returns only when durable.
   - `pending() -> [OutboxItem]` ordered by `createdAt`.
   - `markDelivered(id)` — deletes JSON + files directory.
   - `markFailed(id, error: String, nextAttemptAt: Date)`.
   - `OutboxItem = { capture, attempts, lastError, nextAttemptAt }`.
4. `DeliveryService` (actor):
   - One serial lane per `DestinationID` (an actor or `AsyncStream` per destination).
   - `kick()` drains due items. Called after enqueue, at launch (deferred 1 s), and on wake (`NSWorkspace.didWakeNotification` — wire in the app target).
   - Retry backoff: 2 s, 10 s, 60 s, then every 5 min. Single `Task.sleep` until the earliest `nextAttemptAt`; **no timer when the outbox is empty**.
   - Publishes `status: (pendingCount, failingDestinations, lastError)` for the UI.
   - Missing destination for an item → leave it pending, flag it in status (re-routing UI is T10).
5. `RecentStore`: ring buffer of last 20 receipts with first line (≤80 chars), destination name, location, time. `recent.json`. Can be disabled.
6. `CaptureService` (app target): `submit(text, attachments, destinationID?)` → builds `Capture` → `outbox.enqueue` → on success clear draft, hide panel → `delivery.kick()`. If enqueue throws (disk full), keep the panel open and show the error in the footer.
7. `FakeDestination` in tests: configurable to fail N times, delay, or throw specific errors.

## Implementation notes

- `fsync`: use `FileHandle(forWritingTo:).synchronize()` on the temp file before rename, then open the directory with `open(O_RDONLY)` and `fsync` the fd.
- Use `JSONEncoder` with `.iso8601` dates and sorted keys (readable when debugging).
- Capture `createdAt` with `TimeZone.current` stored alongside (`timeZoneIdentifier`), so formatting at delivery time uses the capture's local time, not the delivery's.
- Everything must survive the app being killed at any line. Write the crash test first.

## Acceptance criteria

- [x] Unit test: enqueue → "crash" (drop actors) → new `Outbox` on the same dir → item pending → delivered.
- [x] Unit test: destination fails 3 times then succeeds → exactly one successful delivery, attempts = 4, backoff times correct (inject a clock).
- [x] Unit test: 100 captures to one destination are delivered in order; a slow destination doesn't delay another.
- [x] Enqueue p95 < 10 ms on an SSD (measured in a test with 1 KB notes).
- [ ] No CPU wakeups when the outbox is empty (verify with Activity Monitor "Idle Wake Ups").

## Out of scope

Concrete destinations (T06–T08). UI for failures (T10/T12).
