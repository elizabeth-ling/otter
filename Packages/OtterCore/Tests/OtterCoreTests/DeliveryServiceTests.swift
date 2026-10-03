import Foundation
import Testing
@testable import OtterCore

@Test func retryPolicyBacksOffTwoTenSixtyThenEveryFiveMinutes() {
    #expect((1...6).map(RetryPolicy.delay(afterFailures:)) == [2, 10, 60, 300, 300, 300])
}

@Test(.timeLimit(.minutes(1)))
func failingThreeTimesThenSucceedingDeliversOnceAfterFourAttemptsWithBackoff() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let destination = FakeDestination(failTimes: 3, error: FakeDeliveryError.permissionDenied, clock: clock)
    let outbox = Outbox(directory: root)
    let service = DeliveryService(outbox: outbox, destinations: { _ in destination }, clock: clock)
    let capture = makeCapture(destination: destination.id)
    let t0 = clock.now

    try await outbox.enqueue(capture)
    await service.kick()
    await service.waitUntilIdle()

    // Each failure schedules exactly one sleep, until the next attempt.
    for (failures, expectedDelay) in [(1, 2.0), (2, 10.0), (3, 60.0)] {
        let deadline = await clock.nextSleepDeadline()
        let item = try #require(await outbox.pending().first)
        #expect(item.attempts == failures)
        #expect(item.nextAttemptAt == deadline)
        #expect(deadline == clock.now.addingTimeInterval(expectedDelay))
        #expect(clock.sleepDeadlines.count == 1)
        #expect(await service.status.failingDestinations == [destination.id])
        #expect(await service.status.lastError != nil)
        clock.advance(to: deadline)
    }

    await destination.waitForDeliveries(1)
    await service.waitUntilIdle()

    #expect(await destination.attemptTimes == [t0, t0 + 2, t0 + 12, t0 + 72])
    #expect(await destination.delivered == [capture])
    #expect(await outbox.pending().isEmpty)
    #expect(clock.sleepDeadlines.isEmpty, "no timer once the outbox is empty")
    #expect(await service.status == .idle)
}

@Test(.timeLimit(.minutes(1)))
func hundredCapturesToOneDestinationArriveInOrder() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let destination = FakeDestination(clock: clock)
    let outbox = Outbox(directory: root)

    // All in the same second, so only the enqueue order tells them apart.
    let captures = (1...100).map { makeCapture("Note \($0)", destination: destination.id) }
    for capture in captures {
        try await outbox.enqueue(capture)
    }

    // The order survives a relaunch too.
    let relaunched = Outbox(directory: root)
    #expect(await relaunched.pending().map(\.capture.id) == captures.map(\.id))

    let service = DeliveryService(outbox: relaunched, destinations: { _ in destination }, clock: clock)
    await service.kick()
    await service.waitUntilIdle()

    #expect(await destination.delivered.map(\.id) == captures.map(\.id))
    #expect(await relaunched.pending().isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func pendingIsOrderedByCreationTimeNotEnqueueOrder() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outbox = Outbox(directory: root)
    let id = DestinationID()
    let later = makeCapture("later", destination: id, createdAt: referenceDate + 60)
    let earlier = makeCapture("earlier", destination: id, createdAt: referenceDate)

    try await outbox.enqueue(later)
    try await outbox.enqueue(earlier)

    #expect(await outbox.pending().map(\.capture.id) == [earlier.id, later.id])
}

@Test(.timeLimit(.minutes(1)))
func slowDestinationDoesNotDelayAnother() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let slow = FakeDestination(name: "Slow", held: true, clock: clock)
    let fast = FakeDestination(name: "Fast", clock: clock)
    let outbox = Outbox(directory: root)
    let service = DeliveryService(outbox: outbox, destinations: { $0 == slow.id ? slow : fast }, clock: clock)

    let slowCaptures = [makeCapture("slow 1", destination: slow.id), makeCapture("slow 2", destination: slow.id)]
    let fastCaptures = (1...10).map { makeCapture("fast \($0)", destination: fast.id) }
    for capture in [slowCaptures[0]] + fastCaptures + [slowCaptures[1]] {
        try await outbox.enqueue(capture)
    }
    await service.kick()

    // Every fast capture lands while the slow destination is still stuck on its first one.
    await fast.waitForDeliveries(fastCaptures.count)
    #expect(await fast.delivered.map(\.id) == fastCaptures.map(\.id))
    #expect(await slow.attemptTimes.count == 1)
    #expect(await slow.delivered.isEmpty)

    await slow.release()
    await service.waitUntilIdle()
    #expect(await slow.delivered.map(\.id) == slowCaptures.map(\.id))
    #expect(await outbox.pending().isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func delayedDestinationStillDelivers() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let destination = FakeDestination(delay: .milliseconds(20), clock: clock)
    let outbox = Outbox(directory: root)
    let service = DeliveryService(outbox: outbox, destinations: { _ in destination }, clock: clock)
    let capture = makeCapture(destination: destination.id)

    try await outbox.enqueue(capture)
    await service.kick()
    await service.waitUntilIdle()

    #expect(await destination.delivered == [capture])
}

