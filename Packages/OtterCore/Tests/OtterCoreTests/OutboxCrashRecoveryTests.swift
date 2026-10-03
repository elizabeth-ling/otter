import Foundation
import Testing
@testable import OtterCore

// T05's first test: a capture the outbox accepted survives the process dying at any point
// afterwards. "Crash" = the actors go away with no shutdown step; only the files remain.

@Test(.timeLimit(.minutes(1)))
func enqueuedCaptureSurvivesCrashAndIsDeliveredAfterRelaunch() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outboxDirectory = root.appendingPathComponent("outbox", isDirectory: true)
    let destinationID = DestinationID()

    let staged = try stageAttachment(named: "photo.png", in: root, bytes: 2048)
    let capture = makeCapture(destination: destinationID, attachments: [staged.attachment])

    do {
        let outbox = Outbox(directory: outboxDirectory)
        try await outbox.enqueue(capture, attachmentFiles: [staged.file])
    } // Crash: nothing else runs. No delivery service ever saw the capture.

    #expect(!FileManager.default.fileExists(atPath: staged.file.path), "the staged file moved into the outbox")

    let relaunched = Outbox(directory: outboxDirectory)
    let pending = await relaunched.pending()
    #expect(pending.map(\.capture) == [capture])
    #expect(pending.first?.attempts == 0)
    #expect(pending.first?.lastError == nil)

    let clock = TestClock()
    let destination = FakeDestination(id: destinationID, clock: clock)
    let service = DeliveryService(outbox: relaunched, destinations: { $0 == destinationID ? destination : nil }, clock: clock)
    await service.kick()
    await service.waitUntilIdle()

    #expect(await destination.delivered == [capture])
    #expect(await destination.sawAllAttachments == [true])
    #expect(await relaunched.pending().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: outboxDirectory.appendingPathComponent("\(capture.id).json").path))
    #expect(!FileManager.default.fileExists(atPath: outboxDirectory.appendingPathComponent(capture.id.uuidString).path))
    #expect(clock.sleepDeadlines.isEmpty, "nothing left to retry, so nothing sleeps")
}

@Test(.timeLimit(.minutes(1)))
func failedAttemptSurvivesCrashWithItsRetryState() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let destinationID = DestinationID()
    let capture = makeCapture(destination: destinationID)
    let clock = TestClock()

    do {
        let outbox = Outbox(directory: root)
        try await outbox.enqueue(capture)
        let destination = FakeDestination(id: destinationID, failTimes: 1, clock: clock)
        let service = DeliveryService(outbox: outbox, destinations: { _ in destination }, clock: clock)
        await service.kick()
        await service.waitUntilIdle()
    } // Crash while a retry is scheduled.

    let pending = await Outbox(directory: root).pending()
    #expect(pending.count == 1)
    #expect(pending.first?.attempts == 1)
    #expect(pending.first?.lastError != nil)
    #expect(pending.first?.nextAttemptAt == referenceDate.addingTimeInterval(2))
}

@Test(.timeLimit(.minutes(1)))
func interruptedWritesAreCleanedUpWithoutTouchingCommittedCaptures() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let capture = makeCapture(destination: DestinationID())

    do {
        let outbox = Outbox(directory: root)
        try await outbox.enqueue(capture)
    }

    // What a kill can leave behind: a temp file that was never renamed into place, and the
    // attachment folder of an enqueue that never wrote its JSON (its originals are still staged).
    let fileManager = FileManager.default
    let orphanID = UUID()
    let tempFile = root.appendingPathComponent("\(orphanID).json.tmp")
    let orphanFiles = root.appendingPathComponent(orphanID.uuidString, isDirectory: true)
        .appendingPathComponent("files", isDirectory: true)
    try Data("{\"capt".utf8).write(to: tempFile)
    try fileManager.createDirectory(at: orphanFiles, withIntermediateDirectories: true)
    try Data(count: 16).write(to: orphanFiles.appendingPathComponent("a.png"))

    let pending = await Outbox(directory: root).pending()
    #expect(pending.map(\.capture) == [capture])
    #expect(!fileManager.fileExists(atPath: tempFile.path))
    #expect(!fileManager.fileExists(atPath: orphanFiles.deletingLastPathComponent().path))
}
