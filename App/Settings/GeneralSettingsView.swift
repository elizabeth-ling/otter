import KeyboardShortcuts
import OtterCore
import SwiftUI

/// Settings › General (UX_SPEC §5).
struct GeneralSettingsView: View {
    @Bindable var model: SettingsModel

    @State private var toggleNote: String?
    @State private var saveClipboardNote: String?
    @State private var hasSaveClipboardShortcut = KeyboardShortcuts.getShortcut(for: .saveClipboard) != nil

    private var hotkeys: HotkeyService { model.hotkeys }

    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Open panel:", name: .togglePanel) { _ in
                    toggleNote = ShortcutText.note(for: hotkeys.shortcutDidChange(for: .togglePanel), otherAction: "Save clipboard")
                }
                if let toggleNote {
                    ShortcutWarning(text: toggleNote)
                }
                LabeledContent("Shortcut in use:", value: ShortcutText.describe(hotkeys.effectiveToggle.combo))

                if hotkeys.needsSpotlightHandoff {
                    LabeledContent("Finish setting up ⌘Space") {
                        SpotlightHandoffView(hotkeys: hotkeys)
                    }
                } else if hotkeys.effectiveToggle.needsPressToConfirm {
                    Text("Couldn't check Spotlight's shortcut. Press ⌘Space once to make sure it reaches Otter.")
                        .font(.callout)
                }
                if !hotkeys.choseCommandSpace {
                    Button("Use ⌘Space") {
                        toggleNote = ShortcutText.note(for: hotkeys.useCommandSpace(), otherAction: "Save clipboard")
                    }
                }

                KeyboardShortcuts.Recorder("Save clipboard:", name: .saveClipboard) { shortcut in
                    hasSaveClipboardShortcut = shortcut != nil
                    saveClipboardNote = ShortcutText.note(for: hotkeys.shortcutDidChange(for: .saveClipboard), otherAction: "Open panel")
                }
                if let saveClipboardNote {
                    ShortcutWarning(text: saveClipboardNote)
                }
                if !hasSaveClipboardShortcut {
                    Button("Use ⌥⇧Space") {
                        KeyboardShortcuts.setShortcut(ShortcutText.suggestedSaveClipboard, for: .saveClipboard)
                        saveClipboardNote = ShortcutText.note(for: hotkeys.shortcutDidChange(for: .saveClipboard), otherAction: "Open panel")
                        hasSaveClipboardShortcut = KeyboardShortcuts.getShortcut(for: .saveClipboard) != nil
                    }
                }
            }

            Section("Panel") {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Toggle("Close panel when clicking elsewhere", isOn: Binding(
                    get: { !model.keepPanelOpen },
                    set: { model.keepPanelOpen = !$0 }
                ))
                Picker("Font:", selection: $model.fontFamily) {
                    Text("System").tag(EditorFontFamily.system)
                    Text("Monospaced").tag(EditorFontFamily.monospaced)
                }
                Stepper(value: $model.fontSize, in: AppSettings.fontSizes, step: 1) {
                    LabeledContent("Size:", value: "\(Int(model.fontSize)) pt")
                }
                Toggle(isOn: $model.smartQuotesAndDashes) {
                    Text("Smart quotes and dashes")
                    Text("Off by default: notes often contain code.")
                }
                LabeledContent("Position and size:") {
                    Button("Reset") {
                        model.resetPanelPosition()
                    }
                    .accessibilityLabel("Reset panel position and size")
                }
            }
        }
        .formStyle(.grouped)
    }
}
