import Foundation
import Testing
@testable import OtterCore

private func receipt(_ seconds: TimeInterval) -> DeliveryReceipt {
    DeliveryReceipt(location: .file(URL(fileURLWithPath: "/Notes/Inbox/2026-09-21 0900 Note.md")), deliveredAt: referenceDate + seconds)
}

@Test func keepsTheLastTwentyNewestFirstAndPersists() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("recent.json")
    let store = RecentStore(fileURL: file)
    let captures = (1...25).map { makeCapture("Note \($0)", destination: DestinationID()) }

    for (index, capture) in captures.enumerated() {
        await store.record(capture, receipt: receipt(TimeInterval(index)), destinationName: "Notes")
    }

    let expected = captures.suffix(20).reversed().map(\.id)
    #expect(await store.recent().map(\.id) == expected)
    #expect(await RecentStore(fileURL: file).recent().map(\.id) == expected)
    #expect(await store.recent().first?.firstLine == "Note 25")
}

@Test func disabledStoreRecordsNothingAndDisablingDeletesTheFile() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("recent.json")
    let store = RecentStore(fileURL: file)
    await store.record(makeCapture(destination: DestinationID()), receipt: receipt(0), destinationName: "Inbox")
    #expect(FileManager.default.fileExists(atPath: file.path))

    await store.setEnabled(false)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    await store.record(makeCapture(destination: DestinationID()), receipt: receipt(1), destinationName: "Inbox")
    #expect(await store.recent().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.path))

    let off = RecentStore(fileURL: file, isEnabled: false)
    await off.record(makeCapture(destination: DestinationID()), receipt: receipt(2), destinationName: "Inbox")
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func firstLineIsTheFirstNonEmptyLineTrimmedToEightyCharacters() {
    #expect(RecentStore.firstLine(of: "\n\n   Hello world  \nsecond") == "Hello world")
    #expect(RecentStore.firstLine(of: "") == "")
    #expect(RecentStore.firstLine(of: " \n\t\n") == "")

    let exactly80 = String(repeating: "a", count: 80)
    #expect(RecentStore.firstLine(of: exactly80) == exactly80)

    let long = String(repeating: "é", count: 120)
    let cut = RecentStore.firstLine(of: long)
    #expect(cut.count == 80)
    #expect(cut.hasSuffix("…"))
}
