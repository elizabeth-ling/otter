import Foundation
import os
import Testing
@testable import OtterCore

/// Bookmark changes reported by a destination.
private final class BookmarkChanges: Sendable {
    private let changes = OSAllocatedUnfairLock<[(bookmark: Data, displayPath: String)]>(initialState: [])

    var all: [(bookmark: Data, displayPath: String)] {
        changes.withLock { $0 }
    }

    func record(_ bookmark: Data, _ displayPath: String) {
        changes.withLock { $0.append((bookmark, displayPath)) }
    }
}

private func makeFolder(in root: URL, named name: String = "Notes") throws -> URL {
    let folder = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func makeDestination(
    folder: URL,
    mode: FolderOptions.Mode = .newFilePerNote,
    subfolder: String? = nil,
    frontmatter: Bool = true,
    changes: BookmarkChanges? = nil
) throws -> FolderDestination {
    let options = FolderOptions(bookmark: try FolderBookmark.make(for: folder), displayPath: folder.path, mode: mode, subfolder: subfolder, frontmatter: frontmatter)
    return FolderDestination(id: DestinationID(), name: "Notes", options: options) { bookmark, path in
        changes?.record(bookmark, path)
    }
}

private func contents(of directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

private func fileURL(of receipt: DeliveryReceipt) throws -> URL {
    guard case let .file(url) = receipt.location else {
        throw FolderDestinationError.folderMissing
    }
    return url
}

private let noFiles = URL(fileURLWithPath: "/nonexistent")

/// Bookmarks resolve temp paths through `/private`, so compare real paths.
private func isSameDirectory(_ a: URL, _ b: URL) -> Bool {
    a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
}

// MARK: - New file per note

@Test func newNoteIsWrittenAsMarkdownWithNoTempFileLeft() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder)
    let capture = makeCapture("Buy oat milk\nand bread", destination: destination.id)

    let file = try fileURL(of: await destination.deliver(capture, files: noFiles))

    #expect(file.lastPathComponent == "2026-09-21 1613 Buy oat milk.md")
    #expect(isSameDirectory(file.deletingLastPathComponent(), folder))
    #expect(try String(contentsOf: file, encoding: .utf8) == "---\ncreated: 2026-09-21T16:13:20+02:00\nsource: otter\n---\nBuy oat milk\nand bread\n")
    #expect(try contents(of: folder) == ["2026-09-21 1613 Buy oat milk.md"])
}

@Test func sameNameTwiceGetsANumberedSecondFile() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder, frontmatter: false)

    for text in ["Standup", "Standup", "Standup"] {
        _ = try await destination.deliver(makeCapture(text, destination: destination.id), files: noFiles)
    }

    #expect(try contents(of: folder) == ["2026-09-21 1613 Standup 2.md", "2026-09-21 1613 Standup 3.md", "2026-09-21 1613 Standup.md"])
}

// MARK: - Save panel (T16)

@Test func savePanelNoteIsWrittenToTheChosenFileWithATitle() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let elsewhere = try makeFolder(in: root, named: "Elsewhere")
    let chosen = elsewhere.appendingPathComponent("Groceries.md")
    let destination = try makeDestination(folder: folder, mode: .appendToFile(name: "Inbox"))

    let capture = makeCapture("oat milk\nbread", title: "Groceries", fileURL: chosen, destination: destination.id)
    let file = try fileURL(of: await destination.deliver(capture, files: noFiles))

    #expect(file == chosen)
    #expect(try String(contentsOf: chosen, encoding: .utf8) == "---\ntitle: \"Groceries\"\ncreated: 2026-09-21T16:13:20+02:00\nsource: otter\n---\noat milk\nbread\n")
    #expect(try contents(of: elsewhere) == ["Groceries.md"])
    #expect(try contents(of: folder).isEmpty)
}

@Test func savePanelNoteReplacesTheChosenFile() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let chosen = folder.appendingPathComponent("Groceries.md")
    try Data("old".utf8).write(to: chosen)
    let destination = try makeDestination(folder: folder, frontmatter: false)

    for _ in 1...2 {
        _ = try await destination.deliver(makeCapture("new", title: "Groceries", fileURL: chosen, destination: destination.id), files: noFiles)
    }

    #expect(try String(contentsOf: chosen, encoding: .utf8) == "new\n")
    #expect(try contents(of: folder) == ["Groceries.md"])
}

