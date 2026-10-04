import AppKit

/// Owns the menu bar item. AppKit `NSStatusItem` rather than SwiftUI `MenuBarExtra`
/// because T12 needs a badge state and a dynamic menu.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let hotkeyWindowController: HotkeyWindowController
    private let panelController: PanelController
    private let folderChooser: FolderChooser?

    init(hotkeyWindowController: HotkeyWindowController, panelController: PanelController, folderChooser: FolderChooser?) {
        self.hotkeyWindowController = hotkeyWindowController
        self.panelController = panelController
        self.folderChooser = folderChooser
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Otter")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        // Until destination settings land (T10).
        if let folderChooser {
            let folderItem = menu.addItem(withTitle: "Choose Folder…", action: #selector(FolderChooser.chooseFolder(_:)), keyEquivalent: "")
            folderItem.target = folderChooser
        }
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
}
