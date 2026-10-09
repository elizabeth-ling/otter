import Foundation

/// Where Otter keeps its files: `~/Library/Application Support/Otter/` (ARCHITECTURE §8).
/// Nothing is created here. Each store creates what it needs on first write, so launch does no disk work.
public enum StorageLocations {
    /// Replaces `root` for the soak test and the benchmarks (T14), so they never touch the user's
    /// outbox or draft. Set once at launch, before any store is created; `nil` in a normal run.
    public nonisolated(unsafe) static var rootOverride: URL?

    public static var root: URL {
        rootOverride ?? URL.applicationSupportDirectory.appendingPathComponent("Otter", isDirectory: true)
    }

    public static var outbox: URL {
        root.appendingPathComponent("outbox", isDirectory: true)
    }

    /// The in-progress note (T04).
    public static var draft: URL {
        drafts.appendingPathComponent("current.json")
    }

    /// The in-progress note's attachments, until it's submitted (T09).
    public static var draftFiles: URL {
        drafts.appendingPathComponent("files", isDirectory: true)
    }

    private static var drafts: URL {
        root.appendingPathComponent("drafts", isDirectory: true)
    }

    public static var recents: URL {
        root.appendingPathComponent("recent.json")
    }

    /// Logs exported from Settings › Advanced › Reveal Logs. `os.Logger` is the real log (§10).
    public static var logs: URL {
        root.appendingPathComponent("logs", isDirectory: true)
    }
}
