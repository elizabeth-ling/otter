import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// Keeps the draft's attachments in `drafts/files/` (ARCHITECTURE §8), so a pasted screenshot
/// survives a hide, a quit or a crash along with the text. Each file is saved as
/// `<attachment-id>.<ext>`; the attachment's `originalName` remembers what it was called.
/// `Outbox.enqueue` takes the files from here when the note is submitted.
///
/// An actor on the shared pool, so copying a large file never blocks the panel. Never logs file
/// names: they're the user's.
public actor AttachmentStager {
    public nonisolated let directory: URL
    /// Files staged since launch. Orphan cleanup never touches them, even if it runs after a paste.
    private var stagedThisSession: Set<String> = []

    /// Does no disk work. The folder is created on the first paste.
    public init(directory: URL) {
        self.directory = directory
    }

    /// Where `attachment`'s staged file is.
    public nonisolated func file(for attachment: Attachment) -> URL {
        directory.appendingPathComponent(attachment.relativePath)
    }

    /// The draft's attachments whose staged file is still there, ready to submit. A file can be
    /// missing if the app quit after the outbox took it but before the draft was cleared.
    public nonisolated func staged(_ attachments: [Attachment]) -> [StagedAttachment] {
        attachments.compactMap { attachment in
            let file = file(for: attachment)
            guard FileManager.default.fileExists(atPath: file.path) else {
                return nil
            }
            return StagedAttachment(attachment: attachment, file: file)
        }
    }

    /// Copies the file at `source` (never moves it). Folders, packages and files over
    /// `AttachmentLimits.maxBytes` are refused.
    public func stageFile(at source: URL) throws -> StagedAttachment {
        let name = source.lastPathComponent
        let values: URLResourceValues
        do {
            values = try source.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey])
        } catch {
            Logger.panel.error("Couldn't read a file to attach: \(error.loggableCode, privacy: .public)")
            throw AttachmentError.unreadable(name: name)
        }
        if values.isDirectory == true {
            throw AttachmentError.folder(name: name)
        }
        if AttachmentLimits.isTooLarge(values.fileSize ?? 0) {
            throw AttachmentError.tooLarge(name: name)
        }

        let uti = values.contentType?.identifier
            ?? UTType(filenameExtension: source.pathExtension)?.identifier
            ?? UTType.data.identifier
        let id = UUID()
        let target = stagedURL(id: id, pathExtension: source.pathExtension)
        do {
            try prepareDirectory()
            try FileManager.default.copyItem(at: source, to: target)
            try Self.synchronize(target)
            let byteCount = try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int ?? 0
            // Checked again: the file may have grown since it was measured.
            guard !AttachmentLimits.isTooLarge(byteCount) else {
                try? FileManager.default.removeItem(at: target)
                throw AttachmentError.tooLarge(name: name)
            }
            let attachment = Attachment(id: id, originalName: name, uti: uti, relativePath: target.lastPathComponent, byteCount: byteCount)
            stagedThisSession.insert(attachment.relativePath)
            return StagedAttachment(attachment: attachment, file: target)
        } catch let error as AttachmentError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: target)
            Logger.panel.error("Couldn't stage a file to attach: \(error.loggableCode, privacy: .public)")
            throw AttachmentError.unreadable(name: name)
        }
    }

    /// Saves pasted image data of type `uti` (one of `PasteRules.imageTypes`). TIFF is converted to
    /// PNG; PNG, JPEG and HEIC are kept as they are. The attachment has no `originalName`, so the
    /// destination names it after the capture's time.
    public func stageImage(_ data: Data, uti: String) throws -> StagedAttachment {
        let displayName = "Pasted image"
        var data = data
        var type = UTType(uti) ?? .png
        if type == .tiff {
            guard let png = Self.pngData(fromImage: data) else {
                throw AttachmentError.unreadable(name: displayName)
            }
            data = png
            type = .png
        }
        if AttachmentLimits.isTooLarge(data.count) {
            throw AttachmentError.tooLarge(name: displayName)
        }

        let id = UUID()
        let target = stagedURL(id: id, pathExtension: type.preferredFilenameExtension ?? "png")
        do {
            try prepareDirectory()
            try data.write(to: target, options: .atomic)
            try Self.synchronize(target)
        } catch {
            try? FileManager.default.removeItem(at: target)
            Logger.panel.error("Couldn't stage a pasted image: \(error.loggableCode, privacy: .public)")
            throw AttachmentError.unreadable(name: displayName)
        }
        let attachment = Attachment(id: id, originalName: nil, uti: type.identifier, relativePath: target.lastPathComponent, byteCount: data.count)
        stagedThisSession.insert(attachment.relativePath)
        return StagedAttachment(attachment: attachment, file: target)
    }

    /// Deletes the staged files of attachments the user removed or discarded.
    public func remove(_ attachments: [Attachment]) {
        for attachment in attachments {
            let file = file(for: attachment)
            guard FileManager.default.fileExists(atPath: file.path) else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                Logger.panel.error("Couldn't remove a staged attachment: \(error.loggableCode, privacy: .public)")
            }
        }
    }

    /// Deletes every staged file the draft no longer refers to: leftovers of removals that failed,
    /// or of a crash part-way through staging. Call once at launch. Files staged since then are kept.
    public func removeOrphans(keeping attachments: [Attachment]) {
        let keep = Set(attachments.map(\.relativePath)).union(stagedThisSession)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        var removed = 0
        for name in names where !keep.contains(name) {
            if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))) != nil {
                removed += 1
            }
        }
        if removed > 0 {
            Logger.panel.info("Removed \(removed, privacy: .public) staged file(s) no draft refers to")
        }
    }

    // MARK: - Private

    private func stagedURL(id: UUID, pathExtension: String) -> URL {
        let name = pathExtension.isEmpty ? id.uuidString : "\(id.uuidString).\(pathExtension)"
        // `pathExtension` comes from a file name; anything that isn't a plain extension is dropped.
        guard !pathExtension.contains("/"), name.utf8.count <= FileNamer.maxNameBytes else {
            return directory.appendingPathComponent(id.uuidString)
        }
        return directory.appendingPathComponent(name)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The staged copy is on disk before the draft that refers to it is saved.
    private static func synchronize(_ file: URL) throws {
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    /// The first image in `data` (TIFF from the pasteboard) encoded as PNG.
    static func pngData(fromImage data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}
