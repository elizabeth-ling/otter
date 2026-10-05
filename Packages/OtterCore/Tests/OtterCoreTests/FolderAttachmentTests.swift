import Foundation
import Testing
@testable import OtterCore

/// A capture with attachments in an outbox-like `files` folder, as `Outbox.enqueue` leaves it.
private struct Fixture {
    let root: URL
    let folder: URL
    let files: URL

    init(folderName: String = "Notes") throws {
        root = try makeTemporaryDirectory()
        folder = root.appendingPathComponent(folderName, isDirectory: true)
        files = root.appendingPathComponent("outbox-files", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    }

    /// A pasted image (no original name) or a file, with `contents` as its bytes.
    func attachment(named name: String? = nil, uti: String = "public.png", contents: String = "png bytes") throws -> OtterCore.Attachment {
        let relativePath = "\(UUID().uuidString).\(name.map { ($0 as NSString).pathExtension } ?? "png")"
        try Data(contents.utf8).write(to: files.appendingPathComponent(relativePath))
        return OtterCore.Attachment(originalName: name, uti: uti, relativePath: relativePath, byteCount: contents.utf8.count)
    }

    func destination(
        folder: URL? = nil,
        mode: FolderOptions.Mode = .newFilePerNote,
        appendTemplate: String = AppendTemplate.default,
        attachmentsFolder: String = "attachments"
    ) throws -> FolderDestination {
        let folder = folder ?? self.folder
        let options = FolderOptions(
            bookmark: try FolderBookmark.make(for: folder),
            displayPath: folder.path,
            mode: mode,
            frontmatter: false,
            appendTemplate: appendTemplate,
            attachmentsFolder: attachmentsFolder
        )
        return FolderDestination(id: DestinationID(), name: "Notes", options: options)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func noteText(_ receipt: DeliveryReceipt) throws -> String {
    guard case let .file(url) = receipt.location else {
        throw FolderDestinationError.folderMissing
    }
    return try String(contentsOf: url, encoding: .utf8)
}

private func names(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

@Test func attachmentsAreCopiedNextToTheNoteAndLinkedAtTheEnd() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = try fixture.destination()
    let image = try fixture.attachment()
    let pdf = try fixture.attachment(named: "spec v2.pdf", uti: "com.adobe.pdf", contents: "%PDF")
    let capture = makeCapture("Call Sam", destination: destination.id, attachments: [image, pdf])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(destination.supportsAttachments)
    #expect(note == "Call Sam\n\n![](attachments/Pasted%20image%2020260921161320.png)\n[spec v2.pdf](attachments/spec%20v2.pdf)\n")
    let attachments = fixture.folder.appendingPathComponent("attachments")
    #expect(try names(in: attachments) == ["Pasted image 20260921161320.png", "spec v2.pdf"])
    #expect(try String(contentsOf: attachments.appendingPathComponent("spec v2.pdf"), encoding: .utf8) == "%PDF")
    // The outbox keeps its copies until the capture is marked delivered.
    #expect(try names(in: fixture.files).count == 2)
}

@Test func aNoteWithOnlyAnImageIsJustTheEmbed() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = try fixture.destination()
    let capture = makeCapture("", destination: destination.id, attachments: [try fixture.attachment()])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(note == "![](attachments/Pasted%20image%2020260921161320.png)\n")
}

@Test func aTakenNameGetsANumberButARetryReusesItsOwnCopy() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = try fixture.destination()
    let attachments = fixture.folder.appendingPathComponent("attachments")
    try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
    try Data("someone else's".utf8).write(to: attachments.appendingPathComponent("spec.pdf"))
    let pdf = try fixture.attachment(named: "spec.pdf", uti: "com.adobe.pdf", contents: "mine")
    let capture = makeCapture("Spec", destination: destination.id, attachments: [pdf])

    let first = try noteText(await destination.deliver(capture, files: fixture.files))
    // Delivered again, as after a crash before the outbox removed it.
    let second = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(first.hasSuffix("[spec 2.pdf](attachments/spec%202.pdf)\n"))
    #expect(second == first)
    #expect(try names(in: attachments) == ["spec 2.pdf", "spec.pdf"])
}

@Test func twoImagesPastedIntoOneNoteGetTwoNames() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = try fixture.destination()
    let first = try fixture.attachment(contents: "one")
    let second = try fixture.attachment(contents: "two")
    let capture = makeCapture("Two shots", destination: destination.id, attachments: [first, second])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(note.hasSuffix("![](attachments/Pasted%20image%2020260921161320.png)\n![](attachments/Pasted%20image%2020260921161320%202.png)\n"))
}

