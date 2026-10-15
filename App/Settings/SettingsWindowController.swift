import AppKit
import Observation
import SwiftUI

/// The Settings window (T10): SwiftUI in an `NSWindow` Otter controls, built on first use. It's an
/// ordinary window that activates Otter, since Otter is an agent app (ARCHITECTURE §6). The tabs
/// are a preference-style `NSToolbar`, centred with the icon over the label, and the window is
/// titled after the tab shown. On first run it shows onboarding instead, with the toolbar hidden
/// (UX_SPEC §6).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    @MainActor
    @Observable
    final class Router {
        enum Mode {
            case settings
            case onboarding
        }

        enum Tab: String, CaseIterable, Hashable {
            case general
            case shortcuts
            case destinations
            case advanced

            var title: String {
                switch self {
                case .general: "General"
                case .shortcuts: "Shortcuts"
                case .destinations: "Destinations"
                case .advanced: "Advanced"
                }
            }

            var symbolName: String {
                switch self {
                case .general: "gearshape"
                case .shortcuts: "keyboard"
                case .destinations: "folder"
                case .advanced: "slider.horizontal.3"
                }
            }

            var toolbarID: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }
        }

        var mode = Mode.settings
        var tab = Tab.general
    }

    private let model: SettingsModel
    private let onboarding: OnboardingModel
    private let router = Router()
    private var window: NSWindow?

    init(model: SettingsModel, onboarding: OnboardingModel) {
        self.model = model
        self.onboarding = onboarding
        super.init()
        onboarding.onFinish = { [weak self] in
            self?.window?.close()
        }
    }

    /// `⌘,` in the panel and "Settings…" in the menu bar. Brings onboarding back if it's open.
    func showSettings(tab: Router.Tab? = nil) {
        // Onboarding finished or was closed: the tabs replace it now, not while its window closed.
        if router.mode == .onboarding, window?.isVisible != true {
            router.mode = .settings
        }
        if let tab, router.mode == .settings {
            select(tab)
        }
        show()
    }

    /// First run.
    func showOnboarding() {
        router.mode = .onboarding
        onboarding.start()
        show()
    }

    /// The menu bar's "Finish setting up ⌘Space…": onboarding's hotkey step on its own (T12). First-run
    /// onboarding, if it's open, comes forward as it is.
    func showHotkeySetup() {
        if router.mode != .onboarding || window?.isVisible != true {
            router.mode = .onboarding
            onboarding.start(hotkeyOnly: true)
        }
        show()
    }

    /// The toggle hotkey fired. Onboarding's hotkey step uses the press, so the panel doesn't open.
    /// - Returns: Whether the press was used here.
    func handleTogglePress() -> Bool {
        guard router.mode == .onboarding, window?.isVisible == true else {
            return false
        }
        return onboarding.handleTogglePress()
    }

    // MARK: - NSWindowDelegate

    /// Leaves the content as it is: swapping onboarding for the tabs here would lay the tabs out in
    /// a closing window ("Invalid view geometry: width is negative"). `showSettings` swaps them.
    func windowWillClose(_ notification: Notification) {
        if router.mode == .onboarding {
            onboarding.windowWillClose()
        }
        model.windowWillClose()
    }

    // MARK: - Private

    private func select(_ tab: Router.Tab) {
        router.tab = tab
        window?.toolbar?.selectedItemIdentifier = tab.toolbarID
        updateTitle()
    }

    @objc private func toolbarItemClicked(_ item: NSToolbarItem) {
        Router.Tab(rawValue: item.itemIdentifier.rawValue).map(select)
    }

    private func updateTitle() {
        window?.title = switch router.mode {
        case .onboarding: onboarding.isHotkeyOnly ? "Finish Setting Up ⌘Space" : "Welcome to Otter"
        case .settings: router.tab.title
        }
    }

    private func show() {
        let window = window ?? makeWindow()
        window.toolbar?.isVisible = router.mode == .settings
        window.toolbar?.selectedItemIdentifier = router.tab.toolbarID
        updateTitle()
        model.window = window
        onboarding.window = window
        model.windowDidOpen()
        NSApp.activate()
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(router: router, model: model, onboarding: onboarding)
        let hosting = NSHostingController(rootView: root)
        // The window takes the size of the tab or step shown.
        hosting.sizingOptions = [.preferredContentSize]
        let window = SettingsWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        let toolbar = NSToolbar(identifier: "OtterSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }
}

// MARK: - NSToolbarDelegate

extension SettingsWindowController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = Router.Tab(rawValue: itemIdentifier.rawValue) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Router.Tab.allCases.map(\.toolbarID)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}

private struct SettingsRootView: View {
    let router: SettingsWindowController.Router
    let model: SettingsModel
    let onboarding: OnboardingModel

    var body: some View {
        switch router.mode {
        case .onboarding:
            OnboardingView(model: onboarding)
        case .settings:
            Group {
                switch router.tab {
                case .general:
                    GeneralSettingsView(model: model)
                case .shortcuts:
                    ShortcutsSettingsView(model: model)
                case .destinations:
                    DestinationsSettingsView(model: model)
                case .advanced:
                    AdvancedSettingsView(model: model)
                }
            }
            .frame(width: 700, height: 520)
        }
    }
}

/// `⌘W` closes it: an agent app's menu bar may have no File › Close for the key equivalent.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) {
            return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return false
    }
}
