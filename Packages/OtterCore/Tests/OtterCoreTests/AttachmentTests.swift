import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OtterCore

private let paris = TimeZone(identifier: "Europe/Paris")!

private func attachment(named name: String?, uti: String = "public.png", bytes: Int = 10) -> OtterCore.Attachment {
    OtterCore.Attachment(originalName: name, uti: uti, relativePath: "\(UUID().uuidString).png", byteCount: bytes)
}

// MARK: - Naming

@Test func pastedImagesAreNamedAfterTheCaptureTimeInItsTimeZone() {
    #expect(FileNamer.pastedImageName(date: referenceDate, timeZone: paris, pathExtension: "png") == "Pasted image 20260921161320.png")
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    #expect(FileNamer.pastedImageName(date: referenceDate, timeZone: tokyo, pathExtension: "png") == "Pasted image 20260921231320.png")
}

@Test(arguments: [("public.png", "png"), ("public.jpeg", "jpeg"), ("public.heic", "heic")])
func pastedImagesKeepTheirFormatsExtension(uti: String, pathExtension: String) {
    let name = FileNamer.attachmentName(for: attachment(named: nil, uti: uti), capturedAt: referenceDate, timeZone: paris)
    #expect(name == "Pasted image 20260921161320.\(pathExtension)")
}

@Test(arguments: [
    ("spec.pdf", "spec.pdf"),
    ("Plan #2 [draft].pdf", "Plan #2 [draft].pdf"),
    (".env", "env"),
    ("  report.txt", "report.txt"),
    ("a/b.txt", "ab.txt"),
    ("tab\there.txt", "tabhere.txt"),
    ("...", FileNamer.fallbackAttachmentName),
])
func filesKeepTheirNameMadeSafe(original: String, expected: String) {
    #expect(FileNamer.attachmentName(for: attachment(named: original), capturedAt: referenceDate, timeZone: paris) == expected)
}

@Test func aLongNameIsShortenedButKeepsItsExtension() {
    let name = FileNamer.attachmentName(for: attachment(named: String(repeating: "é", count: 200) + ".pdf"), capturedAt: referenceDate, timeZone: paris)
    #expect(name.utf8.count <= 255)
    #expect(name.hasSuffix("é.pdf"))
}

@Test func collisionsAreNumberedBeforeTheExtension() {
    #expect(FileNamer.numberedAttachmentName("spec.pdf", number: 1) == "spec.pdf")
    #expect(FileNamer.numberedAttachmentName("spec.pdf", number: 2) == "spec 2.pdf")
    #expect(FileNamer.numberedAttachmentName("Pasted image 20260921161320.png", number: 3) == "Pasted image 20260921161320 3.png")
    #expect(FileNamer.numberedAttachmentName("README", number: 2) == "README 2")
}

// MARK: - What a paste becomes

@Test(arguments: [
    // A ⌃⇧⌘4 screenshot.
    (["public.png"], false, false, PasteKind.image(uti: "public.png")),
    (["public.png", "public.tiff"], false, false, .image(uti: "public.png")),
    (["public.tiff"], false, false, .image(uti: "public.tiff")),
    (["public.jpeg"], false, false, .image(uti: "public.jpeg")),
    (["public.heic"], false, false, .image(uti: "public.heic")),
    // Files copied in Finder come with their names as text and an icon.
    (["public.file-url", "public.utf8-plain-text", "public.tiff"], true, true, .files),
    // Text from a web page.
    (["public.html", "public.rtf", "public.utf8-plain-text"], false, true, .text),
    // Text from Word or Pages, with a picture of it.
    (["public.rtf", "public.utf8-plain-text", "public.png"], false, true, .text),
    // A browser's "Copy Image".
    (["public.html", "public.png"], false, false, .image(uti: "public.png")),
    (["public.tiff", "public.url", "public.utf8-plain-text"], false, true, .image(uti: "public.tiff")),
    // A password manager's copy.
    (["org.nspasteboard.ConcealedType", "public.png"], false, false, .text),
    (["org.nspasteboard.ConcealedType", "public.file-url"], true, false, .text),
    (["public.utf8-plain-text"], false, true, .text),
])
func pasteKinds(types: [String], hasFileURLs: Bool, hasText: Bool, expected: PasteKind) {
    #expect(PasteRules.kind(types: types, hasFileURLs: hasFileURLs, hasText: hasText) == expected)
}

// MARK: - Limits and the footer

