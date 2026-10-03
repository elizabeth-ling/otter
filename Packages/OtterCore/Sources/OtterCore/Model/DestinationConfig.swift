import Foundation

/// Identifies one configured destination. Stored as a UUID string.
public struct DestinationID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue.uuidString
    }
}

/// The kinds of destination Otter can build. T07 adds Obsidian, T08 adds Apple Notes.
public enum DestinationKind: String, Codable, Sendable, CaseIterable {
    case folder
}

/// One configured destination as the user set it up, persisted in `UserDefaults` by
/// `DestinationRegistry`. `id` and `name` are common to every kind, and `options` holds the rest.
public struct DestinationConfig: Codable, Identifiable, Sendable, Equatable {
    public enum Options: Codable, Sendable, Equatable {
        case folder(FolderOptions)
    }

    public var id: DestinationID
    /// Shown in the panel footer and the menu bar.
    public var name: String
    public var options: Options

    public init(id: DestinationID = DestinationID(), name: String, options: Options) {
        self.id = id
        self.name = name
        self.options = options
    }

    public var kind: DestinationKind {
        switch options {
        case .folder:
            .folder
        }
    }
}

/// Where a folder destination writes. T06 adds the write mode, templates and the rest.
public struct FolderOptions: Codable, Sendable, Equatable {
    /// Bookmark data rather than a path, so a moved or renamed folder keeps working.
    public var bookmark: Data
    /// For display only.
    public var displayPath: String

    public init(bookmark: Data, displayPath: String) {
        self.bookmark = bookmark
        self.displayPath = displayPath
    }
}
