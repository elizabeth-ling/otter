import Foundation

/// `obsidian://` links for opening a delivered note in Obsidian (ARCHITECTURE §5.2). The app adds
/// `open(_:)`, which falls back to Finder.
public enum ObsidianLink {
    /// `A–Z a–z 0–9 - . _ ~`. Everything else, including `/`, `&`, `=`, `#` and spaces, is
    /// percent-encoded.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `obsidian://open?vault=<name>&file=<path>`, with `.md` dropped from the path as Obsidian expects.
    ///
    /// - Parameter relativePath: The note's path inside the vault, e.g. `Inbox/Call Sam.md`.
    public static func openURL(vault: ObsidianVault, relativePath: String) -> URL {
        var file = relativePath
        if file.hasSuffix(".md") {
            file.removeLast(3)
        }
        let string = "obsidian://open?vault=\(encoded(vault.name))&file=\(encoded(file))"
        // Every character outside the unreserved set is encoded, so this always parses.
        return URL(string: string)!
    }

    private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
