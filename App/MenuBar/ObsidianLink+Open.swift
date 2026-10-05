import AppKit
import OtterCore
import os

extension ObsidianLink {
    /// Opens a delivered note: in Obsidian when it's inside a vault and something handles
    /// `obsidian://`, otherwise selected in Finder. The vault is looked up now rather than at
    /// delivery, so a folder moved into or out of a vault since still opens the right way. Used by
    /// the Recent menu (T12).
    @MainActor
    static func open(_ fileURL: URL) {
        if let vault = ObsidianVault.containing(fileURL.deletingLastPathComponent()),
           let path = vault.relativePath(of: fileURL), !path.isEmpty {
            let url = openURL(vault: vault, relativePath: path)
            if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
                NSWorkspace.shared.open(url)
                return
            }
            Logger.obsidian.info("No app handles obsidian:// links; showing the note in Finder")
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
