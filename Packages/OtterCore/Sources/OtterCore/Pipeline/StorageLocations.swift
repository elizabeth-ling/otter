import Foundation

/// Where Otter keeps its files: `~/Library/Application Support/Otter/` (ARCHITECTURE §8).
/// Nothing is created here. Each store creates what it needs on first write, so launch does no disk work.
public enum StorageLocations {
    public static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Otter", isDirectory: true)
    }

    public static var outbox: URL {
        root.appendingPathComponent("outbox", isDirectory: true)
    }

    /// The in-progress note (T04). Pasted files are staged next to it in `drafts/files/` (T09).
    public static var draft: URL {
        root.appendingPathComponent("drafts", isDirectory: true).appendingPathComponent("current.json")
    }

    public static var recents: URL {
        root.appendingPathComponent("recent.json")
    }
}
