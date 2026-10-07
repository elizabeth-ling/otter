import KeyboardShortcuts
import OtterCore
import SwiftUI

/// First run (UX_SPEC §6): three steps in the Settings window.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.isHotkeyOnly {
                Text("Step \(model.step.rawValue + 1) of \(OnboardingModel.Step.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch model.step {
            case .hotkey:
                HotkeyStep(model: model)
            case .destination:
                DestinationStep(model: model)
            case .tryIt:
                TryItStep(model: model)
            }
            Spacer(minLength: 0)
            HStack {
                if model.step != .hotkey {
                    Button("Back") { model.back() }
                }
                Spacer()
                primaryButtons
            }
        }
        .padding(28)
        .frame(width: 560, height: 430, alignment: .topLeading)
    }

    @ViewBuilder private var primaryButtons: some View {
        switch model.step {
        case .hotkey where model.isHotkeyOnly:
            // `⌥Space` keeps working until `⌘Space` is free.
            Button(model.hotkeyStatus.isConfirmed ? "Done" : "Not Now") { model.next() }
                .keyboardShortcut(.defaultAction)
        case .hotkey:
            if model.hotkeyStatus.isConfirmed {
                Button("Continue") { model.next() }
                    .keyboardShortcut(.defaultAction)
            } else {
                // `⌥Space` (or the fallback while Spotlight has `⌘Space`) keeps working.
                Button("Skip for Now") { model.next() }
                    .keyboardShortcut(.defaultAction)
            }
        case .destination:
            Button("Continue") { model.next() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.choice == .folder && model.chosenFolder == nil)
        case .tryIt:
            Button("Done") { model.next() }
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Step 1

private struct HotkeyStep: View {
    @Bindable var model: OnboardingModel

    private var hotkeys: HotkeyService { model.hotkeys }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your hotkey")
                .font(.title2.bold())
            Text("Press it from any app to open a note.")
                .foregroundStyle(.secondary)

            status
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)

            if let note = model.shortcutNote {
                ShortcutWarning(text: note)
            }

            HStack {
                if !hotkeys.choseCommandSpace {
                    Button("Use ⌘Space Instead") { model.useCommandSpace() }
                }
                Button("Use a Different Shortcut") { model.isRecordingOtherShortcut = true }
                    .disabled(model.isRecordingOtherShortcut)
            }
            if model.isRecordingOtherShortcut {
                KeyboardShortcuts.Recorder("Shortcut:", name: .togglePanel) { _ in
                    model.recordedShortcut()
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.hotkeyStatus {
        case let .pressToConfirm(combo):
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Press \(ShortcutText.describe(combo)) now to check it reaches Otter.")
            }
        case let .confirmed(combo):
            Label("\(ShortcutText.describe(combo)) works. Press it any time to open the panel.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .waitingForSpotlight:
            VStack(alignment: .leading, spacing: 8) {
                SpotlightHandoffView(hotkeys: hotkeys)
                Text("Otter checks again when you come back. ⌥Space works in the meantime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .noShortcut:
            Text("No shortcut is set. Record one to open the panel.")
        }
    }
}

// MARK: - Step 2

private struct DestinationStep: View {
    @Bindable var model: OnboardingModel

    @State private var previousChoice = OnboardingModel.DestinationChoice.inbox

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should notes go?")
                .font(.title2.bold())
            Text("Each note is saved as its own Markdown file. You can add more places in Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Save notes to:", selection: $model.choice) {
                ForEach(model.vaults) { vault in
                    Text("\(vault.name) — Obsidian vault").tag(OnboardingModel.DestinationChoice.vault(vault.path))
                }
                Text("Otter Inbox in Documents").tag(OnboardingModel.DestinationChoice.inbox)
                Text(model.chosenFolder.map { "A folder: \(FileManager.default.displayName(atPath: $0.path))" } ?? "A folder…")
                    .tag(OnboardingModel.DestinationChoice.folder)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .onChange(of: model.choice) { old, new in
                if new == .folder, model.chosenFolder == nil {
                    Task { await model.chooseFolder(otherwise: old) }
                } else {
                    previousChoice = old
                }
            }

            if model.choice == .folder, model.chosenFolder != nil {
                Button("Choose Another Folder…") {
                    Task { await model.chooseFolder(otherwise: previousChoice) }
                }
            }
        }
    }
}

// MARK: - Step 3

private struct TryItStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Try it")
                .font(.title2.bold())
            Text("Press \(ShortcutText.describe(model.hotkeys.effectiveToggle.combo)), type anything, hit ⌘↩.")

            Group {
                if let delivery = model.firstDelivery {
                    HStack {
                        Label("Saved to \(delivery.destinationName).", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Open") { model.openFirstNote() }
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for your first note…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .contain)

            Toggle("Open Otter when you log in", isOn: $model.launchAtLogin)
        }
    }
}
