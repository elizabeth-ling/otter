/// A chord macOS keeps for itself by default, so a global hotkey on it is unreliable (T02 scope 9).
/// `⌘Space` is deliberately not listed: it gets the Spotlight handoff instead (ADR-010).
public enum ReservedShortcut: Equatable, Sendable, CaseIterable {
    /// `⌃Space`: select the previous input source.
    case inputSourceSwitching
    /// `⌘⇥`: the app switcher.
    case appSwitcher
    /// `⌃⌘Space`: the emoji & symbols picker.
    case emojiPicker

    public var combo: HotkeyCombo {
        switch self {
        case .inputSourceSwitching: .controlSpace
        case .appSwitcher: .commandTab
        case .emojiPicker: .controlCommandSpace
        }
    }

    public init?(_ combo: HotkeyCombo) {
        guard let match = Self.allCases.first(where: { $0.combo == combo }) else {
            return nil
        }
        self = match
    }
}

/// The verdict on a shortcut the user just recorded.
public enum ShortcutValidation: Equatable, Sendable {
    case ok
    /// Accepted, but the recorder shows a warning.
    case reserved(ReservedShortcut)
    /// Refused: the other Otter shortcut already uses it.
    case duplicate

    /// - Parameters:
    ///   - recorded: The new shortcut, or `nil` if the user cleared it.
    ///   - other: The other Otter shortcut (toggle panel vs. save clipboard).
    public init(recorded: HotkeyCombo?, other: HotkeyCombo?) {
        guard let recorded else {
            self = .ok
            return
        }
        if recorded == other {
            self = .duplicate
        } else if let reserved = ReservedShortcut(recorded) {
            self = .reserved(reserved)
        } else {
            self = .ok
        }
    }
}
