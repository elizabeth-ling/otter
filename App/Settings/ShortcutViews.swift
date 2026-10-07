import KeyboardShortcuts
import OtterCore
import SwiftUI

/// The shortcut recorders' shared pieces, for Settings › General and onboarding's step 1. Replaces
/// T02's temporary Hotkey window. `@MainActor` because `Shortcut` isn't `Sendable`.
@MainActor
enum ShortcutText {
    static let commandSpace = KeyboardShortcuts.Shortcut(.space, modifiers: [.command])
    /// The suggested save-clipboard shortcut (UX_SPEC §2); it ships unset (ADR-011).
    static let suggestedSaveClipboard = KeyboardShortcuts.Shortcut(.space, modifiers: [.option, .shift])

    static func describe(_ combo: HotkeyCombo?) -> String {
        combo.map { "\(KeyboardShortcuts.Shortcut($0))" } ?? "None"
    }

    /// Why a recording was refused or may not work, or `nil` when it's fine.
    static func note(for validation: ShortcutValidation, otherAction: String) -> String? {
        switch validation {
        case .ok:
            nil
        case .duplicate:
            "\(otherAction) already uses that shortcut. Kept the previous one."
        case .reserved(.inputSourceSwitching):
            "macOS uses ⌃Space to switch input sources, so it may not reach Otter."
        case .reserved(.appSwitcher):
            "macOS uses ⌘⇥ for the app switcher, so it may not reach Otter."
        case .reserved(.emojiPicker):
            "macOS uses ⌃⌘Space for the emoji picker, so it may not reach Otter."
        }
    }
}

extension HotkeyService {
    /// The user chose `⌘Space`, whether or not Spotlight has let go of it yet.
    var choseCommandSpace: Bool {
        needsSpotlightHandoff || effectiveToggle.combo == .commandSpace
    }

    /// Records `⌘Space` without the recorder's "used by the system" alert: `⌘Space` gets the
    /// Spotlight handoff instead (ADR-011).
    func useCommandSpace() -> ShortcutValidation {
        KeyboardShortcuts.setShortcut(ShortcutText.commandSpace, for: .togglePanel)
        return shortcutDidChange(for: .togglePanel)
    }
}

/// An orange warning under a recorder.
struct ShortcutWarning: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
    }
}

/// The `⌘Space` handoff (ADR-011, UX_SPEC §6): what to change in System Settings, and the button
/// that opens it. `HotkeyService` re-checks whenever an app comes to the front.
struct SpotlightHandoffView: View {
    let hotkeys: HotkeyService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spotlight is using ⌘Space, so Otter uses ⌥Space for now. Uncheck “Show Spotlight search”, or change it to ⌥Space.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Keyboard Shortcuts…") {
                hotkeys.openSpotlightShortcutSettings()
            }
        }
    }
}
