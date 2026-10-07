import Foundation

/// The menu bar's Recent submenu (UX_SPEC §4): the last deliveries, each "first line · destination · time".
public enum RecentMenu {
    /// Items shown. `RecentStore` keeps more.
    public static let count = 10
    /// The first line is cut to this many characters, "…" included, to keep the menu narrow.
    public static let maxFirstLineLength = 40
    /// For a note with no text, only attachments.
    public static let untitled = "Untitled note"

    /// "Call the dentist · Inbox · 5 min. ago". A delivery time in the future (the clock moved back)
    /// reads as now.
    public static func title(for recent: RecentCapture, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        let time = formatter.localizedString(for: min(recent.deliveredAt, now), relativeTo: now)
        return [firstLine(recent.firstLine), recent.destinationName, time].joined(separator: " · ")
    }

    static func firstLine(_ line: String) -> String {
        guard !line.isEmpty else {
            return untitled
        }
        guard line.count > maxFirstLineLength else {
            return line
        }
        return line.prefix(maxFirstLineLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