@Test func unsafeAttachmentsFolderIsRefused() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = try fixture.destination(attachmentsFolder: "../outside")
    let capture = makeCapture("x", destination: destination.id, attachments: [try fixture.attachment()])

    await #expect(throws: FolderDestinationError.unsafePath) {
        try await destination.deliver(capture, files: fixture.files)
    }
    #expect(try names(in: fixture.folder).isEmpty)
}

@Test func appendModeAddsTheEmbedsToTheBlock() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = try fixture.destination(mode: .appendToFile(name: "Inbox"))
    let capture = makeCapture("Whiteboard", destination: destination.id, attachments: [try fixture.attachment()])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(note == "### 16:13\nWhiteboard\n\n![](attachments/Pasted%20image%2020260921161320.png)\n")
}

@Test func appendTemplateCanPlaceTheEmbeds() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = try fixture.destination(mode: .appendToFile(name: "Inbox"), appendTemplate: "- {{time}} {{text}} {{attachments}}")
    let capture = makeCapture("Whiteboard", destination: destination.id, attachments: [try fixture.attachment()])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(note == "- 16:13 Whiteboard ![](attachments/Pasted%20image%2020260921161320.png)\n")
}

@Test func savePanelNoteGetsItsAttachmentsBesideTheChosenFile() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = try fixture.destination()
    let elsewhere = fixture.root.appendingPathComponent("Elsewhere", isDirectory: true)
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    let file = elsewhere.appendingPathComponent("Plan.md")
    let capture = makeCapture("Plan", title: "Plan", fileURL: file, destination: destination.id, attachments: [try fixture.attachment()])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(note.hasSuffix("Plan\n\n![](attachments/Pasted%20image%2020260921161320.png)\n"))
    #expect(try names(in: elsewhere.appendingPathComponent("attachments")) == ["Pasted image 20260921161320.png"])
    #expect(try names(in: fixture.folder).isEmpty)
}

// MARK: - Obsidian vaults

private func makeVault(in root: URL, appJSON: String?) throws -> URL {
    let vault = root.appendingPathComponent("Vault", isDirectory: true)
    let config = vault.appendingPathComponent(".obsidian", isDirectory: true)
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    if let appJSON {
        try Data(appJSON.utf8).write(to: config.appendingPathComponent("app.json"))
    }
    return vault
}

@Test func inAVaultTheImageGoesWhereAppJSONSaysWithAWikilink() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let vault = try makeVault(in: fixture.root, appJSON: #"{"attachmentFolderPath": "./assets"}"#)
    let inbox = vault.appendingPathComponent("Inbox", isDirectory: true)
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let destination = try fixture.destination(folder: inbox)
    let capture = makeCapture("Screenshot", destination: destination.id, attachments: [try fixture.attachment()])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(note == "Screenshot\n\n![[Pasted image 20260921161320.png]]\n")
    #expect(try names(in: inbox.appendingPathComponent("assets")) == ["Pasted image 20260921161320.png"])
    // `attachmentsFolder` isn't used inside a vault.
    #expect(!FileManager.default.fileExists(atPath: inbox.appendingPathComponent("attachments").path))
}

@Test func inAVaultWithMarkdownLinksTheLinkIsRelativeToTheNote() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let vault = try makeVault(in: fixture.root, appJSON: #"{"attachmentFolderPath": "Assets/Images", "useMarkdownLinks": true}"#)
    let inbox = vault.appendingPathComponent("Inbox", isDirectory: true)
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let destination = try fixture.destination(folder: inbox)
    let capture = makeCapture("Screenshot", destination: destination.id, attachments: [try fixture.attachment()])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(note == "Screenshot\n\n![](../Assets/Images/Pasted%20image%2020260921161320.png)\n")
    #expect(try names(in: vault.appendingPathComponent("Assets/Images")) == ["Pasted image 20260921161320.png"])
}

@Test func atAVaultsRootWithoutAppJSONAttachmentsGoToTheRoot() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let vault = try makeVault(in: fixture.root, appJSON: nil)
    let destination = try fixture.destination(folder: vault)
    let pdf = try fixture.attachment(named: "spec.pdf", uti: "com.adobe.pdf")
    let capture = makeCapture("Spec", destination: destination.id, attachments: [pdf])

    let note = try noteText(await destination.deliver(capture, files: fixture.files))

    #expect(note == "Spec\n\n[[spec.pdf]]\n")
    #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent("spec.pdf").path))
}
