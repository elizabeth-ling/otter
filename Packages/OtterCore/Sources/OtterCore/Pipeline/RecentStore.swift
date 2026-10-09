import Foundation
import os

/// One delivered capture in the Recent menu (T12).
public struct RecentCapture: Codable, Identifiable, Sendable, Equatable {
    /// The capture's ID.
    public var id: UUID
    /// The note's first non-empty line, at most `RecentStore.maxFirstLineLength` characters.
    public var firstLine: String
    public var destinationName: String
    public var location: DeliveryReceipt.Location
    public var deliveredAt: Date
}

/// The last 20 deliveries, newest first, kept in `recent.json` (ARCHITECTURE §8).
/// The file holds the start of each note, so turning recents off also deletes it.
public actor RecentStore {
    public static let capacity = 20
    public static let maxFirstLineLength = 80

    public nonisolated let fileURL: URL
    public private(set) var isEnabled: Bool

    /// Read lazily, on first use.
    private var cache: [RecentCapture]?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, isEnabled: Bool = true) {
        self.fileURL = fileURL
        self.isEnabled = isEnabled
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Newest first. Empty while disabled.
    public func recent() -> [RecentCapture] {
        isEnabled ? load() : []
    }

    public func record(_ capture: Capture, receipt: DeliveryReceipt, destinationName: String) {
        guard isEnabled else {
            return
        }
        let entry = RecentCapture(
            id: capture.id,
            firstLine: Self.firstLine(of: capture.text),
            destinationName: destinationName,
            location: receipt.location,
            deliveredAt: receipt.deliveredAt
        )
        var entries = load()
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        save(Array(entries.prefix(Self.capacity)))
    }

    /// Turning recents off clears them.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            clear()
        }
    }

    public func clear() {
        cache = []
        AtomicWriteLeftovers.remove(besides: fileURL)
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            Logger.pipeline.error("Couldn't delete the recent captures: \(error.loggableCode, privacy: .public)")
        }
    }

    /// The first non-empty line, trimmed. A line longer than `maxFirstLineLength` is cut and ends
    /// in "…", so the result always fits.
    public static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard line.count > maxFirstLineLength else {
            return line
        }
        return line.prefix(maxFirstLineLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Private

    private func load() -> [RecentCapture] {
        if let cache {
            return cache
        }
        // Actor-isolated like `save`, so no write is running.
        AtomicWriteLeftovers.remove(besides: fileURL)
        var entries: [RecentCapture] = []
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                entries = try decoder.decode([RecentCapture].self, from: Data(contentsOf: fileURL))
            } catch {
                // Not worth keeping: the next delivery rewrites it.
                Logger.pipeline.error("Couldn't read the recent captures: \(error.loggableCode, privacy: .public)")
            }
        }
        cache = entries
        return entries
    }

    private func save(_ entries: [RecentCapture]) {
        cache = entries
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            Logger.pipeline.error("Couldn't save the recent captures: \(error.loggableCode, privacy: .public)")
        }
    }
}
