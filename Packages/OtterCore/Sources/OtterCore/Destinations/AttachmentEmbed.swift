import Foundation
import UniformTypeIdentifiers

/// How a note links to an attachment with a Markdown link: `![](…)` embeds an image, `[name](…)`
/// links any other file (ARCHITECTURE §5.1, §5.2). Shared by plain folders and Obsidian vaults.
/// Pure: no disk access.
enum AttachmentEmbed {
    /// `components` is the path from the note's folder to the attachment, ending with its name.
    static func markdown(fileName: String, path components: [String]) -> String {
        let url = components.map(percentEncoded).joined(separator: "/")
        return isImage(fileName) ? "![](\(url))" : "[\(escapedLinkText(fileName))](\(url))"
    }

    /// Decided by the extension, so it matches what the note's reader (Obsidian, a Markdown
    /// previewer) will do with the link.
    static func isImage(_ fileName: String) -> Bool {
        let pathExtension = (fileName as NSString).pathExtension
        return UTType(filenameExtension: pathExtension)?.conforms(to: .image) ?? false
    }

    /// Percent-encodes everything but `A–Z a–z 0–9 - . _ ~`, so spaces, `#`, `(` and `)` can't end
    /// the link early.
    private static func percentEncoded(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: ObsidianLink.unreserved) ?? component
    }

    private static func escapedLinkText(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}
