import Foundation
import os

/// One logger per ARCHITECTURE §10 category. Never log note contents —
/// only capture IDs, byte counts, destination IDs and error codes.
public extension Logger {
    static let subsystem = "io.github.elizabeth-ling.otter"

    /// The menu bar, notifications, the login item and other app lifecycle.
    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let folder = Logger(subsystem: subsystem, category: "folder")
    static let obsidian = Logger(subsystem: subsystem, category: "obsidian")
    static let notes = Logger(subsystem: subsystem, category: "notes")
}

public extension Error {
    /// Domain and code only, e.g. `NSCocoaErrorDomain 640`. Safe to log publicly: an error's
    /// description can contain a file name taken from the note's first line.
    var loggableCode: String {
        let error = self as NSError
        return "\(error.domain) \(error.code)"
    }
}
