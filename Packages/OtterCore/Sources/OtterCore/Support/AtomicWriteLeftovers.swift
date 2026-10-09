import Foundation

/// `Data.write(to:options: .atomic)` writes `<name>.sb-…` beside the file, then renames it into
/// place. A kill in between leaves that temp file behind, holding what was being written: for the
/// draft and the recents, note text. Found by the soak test (T14).
enum AtomicWriteLeftovers {
    /// Deletes `file`'s leftover temp files. Call where no atomic write to `file` can be running.
    static func remove(besides file: URL) {
        let directory = file.deletingLastPathComponent()
        let prefix = file.lastPathComponent + ".sb-"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return
        }
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
