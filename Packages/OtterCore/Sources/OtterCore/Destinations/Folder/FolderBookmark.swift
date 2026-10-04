import Foundation

/// Bookmark data for a chosen folder. Otter isn't sandboxed, but the bookmarks are security-scoped
/// anyway, so a later move to the sandbox is cheap (DECISIONS ADR-004).
public enum FolderBookmark {
    public static func make(for folder: URL) throws -> Data {
        do {
            return try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            return try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    /// Where the folder is now. `isStale` means it moved or was renamed, so the bookmark should be
    /// re-created. Never shows UI or mounts a volume: a delivery lane calls this.
    public static func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        } catch {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        }
    }

    /// The path the folder had when the bookmark was made.
    public static func originalPath(of bookmark: Data) -> String? {
        URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path
    }

    /// A folder deleted in Finder still resolves, to its place in the Trash.
    public static func isInTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}
