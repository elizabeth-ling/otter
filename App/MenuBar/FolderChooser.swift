import AppKit
import OtterCore
import os

/// "Choose Folder…" in the menu bar (T06): picks the folder notes are saved to. The minimal M0
/// setup until destination settings land (T10).
@MainActor
final class FolderChooser: NSObject {
    private let destinations: DestinationRegistry
    private let delivery: DeliveryService

    init(destinations: DestinationRegistry, delivery: DeliveryService) {
        self.destinations = destinations
        self.delivery = delivery
    }

    @objc func chooseFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Otter saves your notes to."
        if let current = currentFolder() {
            panel.directoryURL = current
        }

        // A menu-bar agent has to activate itself for the open panel to come to the front.
        NSApp.activate()
        guard panel.runModal() == .OK, let folder = panel.url else {
            return
        }
        use(folder)
    }

    // MARK: - Private

    private func use(_ folder: URL) {
        let bookmark: Data
        do {
            bookmark = try FolderBookmark.make(for: folder)
        } catch {
            Logger.folder.error("Couldn't bookmark the chosen folder: \(error.loggableCode, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Otter can't use that folder."
            alert.runModal()
            return
        }

        let name = FileManager.default.displayName(atPath: folder.path)
        let id = destinations.chooseFolder(bookmark: bookmark, displayPath: (folder.path as NSString).abbreviatingWithTildeInPath, name: name)
        Logger.folder.info("Destination \(id, privacy: .public) now saves to the chosen folder")
        // Captures that were waiting for a missing folder go now.
        Task { [delivery] in
            await delivery.kick()
        }
    }

    /// Where the default folder destination points now, so the panel opens there.
    private func currentFolder() -> URL? {
        guard let id = destinations.defaultID, case let .folder(options)? = destinations.config(for: id)?.options else {
            return nil
        }
        if !options.bookmark.isEmpty, let folder = try? FolderBookmark.resolve(options.bookmark).url {
            return folder
        }
        return options.fallbackPath.map { URL(fileURLWithPath: $0, isDirectory: true).deletingLastPathComponent() }
    }
}