@Test func savePanelNoteInAMissingFolderFailsAndLeavesNothing() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder)
    let chosen = root.appendingPathComponent("Gone/Groceries.md")

    await #expect(throws: (any Error).self) {
        try await destination.deliver(makeCapture(title: "Groceries", fileURL: chosen, destination: destination.id), files: noFiles)
    }
    #expect(try contents(of: root) == ["Notes"])
}

@Test func subfolderIsCreatedOnFirstWrite() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder, subfolder: "Inbox/Otter")

    let file = try fileURL(of: await destination.deliver(makeCapture(destination: destination.id), files: noFiles))

    #expect(isSameDirectory(file.deletingLastPathComponent(), folder.appendingPathComponent("Inbox/Otter")))
}

@Test(arguments: ["../Escape", "/tmp", "Inbox/../../x"])
func subfolderOutsideTheFolderIsRefused(subfolder: String) async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder, subfolder: subfolder)

    await #expect(throws: FolderDestinationError.unsafePath) {
        try await destination.deliver(makeCapture(destination: destination.id), files: noFiles)
    }
    #expect(try contents(of: root) == ["Notes"])
}

// MARK: - Append to file

@Test func appendCreatesTheFileAndSeparatesBlocksWithABlankLine() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder, mode: .appendToFile(name: "Inbox"))

    let file = try fileURL(of: await destination.deliver(makeCapture("First", destination: destination.id), files: noFiles))
    _ = try await destination.deliver(makeCapture("Second\nwith detail", destination: destination.id), files: noFiles)

    #expect(file.lastPathComponent == "Inbox.md")
    #expect(try String(contentsOf: file, encoding: .utf8) == "- 16:13 First\n\n### 16:13\nSecond\nwith detail\n")
}

@Test func appendAddsTheMissingNewlineToAnExistingFile() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let file = folder.appendingPathComponent("Log.md")
    try Data("# Log\nno newline".utf8).write(to: file)
    let destination = try makeDestination(folder: folder, mode: .appendToFile(name: "Log.md"))

    _ = try await destination.deliver(makeCapture("Entry", destination: destination.id), files: noFiles)

    #expect(try String(contentsOf: file, encoding: .utf8) == "# Log\nno newline\n\n- 16:13 Entry\n")
}

@Test func appendFileNameOutsideTheFolderIsRefused() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder, mode: .appendToFile(name: "../outside.md"))

    await #expect(throws: FolderDestinationError.unsafePath) {
        try await destination.deliver(makeCapture(destination: destination.id), files: noFiles)
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("outside.md").path))
}

@Test(.timeLimit(.minutes(1)))
func fiftyConcurrentAppendsAreAllIntact() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder, mode: .appendToFile(name: "Inbox.md"))

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<50 {
            group.addTask {
                _ = try await destination.deliver(makeCapture("note \(index)", destination: destination.id), files: noFiles)
            }
        }
        try await group.waitForAll()
    }

    let blocks = try String(contentsOf: folder.appendingPathComponent("Inbox.md"), encoding: .utf8)
        .split(separator: "\n\n").map(String.init)
    #expect(blocks.count == 50)
    #expect(Set(blocks.map { $0.trimmingCharacters(in: .newlines) }) == Set((0..<50).map { "- 16:13 note \($0)" }))
}

@Test(.timeLimit(.minutes(1)))
func fiftyCapturesThroughTheDeliveryLaneAppendInOrder() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder, mode: .appendToFile(name: "Inbox.md"))
    let outbox = Outbox(directory: root.appendingPathComponent("outbox", isDirectory: true))
    let service = DeliveryService(outbox: outbox, destinations: { _ in destination })

    // Kicked after every enqueue, as `CaptureService` does, so the lane is delivering while
    // later captures arrive.
    for index in 0..<50 {
        try await outbox.enqueue(makeCapture("note \(index)\nline two", destination: destination.id))
        await service.kick()
    }
    while await !outbox.pending().isEmpty {
        await service.waitUntilIdle()
        await service.kick()
    }

    let text = try String(contentsOf: folder.appendingPathComponent("Inbox.md"), encoding: .utf8)
    let expected = (0..<50).map { "### 16:13\nnote \($0)\nline two\n" }.joined(separator: "\n")
    #expect(text == expected)
}

