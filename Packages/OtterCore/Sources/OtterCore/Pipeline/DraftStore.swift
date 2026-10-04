import Foundation
import os

/// The note being written in the panel, kept so it survives a hide, a quit or a crash (T04).
public struct Draft: Codable, Sendable, Equatable {
    public var text: String
    /// Pasted files staged in `drafts/files/` (T09).
    public var attachmentRefs: [Attachment]
    public var updatedAt: Date

    public init(text: String, attachmentRefs: [Attachment] = [], updatedAt: Date = Date()) {
        self.text = text
        self.attachmentRefs = attachmentRefs
        self.updatedAt = updatedAt
    }

    /// Nothing worth keeping. Whitespace is kept: it's what the user typed.
    public var isEmpty: Bool {
        text.isEmpty && attachmentRefs.isEmpty
    }
}

/// Keeps the in-progress note in `drafts/current.json` (ARCHITECTURE §8).
///
/// The latest draft lives in memory, so reading it never touches the disk after the first `load()`.
/// Writes go to a serial background queue: `save` waits for a pause in typing, `saveNow` writes
/// straight away, and `flush` blocks until the disk matches memory (for quitting). Each write is
/// atomic, so a crash leaves the previous draft or the new one, never a torn file. An empty draft
/// deletes the file.
///
/// Thread-safe: call it from any thread.
public final class DraftStore: @unchecked Sendable {
    public static let defaultDebounce: Duration = .milliseconds(300)

    public let fileURL: URL
    private let debounce: Duration
    private let queue = DispatchQueue(label: "com.otter.drafts", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // Guarded by `lock`.
    private let lock = NSLock()
    private var cache: Draft?
    private var isLoaded = false
    /// Memory has changed since the last write.
    private var isDirty = false
    private var pendingWrite: DispatchWorkItem?

    public init(fileURL: URL, debounce: Duration = DraftStore.defaultDebounce) {
        self.fileURL = fileURL
        self.debounce = debounce
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// The latest draft, or `nil` if there's none. Reads the file on the first call only; an
    /// unreadable file counts as no draft.
    public func load() -> Draft? {
        lock.withLock {
            if !isLoaded {
                cache = readFile()
                isLoaded = true
            }
            return cache
        }
    }

    /// Remembers `draft` and writes it once nothing has changed for the debounce interval.
    public func save(_ draft: Draft) {
        lock.withLock {
            store(draft)
            scheduleWrite(after: debounce)
        }
    }

    /// Remembers `draft` and writes it without waiting (the panel hiding). Doesn't block.
    public func saveNow(_ draft: Draft) {
        lock.withLock {
            store(draft)
            scheduleWrite(after: nil)
        }
    }

    /// Forgets the draft and deletes the file. Doesn't block.
    public func clear() {
        lock.withLock {
            store(nil)
            scheduleWrite(after: nil)
        }
    }

    /// Blocks until any pending change is on disk. Call when the app quits.
    public func flush() {
        lock.withLock {
            pendingWrite?.cancel()
            pendingWrite = nil
        }
        queue.sync {
            writeIfDirty()
        }
    }

    // MARK: - Private

    /// Call with `lock` held.
    private func store(_ draft: Draft?) {
        cache = draft.flatMap { $0.isEmpty ? nil : $0 }
        isLoaded = true
        isDirty = true
    }

    /// Replaces any write still waiting. Call with `lock` held.
    private func scheduleWrite(after delay: Duration?) {
        pendingWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.writeIfDirty()
        }
        pendingWrite = item
        if let delay {
            queue.asyncAfter(deadline: .now() + delay.timeInterval, execute: item)
        } else {
            queue.async(execute: item)
        }
    }

    /// Runs on `queue`, so writes never overlap or land out of order.
    private func writeIfDirty() {
        let (isDirty, draft): (Bool, Draft?) = lock.withLock {
            defer { self.isDirty = false }
            return (self.isDirty, cache)
        }
        guard isDirty else {
            return
        }
        guard let draft else {
            deleteFile()
            return
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(draft).write(to: fileURL, options: .atomic)
        } catch {
            Logger.panel.error("Couldn't save the draft: \(error.loggableCode, privacy: .public)")
        }
    }

    private func deleteFile() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            Logger.panel.error("Couldn't delete the draft: \(error.loggableCode, privacy: .public)")
        }
    }

    private func readFile() -> Draft? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let draft = try decoder.decode(Draft.self, from: Data(contentsOf: fileURL))
            return draft.isEmpty ? nil : draft
        } catch {
            // Left in place: the next save overwrites it.
            Logger.panel.error("Couldn't read the draft: \(error.loggableCode, privacy: .public)")
            return nil
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
