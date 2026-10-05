import Foundation

/// One submitted note: the text, its attachments, when it was captured and where it goes
/// (ARCHITECTURE §3). It lives in the outbox until a destination accepts it.
public struct Capture: Codable, Identifiable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        case panel
        case clipboard
    }

    public let id: UUID
    public let createdAt: Date
    /// `TimeZone.current` at capture time, so delivery formats `createdAt` in the capture's
    /// local time rather than the time zone in effect when it's delivered.
    public let timeZoneIdentifier: String
    public var text: String
    /// The name given with `⌘S` save-as (T16). `nil` for an unnamed note: every `⌘↩`/`⇧⌘↩` save and
    /// every clipboard save. Outbox entries written before this field existed decode as `nil`.
    public var title: String?
    /// The file chosen in the `⌘S` Save panel (T16), written as it is, replacing a file already
    /// there (the Save panel asked first). `nil` lets the destination name the file.
    public var fileURL: URL?
    public var attachments: [Attachment]
    public var destinationID: DestinationID
    public var source: Source

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        timeZone: TimeZone = .current,
        text: String,
        title: String? = nil,
        fileURL: URL? = nil,
        attachments: [Attachment] = [],
        destinationID: DestinationID,
        source: Source
    ) {
        self.id = id
        self.createdAt = createdAt
        timeZoneIdentifier = timeZone.identifier
        self.text = text
        self.title = title
        self.fileURL = fileURL
        self.attachments = attachments
        self.destinationID = destinationID
        self.source = source
    }

    /// The time zone the note was captured in. Falls back to the current one if macOS no longer
    /// knows the stored identifier.
    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}
