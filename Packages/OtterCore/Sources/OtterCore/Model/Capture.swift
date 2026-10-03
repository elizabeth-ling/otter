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
    public var attachments: [Attachment]
    public var destinationID: DestinationID
    public var source: Source

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        timeZone: TimeZone = .current,
        text: String,
        attachments: [Attachment] = [],
        destinationID: DestinationID,
        source: Source
    ) {
        self.id = id
        self.createdAt = createdAt
        timeZoneIdentifier = timeZone.identifier
        self.text = text
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