// MARK: - Finding the folder

@Test func renamedFolderIsFollowedAndRebookmarked() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let changes = BookmarkChanges()
    let destination = try makeDestination(folder: folder, changes: changes)
    let renamed = root.appendingPathComponent("Renamed", isDirectory: true)
    try FileManager.default.moveItem(at: folder, to: renamed)

    let file = try fileURL(of: await destination.deliver(makeCapture(destination: destination.id), files: noFiles))

    #expect(isSameDirectory(file.deletingLastPathComponent(), renamed))
    let change = try #require(changes.all.last)
    #expect(change.displayPath.hasSuffix("/Renamed"))
    #expect(try FolderBookmark.resolve(change.bookmark).url.lastPathComponent == "Renamed")
}

@Test func healthCheckRebookmarksARenamedFolder() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let changes = BookmarkChanges()
    let destination = try makeDestination(folder: folder, changes: changes)
    try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("Renamed", isDirectory: true))

    #expect(await destination.healthCheck() == .ok)
    let change = try #require(changes.all.last)
    #expect(change.displayPath.hasSuffix("/Renamed"))
}

@Test func deletedFolderIsMissingAndNotRecreated() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder)
    try FileManager.default.removeItem(at: folder)

    await #expect(throws: FolderDestinationError.folderMissing) {
        try await destination.deliver(makeCapture(destination: destination.id), files: noFiles)
    }
    #expect(await destination.healthCheck() == .unreachable("Folder missing"))
    #expect(!FileManager.default.fileExists(atPath: folder.path))
}

@Test func folderRecreatedWhereItWasIsUsedAgain() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = try makeFolder(in: root)
    let destination = try makeDestination(folder: folder)
    try FileManager.default.removeItem(at: folder)
    await #expect(throws: FolderDestinationError.folderMissing) {
        try await destination.deliver(makeCapture(destination: destination.id), files: noFiles)
    }

    _ = try makeFolder(in: root)
    _ = try await destination.deliver(makeCapture(destination: destination.id), files: noFiles)

    #expect(try contents(of: folder).count == 1)
}

@Test func folderInTheTrashCountsAsMissing() {
    #expect(FolderBookmark.isInTrash(URL(fileURLWithPath: "/Users/me/.Trash/Notes")))
    #expect(FolderBookmark.isInTrash(URL(fileURLWithPath: "/Volumes/Disk/.Trashes/501/Notes")))
    #expect(!FolderBookmark.isInTrash(URL(fileURLWithPath: "/Users/me/Documents/Trash notes")))
}

@Test func defaultInboxIsCreatedOnFirstSaveAndBookmarked() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let config = DestinationConfig.defaultInbox(documents: root)
    guard case let .folder(options) = config.options else {
        Issue.record("The default inbox is a folder destination")
        return
    }
    let changes = BookmarkChanges()
    let destination = FolderDestination(id: config.id, name: config.name, options: options) { changes.record($0, $1) }
    let inbox = root.appendingPathComponent("Otter Inbox", isDirectory: true)

    #expect(await destination.healthCheck() == .ok)
    #expect(!FileManager.default.fileExists(atPath: inbox.path))

    _ = try await destination.deliver(makeCapture(destination: config.id), files: noFiles)

    #expect(try contents(of: inbox).count == 1)
    let change = try #require(changes.all.first)
    #expect(try FolderBookmark.resolve(change.bookmark).url.lastPathComponent == "Otter Inbox")
}

// MARK: - Health

@Test func healthCheckReportsAWritableFolderAsOK() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = try makeDestination(folder: try makeFolder(in: root))

    #expect(await destination.healthCheck() == .ok)
}

@Test func healthCheckReportsAReadOnlyFolder() async throws {
    let root = try makeTemporaryDirectory()
    let folder = try makeFolder(in: root)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: root)
    }
    let destination = try makeDestination(folder: folder)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

    #expect(await destination.healthCheck() == .needsPermission)
    await #expect(throws: (any Error).self) {
        try await destination.deliver(makeCapture(destination: destination.id), files: noFiles)
    }
}

@Test func healthCheckReportsAFileAsMissing() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("not-a-folder")
    try Data().write(to: file)
    let destination = try makeDestination(folder: file)

    #expect(await destination.healthCheck() == .unreachable("Folder missing"))
}
