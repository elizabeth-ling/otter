import AppKit
import KeyboardShortcuts
import OtterCore
import SwiftUI

/// Temporary "Hotkey…" window with recorders for both shortcuts (T02 scope 8).
/// The Settings window replaces it in T10.
final class HotkeyWindowController: NSWindowController {
    private let hotkeys: HotkeyService

    init(hotkeys: HotkeyService) {
        self.hotkeys = hotkeys
        // The window is built on first use, keeping it off the cold-launch path.
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HotkeyRecorderView(hotkeys: hotkeys)))
            window.title = "Otter Hotkeys"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        hotkeys.refreshSpotlightState()
        // A menu-bar agent has to activate itself for its window to come to the front.
        NSApp.activate()
        super.showWindow(sender)
    }
}

private struct HotkeyRecorderView: View {
    let hotkeys: HotkeyService

    @State private var toggleNote: String?
    @State private var saveClipboardNote: String?

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle panel:", name: .togglePanel) { _ in
                    toggleNote = note(for: hotkeys.shortcutDidChange(for: .togglePanel), otherAction: "Save clipboard")
                }
                if let toggleNote {
                    warning(toggleNote)
                }

                KeyboardShortcuts.Recorder("Save clipboard:", name: .saveClipboard) { _ in
                    saveClipboardNote = note(for: hotkeys.shortcutDidChange(for: .saveClipboard), otherAction: "Toggle panel")
                }
                if let saveClipboardNote {
                    warning(saveClipboardNote)
                }
                // The suggested shortcut (UX_SPEC §2); it ships unset (ADR-011).
                Button("Use ⌥⇧Space") {
                    KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.option, .shift]), for: .saveClipboard)
                    saveClipboardNote = note(for: hotkeys.shortcutDidChange(for: .saveClipboard), otherAction: "Toggle panel")
                }
            }

            Section {
                LabeledContent("Toggle panel now uses:", value: effectiveToggleDescription)

                if hotkeys.needsSpotlightHandoff {
                    Text("Spotlight is using ⌘Space, so Otter uses ⌥Space for now. Uncheck “Show Spotlight search”, or change it to ⌥Space.")
                        .font(.callout)
                    Button("Open Keyboard Shortcuts…") {
                        hotkeys.openSpotlightShortcutSettings()
                    }
                } else if hotkeys.effectiveToggle.needsPressToConfirm {
                    Text("Couldn't check Spotlight's shortcut. Press ⌘Space once to make sure it reaches Otter.")
                        .font(.callout)
                }

                // Records ⌘Space without the recorder's "used by the system" alert: ⌘Space gets the
                // Spotlight handoff instead of a warning.
                Button("Use ⌘Space") {
                    KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.command]), for: .togglePanel)
                    toggleNote = note(for: hotkeys.shortcutDidChange(for: .togglePanel), otherAction: "Save clipboard")
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var effectiveToggleDescription: String {
        hotkeys.effectiveToggle.combo.map { "\(KeyboardShortcuts.Shortcut($0))" } ?? "None"
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
    }

    private func note(for validation: ShortcutValidation, otherAction: String) -> String? {
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
