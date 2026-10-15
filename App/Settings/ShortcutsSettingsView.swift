import KeyboardShortcuts
import OtterCore
import SwiftUI

/// Settings › Shortcuts (UX_SPEC §5): the two global shortcuts, which can be recorded, and the
/// panel's, for reference (UX_SPEC §2). The search matches an action's name or its keys.
struct ShortcutsSettingsView: View {
    @Bindable var model: SettingsModel

    @State private var query = ""
    @State private var toggleNote: String?
    @State private var saveClipboardNote: String?
    // Read back after every change, since `shortcutDidChange` can refuse and revert a recording.
    @State private var toggleShortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
    @State private var saveClipboardShortcut = KeyboardShortcuts.getShortcut(for: .saveClipboard)

    private var hotkeys: HotkeyService { model.hotkeys }

    var body: some View {
        VStack(spacing: 20) {
            if hotkeys.needsSpotlightHandoff {
                SpotlightHandoffView(hotkeys: hotkeys)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsCard()
            }
            HStack(alignment: .top, spacing: 24) {
                list
                    .frame(width: 400)
                sidebar
            }
        }
        .padding(24)
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if showsOpenPanel || showsSaveClipboard {
                        Section {
                            if showsOpenPanel {
                                openPanelRow
                            }
                            if showsSaveClipboard {
                                saveClipboardRow
                            }
                        } header: {
                            SectionHeader(title: "Anywhere on your Mac")
                        }
                    }
                    if !panelShortcuts.isEmpty {
                        Section {
                            ForEach(panelShortcuts) { shortcut in
                                ShortcutRow(title: shortcut.title) {
                                    KeyCap(text: shortcut.display)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        } header: {
                            SectionHeader(title: "In the panel")
                        }
                    }
                    if !showsOpenPanel, !showsSaveClipboard, panelShortcuts.isEmpty {
                        Text("No shortcuts match “\(query)”.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
            }
        }
        .settingsCard()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Type an action or shortcut (like “⌘K”)", text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search shortcuts")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var openPanelRow: some View {
        ShortcutRow(title: "Open panel") {
            KeyboardShortcuts.Recorder(for: .togglePanel) { _ in
                toggleNote = ShortcutText.note(for: hotkeys.shortcutDidChange(for: .togglePanel), otherAction: "Save clipboard")
                refresh()
            }
        } detail: {
            if let toggleNote {
                ShortcutWarning(text: toggleNote)
            }
            if !hotkeys.needsSpotlightHandoff, hotkeys.effectiveToggle.needsPressToConfirm {
                Text("Couldn't check Spotlight's shortcut. Press ⌘Space once to make sure it reaches Otter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !hotkeys.choseCommandSpace {
                Button("Use ⌘Space") {
                    toggleNote = ShortcutText.note(for: hotkeys.useCommandSpace(), otherAction: "Save clipboard")
                    refresh()
                }
                .buttonStyle(.link)
            }
        }
    }

    private var saveClipboardRow: some View {
        ShortcutRow(title: "Save clipboard") {
            KeyboardShortcuts.Recorder(for: .saveClipboard) { _ in
                saveClipboardNote = ShortcutText.note(for: hotkeys.shortcutDidChange(for: .saveClipboard), otherAction: "Open panel")
                refresh()
            }
        } detail: {
            if let saveClipboardNote {
                ShortcutWarning(text: saveClipboardNote)
            }
            if saveClipboardShortcut == nil {
                Button("Use ⌥⇧Space") {
                    KeyboardShortcuts.setShortcut(ShortcutText.suggestedSaveClipboard, for: .saveClipboard)
                    saveClipboardNote = ShortcutText.note(for: hotkeys.shortcutDidChange(for: .saveClipboard), otherAction: "Open panel")
                    refresh()
                }
                .buttonStyle(.link)
            }
        }
    }

    private var showsOpenPanel: Bool {
        ShortcutSearch.matches(query, title: "Open panel", keys: [toggleShortcut.map { "\($0)" } ?? ""])
    }

    private var showsSaveClipboard: Bool {
        ShortcutSearch.matches(query, title: "Save clipboard", keys: [saveClipboardShortcut.map { "\($0)" } ?? ""])
    }

    private var panelShortcuts: [PanelShortcut] {
        PanelShortcut.all.filter { ShortcutSearch.matches(query, title: $0.title, keys: $0.keys) }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            KeyCapIllustration(shortcut: hotkeys.effectiveToggle.combo.map(KeyboardShortcuts.Shortcut.init) ?? HotkeyService.fallbackToggle)
                .padding(.bottom, 14)
            Text("Custom Shortcuts")
                .font(.title3.weight(.semibold))
            Text("Open the panel or save your clipboard from any app. Click a shortcut to record a new one.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("The panel's shortcuts work while you're writing a note.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Reset Shortcuts") {
                hotkeys.resetShortcuts {}
                toggleNote = nil
                saveClipboardNote = nil
                refresh()
            }
            .disabled(toggleShortcut == KeyboardShortcuts.Name.togglePanel.defaultShortcut && saveClipboardShortcut == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func refresh() {
        toggleShortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
        saveClipboardShortcut = KeyboardShortcuts.getShortcut(for: .saveClipboard)
    }
}

/// One of the panel's fixed shortcuts (UX_SPEC §2).
private struct PanelShortcut: Identifiable {
    let title: String
    /// Every chord that does it, for the search.
    let keys: [String]
    let display: String

    var id: String { title }

    init(_ title: String, _ keys: String...) {
        self.title = title
        self.keys = keys
        display = keys.joined(separator: " / ")
    }

    init(_ title: String, keys: [String], display: String) {
        self.title = title
        self.keys = keys
        self.display = display
    }

    static let all: [PanelShortcut] = [
        PanelShortcut("Save and close", "⌘↩"),
        PanelShortcut("Save and keep open", "⇧⌘↩"),
        PanelShortcut("Save as…", "⌘S"),
        PanelShortcut("Close, keeping the draft", "Esc"),
        PanelShortcut("Discard draft", "⇧⌘⌫"),
        PanelShortcut("Send to destination 1–9", keys: (1...9).map { "⌘\($0)" }, display: "⌘1 … ⌘9"),
        PanelShortcut("Change save folder", "⇧⌘O"),
        PanelShortcut("Bold", "⌘B"),
        PanelShortcut("Italic", "⌘I"),
        PanelShortcut("Strikethrough", "⇧⌘X"),
        PanelShortcut("Inline code", "⌘E"),
        PanelShortcut("Link", "⌘K"),
        PanelShortcut("Task", "⌘L"),
        PanelShortcut("Bullet", "⇧⌘8"),
        PanelShortcut("Indent / outdent list item", "Tab", "⇧Tab"),
        PanelShortcut("Open Settings", "⌘,"),
        PanelShortcut("Undo", "⌘Z"),
        PanelShortcut("Redo", "⇧⌘Z"),
    ]
}

/// Matches a search against an action's name, or its keys: "⇧⌘O", "cmd shift o" and "⌘O" all find
/// `⇧⌘O`, since the modifiers can be typed in any order and need only be a subset.
enum ShortcutSearch {
    private static let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
    /// Longest first, so "command" isn't read as "cmd" plus "and".
    private static let words: [(String, String)] = [
        ("command", "⌘"), ("cmd", "⌘"), ("shift", "⇧"), ("option", "⌥"), ("opt", "⌥"), ("alt", "⌥"),
        ("control", "⌃"), ("ctrl", "⌃"), ("return", "↩"), ("enter", "↩"), ("backspace", "⌫"), ("delete", "⌫"),
    ]

    static func matches(_ query: String, title: String, keys: [String]) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        if query.isEmpty || title.localizedCaseInsensitiveContains(query) {
            return true
        }
        let wanted = chord(query)
        return keys.contains { key in
            let candidate = chord(key)
            return !candidate.key.isEmpty && wanted.modifiers.isSubset(of: candidate.modifiers) && candidate.key.hasPrefix(wanted.key)
        }
    }

    private static func chord(_ text: String) -> (modifiers: Set<Character>, key: String) {
        var text = text.lowercased()
        for (word, symbol) in words {
            text = text.replacingOccurrences(of: word, with: symbol)
        }
        text.removeAll { $0 == " " || $0 == "+" || $0 == "-" }
        return (Set(text.filter(modifiers.contains)), String(text.filter { !modifiers.contains($0) }).uppercased())
    }
}

// MARK: - Pieces

private struct ShortcutRow<Keys: View, Detail: View>: View {
    let title: String
    @ViewBuilder let keys: Keys
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                keys
            }
            detail
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.horizontal, 16)
        }
    }
}

extension ShortcutRow where Detail == EmptyView {
    init(title: String, @ViewBuilder keys: () -> Keys) {
        self.init(title: title, keys: keys, detail: { EmptyView() })
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityAddTraits(.isHeader)
    }
}

/// A panel shortcut, drawn like the recorder beside it.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(minWidth: 64)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// The open-panel shortcut as big keys in the accent colour, one per modifier and one for the key.
private struct KeyCapIllustration: View {
    let shortcut: KeyboardShortcuts.Shortcut

    private var labels: [String] {
        let text = "\(shortcut)"
        let modifiers = text.prefix { "⌃⌥⇧⌘".contains($0) }
        return modifiers.map(String.init) + [String(text.dropFirst(modifiers.count))]
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: label.count > 1 ? 18 : 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, label.count > 1 ? 14 : 0)
                    .frame(minWidth: 52, minHeight: 52)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
                    .padding([.horizontal, .top], 5)
                    .padding(.bottom, 9)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .accessibilityHidden(true)
    }
}

private extension View {
    func settingsCard() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
