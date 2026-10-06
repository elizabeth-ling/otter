import AppKit
import OtterCore

/// Owns the menu bar item. AppKit `NSStatusItem` rather than SwiftUI `MenuBarExtra`
/// because T12 needs a badge state and a dynamic menu.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let hotkeyWindowController: HotkeyWindowController
    private let panelController: PanelController
    private let folderChooser: FolderChooser?
    private let vaultMenu: ObsidianVaultMenu?
    private let recents: RecentStore?
    private let clipboardCapture: ClipboardCapture?

    init(
        hotkeyWindowController: HotkeyWindowController,
        panelController: PanelController,
        folderChooser: FolderChooser?,
        recents: RecentStore?,
        clipboardCapture: ClipboardCapture?
    ) {
        self.hotkeyWindowController = hotkeyWindowController
        self.panelController = panelController
        self.folderChooser = folderChooser
        vaultMenu = folderChooser.map(ObsidianVaultMenu.init(folderChooser:))
        self.recents = recents
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
        // Until destination settings land (T10).
        if let folderChooser {
            let folderItem = menu.addItem(withTitle: "Choose Folder…", action: #selector(FolderChooser.chooseFolder(_:)), keyEquivalent: "")
            folderItem.target = folderChooser
        }
        if let vaultMenu {
            let vaultItem = menu.addItem(withTitle: "Use Obsidian Vault", action: nil, keyEquivalent: "")
            vaultItem.submenu = vaultMenu.menu
        }
        #if DEBUG
        // Until the Recent menu lands (T12): checks `ObsidianLink.open` by hand (T07).
        if recents != nil {
            let openItem = menu.addItem(withTitle: "Open Last Note (Debug)", action: #selector(openLastNote(_:)), keyEquivalent: "")
            openItem.target = self
        }
        #endif
        // Temporary until Settings lands (T10).
        let hotkeyItem = menu.addItem(withTitle: "Hotkey…", action: #selector(NSWindowController.showWindow(_:)), keyEquivalent: "")
        hotkeyItem.target = hotkeyWindowController
        // Moves to Settings › General with T10.
        let resetItem = menu.addItem(withTitle: "Reset Panel Position", action: #selector(PanelController.resetPanelPosition(_:)), keyEquivalent: "")
        resetItem.target = panelController
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Otter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
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
