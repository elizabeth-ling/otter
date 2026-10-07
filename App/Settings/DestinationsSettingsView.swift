import OtterCore
import SwiftUI

/// Settings › Destinations (UX_SPEC §5): the list in `⌘1…⌘9` order, the Add menu, and the
/// selected destination's form. Built around `DestinationKind`, so T08 adds an Apple Notes row icon
/// and form beside the folder ones.
struct DestinationsSettingsView: View {
    @Bindable var model: SettingsModel

    /// A destination being deleted that has notes waiting for it.
    @State private var pendingDelete: (id: DestinationID, count: Int)?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    ForEach(Array(model.destinations.enumerated()), id: \.element.id) { index, config in
                        DestinationRow(model: model, config: config, index: index)
                            .tag(config.id)
                    }
                    .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                }
                .accessibilityLabel("Destinations")
                Divider()
                listButtons
            }
            .frame(width: 250)

            Divider()

            if let id = model.selection, let config = model.config(id) {
                DestinationForm(model: model, config: config)
                    .id(id)
            } else {
                Text("No destination selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { model.checkHealth() }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { pending in
            Button("Move Them and Delete", role: .destructive) {
                Task { await model.delete(pending.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They'll be saved to \(newDefaultName) instead.")
        }
    }

    private var listButtons: some View {
        HStack(spacing: 0) {
            Menu {
                if !model.discoveredVaults.isEmpty {
                    Section("Obsidian Vaults") {
                        ForEach(model.discoveredVaults) { vault in
                            Button(vault.name) { model.addVault(vault) }
                        }
                    }
                }
                Button("Folder…") {
                    Task { await model.addFolder() }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Add destination")

            Button {
                deleteSelection()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(model.selection == nil || model.destinations.count < 2)
            .accessibilityLabel("Delete destination")
            .help(model.destinations.count < 2 ? "Otter needs one destination" : "Delete destination")
            Spacer()
        }
        .padding(6)
    }

    private var deleteTitle: String {
        let count = pendingDelete?.count ?? 0
        let name = pendingDelete.flatMap { model.config($0.id)?.name } ?? "this destination"
        return "\(count) \(count == 1 ? "note is" : "notes are") waiting to be saved to ‘\(name)’."
    }

    /// Where waiting notes go: the default, or the first other destination if this is the default.
    private var newDefaultName: String {
        guard let id = pendingDelete?.id else {
            return "the default destination"
        }
        let remaining = model.destinations.filter { $0.id != id }
        let target = remaining.first { $0.id == model.defaultID } ?? remaining.first
        return target.map { "‘\($0.name)’" } ?? "the default destination"
    }

    private func deleteSelection() {
        guard let id = model.selection else {
            return
        }
        Task {
            let count = await model.pendingCount(for: id)
            if count > 0 {
                pendingDelete = (id, count)
            } else {
                await model.delete(id)
            }
        }
    }
}

/// One destination in the list: icon, name and mode, health dot, `⌘` number, and the default star.
private struct DestinationRow: View {
    let model: SettingsModel
    let config: DestinationConfig
    let index: Int

    private var isDefault: Bool { config.id == model.defaultID }
    private var health: DestinationHealth? { model.health[config.id] }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(config.name)
                    .lineLimit(1)
                Text(config.modeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HealthDot(health: health)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Button {
                model.setDefault(config.id)
            } label: {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isDefault ? "Default destination" : "Make default")
            .accessibilityLabel(isDefault ? "Default destination" : "Make default")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: "Make default") { model.setDefault(config.id) }
        .accessibilityAction(named: "Move up") { model.move(config.id, by: -1) }
        .accessibilityAction(named: "Move down") { model.move(config.id, by: 1) }
        .contextMenu {
            Button("Make Default") { model.setDefault(config.id) }
                .disabled(isDefault)
            Button("Move Up") { model.move(config.id, by: -1) }
                .disabled(index == 0)
            Button("Move Down") { model.move(config.id, by: 1) }
                .disabled(index == model.destinations.count - 1)
        }
    }

    private var icon: String {
        switch config.kind {
        case .folder:
            model.vaultIDs.contains(config.id) ? "books.vertical" : "folder"
        }
    }

    private var accessibilityLabel: String {
        var parts = [config.name, config.modeSummary]
        if let health {
            parts.append(HealthDot.description(of: health))
        }
        if index < 9 {
            parts.append("Command \(index + 1)")
        }
        if isDefault {
            parts.append("default")
        }
        return parts.joined(separator: ", ")
    }
}

/// Green, amber or red from `healthCheck()`; grey until the first check.
private struct HealthDot: View {
    let health: DestinationHealth?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(health.map(Self.description) ?? "Checking…")
    }

    private var color: Color {
        switch health?.level {
        case .good: .green
        case .warning: .orange
        case .failing: .red
        case nil: .secondary.opacity(0.4)
        }
    }

    static func description(of health: DestinationHealth) -> String {
        switch health {
        case .ok: "Working"
        case .needsPermission: "Needs access"
        case let .unreachable(reason): reason
        }
    }
}