@Test(.timeLimit(.minutes(1)))
func missingDestinationLeavesCapturesPendingAndFlaggedWithoutATimer() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let table = DestinationTable()
    let outbox = Outbox(directory: root)
    let service = DeliveryService(outbox: outbox, destinations: table.lookup, clock: clock)
    let destinationID = DestinationID()
    let capture = makeCapture(destination: destinationID)

    try await outbox.enqueue(capture)
    await service.kick()
    await service.waitUntilIdle()

    #expect(await outbox.pending().map(\.capture) == [capture])
    #expect(await outbox.pending().first?.attempts == 0, "a missing destination isn't a failed attempt")
    #expect(await service.status.missingDestinations == [destinationID])
    #expect(await service.status.pendingCount == 1)
    #expect(clock.sleepDeadlines.isEmpty, "nothing to retry on a timer")
    let lookupsAfterFirstKick = table.lookups

    // Once the destination exists (re-routing, T10), the next kick delivers.
    let destination = FakeDestination(id: destinationID, clock: clock)
    table.set(destination, for: destinationID)
    await service.kick()
    await service.waitUntilIdle()

    #expect(table.lookups > lookupsAfterFirstKick)
    #expect(await destination.delivered == [capture])
    #expect(await service.status == .idle)
}

@Test(.timeLimit(.minutes(1)))
func emptyOutboxNeverSleeps() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let service = DeliveryService(outbox: Outbox(directory: root), destinations: { _ in nil }, clock: clock)

    await service.kick()
    await service.kick()
    await service.waitUntilIdle()

    #expect(clock.sleepDeadlines.isEmpty)
    #expect(await service.status == .idle)
}

@Test(.timeLimit(.minutes(1)))
func statusUpdatesPublishChanges() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let destination = FakeDestination(failTimes: 1, clock: clock)
    let outbox = Outbox(directory: root)
    let service = DeliveryService(outbox: outbox, destinations: { _ in destination }, clock: clock)
    var updates = await service.statusUpdates().makeAsyncIterator()

    #expect(await updates.next() == .idle)

    try await outbox.enqueue(makeCapture(destination: destination.id))
    await service.kick()
    await service.waitUntilIdle()

    // The newest status wins in the buffer: one pending capture, failing.
    let failing = try #require(await updates.next())
    #expect(failing.pendingCount == 1)
    #expect(failing.failingDestinations == [destination.id])
    #expect(failing.lastError == FakeDeliveryError.offline.localizedDescription)

    clock.advance(to: await clock.nextSleepDeadline())
    await destination.waitForDeliveries(1)
    await service.waitUntilIdle()
    #expect(await updates.next() == .idle)
}

@Test(.timeLimit(.minutes(1)))
func deliveryIsRecordedInRecents() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let destination = FakeDestination(name: "Inbox", clock: clock)
    let outbox = Outbox(directory: root.appendingPathComponent("outbox"))
    let recents = RecentStore(fileURL: root.appendingPathComponent("recent.json"))
    let service = DeliveryService(outbox: outbox, destinations: { _ in destination }, recents: recents, clock: clock)
    let capture = makeCapture("\n  Call the dentist  \nabout Tuesday", destination: destination.id)

    try await outbox.enqueue(capture)
    await service.kick()
    await service.waitUntilIdle()

    let recent = try #require(await recents.recent().first)
    #expect(recent.id == capture.id)
    #expect(recent.firstLine == "Call the dentist")
    #expect(recent.destinationName == "Inbox")
    #expect(recent.location == .file(URL(fileURLWithPath: "/fake/\(capture.id).md")))
}
