import Foundation
import os

/// The parts of a vault's `.obsidian/app.json` that decide where attachments go and how links are
/// written (ARCHITECTURE §5.2). Read at each delivery rather than cached, so a change made in
/// Obsidian applies without relaunching Otter; the file is tiny. Never writes.
public struct ObsidianVaultSettings: Sendable, Equatable {
    /// Obsidian's "New link format".
    public enum LinkFormat: String, Sendable, Equatable {
        case shortest
        case relative
        case absolute
    }

    /// Obsidian's defaults, used for a missing file and for any key that's missing or of the wrong type.
    public static let defaults = ObsidianVaultSettings()

    /// `/` = vault root, `./` = the note's folder, `./sub` = `sub` under the note's folder, anything
    /// else = relative to the vault root. See `ObsidianAttachmentPlacement`.
    public var attachmentFolderPath: String
    /// `false` = wikilinks (`![[x.png]]`), `true` = Markdown links (`![](x.png)`).
    public var useMarkdownLinks: Bool
    public var newLinkFormat: LinkFormat

    public init(attachmentFolderPath: String = "/", useMarkdownLinks: Bool = false, newLinkFormat: LinkFormat = .shortest) {
        self.attachmentFolderPath = attachmentFolderPath
        self.useMarkdownLinks = useMarkdownLinks
        self.newLinkFormat = newLinkFormat
    }

    /// Parses `app.json`. Each key falls back to its default on its own when it's missing or of the
    /// wrong type; a file that isn't a JSON object gives all defaults.
    public init(appJSON data: Data) {
        self = (try? JSONDecoder().decode(AppJSON.self, from: data))?.settings ?? .defaults
    }

    /// Reads `<vault>/.obsidian/app.json`. Defaults if it's missing or can't be read.
    public static func load(from vault: ObsidianVault) -> ObsidianVaultSettings {
        let file = vault.configDirectory.appendingPathComponent("app.json")
        do {
            return ObsidianVaultSettings(appJSON: try Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .defaults
        } catch {
            Logger.obsidian.error("Couldn't read the vault's app.json: \(error.loggableCode, privacy: .public)")
            return .defaults
        }
    }

    // MARK: - Private

    private struct AppJSON: Decodable {
        let settings: ObsidianVaultSettings

        private enum CodingKeys: String, CodingKey {
            case attachmentFolderPath, useMarkdownLinks, newLinkFormat
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var settings = ObsidianVaultSettings.defaults
            if let path = try? container.decodeIfPresent(String.self, forKey: .attachmentFolderPath) {
                // Older vaults store the root as an empty string.
                settings.attachmentFolderPath = path.isEmpty ? "/" : path
            }
            if let markdown = try? container.decodeIfPresent(Bool.self, forKey: .useMarkdownLinks) {
                settings.useMarkdownLinks = markdown
            }
            if let format = (try? container.decodeIfPresent(String.self, forKey: .newLinkFormat)).flatMap(LinkFormat.init(rawValue:)) {
                settings.newLinkFormat = format
            }
            self.settings = settings
        }
    }
}