@Test func noWarningWithoutAttachmentsOrWithSmallOnes() {
    #expect(AttachmentLimits.footerWarning(for: [], destinationName: "Notes", supportsAttachments: false) == nil)
    #expect(AttachmentLimits.footerWarning(for: [attachment(named: "a.png", bytes: 25_000_000)], destinationName: "Notes", supportsAttachments: true) == nil)
}

@Test func aDestinationThatCantTakeAttachmentsIsWarnedAbout() {
    let destination = FakeDestination(name: "Apple Notes", supportsAttachments: false, clock: TestClock())
    let warning = AttachmentLimits.footerWarning(
        for: [attachment(named: nil)],
        destinationName: destination.displayName,
        supportsAttachments: destination.supportsAttachments
    )
    #expect(warning == "Apple Notes can't take attachments — they'll be dropped.")
}

@Test func largeAttachmentsAreWarnedAbout() {
    let large = attachment(named: "talk.mov", bytes: 25_000_001)
    #expect(AttachmentLimits.footerWarning(for: [large], destinationName: "Notes", supportsAttachments: true) == "talk.mov is over 25 MB.")
    #expect(AttachmentLimits.footerWarning(for: [large, large], destinationName: "Notes", supportsAttachments: true) == "2 attachments are over 25 MB.")
    #expect(!AttachmentLimits.isTooLarge(200_000_000))
    #expect(AttachmentLimits.isTooLarge(200_000_001))
}

// MARK: - Staging

@Test func stagingAFileCopiesIt() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("spec.pdf")
    try Data("%PDF-1.7".utf8).write(to: source)
    let stager = AttachmentStager(directory: root.appendingPathComponent("drafts/files", isDirectory: true))

    let staged = try await stager.stageFile(at: source)

    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(staged.file == stager.file(for: staged.attachment))
    #expect(try Data(contentsOf: staged.file) == Data("%PDF-1.7".utf8))
    #expect(staged.attachment.originalName == "spec.pdf")
    #expect(staged.attachment.uti == "com.adobe.pdf")
    #expect(staged.attachment.byteCount == 8)
    #expect(staged.attachment.relativePath == "\(staged.attachment.id.uuidString).pdf")
}

@Test func stagingAFolderIsRefused() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Photos", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let stager = AttachmentStager(directory: root.appendingPathComponent("files", isDirectory: true))

    await #expect(throws: AttachmentError.folder(name: "Photos")) {
        try await stager.stageFile(at: folder)
    }
}

@Test func pastedTIFFIsStagedAsPNG() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let stager = AttachmentStager(directory: root)

    let staged = try await stager.stageImage(try makeImage(type: .tiff), uti: "public.tiff")

    #expect(staged.attachment.uti == "public.png")
    #expect(staged.attachment.originalName == nil)
    #expect(staged.file.pathExtension == "png")
    let source = try #require(CGImageSourceCreateWithURL(staged.file as CFURL, nil))
    #expect(CGImageSourceGetType(source) as String? == "public.png")
}

@Test func pastedPNGIsKeptAsItIs() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let stager = AttachmentStager(directory: root)
    let png = try makeImage(type: .png)

    let staged = try await stager.stageImage(png, uti: "public.png")

    #expect(try Data(contentsOf: staged.file) == png)
    #expect(staged.attachment.byteCount == png.count)
}

@Test func removingAndOrphanCleanupDeleteStagedFiles() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let stager = AttachmentStager(directory: root.appendingPathComponent("files", isDirectory: true))
    let png = try makeImage(type: .png)
    let kept = try await stager.stageImage(png, uti: "public.png")
    let removed = try await stager.stageImage(png, uti: "public.png")
    let orphan = try await stager.stageImage(png, uti: "public.png")

    await stager.remove([removed.attachment])
    #expect(!FileManager.default.fileExists(atPath: removed.file.path))
    #expect(stager.staged([kept.attachment, removed.attachment]) == [kept])

    // Files staged since launch are never orphans; after a relaunch they are.
    await stager.removeOrphans(keeping: [kept.attachment])
    #expect(FileManager.default.fileExists(atPath: orphan.file.path))
    let relaunched = AttachmentStager(directory: stager.directory)
    await relaunched.removeOrphans(keeping: [kept.attachment])
    #expect(!FileManager.default.fileExists(atPath: orphan.file.path))
    #expect(FileManager.default.fileExists(atPath: kept.file.path))
}

/// A 2 × 2 red image encoded as `type`.
private func makeImage(type: UTType) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}
