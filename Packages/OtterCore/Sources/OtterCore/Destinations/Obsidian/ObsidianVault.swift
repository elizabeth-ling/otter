import Foundation

/// The Obsidian vault a folder sits in (ARCHITECTURE §5.2). A vault is any folder with a
/// `.obsidian/` directory; there's no separate Obsidian destination. Looked up fresh each time
/// rather than cached, so a folder moved into or out of a vault is followed. Never writes.
public struct ObsidianVault: Sendable, Equatable {
    static let configDirectoryName = ".obsidian"

    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// What `obsidian://` calls the vault: its root folder's name.
    public var name: String {
        root.lastPathComponent
    }

    var configDirectory: URL {
        root.appendingPathComponent(Self.configDirectoryName, isDirectory: true)
    }

    /// The nearest vault at or above `url`: walks up from `url` itself to the first folder with a
    /// `.obsidian` directory, so in a vault inside a vault the inner one wins. A `.obsidian` file
    /// doesn't count. `nil` outside any vault.
    public static func containing(_ url: URL) -> ObsidianVault? {
        var directory = url.standardizedFileURL
        while true {
            if isVaultRoot(directory) {
                return ObsidianVault(root: directory)
            }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            if parent.path == directory.path || directory.path == "/" {
                return nil
            }
            directory = parent
        }
    }

    /// Whether `directory` has a `.obsidian` directory.
    static func isVaultRoot(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let config = directory.appendingPathComponent(configDirectoryName, isDirectory: true)
        return FileManager.default.fileExists(atPath: config.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// `url`'s path inside the vault, `/`-separated with no leading slash, e.g. `Inbox/Note.md`.
    /// Empty for the root itself, `nil` outside the vault. Symlinks such as `/var` → `/private/var`
    /// are resolved on both sides first.
    public func relativePath(of url: URL) -> String? {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let components = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else {
            return nil
        }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
