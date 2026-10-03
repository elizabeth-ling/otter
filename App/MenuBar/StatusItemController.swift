import AppKit

/// Owns the menu bar item. AppKit `NSStatusItem` rather than SwiftUI `MenuBarExtra`
/// because T12 needs a badge state and a dynamic menu.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Otter")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Otter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}
