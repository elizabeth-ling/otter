import AppKit
import KeyboardShortcuts
import Observation
import OtterCore
import os

// `@MainActor` because `Name` isn't `Sendable` (Swift 6 rejects it as a plain global), and creating
// one with a default writes UserDefaults and registers a Carbon hotkey, which belongs on main anyway.
extension KeyboardShortcuts.Name {
    /// The toggle shortcut the user chose. It backs the recorder and is never registered directly:
    /// `HotkeyService` registers the effective shortcut instead. A recorder for it must call
    /// `HotkeyService.shortcutDidChange(for:)`.
    /// Defaults to `⌥Space` (ADR-011); `⌘Space` is opt-in and gets the Spotlight handoff.
    @MainActor static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
    /// No default (UX_SPEC §2 suggests `⌥⇧Space`). A recorder for it must call `HotkeyService.shortcutDidChange(for:)`.
    @MainActor static let saveClipboard = Self("saveClipboard")
    /// What `HotkeyService` actually registers for the toggle: the user's choice, or the fallback.
    @MainActor fileprivate static let effectiveTogglePanel = Self("effectiveTogglePanel")
}

extension HotkeyCombo {
    init(_ shortcut: KeyboardShortcuts.Shortcut) {
        self.init(carbonKeyCode: shortcut.carbonKeyCode, carbonModifiers: shortcut.carbonModifiers)
    }
}

extension KeyboardShortcuts.Shortcut {
    init(_ combo: HotkeyCombo) {
        self.init(carbonKeyCode: combo.carbonKeyCode, carbonModifiers: combo.carbonModifiers)
    }
}

/// Owns Otter's global hotkeys (T02, ADR-010, ADR-011).
///
/// The user's toggle shortcut is a preference; what gets registered is the effective shortcut from
/// `EffectiveToggleHotkey`: the user's choice, or `⌥Space` if they chose `⌘Space` while Spotlight
/// still holds it. Spotlight is
/// re-checked whenever another app comes to the front, so freeing `⌘Space` in System Settings
/// takes effect without a relaunch. KeyboardShortcuts uses Carbon `RegisterEventHotKey`, which
/// needs no Accessibility or Input Monitoring permission.
@MainActor
@Observable
final class HotkeyService {
    static let fallbackToggle = KeyboardShortcuts.Shortcut(EffectiveToggleHotkey.fallback)

    /// Toggle-panel key-down. The panel controller decides what to do with `PanelToggleAction`.
    @ObservationIgnored var onTogglePanel: (@MainActor () -> Void)?
    /// Save-clipboard key-down.
    @ObservationIgnored var onSaveClipboard: (@MainActor () -> Void)?

    private(set) var spotlightState: SpotlightShortcutState = .unknown
    private(set) var effectiveToggle = EffectiveToggleHotkey(combo: nil)

    /// The user chose `⌘Space` but Spotlight still has it, so Otter is on `⌥Space` for now.
    /// Drives the onboarding step (T10) and the menu bar row (T12).
    var needsSpotlightHandoff: Bool { effectiveToggle.needsSpotlightHandoff }

    @ObservationIgnored private let probe = SpotlightShortcutProbe()
    @ObservationIgnored private var appActivationObserver: (any NSObjectProtocol)?
    /// Each name's last accepted shortcut, so a refused recording can be put back.
    @ObservationIgnored private var acceptedShortcuts: [KeyboardShortcuts.Name: HotkeyCombo] = [:]

