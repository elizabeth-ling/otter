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
        // Until the panel lands (T03/T04).
        pipeline.captureService.onCaptured = {
            Logger.pipeline.info("Capture saved; the panel will clear its draft and hide here (T03/T04)")
        }
        pipeline.captureService.onCaptureFailed = { message in
            Logger.pipeline.error("Capture not saved; the panel will keep it open and show this in the footer (T03): \(message, privacy: .public)")
        }
        pipeline.start()
        capturePipeline = pipeline
    }

    private var statusItemController: StatusItemController?
    private var hotkeyService: HotkeyService?

    // Keep this minimal: it sits on the cold-launch path (ARCHITECTURE §9).
    // Later tasks register services here; anything slow must be deferred.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let hotkeys = HotkeyService()
        // Until the panel lands (T03), the toggle only proves the hotkey fires.
        hotkeys.onTogglePanel = {
            Logger.hotkey.info("Toggle panel hotkey pressed")
            NSSound.beep()
        }
        // Until clipboard capture lands (T11).
        hotkeys.onSaveClipboard = {
            Logger.hotkey.info("Save clipboard hotkey pressed")
        }
        hotkeys.start()
        hotkeyService = hotkeys

        statusItemController = StatusItemController(hotkeyWindowController: HotkeyWindowController(hotkeys: hotkeys))
    }
}
