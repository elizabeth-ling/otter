import Foundation
import os

/// A capture waiting for delivery, with its retry state. Stored as `outbox/<capture-id>.json`.
public struct OutboxItem: Codable, Sendable, Equatable {
    public var capture: Capture
    /// Failed delivery attempts so far.
    public var attempts: Int
    public var lastError: String?
    /// When the next attempt may start. `nil` means it hasn't been tried yet and is due now.
    public var nextAttemptAt: Date?
    /// Enqueue order. It breaks ties between captures with the same `createdAt`, because dates are
    /// stored to the second.
    public var sequence: Int

    public func isDue(at now: Date) -> Bool {
        nextAttemptAt.map { $0 <= now } ?? true
    }
}

public enum OutboxError: Error, Equatable {
    case duplicateCapture(UUID)
    case attachmentCountMismatch(attachments: Int, files: Int)
    /// An attachment's `relativePath` isn't a single, plain file name.
    case invalidAttachmentPath
    case notFound(UUID)
}

/// The local journal behind "never lose a note" (ARCHITECTURE §4, §8, ADR-005).
///
/// `enqueue` returns only once the capture is on disk. Every change is an atomic rename followed by
/// an `fsync` of the file and its directory, so killing the app at any point leaves each capture
/// either fully in the outbox or not in it. In the second case the draft still holds it, because the
/// draft is cleared only after `enqueue` returns.
public actor Outbox {
    public nonisolated let directory: URL

    private var items: [UUID: OutboxItem] = [:]
    private var lastSequence = 0
    private var isLoaded = false
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Does no disk work. The outbox is read on first use.
    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// `outbox/<capture-id>/files/`, where a capture's attachments wait for delivery.
    public nonisolated func filesDirectory(for captureID: UUID) -> URL {
        captureDirectory(for: captureID).appendingPathComponent("files", isDirectory: true)
    }

    /// Journals `capture`, and returns once it is durable.
    ///
    /// `attachmentFiles[i]` is the staged file for `capture.attachments[i]`. It moves to
    /// `outbox/<id>/files/<relativePath>`. The move is a hard link (a copy across volumes), and the
    /// original is removed only after the JSON is durable. A kill part-way through therefore leaves
    /// the staged files where they were.
    public func enqueue(_ capture: Capture, attachmentFiles: [URL] = []) throws {
        loadIfNeeded()
        guard items[capture.id] == nil else {
            throw OutboxError.duplicateCapture(capture.id)
        }
        guard attachmentFiles.count == capture.attachments.count else {
            throw OutboxError.attachmentCountMismatch(attachments: capture.attachments.count, files: attachmentFiles.count)
        }
        guard capture.attachments.allSatisfy({ Self.isPlainFileName($0.relativePath) }) else {
            throw OutboxError.invalidAttachmentPath
        }

        let fileManager = FileManager.default
        let captureDirectory = captureDirectory(for: capture.id)
        let item = OutboxItem(capture: capture, attempts: 0, lastError: nil, nextAttemptAt: nil, sequence: lastSequence + 1)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if !attachmentFiles.isEmpty {
                let files = filesDirectory(for: capture.id)
                try fileManager.createDirectory(at: files, withIntermediateDirectories: true)
                for (attachment, source) in zip(capture.attachments, attachmentFiles) {
                    try DurableFile.linkOrCopy(source, to: files.appendingPathComponent(attachment.relativePath))
                }
                try DurableFile.syncDirectory(files)
                try DurableFile.syncDirectory(captureDirectory)
            }
            try write(item)
        } catch {
            // Undo partial work, including a JSON that was renamed into place before its directory
            // sync failed. The caller keeps the draft. The staged originals were never touched.
            try? fileManager.removeItem(at: jsonURL(for: capture.id))
            try? fileManager.removeItem(at: captureDirectory)
            throw error
        }
        items[capture.id] = item
        lastSequence = item.sequence

        // Committed. The capture now lives here, so the staged originals can go.
        for source in attachmentFiles {
            do {
                try fileManager.removeItem(at: source)
            } catch {
                Logger.pipeline.error("Couldn't remove a staged attachment of \(capture.id, privacy: .public): \(error.loggableCode, privacy: .public)")
            }
        }
    }

    /// Everything not yet delivered, oldest first.
    public func pending() -> [OutboxItem] {
        loadIfNeeded()
        return items.values.sorted {
            ($0.capture.createdAt, $0.sequence) < ($1.capture.createdAt, $1.sequence)
        }
    }

    /// Removes a delivered capture and its files. The JSON goes first: once it's gone the capture
    /// counts as delivered, and leftover files are swept up on the next launch.
    public func markDelivered(_ id: UUID) throws {
        loadIfNeeded()
        let fileManager = FileManager.default
        let json = jsonURL(for: id)
        if fileManager.fileExists(atPath: json.path) {
            try fileManager.removeItem(at: json)
        }
        items[id] = nil
        do {
            try DurableFile.syncDirectory(directory)
        } catch {
            Logger.pipeline.error("Couldn't sync the outbox after delivering \(id, privacy: .public): \(error.loggableCode, privacy: .public)")
        }
        let captureDirectory = captureDirectory(for: id)
        if fileManager.fileExists(atPath: captureDirectory.path) {
            do {
                try fileManager.removeItem(at: captureDirectory)
            } catch {
                Logger.pipeline.error("Couldn't remove the files of \(id, privacy: .public): \(error.loggableCode, privacy: .public)")
            }
        }
    }

    /// Records a failed attempt. Memory is updated before the disk, so the backoff holds for this
    /// run even if the write fails.
    public func markFailed(_ id: UUID, error: String, nextAttemptAt: Date) throws {
        loadIfNeeded()
        guard var item = items[id] else {
            throw OutboxError.notFound(id)
        }
        item.attempts += 1
        item.lastError = error
        item.nextAttemptAt = nextAttemptAt
        items[id] = item
        try write(item)
    }

    // MARK: - Private

    private nonisolated func captureDirectory(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private nonisolated func jsonURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func write(_ item: OutboxItem) throws {
        try DurableFile.write(try encoder.encode(item), to: jsonURL(for: item.capture.id))
    }

    /// Reads the outbox from disk once, and sweeps what a kill can leave behind: temp files that
    /// were never renamed into place, and attachment folders with no JSON. Their staged originals
    /// still exist, or the capture was already delivered.
    private func loadIfNeeded() {
        guard !isLoaded else {
            return
        }
        let fileManager = FileManager.default
        let entries: [URL]
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        } catch {
            Logger.pipeline.error("Couldn't read the outbox: \(error.loggableCode, privacy: .public)")
            return
        }

        let jsonNames = Set(entries.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent })
        var loaded: [UUID: OutboxItem] = [:]
        for entry in entries {
            let name = entry.lastPathComponent
            if entry.pathExtension == "json" {
                do {
                    let item = try decoder.decode(OutboxItem.self, from: Data(contentsOf: entry))
                    loaded[item.capture.id] = item
                } catch {
                    // Never delete what can't be read; it may be a newer format.
                    Logger.pipeline.error("Skipping unreadable outbox entry \(name, privacy: .public): \(error.loggableCode, privacy: .public)")
                }
            } else if name.hasSuffix(".json.tmp") {
                try? fileManager.removeItem(at: entry)
            } else if
                UUID(uuidString: name) != nil,
                !jsonNames.contains(name),
                (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            {
                try? fileManager.removeItem(at: entry)
            }
        }

        // Keep anything enqueued before the load (only possible if an earlier load failed).
        items = loaded.merging(items) { _, current in current }
        lastSequence = max(lastSequence, items.values.map(\.sequence).max() ?? 0)
        isLoaded = true
        if !items.isEmpty {
            Logger.pipeline.info("Outbox has \(self.items.count, privacy: .public) pending capture(s)")
        }
    }

    private static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}

/// Atomic, `fsync`ed file operations for the outbox.
enum DurableFile {
    /// Writes `data` to a temp file in the same directory, `fsync`s it, renames it over `url`, then
    /// `fsync`s the directory. Readers see the old file or the new one, never a partial one.
    static func write(_ data: Data, to url: URL) throws {
        let temp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: temp)
            let handle = try FileHandle(forWritingTo: temp)
            defer { try? handle.close() }
            try handle.synchronize()
            guard rename(temp.path, url.path) == 0 else {
                throw POSIXError.current
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        try syncDirectory(url.deletingLastPathComponent())
    }

    /// Makes a directory's entries (new, renamed or removed files) durable.
    static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw POSIXError.current
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError.current
        }
    }

    /// Hard-links `source` at `target`, or copies it and `fsync`s the copy if linking fails
    /// (another volume).
    static func linkOrCopy(_ source: URL, to target: URL) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.linkItem(at: source, to: target)
        } catch {
            try fileManager.copyItem(at: source, to: target)
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            try handle.synchronize()
        }
    }
}

private extension POSIXError {
    static var current: POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
