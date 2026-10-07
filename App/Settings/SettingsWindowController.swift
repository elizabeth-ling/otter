import AppKit
import Observation
import SwiftUI

/// The Settings window (T10): SwiftUI in an `NSWindow` Otter controls, built on first use. It's an
/// ordinary window that activates Otter, since Otter is an agent app (ARCHITECTURE §6). On first
/// run it shows onboarding instead of the tabs (UX_SPEC §6).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    @MainActor
    @Observable
    final class Router {
        enum Mode {
            case settings
            case onboarding
        }

        enum Tab: Hashable {
            case general
            case destinations
            case advanced
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
            router.tab = tab
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

    private func show() {
        let window = window ?? makeWindow()
        window.title = switch router.mode {
        case .onboarding: onboarding.isHotkeyOnly ? "Finish Setting Up ⌘Space" : "Welcome to Otter"
        case .settings: "Otter Settings"
        }
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
        let hosting = NSHostingController(rootView: SettingsRootView(router: router, model: model, onboarding: onboarding))
        // The window takes the size of the tab or step shown.
        hosting.sizingOptions = [.preferredContentSize]
        let window = SettingsWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }
}

private struct SettingsRootView: View {
    @Bindable var router: SettingsWindowController.Router
    let model: SettingsModel
    let onboarding: OnboardingModel

    var body: some View {
        switch router.mode {
        case .onboarding:
            OnboardingView(model: onboarding)
        case .settings:
            TabView(selection: $router.tab) {
                GeneralSettingsView(model: model)
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsWindowController.Router.Tab.general)
                DestinationsSettingsView(model: model)
                    .tabItem { Label("Destinations", systemImage: "folder") }
                    .tag(SettingsWindowController.Router.Tab.destinations)
                AdvancedSettingsView(model: model)
                    .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                    .tag(SettingsWindowController.Router.Tab.advanced)
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