    /// Registers the hotkeys. Call once at launch.
    func start() {
        spotlightState = probe.probe()
        applyRegistration(force: true)

        // Key-down, not key-up: it feels faster.
        KeyboardShortcuts.onKeyDown(for: .effectiveTogglePanel) { [weak self] in
            self?.toggleKeyDown()
        }
        KeyboardShortcuts.onKeyDown(for: .saveClipboard) { [weak self] in
            self?.onSaveClipboard?()
        }

        // Fires whenever any app comes to the front, e.g. the user leaving System Settings.
        // Otter itself is rarely active, so its own activation isn't enough. No polling.
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshSpotlightState()
            }
        }
    }

    /// Re-reads Spotlight's shortcut and re-registers if the answer changed. Cheap; call it when the
    /// panel or Settings opens.
    func refreshSpotlightState() {
        let state = probe.probe()
        guard state != spotlightState else {
            return
        }
        Logger.hotkey.info("Spotlight shortcut is now \(String(describing: state), privacy: .public)")
        spotlightState = state
        applyRegistration(force: false)
    }

    /// Call after a recorder changes `name`. Refuses (and reverts) a shortcut the other action
    /// already uses, then re-registers. The recorder shows a warning for `.reserved`.
    @discardableResult
    func shortcutDidChange(for name: KeyboardShortcuts.Name) -> ShortcutValidation {
        let other: KeyboardShortcuts.Name = name == .togglePanel ? .saveClipboard : .togglePanel
        let validation = ShortcutValidation(recorded: combo(for: name), other: combo(for: other))

        switch validation {
        case .duplicate:
            Logger.hotkey.warning("Refused \(name.rawValue, privacy: .public): \(other.rawValue, privacy: .public) already uses that shortcut")
            KeyboardShortcuts.setShortcut(acceptedShortcuts[name].map(KeyboardShortcuts.Shortcut.init), for: name)
        case .reserved(let reserved):
            Logger.hotkey.warning("\(name.rawValue, privacy: .public) is on a shortcut macOS reserves (\(String(describing: reserved), privacy: .public))")
        case .ok:
            break
        }

        applyRegistration(force: true)
        return validation
    }

    /// Opens System Settings › Keyboard, where Keyboard Shortcuts › Spotlight lives.
    func openSpotlightShortcutSettings() {
        let workspace = NSWorkspace.shared
        if
            let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
            workspace.open(url)
        {
            return
        }

        Logger.hotkey.error("Couldn't open Keyboard settings; opening System Settings instead")
        guard let systemSettings = workspace.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            Logger.hotkey.error("Couldn't find System Settings")
            return
        }
        workspace.openApplication(at: systemSettings, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Private

    private func toggleKeyDown() {
        // The panel controller begins the `hotkey→visible` signpost when the press shows the panel.
        onTogglePanel?()
        // "Re-probe when the panel opens", kept off the hotkey → visible path.
        Task { [weak self] in
            self?.refreshSpotlightState()
        }
    }

    private func combo(for name: KeyboardShortcuts.Name) -> HotkeyCombo? {
        KeyboardShortcuts.getShortcut(for: name).map(HotkeyCombo.init)
    }

    /// Registers the effective toggle shortcut. `force` re-registers even when the decision is
    /// unchanged, which a recording needs: the library may have registered or unregistered the
    /// chord behind our back.
    private func applyRegistration(force: Bool) {
        let chosen = combo(for: .togglePanel)
        let saveClipboard = combo(for: .saveClipboard)
        acceptedShortcuts = [.togglePanel: chosen, .saveClipboard: saveClipboard].compactMapValues { $0 }

        let decision = EffectiveToggleHotkey.resolve(chosen: chosen, spotlight: spotlightState, saveClipboard: saveClipboard)
        guard force || decision != effectiveToggle else {
            return
        }
        effectiveToggle = decision

        // KeyboardShortcuts registers a name's shortcut whenever it is written (the default on first
        // launch, every recording). The preference must never be live next to the fallback, so only
        // the internal name stays registered. Order matters: they can share a chord.
        KeyboardShortcuts.disable(.togglePanel)
        KeyboardShortcuts.setShortcut(decision.combo.map(KeyboardShortcuts.Shortcut.init), for: .effectiveTogglePanel)
        // Unregistering above can drop a chord the save-clipboard shortcut shared mid-recording.
        // Registering is idempotent.
        KeyboardShortcuts.enable(.saveClipboard)

        logRegistration(decision)
    }

    /// KeyboardShortcuts doesn't surface `RegisterEventHotKey` errors, and a chord macOS owns
    /// (Spotlight's `⌘Space`) registers fine but never fires. So log what was registered and why.
    private func logRegistration(_ decision: EffectiveToggleHotkey) {
        let shortcut = decision.combo.map { "\(KeyboardShortcuts.Shortcut($0))" } ?? "none"
        let spotlight = String(describing: spotlightState)
        Logger.hotkey.info("Toggle hotkey: \(shortcut, privacy: .public) (Spotlight \(spotlight, privacy: .public), handoff needed: \(decision.needsSpotlightHandoff, privacy: .public))")

        if decision.needsSpotlightHandoff, decision.combo == .commandSpace {
            Logger.hotkey.warning("Save clipboard uses the ⌥Space fallback; the toggle waits for ⌘Space")
        }
        if decision.needsPressToConfirm {
            Logger.hotkey.notice("Couldn't read Spotlight's shortcut; registered ⌘Space unconfirmed")
        }
    }
}
