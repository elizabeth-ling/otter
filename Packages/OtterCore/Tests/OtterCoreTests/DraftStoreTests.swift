import Foundation
import Testing
@testable import OtterCore

private let attachmentID = UUID()

private func makeDraft(_ text: String = "Call Sam re: Q4 deck") -> Draft {
    Draft(
        text: text,
        attachmentRefs: [Attachment(id: attachmentID, originalName: "img.png", uti: "public.png", relativePath: "img.png", byteCount: 12)],
        updatedAt: referenceDate
    )
}

private func draftFile(in root: URL) -> URL {
    root.appendingPathComponent("drafts", isDirectory: true).appendingPathComponent("current.json")
}

@Test func savedDraftIsReadBackByANewStore() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = draftFile(in: root)
    let store = DraftStore(fileURL: file)

    store.save(makeDraft())
    #expect(store.load() == makeDraft())
    store.flush()

    #expect(DraftStore(fileURL: file).load() == makeDraft())
}

@Test func saveWaitsForThePauseAndKeepsOnlyTheLatest() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = draftFile(in: root)
    let store = DraftStore(fileURL: file, debounce: .milliseconds(100))

    store.save(makeDraft("C"))
    store.save(makeDraft("Ca"))
    store.save(makeDraft("Cat"))
    #expect(!FileManager.default.fileExists(atPath: file.path))

    try await Task.sleep(for: .milliseconds(400))
    #expect(DraftStore(fileURL: file).load()?.text == "Cat")
}

@Test func saveNowWritesWithoutWaiting() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = draftFile(in: root)
    let store = DraftStore(fileURL: file, debounce: .seconds(60))

    store.save(makeDraft("typed"))
    store.saveNow(makeDraft("hidden"))
    try await Task.sleep(for: .milliseconds(200))

    #expect(DraftStore(fileURL: file).load()?.text == "hidden")
}

@Test func clearForgetsTheDraftAndDeletesTheFile() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = draftFile(in: root)
    let store = DraftStore(fileURL: file)
    store.saveNow(makeDraft())
    store.flush()
    #expect(FileManager.default.fileExists(atPath: file.path))

    store.clear()
    #expect(store.load() == nil)
    store.flush()
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(DraftStore(fileURL: file).load() == nil)
}

@Test func emptyDraftCountsAsNoDraft() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = draftFile(in: root)
    let store = DraftStore(fileURL: file)
    store.saveNow(makeDraft())
    store.flush()

    store.save(Draft(text: ""))
    store.flush()

    #expect(store.load() == nil)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    // Whitespace is still the user's text.
    store.save(Draft(text: "  \n"))
    #expect(store.load()?.text == "  \n")
}

@Test func corruptFileLoadsAsNilAndIsReplacedByTheNextSave() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = draftFile(in: root)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{\"text\": \"half a".utf8).write(to: file)

    let store = DraftStore(fileURL: file)
    #expect(store.load() == nil)

    store.save(makeDraft())
    store.flush()
    #expect(DraftStore(fileURL: file).load() == makeDraft())
}

@Test func missingFileLoadsAsNil() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(DraftStore(fileURL: draftFile(in: root)).load() == nil)
}

@Test func fileHasTheDocumentedShape() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = draftFile(in: root)
    let store = DraftStore(fileURL: file)
    store.save(makeDraft())
    store.flush()

    let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(Set(object.keys) == ["text", "attachmentRefs", "updatedAt"])
}

/// A kill during an atomic save leaves `current.json.sb-…`, holding the note (T14 soak).
@Test func leftoverTempFilesOfAKilledSaveAreDeletedOnLoadAndOnClear() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = draftFile(in: root)
    let leftover = file.deletingLastPathComponent().appendingPathComponent("current.json.sb-1a2b3c4d-XyZ123")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: leftover.path, contents: Data("the note".utf8))

    let store = DraftStore(fileURL: file)
    #expect(store.load() == nil)
    #expect(!FileManager.default.fileExists(atPath: leftover.path))

    store.saveNow(makeDraft())
    store.flush()
    FileManager.default.createFile(atPath: leftover.path, contents: Data("the note".utf8))
    store.clear()
    store.flush()
    #expect(!FileManager.default.fileExists(atPath: leftover.path))
}
