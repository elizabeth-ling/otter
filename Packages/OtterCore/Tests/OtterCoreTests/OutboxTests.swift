import Foundation
import Testing
@testable import OtterCore

@Test func enqueueMovesAttachmentsIntoTheOutbox() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outbox = Outbox(directory: root.appendingPathComponent("outbox"))
    let staged = try stageAttachment(named: "diagram.png", in: root, bytes: 512)
    let capture = makeCapture(destination: DestinationID(), attachments: [staged.attachment])

    try await outbox.enqueue(capture, attachmentFiles: [staged.file])

    let moved = outbox.filesDirectory(for: capture.id).appendingPathComponent("diagram.png")
    #expect(FileManager.default.fileExists(atPath: moved.path))
    #expect(try Data(contentsOf: moved).count == 512)
    #expect(!FileManager.default.fileExists(atPath: staged.file.path))
}

@Test func journalIsReadableJSONWithISO8601DatesSortedKeysAndTheCaptureTimeZone() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outbox = Outbox(directory: root)
    let capture = makeCapture(destination: DestinationID())

    try await outbox.enqueue(capture)

    let json = try String(contentsOf: root.appendingPathComponent("\(capture.id).json"), encoding: .utf8)
    #expect(json.contains("\"createdAt\" : \"2026-09-21T14:13:20Z\""))
    #expect(json.contains("\"timeZoneIdentifier\" : \"Europe/Paris\""))
    let keys = ["attempts", "capture", "sequence"]
    let positions = try keys.map { try #require(json.range(of: "\"\($0)\"")).lowerBound }
    #expect(positions == positions.sorted())
}

@Test func captureKeepsItsTimeZoneThroughTheOutbox() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let capture = Capture(createdAt: referenceDate, timeZone: tokyo, text: "x", destinationID: DestinationID(), source: .clipboard)

    try await Outbox(directory: root).enqueue(capture)
    let reloaded = try #require(await Outbox(directory: root).pending().first?.capture)

    #expect(reloaded.timeZone == tokyo)
    #expect(reloaded.source == .clipboard)
}

@Test func markFailedPersistsAttemptsErrorAndNextAttempt() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outbox = Outbox(directory: root)
    let capture = makeCapture(destination: DestinationID())
    try await outbox.enqueue(capture)

    try await outbox.markFailed(capture.id, error: "Folder is missing", nextAttemptAt: referenceDate + 10)
    try await outbox.markFailed(capture.id, error: "Still missing", nextAttemptAt: referenceDate + 70)

    let item = try #require(await Outbox(directory: root).pending().first)
    #expect(item.attempts == 2)
    #expect(item.lastError == "Still missing")
    #expect(item.nextAttemptAt == referenceDate + 70)
    #expect(!item.isDue(at: referenceDate + 69))
    #expect(item.isDue(at: referenceDate + 70))
}

@Test func markDeliveredRemovesTheJournalAndFiles() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outboxDirectory = root.appendingPathComponent("outbox")
    let outbox = Outbox(directory: outboxDirectory)
    let staged = try stageAttachment(named: "a.png", in: root, bytes: 8)
    let capture = makeCapture(destination: DestinationID(), attachments: [staged.attachment])
    try await outbox.enqueue(capture, attachmentFiles: [staged.file])

    try await outbox.markDelivered(capture.id)

    #expect(await outbox.pending().isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: outboxDirectory.path).isEmpty)
}

@Test func enqueueRejectsBadInputWithoutLeavingAnythingBehind() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outboxDirectory = root.appendingPathComponent("outbox")
    let outbox = Outbox(directory: outboxDirectory)
    let staged = try stageAttachment(named: "a.png", in: root, bytes: 8)
    var escaping = staged.attachment
    escaping.relativePath = "../a.png"

    await #expect(throws: OutboxError.invalidAttachmentPath) {
        try await outbox.enqueue(makeCapture(destination: DestinationID(), attachments: [escaping]), attachmentFiles: [staged.file])
    }
    await #expect(throws: OutboxError.attachmentCountMismatch(attachments: 1, files: 0)) {
        try await outbox.enqueue(makeCapture(destination: DestinationID(), attachments: [staged.attachment]))
    }
    let capture = makeCapture(destination: DestinationID())
    try await outbox.enqueue(capture)
    await #expect(throws: OutboxError.duplicateCapture(capture.id)) {
        try await outbox.enqueue(capture)
    }

    #expect(FileManager.default.fileExists(atPath: staged.file.path), "a refused enqueue leaves the staged file alone")
    #expect(try FileManager.default.contentsOfDirectory(atPath: outboxDirectory.path) == ["\(capture.id).json"])
}

@Test func failedWriteRollsBackAndKeepsTheStagedFiles() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    // A file where the outbox directory should be: every write fails.
    let blocked = root.appendingPathComponent("outbox")
    try Data().write(to: blocked)
    let staged = try stageAttachment(named: "a.png", in: root, bytes: 8)
    let capture = makeCapture(destination: DestinationID(), attachments: [staged.attachment])
    let outbox = Outbox(directory: blocked)

    await #expect(throws: (any Error).self) {
        try await outbox.enqueue(capture, attachmentFiles: [staged.file])
    }

    #expect(await outbox.pending().isEmpty)
    #expect(FileManager.default.fileExists(atPath: staged.file.path))
}

@Test func unreadableEntriesAreSkippedButNeverDeleted() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let unreadable = root.appendingPathComponent("\(UUID()).json")
    try Data("not json".utf8).write(to: unreadable)

    #expect(await Outbox(directory: root).pending().isEmpty)
    #expect(FileManager.default.fileExists(atPath: unreadable.path))
}

@Test func enqueueP95IsUnderTenMillisecondsForOneKilobyteNotes() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outbox = Outbox(directory: root)
    let destination = DestinationID()
    let text = String(repeating: "x", count: 1024)
    let clock = ContinuousClock()
    var samples: [Duration] = []

    for _ in 0..<200 {
        let capture = Capture(text: text, destinationID: destination, source: .panel)
        let start = clock.now
        try await outbox.enqueue(capture)
        samples.append(start.duration(to: clock.now))
    }

    samples.sort()
    let p95 = samples[samples.count * 95 / 100 - 1]
    print("Outbox enqueue of a 1 KB note: p50 \(samples[samples.count / 2]), p95 \(p95), max \(samples[samples.count - 1])")
    #expect(p95 < .milliseconds(10))
}
