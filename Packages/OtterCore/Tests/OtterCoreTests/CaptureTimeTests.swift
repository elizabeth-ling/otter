import Foundation
import Testing
@testable import OtterCore

// T14's test matrix, "Time": a note is dated when and where it was captured, however late it's
// delivered. Each capture goes through a relaunched outbox, as after a night with the folder offline.

private let newYork = TimeZone(identifier: "America/New_York")!

private func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// Journals each capture, reads them back with a new outbox, delivers them to a folder, and
/// returns each note's file name and contents.
private func deliverAfterRelaunch(_ captures: [(Date, TimeZone)], mode: FolderOptions.Mode = .newFilePerNote) async throws -> [(name: String, text: String)] {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Notes", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destinationID = DestinationID()
    let outbox = Outbox(directory: root.appendingPathComponent("outbox", isDirectory: true))
    for (index, (date, timeZone)) in captures.enumerated() {
        try await outbox.enqueue(Capture(createdAt: date, timeZone: timeZone, text: "Note \(index + 1)", destinationID: destinationID, source: .panel))
    }

    let options = FolderOptions(bookmark: try FolderBookmark.make(for: folder), displayPath: folder.path, mode: mode)
    let destination = FolderDestination(id: destinationID, name: "Notes", options: options)
    let relaunched = Outbox(directory: outbox.directory)
    var notes: [(String, String)] = []
    for item in await relaunched.pending() {
        guard case let .file(file) = try await destination.deliver(item.capture, files: relaunched.filesDirectory(for: item.capture.id)).location else {
            continue
        }
        notes.append((file.lastPathComponent, try String(contentsOf: file, encoding: .utf8)))
    }
    return notes
}

@Test func aNoteCapturedAt2359IsDatedThatDayWhenDeliveredAfterMidnight() async throws {
    // 23:59:30 on 7 March in New York; delivered now, years later.
    let notes = try await deliverAfterRelaunch([(utc("2026-03-08T04:59:30Z"), newYork)])
    #expect(notes.first?.name == "2026-03-07 2359 Note 1.md")
    #expect(notes.first?.text.contains("created: 2026-03-07T23:59:30-05:00") == true)
}

@Test func aNoteKeepsTheTimeZoneItWasCapturedInAfterAMove() async throws {
    // Captured in Kiritimati (UTC+14), delivered after flying home: still the 22nd there.
    let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
    let notes = try await deliverAfterRelaunch([(utc("2026-09-21T10:15:00Z"), kiritimati)])
    #expect(notes.first?.name == "2026-09-22 0015 Note 1.md")
    #expect(notes.first?.text.contains("created: 2026-09-22T00:15:00+14:00") == true)
}

@Test func theRepeatedHourWhenClocksGoBackGivesTwoNotesWithTheirOwnOffsets() async throws {
    // 1 November 2026, New York: 01:30 EDT, then an hour later 01:30 EST.
    let notes = try await deliverAfterRelaunch([(utc("2026-11-01T05:30:00Z"), newYork), (utc("2026-11-01T06:30:00Z"), newYork)])
    #expect(notes.map(\.name) == ["2026-11-01 0130 Note 1.md", "2026-11-01 0130 Note 2.md"])
    #expect(notes.first?.text.contains("created: 2026-11-01T01:30:00-04:00") == true)
    #expect(notes.last?.text.contains("created: 2026-11-01T01:30:00-05:00") == true)
}

@Test func theSkippedHourWhenClocksGoForwardJumpsFrom0159To0300() async throws {
    // 8 March 2026, New York: a minute apart across the jump.
    let notes = try await deliverAfterRelaunch([(utc("2026-03-08T06:59:00Z"), newYork), (utc("2026-03-08T07:00:00Z"), newYork)])
    #expect(notes.map(\.name) == ["2026-03-08 0159 Note 1.md", "2026-03-08 0300 Note 2.md"])
}

@Test func appendedBlocksAreTimedInTheCaptureTimeZone() async throws {
    let notes = try await deliverAfterRelaunch([(utc("2026-03-08T04:59:30Z"), newYork)], mode: .appendToFile(name: "Inbox.md"))
    #expect(notes.first?.text == "- 23:59 Note 1\n")
}
