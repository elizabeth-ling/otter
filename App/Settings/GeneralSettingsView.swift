import OtterCore
import SwiftUI

/// Settings › General (UX_SPEC §5). The shortcuts have their own tab.
struct GeneralSettingsView: View {
    @Bindable var model: SettingsModel
    let showShortcuts: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                if model.loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Approve in System Settings › General › Login Items.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") {
                            LoginItem.openSystemSettings()
                        }
                    }
                }
                Toggle("Close panel when clicking elsewhere", isOn: Binding(
                    get: { !model.keepPanelOpen },
                    set: { model.keepPanelOpen = !$0 }
                ))
            }

            Section {
                Picker("Font", selection: $model.fontFamily) {
                    Text("System").tag(EditorFontFamily.system)
                    Text("Monospaced").tag(EditorFontFamily.monospaced)
                }
                Stepper(value: $model.fontSize, in: AppSettings.fontSizes, step: 1) {
                    LabeledContent("Size", value: "\(Int(model.fontSize)) pt")
                }
                Picker("Line spacing", selection: $model.lineSpacing) {
                    Text("Compact").tag(EditorLineSpacing.compact)
                    Text("Comfortable").tag(EditorLineSpacing.comfortable)
                }
                Toggle(isOn: $model.smartQuotesAndDashes) {
                    Text("Smart quotes and dashes")
                    Text("Off by default: notes often contain code.")
                }
            }

            Section {
                LabeledContent("Panel position and size") {
                    Button("Reset") {
                        model.resetPanelPosition()
                    }
                    .accessibilityLabel("Reset panel position and size")
                }
                LabeledContent("Change the shortcuts that open the panel and save your clipboard in Shortcuts.") {
                    Button("Shortcuts…", action: showShortcuts)
                }
            }
        }
        .formStyle(.grouped)
    }
}
