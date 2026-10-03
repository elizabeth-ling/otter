/// The toggle-panel shortcut Otter actually registers, derived from what the user chose and
/// whether Spotlight still holds `⌘Space` (T02 scope 3, ADR-010). The user's choice is the
/// preference; this is the registration.
public struct EffectiveToggleHotkey: Equatable, Sendable {
    /// Registered while Spotlight owns `⌘Space`.
    public static let fallback = HotkeyCombo.optionSpace

    /// What to register; `nil` registers nothing (the user cleared the shortcut).
    public let combo: HotkeyCombo?
    /// The user wants `⌘Space` but Spotlight still has it: onboarding and the menu bar offer the handoff.
    public let needsSpotlightHandoff: Bool
    /// The Spotlight preference couldn't be read: onboarding asks the user to press `⌘Space` once to confirm it works.
    public let needsPressToConfirm: Bool

    public init(combo: HotkeyCombo?, needsSpotlightHandoff: Bool = false, needsPressToConfirm: Bool = false) {
        self.combo = combo
        self.needsSpotlightHandoff = needsSpotlightHandoff
        self.needsPressToConfirm = needsPressToConfirm
    }

    /// - Parameters:
    ///   - chosen: The user's toggle-panel shortcut, or `nil` if they cleared it.
    ///   - spotlight: The latest Spotlight probe.
    ///   - saveClipboard: The save-clipboard shortcut. If the user put it on the fallback chord,
    ///     their explicit choice wins and the toggle stays on `⌘Space` (dead until the handoff)
    ///     rather than firing both actions from one key press.
    public static func resolve(
        chosen: HotkeyCombo?,
        spotlight: SpotlightShortcutState,
        saveClipboard: HotkeyCombo?
    ) -> EffectiveToggleHotkey {
        guard let chosen else {
            return EffectiveToggleHotkey(combo: nil)
        }
        guard chosen == .commandSpace else {
            return EffectiveToggleHotkey(combo: chosen)
        }

        switch spotlight {
        case .disabled:
            return EffectiveToggleHotkey(combo: .commandSpace)
        case .enabled:
            let combo = saveClipboard == fallback ? HotkeyCombo.commandSpace : fallback
            return EffectiveToggleHotkey(combo: combo, needsSpotlightHandoff: true)
        case .unknown:
            return EffectiveToggleHotkey(combo: .commandSpace, needsPressToConfirm: true)
        }
    }
}
