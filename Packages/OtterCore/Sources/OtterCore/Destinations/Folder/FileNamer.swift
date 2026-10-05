import Foundation

/// Names new note files and checks paths from settings (ARCHITECTURE §5.1). Pure: no disk access.
///
/// Note text never reaches a path unsanitized: a title or template can only produce a single file
/// name, and a subfolder or append-file name that leaves the folder is rejected.
public enum FileNamer {
    public static let fallbackTitle = "Quick note"
    public static let maxTitleLength = 60
    /// Leaves room for a collision suffix and `.md` under APFS's 255-byte name limit.
    static let maxBaseNameBytes = 240

    /// Characters that are illegal in file names or break Obsidian links.
    private static let illegalCharacters: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]"]
    /// Line prefixes that are Markdown markup rather than words. `#` and `-` are stripped however
    /// many there are.
    private static let markerPrefixes = ["[ ] ", "[x] ", "[X] ", "* ", "> "]

    /// The note's first non-empty line, without Markdown markers or illegal characters, at most 60
    /// characters (cut at a word boundary when there is one). "Quick note" when nothing is left.
    public static func title(from text: String) -> String {
        guard let line = text.split(whereSeparator: \.isNewline).lazy.map(trimmed).first(where: { !$0.isEmpty }) else {
            return fallbackTitle
        }
        let title = truncated(sanitized(strippingMarkers(from: line)))
        return title.isEmpty ? fallbackTitle : title
    }

    /// The file name without its extension: `template` with `{date}` (`yyyy-MM-dd`), `{time}`
    /// (`HHmm`) and `{title}` filled in, in `timeZone`. Always one path component: illegal
    /// characters are removed from the template too, and leading dots are dropped so the file is
    /// never hidden.
    public static func baseName(template: String, text: String, date: Date, timeZone: TimeZone) -> String {
        let rendered = template
            .replacingOccurrences(of: "{date}", with: format(date, "yyyy-MM-dd", in: timeZone))
            .replacingOccurrences(of: "{time}", with: format(date, "HHmm", in: timeZone))
            .replacingOccurrences(of: "{title}", with: title(from: text))
        var name = trimmed(sanitized(rendered).drop { $0 == "." || $0.isWhitespace })
        while name.utf8.count > maxBaseNameBytes {
            name.removeLast()
        }
        name = trimmed(name)
        return name.isEmpty ? fallbackTitle : name
    }

    /// The name the `⌘S` Save panel offers (T16): `yyyy-MM-dd HHmm` in `timeZone`, which matches the
    /// default `{date} {time}` and is safe as a file name.
    public static func defaultTitle(for date: Date, in timeZone: TimeZone) -> String {
        format(date, "yyyy-MM-dd HHmm", in: timeZone)
    }

    /// The name to try for the `number`th file with this base: `base.md`, then on collisions
    /// `base 2.md`, `base 3.md`….
    public static func fileName(base: String, number: Int, pathExtension: String = "md") -> String {
        number <= 1 ? "\(base).\(pathExtension)" : "\(base) \(number).\(pathExtension)"
    }

    /// The components of a path from settings (a subfolder, an append-file name) that must stay
    /// inside the folder. `nil` if it's absolute, starts with `~`, contains `.` or `..`, or contains
    /// control characters. Empty for an empty path.
    public static func safeRelativePath(_ path: String) -> [String]? {
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains(where: isControl) else {
            return nil
        }
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else {
            return nil
        }
        return components
    }

    // MARK: - Private

    private static func strippingMarkers(from line: String) -> String {
        var line = line
        while true {
            let before = line
            line = String(line.drop { $0 == "#" || $0 == "-" })
            if let marker = markerPrefixes.first(where: line.hasPrefix) {
                line.removeFirst(marker.count)
            }
            line = trimmed(line)
            if line == before {
                return line
            }
        }
    }

    /// Removes illegal and control characters and collapses whitespace runs into one space.
    private static func sanitized(_ text: some StringProtocol) -> String {
        // Tabs and the like are whitespace as well as control characters: they become spaces.
        String(text.filter { !illegalCharacters.contains($0) && !(isControl($0) && !$0.isWhitespace) })
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// At most `maxTitleLength` characters, ending at a word boundary unless the first word alone
    /// is longer.
    private static func truncated(_ title: String) -> String {
        guard title.count > maxTitleLength else {
            return title
        }
        let cut = title.index(title.startIndex, offsetBy: maxTitleLength)
        let prefix = title[..<cut]
        if title[cut].isWhitespace {
            return trimmed(prefix)
        }
        if let space = prefix.lastIndex(where: \.isWhitespace) {
            return trimmed(prefix[..<space])
        }
        return String(prefix)
    }

    private static func isControl(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    private static func trimmed(_ text: some StringProtocol) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    static func format(_ date: Date, _ pattern: String, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
