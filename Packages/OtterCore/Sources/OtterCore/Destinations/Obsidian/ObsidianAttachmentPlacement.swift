import Foundation
import UniformTypeIdentifiers

/// Where an attachment goes in a vault and how the note links to it, following the vault's
/// `app.json` the way Obsidian would (ARCHITECTURE §5.2). Inside a vault this overrides
/// `FolderOptions.attachmentsFolder`. Pure: no disk access. T09 copies the file and adds the embed.
public struct ObsidianAttachmentPlacement: Sendable, Equatable {
    /// The folder to copy the attachment into. It may not exist yet.
    public let directory: URL
    /// What to add to the note: `![[name.png]]`, `![](assets/name.png)`, or `[name.pdf](…)` for a
    /// file that isn't an image.
    public let embed: String

    /// Characters that end or split a wikilink's target (`#` heading, `^` block, `|` alias).
    private static let wikilinkBreakers: Set<Character> = ["#", "^", "[", "]", "|"]

    /// - Parameters:
    ///   - notePath: The note's vault-relative path, e.g. `Inbox/2026-10-04 0912 Call Sam.md`.
    ///   - fileName: The attachment's file name, as it will be saved.
    public init(vault: ObsidianVault, settings: ObsidianVaultSettings, notePath: String, fileName: String) {
        let noteFolder = Array(notePath.split(separator: "/").map(String.init).dropLast())
        let folder = Self.attachmentFolder(settings.attachmentFolderPath, noteFolder: noteFolder)
        directory = folder.reduce(vault.root) { $0.appendingPathComponent($1, isDirectory: true) }

        let isImage = Self.isImage(fileName)
        let fromNote = Self.relativePath(from: noteFolder, to: folder + [fileName])
        let url = fromNote.map(Self.percentEncoded).joined(separator: "/")
        let markdownLink = isImage ? "![](\(url))" : "[\(Self.escapedLinkText(fileName))](\(url))"
        guard !settings.useMarkdownLinks, !fileName.contains(where: Self.wikilinkBreakers.contains) else {
            // A name with `#`, `^`, `[`, `]` or `|` can't be a wikilink target, so it gets a
            // Markdown link even in a wikilink vault; Obsidian resolves both.
            embed = markdownLink
            return
        }
        let target = switch settings.newLinkFormat {
        case .shortest:
            fileName
        case .absolute:
            (folder + [fileName]).joined(separator: "/")
        case .relative:
            fromNote.joined(separator: "/")
        }
        embed = "\(isImage ? "!" : "")[[\(target)]]"
    }

    // MARK: - Private

    /// The attachment folder's vault-relative components. A path with `..`, `~` or a leading `/`
    /// (other than `/` alone) falls back to the vault root rather than leaving the vault.
    private static func attachmentFolder(_ setting: String, noteFolder: [String]) -> [String] {
        if setting == "/" || setting.isEmpty {
            return []
        }
        if setting == "." {
            return noteFolder
        }
        if setting.hasPrefix("./") {
            guard let sub = FileNamer.safeRelativePath(String(setting.dropFirst(2))) else {
                return []
            }
            return noteFolder + sub
        }
        return FileNamer.safeRelativePath(setting) ?? []
    }

    /// The path from the folder `from` to `to`, both vault-relative, using `..` where needed.
    private static func relativePath(from: [String], to: [String]) -> [String] {
        var common = 0
        while common < from.count, common < to.count - 1, from[common] == to[common] {
            common += 1
        }
        return Array(repeating: "..", count: from.count - common) + to.dropFirst(common)
    }

    private static func isImage(_ fileName: String) -> Bool {
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
