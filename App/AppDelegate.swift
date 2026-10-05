import AppKit
import OtterCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var capturePipeline: CapturePipeline?

    /// Builds the capture pipeline before `applicationDidFinishLaunching`, so it already exists when
    /// the panel (T03) and the clipboard hotkey (T11) are wired to it there. It's cheap: no disk work,
    /// and the first outbox drain waits 1 s.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let pipeline = CapturePipeline()
        // The panel keeps the note open; showing `message` in its footer is still to come.
        pipeline.captureService.onCaptureFailed = { message in
            Logger.pipeline.error("Capture not saved; the panel will show this in the footer: \(message, privacy: .public)")
        }
        pipeline.start()
        capturePipeline = pipeline
    }

    private var statusItemController: StatusItemController?
    private var hotkeyService: HotkeyService?
    private var panelController: PanelController?

    // Keep this minimal: it sits on the cold-launch path (ARCHITECTURE §9).
    // Later tasks register services here; anything slow must be deferred.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Built once here and only ordered in and out (ARCHITECTURE §6).
        let destinations = capturePipeline?.destinations
        let captureService = capturePipeline?.captureService
        let folderChooser = capturePipeline.map { FolderChooser(destinations: $0.destinations, delivery: $0.delivery) }
        let panel = PanelController(
            draftStore: DraftStore(fileURL: StorageLocations.draft),
            attachmentStager: AttachmentStager(directory: StorageLocations.draftFiles)
        ) {
            guard let config = destinations?.defaultID.flatMap({ destinations?.config(for: $0) }) else {
                return PanelDestination(name: "No destination")
            }
            return PanelDestination(name: config.name, folderPath: config.folderDisplayPath, supportsAttachments: config.kind.supportsAttachments)
        } refreshDestination: {
            // A folder destination re-bookmarks a renamed folder here, which updates its name.
            guard let destination = destinations?.defaultID.flatMap({ destinations?.destination(for: $0) }) else {
                return
            }
            _ = await destination.healthCheck()
        } submit: { text, file, attachments in
            await captureService?.submit(text: text, saveAs: file, attachments: attachments) ?? false
        } chooseFolder: { window in
            await folderChooser?.chooseFolder(above: window) ?? false
        } chooseSaveFile: { window, defaultName in
            await SaveAsPrompt.chooseFile(above: window, in: folderChooser?.currentFolder(), defaultName: defaultName)
        }
        panelController = panel

        let hotkeys = HotkeyService()
        hotkeys.onTogglePanel = {
            panel.toggle()
        }
        // Until clipboard capture lands (T11).
        hotkeys.onSaveClipboard = {
            Logger.hotkey.info("Save clipboard hotkey pressed")
        }
        hotkeys.start()
        hotkeyService = hotkeys

        statusItemController = StatusItemController(
            hotkeyWindowController: HotkeyWindowController(hotkeys: hotkeys),
            panelController: panel,
            folderChooser: folderChooser,
            recents: capturePipeline?.recents
        )
    }

    /// Synchronous, so the draft is on disk before the process exits.
    func applicationWillTerminate(_ notification: Notification) {
        panelController?.flushDraft()
    }
}
