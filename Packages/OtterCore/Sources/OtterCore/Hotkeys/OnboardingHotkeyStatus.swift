/// Where onboarding's hotkey step stands (UX_SPEC §6 step 1, ADR-011).
public enum OnboardingHotkeyStatus: Equatable, Sendable {
    /// The user cleared the toggle shortcut: there's nothing to press.
    case noShortcut
    /// The user chose `⌘Space`, but Spotlight still has it. `⌥Space` works meanwhile.
    case waitingForSpotlight
    /// Press `combo` once to show it reaches Otter (another app may have taken it).
    case pressToConfirm(HotkeyCombo)
    /// A press of `combo` reached Otter.
    case confirmed(HotkeyCombo)

    /// - Parameters:
    ///   - effective: What `HotkeyService` registered.
    ///   - lastPress: The registered shortcut at the last press that reached Otter during
    ///     onboarding, so changing the shortcut asks for a new press.
    public init(effective: EffectiveToggleHotkey, lastPress: HotkeyCombo?) {
        if effective.needsSpotlightHandoff {
            self = .waitingForSpotlight
        } else if let combo = effective.combo {
            self = lastPress == combo ? .confirmed(combo) : .pressToConfirm(combo)
        } else {
            self = .noShortcut
        }
    }

    public var isConfirmed: Bool {
        if case .confirmed = self {
            return true
        }
        return false
    }
}
