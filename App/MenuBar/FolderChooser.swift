import AppKit
import OtterCore
import os

/// Picks the folder a folder destination saves to: "Change Folder…" in the panel header's menu
/// (T17), the folder buttons and fixes in Settings, and onboarding (T10). Also adds folder
/// destinations from Settings' Add menu.
@MainActor
final class FolderChooser {
    /// Where the folder picker appears.
    enum Presentation {
        /// In its own window. From the capture panel, which floats, it opens on the panel's screen
        /// and above it.
        case window(above: NSWindow?)
        /// As a sheet on a Settings or onboarding window.
        case sheet(on: NSWindow)
    }

    private let destinations: DestinationRegistry
    private let delivery: DeliveryService
    private var openPanel: NSOpenPanel?

    init(destinations: DestinationRegistry, delivery: DeliveryService) {
        self.destinations = destinations
        self.delivery = delivery
    }

    /// Shows the folder picker and, on Choose, points destination `id` at the folder; `nil` is the
    /// default destination, as onboarding uses it.
    ///
    /// - Returns: Whether the folder changed. `false` for Cancel, or if a picker is already open.
    @discardableResult
    func chooseFolder(for id: DestinationID?, presentation: Presentation) async -> Bool {
        guard let folder = await pickFolder(startingAt: currentFolder(for: id), presentation: presentation) else {
            return false
        }
        return use(folder, for: id)
    }

    /// Shows the folder picker, starting at `directory`. Activates Otter, because a menu-bar agent's
    /// open panel only comes to the front that way.
    ///
    /// - Returns: The folder chosen. `nil` for Cancel, or if a picker is already open (that one is
    ///   brought forward).
    func pickFolder(startingAt directory: URL?, prompt: String = "Choose", presentation: Presentation) async -> URL? {
        if let openPanel {
            NSApp.activate()
            openPanel.makeKeyAndOrderFront(nil)
            return nil
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = "Choose the folder Otter saves your notes to."
        if let directory {
            panel.directoryURL = directory
        }

        openPanel = panel
        defer { openPanel = nil }
        NSApp.activate()
        let response: NSApplication.ModalResponse
        switch presentation {
        case let .window(above: window):
            if let window {
                panel.level = max(window.level, .modalPanel)
                if let screen = window.screen {
                    panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.midY - panel.frame.height / 2))
                }
            }
            response = await withCheckedContinuation { continuation in
                panel.begin { response in
                    continuation.resume(returning: response)
                }
            }
        case let .sheet(on: window):
            response = await panel.beginSheetModal(for: window)
        }
        guard response == .OK else {
            return nil
        }
        return panel.url
    }

    /// Points destination `id` at `folder`, or the default destination for `nil` (a vault picked in
    /// onboarding is just another folder, T07). Captures waiting for it go now.
    @discardableResult
    func use(_ folder: URL, for id: DestinationID?) -> Bool {
        guard let bookmark = bookmark(for: folder) else {
            return false
        }
        let displayPath = Self.displayPath(of: folder)
        let changed: DestinationID
        if let id {
            destinations.setFolder(id, bookmark: bookmark, displayPath: displayPath)
            changed = id
        } else {
            changed = destinations.chooseFolder(bookmark: bookmark, displayPath: displayPath, name: FileManager.default.displayName(atPath: folder.path))
        }
        Logger.folder.info("Destination \(changed, privacy: .public) now saves to the chosen folder")
        kick()
        return true
    }

    /// Settings' Add menu: a new folder destination at the end of the list, named after the folder
    /// unless `name` is given (a vault's name).
    func addDestination(at folder: URL, name: String? = nil) -> DestinationID? {
        guard let bookmark = bookmark(for: folder) else {
            return nil
        }
        let options = FolderOptions(bookmark: bookmark, displayPath: Self.displayPath(of: folder))
        let config = DestinationConfig(name: name ?? FileManager.default.displayName(atPath: folder.path), options: .folder(options))
        destinations.add(config)
        Logger.folder.info("Added destination \(config.id, privacy: .public)")
        kick()
        return config.id
    }

    /// Where folder destination `id` (`nil`: the default) points now, so the folder picker and the
    /// `⌘S` Save panel (T16) open there. The default inbox's parent until the first save creates it.
    func currentFolder(for id: DestinationID?) -> URL? {
        guard let id = id ?? destinations.defaultID, case let .folder(options)? = destinations.config(for: id)?.options else {
            return nil
        }
        if !options.bookmark.isEmpty, let folder = try? FolderBookmark.resolve(options.bookmark).url {
            return folder
        }
        return options.fallbackPath.map { URL(fileURLWithPath: $0, isDirectory: true).deletingLastPathComponent() }
    }

    // MARK: - Private

    private func bookmark(for folder: URL) -> Data? {
        do {
            return try FolderBookmark.make(for: folder)
        } catch {
            Logger.folder.error("Couldn't bookmark the chosen folder: \(error.loggableCode, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Otter can't use that folder."
            // Above the capture panel, which floats.
            alert.window.level = .modalPanel
            alert.runModal()
            return nil
        }
    }

    private func kick() {
        Task { [delivery] in
            await delivery.kick()
        }
    }

    private static func displayPath(of folder: URL) -> String {
        (folder.path as NSString).abbreviatingWithTildeInPath
    }
}
