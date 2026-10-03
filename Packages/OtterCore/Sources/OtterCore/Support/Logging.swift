import os

/// One logger per ARCHITECTURE §10 category. Never log note contents —
/// only capture IDs, byte counts, destination IDs and error codes.
public extension Logger {
    static let subsystem = "com.yourname.otter"

    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let folder = Logger(subsystem: subsystem, category: "folder")
    static let obsidian = Logger(subsystem: subsystem, category: "obsidian")
    static let notes = Logger(subsystem: subsystem, category: "notes")
}
