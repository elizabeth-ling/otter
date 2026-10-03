import AppKit
import OtterCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
