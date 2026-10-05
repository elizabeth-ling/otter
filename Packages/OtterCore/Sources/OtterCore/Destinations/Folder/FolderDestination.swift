import Foundation
import os

public enum FolderDestinationError: Error, LocalizedError, Equatable {
    /// The folder was deleted, or is on a volume that isn't mounted.
    case folderMissing
    /// The subfolder or append-file name in the settings leaves the folder.
    case unsafePath

    public var errorDescription: String? {
        switch self {
        case .folderMissing:
            "Folder missing"
        case .unsafePath:
            "The subfolder or file name in this destination's settings points outside its folder"
        }
    }
}

/// Writes captures as Markdown into a folder (ARCHITECTURE §5.1): one new file per note, or a block
/// appended to one file. A folder inside an Obsidian vault is still written here; `ObsidianVault`
/// and its helpers supply the vault's conventions (T07).
///
/// - New files are written to a hidden temp file in the target directory, then renamed into place,
///   so a watcher like Obsidian never sees a half-written note.
/// - A note saved with the `⌘S` Save panel (T16) goes to the file the user chose, wherever it is,
///   whatever the mode; that path comes from the Save panel, never from the note's text.
/// - Appends are coordinated (`NSFileCoordinator`, `.forMerging`), which keeps iCloud Drive and
///   other coordinated writers in step.
/// - The folder is found through its bookmark, so a rename in Finder is followed. A folder in the
///   Trash counts as missing, unless one has been recreated where it was.
///
/// File I/O can block (coordination, a permission prompt for `~/Documents`), so the actor runs on
/// its own dispatch queue rather than the shared concurrency pool. Never logs file names: they come
/// from the note's text.
public actor FolderDestination: Destination {
    /// Saves a re-created bookmark: the folder was renamed or moved, or the default inbox was just
    /// created. `displayPath` is where the folder is now.
    public typealias BookmarkChange = @Sendable (_ bookmark: Data, _ displayPath: String) -> Void

    public nonisolated let id: DestinationID
    public nonisolated let displayName: String
    /// Attachments arrive with T09.
    public nonisolated let supportsAttachments = false

    private let options: FolderOptions
    private var bookmark: Data
    private let onBookmarkChange: BookmarkChange
    private let queue = DispatchSerialQueue(label: "com.otter.folder", qos: .utility)

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    public init(id: DestinationID, name: String, options: FolderOptions, onBookmarkChange: @escaping BookmarkChange = { _, _ in }) {
        self.id = id
        displayName = name
        self.options = options
        bookmark = options.bookmark
        self.onBookmarkChange = onBookmarkChange
    }

    /// The folder exists, is a directory and is writable. The default inbox only needs a writable
    /// parent, since it's created on the first save.
    public func healthCheck() async -> DestinationHealth {
        let missing = DestinationHealth.unreachable(FolderDestinationError.folderMissing.localizedDescription)
        guard let folder = try? locateFolder(creatingIfNeeded: false) else {
            return missing
        }
        var target = folder
        if !isDirectory(folder), options.fallbackPath != nil {
            target = folder.deletingLastPathComponent()
        }
        guard isDirectory(target) else {
            return missing
        }
        guard FileManager.default.isWritableFile(atPath: target.path) else {
            return .unreachable("Folder isn't writable")
        }
        return .ok
    }

    public func deliver(_ capture: Capture, files: URL) async throws -> DeliveryReceipt {
        if let file = capture.fileURL {
            try writeChosenFile(file, for: capture)
            Logger.folder.info("Wrote \(capture.id, privacy: .public) to the file chosen for it")
            return DeliveryReceipt(location: .file(file), deliveredAt: Date())
        }
        let directory = try targetDirectory(in: locateFolder(creatingIfNeeded: true))
        let file: URL
        switch options.mode {
        case .newFilePerNote:
            file = try writeNewFile(for: capture, in: directory)
        case let .appendToFile(name):
            file = try append(capture, toFileNamed: name, in: directory)
        }
        Logger.folder.info("Wrote \(capture.id, privacy: .public) to \(self.id, privacy: .public)")
        return DeliveryReceipt(location: .file(file), deliveredAt: Date())
    }

    // MARK: - Finding the folder

    private func locateFolder(creatingIfNeeded create: Bool) throws -> URL {
        if !bookmark.isEmpty, let folder = resolveBookmark() {
            return folder
        }
        guard let fallbackPath = options.fallbackPath else {
            throw FolderDestinationError.folderMissing
        }
        let folder = URL(fileURLWithPath: fallbackPath, isDirectory: true)
        if create, !isDirectory(folder) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            Logger.folder.info("Created the folder for \(self.id, privacy: .public)")
        }
        if isDirectory(folder) {
            remember(folder)
        }
        return folder
    }

    /// The bookmarked folder, re-bookmarked if it moved. Falls back to a folder at the bookmark's
    /// original path, so a deleted folder that's been recreated counts as the same one.
    private func resolveBookmark() -> URL? {
        do {
            let (folder, isStale) = try FolderBookmark.resolve(bookmark)
            if !FolderBookmark.isInTrash(folder), isDirectory(folder) {
                if isStale {
                    remember(folder)
                }
                return folder
            }
        } catch {
            Logger.folder.error("Couldn't resolve the folder for \(self.id, privacy: .public): \(error.loggableCode, privacy: .public)")
        }
        if let path = FolderBookmark.originalPath(of: bookmark) {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            if !FolderBookmark.isInTrash(folder), isDirectory(folder) {
                remember(folder)
                return folder
            }
        }
        return nil
    }

    private func remember(_ folder: URL) {
        do {
            let updated = try FolderBookmark.make(for: folder)
            guard updated != bookmark else {
                return
            }
            bookmark = updated
            onBookmarkChange(updated, (folder.path as NSString).abbreviatingWithTildeInPath)
        } catch {
            Logger.folder.error("Couldn't bookmark the folder for \(self.id, privacy: .public): \(error.loggableCode, privacy: .public)")
        }
    }

    /// The folder plus the subfolder from the settings, created if needed.
    private func targetDirectory(in folder: URL) throws -> URL {
        guard let components = FileNamer.safeRelativePath(options.subfolder ?? "") else {
            throw FolderDestinationError.unsafePath
        }
        guard !components.isEmpty else {
            return folder
        }
        let directory = components.reduce(folder) { $0.appendingPathComponent($1, isDirectory: true) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Writing

    private func writeNewFile(for capture: Capture, in directory: URL) throws -> URL {
        let base = FileNamer.baseName(template: options.filenameTemplate, text: capture.text, date: capture.createdAt, timeZone: capture.timeZone)
        let temporary = try writeTemporaryFile(for: capture, in: directory)
        defer { try? FileManager.default.removeItem(at: temporary) }

        var number = 1
        while true {
            let file = directory.appendingPathComponent(FileNamer.fileName(base: base, number: number))
            if !FileManager.default.fileExists(atPath: file.path) {
                do {
                    try FileManager.default.moveItem(at: temporary, to: file)
                    return file
                } catch let error as CocoaError where error.code == .fileWriteFileExists {
                    // Another writer took the name since the check; try the next one.
                }
            }
            number += 1
        }
    }

    /// The Save panel's file, replaced in one step if it exists, so a retry after a crash rewrites the
    /// same file rather than adding another.
    private func writeChosenFile(_ file: URL, for capture: Capture) throws {
        let temporary = try writeTemporaryFile(for: capture, in: file.deletingLastPathComponent())
        defer { try? FileManager.default.removeItem(at: temporary) }
        // `rename(2)` replaces an existing file atomically; `moveItem` would refuse.
        guard rename(temporary.path, file.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// The note's Markdown in a hidden temp file in `directory`, synced to disk, for renaming into place.
    private func writeTemporaryFile(for capture: Capture, in directory: URL) throws -> URL {
        let content = MarkdownWriter.newFile(
            text: capture.text,
            title: capture.title,
            createdAt: capture.createdAt,
            timeZone: capture.timeZone,
            frontmatter: options.frontmatter
        )
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try Data(content.utf8).write(to: temporary)
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return temporary
    }

    private func append(_ capture: Capture, toFileNamed name: String, in directory: URL) throws -> URL {
        guard let components = FileNamer.safeRelativePath(name), !components.isEmpty else {
            throw FolderDestinationError.unsafePath
        }
        var file = components.reduce(directory) { $0.appendingPathComponent($1) }
        if file.pathExtension.isEmpty {
            file.appendPathExtension("md")
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)

        let block = MarkdownWriter.appendBlock(template: options.appendTemplate, text: capture.text, createdAt: capture.createdAt, timeZone: capture.timeZone)
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: file, options: .forMerging, error: &coordinationError) { url in
            do {
                try Self.append(block, to: url)
            } catch {
                writeError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
        return file
    }

    /// Creates the file if it's missing, leaves one blank line after what's there, writes the block
    /// and syncs it to disk.
    private static func append(_ block: String, to file: URL) throws {
        // `O_CREAT` without `O_TRUNC`: never truncates a file another app created a moment ago.
        let descriptor = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let end = try handle.seekToEnd()
        var tail = Data()
        if end > 0 {
            try handle.seek(toOffset: end - min(end, 2))
            tail = try handle.readToEnd() ?? Data()
        }
        try handle.write(contentsOf: Data(MarkdownWriter.appendText(block, toFileEndingWith: tail).utf8))
        try handle.synchronize()
    }

    private nonisolated func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
