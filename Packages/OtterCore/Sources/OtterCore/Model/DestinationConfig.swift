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

/// Where and how a folder destination writes (ARCHITECTURE §5.1). Decoding fills in defaults for
/// missing keys, so settings saved by an older version keep loading.
public struct FolderOptions: Codable, Sendable, Equatable {
    public enum Mode: Codable, Sendable, Equatable {
        case newFilePerNote
        /// `name` is relative to the folder (and `subfolder`), e.g. `Inbox.md`. `.md` is added when
        /// it has no extension.
        case appendToFile(name: String)
    }

    public static let defaultFilenameTemplate = "{date} {time} {title}"

    /// Bookmark data rather than a path, so a moved or renamed folder keeps working. Empty until the
    /// folder exists when `fallbackPath` is set.
    public var bookmark: Data
    /// For display only.
    public var displayPath: String
    /// Where to create the folder when there's no bookmark yet, or when it's gone: only the default
    /// inbox has one. The folder is bookmarked once it's created.
    public var fallbackPath: String?
    public var mode: Mode
    /// Relative to the folder, e.g. `Inbox`. Created on first write.
    public var subfolder: String?
    /// `{date}`, `{time}` and `{title}`; see `FileNamer`.
    public var filenameTemplate: String
    public var frontmatter: Bool
    /// See `AppendTemplate`.
    public var appendTemplate: String
    /// Relative to the note's folder. Used by T09.
    public var attachmentsFolder: String

    public init(
        bookmark: Data,
        displayPath: String,
        fallbackPath: String? = nil,
        mode: Mode = .newFilePerNote,
        subfolder: String? = nil,
        filenameTemplate: String = FolderOptions.defaultFilenameTemplate,
        frontmatter: Bool = true,
        appendTemplate: String = AppendTemplate.default,
        attachmentsFolder: String = "attachments"
    ) {
        self.bookmark = bookmark
        self.displayPath = displayPath
        self.fallbackPath = fallbackPath
        self.mode = mode
        self.subfolder = subfolder
        self.filenameTemplate = filenameTemplate
        self.frontmatter = frontmatter
        self.appendTemplate = appendTemplate
        self.attachmentsFolder = attachmentsFolder
    }

    private enum CodingKeys: String, CodingKey {
        case bookmark, displayPath, fallbackPath, mode, subfolder, filenameTemplate, frontmatter, appendTemplate, attachmentsFolder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FolderOptions(bookmark: Data(), displayPath: "")
        bookmark = try container.decode(Data.self, forKey: .bookmark)
        displayPath = try container.decode(String.self, forKey: .displayPath)
        fallbackPath = try container.decodeIfPresent(String.self, forKey: .fallbackPath)
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? defaults.mode
        subfolder = try container.decodeIfPresent(String.self, forKey: .subfolder)
        filenameTemplate = try container.decodeIfPresent(String.self, forKey: .filenameTemplate) ?? defaults.filenameTemplate
        frontmatter = try container.decodeIfPresent(Bool.self, forKey: .frontmatter) ?? defaults.frontmatter
        appendTemplate = try container.decodeIfPresent(String.self, forKey: .appendTemplate) ?? defaults.appendTemplate
        attachmentsFolder = try container.decodeIfPresent(String.self, forKey: .attachmentsFolder) ?? defaults.attachmentsFolder
    }
}
