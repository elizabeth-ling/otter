import AppKit

/// Owns the menu bar item. AppKit `NSStatusItem` rather than SwiftUI `MenuBarExtra`
/// because T12 needs a badge state and a dynamic menu.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let hotkeyWindowController: HotkeyWindowController

    init(hotkeyWindowController: HotkeyWindowController) {
        self.hotkeyWindowController = hotkeyWindowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Otter")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        // Temporary until Settings lands (T10).
        let hotkeyItem = menu.addItem(withTitle: "Hotkey…", action: #selector(NSWindowController.showWindow(_:)), keyEquivalent: "")
        hotkeyItem.target = hotkeyWindowController
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Otter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}
