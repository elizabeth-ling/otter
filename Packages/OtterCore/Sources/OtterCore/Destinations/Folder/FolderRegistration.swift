import Foundation

public extension DestinationFactory {
    /// Registers the `.folder` builder. `onBookmarkChange` saves a folder's re-created bookmark
    /// (it was renamed, or the default inbox was just created), usually through
    /// `DestinationRegistry.updateFolderBookmark`.
    mutating func registerFolder(onBookmarkChange: @escaping @Sendable (DestinationID, _ bookmark: Data, _ displayPath: String) -> Void) {
        register(.folder) { config in
            guard case let .folder(options) = config.options else {
                return nil
            }
            return FolderDestination(id: config.id, name: config.name, options: options) { bookmark, displayPath in
                onBookmarkChange(config.id, bookmark, displayPath)
            }
        }
    }
}

public extension DestinationConfig {
    static let defaultInboxName = "Otter Inbox"

    /// The folder a folder destination saves to, as shown in the panel header's tooltip (T17).
    /// `nil` for other kinds, whose name doesn't open the folder picker.
    var folderDisplayPath: String? {
        switch options {
        case let .folder(options):
            options.displayPath
        }
    }

    /// `~/Documents/Otter Inbox/`, one file per note. The folder is created on the first save.
    static func defaultInbox(documents: URL = .documentsDirectory) -> DestinationConfig {
        let folder = documents.appendingPathComponent(defaultInboxName, isDirectory: true)
        let options = FolderOptions(bookmark: Data(), displayPath: (folder.path as NSString).abbreviatingWithTildeInPath, fallbackPath: folder.path)
        return DestinationConfig(name: defaultInboxName, options: .folder(options))
    }
}

public extension DestinationRegistry {
    /// Adds the default inbox when nothing is configured, so the first note always has somewhere to go.
    func addDefaultInboxIfEmpty(documents: URL = .documentsDirectory) {
        guard configs.isEmpty else {
            return
        }
        add(.defaultInbox(documents: documents))
    }

    /// "Choose Folder…": points the default destination at `bookmark`'s folder if it's a folder
    /// destination, keeping its ID and settings so captures waiting for it follow. Otherwise adds a
    /// folder destination and makes it the default.
    @discardableResult
    func chooseFolder(bookmark: Data, displayPath: String, name: String) -> DestinationID {
        if let id = defaultID, case .folder = config(for: id)?.options {
            modify(id) { config in
                guard case var .folder(options) = config.options else {
                    return
                }
                options.bookmark = bookmark
                options.displayPath = displayPath
                options.fallbackPath = nil
                config.name = name
                config.options = .folder(options)
            }
            return id
        }
        let config = DestinationConfig(name: name, options: .folder(FolderOptions(bookmark: bookmark, displayPath: displayPath)))
        add(config)
        setDefault(config.id)
        return config.id
    }

    /// "Change Folder…" for one folder destination (the panel's destination menu, Settings): points
    /// it at `bookmark`'s folder, keeping its ID and settings so captures waiting for it follow. Its
    /// name follows the folder unless the user gave it one of their own. Does nothing for another kind.
    func setFolder(_ id: DestinationID, bookmark: Data, displayPath: String) {
        modify(id) { config in
            guard case var .folder(options) = config.options else {
                return
            }
            if config.name == (options.displayPath as NSString).lastPathComponent {
                config.name = (displayPath as NSString).lastPathComponent
            }
            options.bookmark = bookmark
            options.displayPath = displayPath
            options.fallbackPath = nil
            config.options = .folder(options)
        }
    }

    /// Saves a folder's re-created bookmark, leaving the rest of its settings alone. A name that's
    /// still the folder's old name follows a rename; one the user chose stays.
    func updateFolderBookmark(_ id: DestinationID, bookmark: Data, displayPath: String) {
        modify(id) { config in
            guard case var .folder(options) = config.options else {
                return
            }
            if config.name == (options.displayPath as NSString).lastPathComponent {
                config.name = (displayPath as NSString).lastPathComponent
            }
            options.bookmark = bookmark
            options.displayPath = displayPath
            config.options = .folder(options)
        }
    }
}
