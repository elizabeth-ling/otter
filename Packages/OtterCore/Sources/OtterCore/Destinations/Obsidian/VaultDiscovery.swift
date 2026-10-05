import Foundation
import os

/// A vault Obsidian knows about, from its `obsidian.json`.
public struct DiscoveredVault: Identifiable, Sendable, Equatable {
    /// Obsidian's ID for the vault.
    public let id: String
    /// The root folder's name, which is also what Obsidian shows.
    public let name: String
    public let path: URL
    /// `nil` when Obsidian didn't record it.
    public let lastOpened: Date?
}

/// Lists the vaults Obsidian has opened, for the Add menu and onboarding (T10). Reads
/// `~/Library/Application Support/obsidian/obsidian.json`; never writes it.
public enum VaultDiscovery {
    public static var configURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("obsidian/obsidian.json")
    }

    /// Newest first. Skips vaults whose folder is gone or has no `.obsidian/` directory. Empty if
    /// the file is missing or malformed.
    public static func vaults(configURL: URL = configURL) -> [DiscoveredVault] {
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            if (error as? CocoaError)?.code != .fileReadNoSuchFile {
                Logger.obsidian.error("Couldn't read obsidian.json: \(error.loggableCode, privacy: .public)")
            }
            return []
        }
        guard let file = try? JSONDecoder().decode(ConfigFile.self, from: data) else {
            Logger.obsidian.error("obsidian.json isn't in the expected format")
            return []
        }
        return file.vaults
            .compactMap { id, entry -> DiscoveredVault? in
                guard let path = entry.path else {
                    return nil
                }
                let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
                guard ObsidianVault.isVaultRoot(root) else {
                    return nil
                }
                return DiscoveredVault(id: id, name: root.lastPathComponent, path: root, lastOpened: entry.ts.map { Date(timeIntervalSince1970: $0 / 1000) })
            }
            .sorted { lhs, rhs in
                switch (lhs.lastOpened, rhs.lastOpened) {
                case let (lhs?, rhs?) where lhs != rhs:
                    lhs > rhs
                case (.some, nil):
                    true
                case (nil, .some):
                    false
                default:
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
    }

    // MARK: - Private

    /// `{"vaults": {"<id>": {"path": "/Users/…/Notes", "ts": 1759000000000, "open": true}}}`, `ts`
    /// in milliseconds.
    private struct ConfigFile: Decodable {
        let vaults: [String: Entry]
    }

    /// Lenient, so one odd entry doesn't hide the others.
    private struct Entry: Decodable {
        let path: String?
        let ts: Double?

        private enum CodingKeys: String, CodingKey {
            case path, ts
        }

        init(from decoder: any Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            path = try? container?.decodeIfPresent(String.self, forKey: .path)
            ts = try? container?.decodeIfPresent(Double.self, forKey: .ts)
        }
    }
}
