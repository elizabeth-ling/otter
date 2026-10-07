import Foundation
import OSLog
import OtterCore

/// "Reveal Logs" (Settings › Advanced): this run's Otter log lines, as a text file in `logs/`.
/// The log never holds note contents (ARCHITECTURE §10), so the file is safe to attach to a report.
enum LogExport {
    /// Writes the file and returns it. Reads the unified log, so call it off the main thread.
    static func write(to directory: URL, now: Date = Date()) throws -> URL {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(
            at: store.position(date: now.addingTimeInterval(-24 * 60 * 60)),
            matching: NSPredicate(format: "subsystem == %@", Logger.subsystem)
        )
        let timestamp = ISO8601DateFormatter()
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var text = ""
        for case let entry as OSLogEntryLog in entries {
            text += "\(timestamp.string(from: entry.date)) [\(entry.category)] \(name(of: entry.level)): \(entry.composedMessage)\n"
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = DateFormatter()
        fileName.locale = Locale(identifier: "en_US_POSIX")
        fileName.dateFormat = "yyyy-MM-dd HHmmss"
        let file = directory.appendingPathComponent("Otter \(fileName.string(from: now)).log")
        try Data(text.utf8).write(to: file, options: .atomic)
        return file
    }

    private static func name(of level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        case .undefined: "default"
        @unknown default: "default"
        }
    }
}
