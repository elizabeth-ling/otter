import AppKit
import OtterCore

/// Owns the menu bar item. AppKit `NSStatusItem` rather than SwiftUI `MenuBarExtra`
/// because T12 needs a badge state and a dynamic menu.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let recents: RecentStore?
    private let clipboardCapture: ClipboardCapture?
    private let openSettings: @MainActor () -> Void

    init(
        recents: RecentStore?,
        clipboardCapture: ClipboardCapture?,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.recents = recents
        self.openSettings = openSettings
        self.clipboardCapture = clipboardCapture
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Otter")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        // First, as in UX_SPEC §4 until T12 adds New Note above it. T12 adds the shortcut hints.
        if clipboardCapture != nil {
            let saveClipboardItem = menu.addItem(withTitle: "Save Clipboard", action: #selector(saveClipboard(_:)), keyEquivalent: "")
            saveClipboardItem.target = self
            menu.addItem(.separator())
        }
        #if DEBUG
        // Until the Recent menu lands (T12): checks `ObsidianLink.open` by hand (T07).
        if recents != nil {
            let openItem = menu.addItem(withTitle: "Open Last Note (Debug)", action: #selector(openLastNote(_:)), keyEquivalent: "")
            openItem.target = self
        }
        #endif
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Otter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showSettings(_ sender: Any?) {
        openSettings()
    }

    /// The same path as the save-clipboard hotkey (T11).
    @objc private func saveClipboard(_ sender: Any?) {
        clipboardCapture?.save()
    }

    #if DEBUG
    @objc private func openLastNote(_ sender: Any?) {
        Task { [recents] in
            guard case let .file(url)? = await recents?.recent().first?.location else {
                NSSound.beep()
                return
            }
            ObsidianLink.open(url)
        }
    }
    #endif
}
