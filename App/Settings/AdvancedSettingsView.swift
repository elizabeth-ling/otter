import OtterCore
import SwiftUI

/// Settings › Advanced (UX_SPEC §5).
struct AdvancedSettingsView: View {
    @Bindable var model: SettingsModel

    @State private var isConfirmingReset = false

    private var status: DeliveryStatus { model.deliveryStatus }

    var body: some View {
        Form {
            Section("Outbox") {
                LabeledContent("Waiting to deliver:", value: status.pendingCount == 1 ? "1 note" : "\(status.pendingCount) notes")
                if let lastError = status.lastError {
                    LabeledContent("Last error:") {
                        Text(lastError)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                if !status.missingDestinations.isEmpty {
                    Text("Some notes are for a destination that's no longer set up. Retry Now sends any whose destination is back.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Retry Now") {
                        model.retryNow()
                    }
                    .disabled(status.pendingCount == 0)
                    Button("Reveal Outbox Folder") {
                        model.revealOutbox()
                    }
                }
            }

            Section("Recent captures") {
                Toggle(isOn: $model.remembersRecents) {
                    Text("Remember recent captures")
                    Text("Keeps the first line of your last 20 notes for the menu bar. Turning this off deletes them.")
                }
                Button("Clear Recents") {
                    model.clearRecents()
                }
            }

            Section("Troubleshooting") {
                HStack {
                    Button("Reveal Logs") {
                        model.revealLogs()
                    }
                    .help("Saves this session's log (no note text) and shows it in Finder")
                    Spacer()
                    Button("Reset All Settings…", role: .destructive) {
                        isConfirmingReset = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $isConfirmingReset) {
            Button("Reset All Settings", role: .destructive) {
                Task { await model.resetAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shortcuts, the panel, the font and your destinations go back to how they were when Otter was installed. Notes waiting to be delivered go to the Otter Inbox. Your saved notes aren't touched.")
        }
    }
}
