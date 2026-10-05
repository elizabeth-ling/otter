import AppKit
import OtterCore
import os

/// Picks the folder notes are saved to, from "Choose Folder…" in the menu bar (T06) and from the
/// folder name in the panel header (T17). The minimal setup until destination settings land (T10).
@MainActor
final class FolderChooser: NSObject {
    private let destinations: DestinationRegistry
    private let delivery: DeliveryService
    private var openPanel: NSOpenPanel?

    init(destinations: DestinationRegistry, delivery: DeliveryService) {
        self.destinations = destinations
        self.delivery = delivery
    }

    /// The menu bar item.
    @objc func chooseFolder(_ sender: Any?) {
        Task {
            await chooseFolder(above: nil)
        }
    }

    /// Shows the folder picker and, on Choose, points the default folder destination at the folder.
    /// Activates Otter, because a menu-bar agent's open panel only comes to the front that way.
    ///
    /// - Parameter window: The capture panel, when the picker is opened from it. The picker opens on
    ///   its screen and above it, since the panel floats.
    /// - Returns: Whether the folder changed. `false` for Cancel, or if a picker is already open.
    @discardableResult
    func chooseFolder(above window: NSWindow?) async -> Bool {
        if let openPanel {
            openPanel.makeKeyAndOrderFront(nil)
            return false
        }
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
        if let window {
            panel.level = max(window.level, .modalPanel)
            if let screen = window.screen {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.midY - panel.frame.height / 2))
            }
        }

        openPanel = panel
        defer { openPanel = nil }
        NSApp.activate()
        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }
        guard response == .OK, let folder = panel.url else {
            return false
        }
        return use(folder)
    }

    /// Points the default folder destination at `folder`, as Choose does. Also used by "Use Obsidian
    /// Vault ▸" (T07), so a vault is just another folder.
    @discardableResult
    func use(_ folder: URL) -> Bool {
        let bookmark: Data
        do {
            bookmark = try FolderBookmark.make(for: folder)
        } catch {
            Logger.folder.error("Couldn't bookmark the chosen folder: \(error.loggableCode, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Otter can't use that folder."
            // Above the capture panel, which floats.
            alert.window.level = .modalPanel
            alert.runModal()
            return false
        }

        let name = FileManager.default.displayName(atPath: folder.path)
        let id = destinations.chooseFolder(bookmark: bookmark, displayPath: (folder.path as NSString).abbreviatingWithTildeInPath, name: name)
        Logger.folder.info("Destination \(id, privacy: .public) now saves to the chosen folder")
        // Captures that were waiting for a missing folder go now.
        Task { [delivery] in
            await delivery.kick()
        }
        return true
    }

    // MARK: - Private

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
