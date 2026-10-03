/// A global-hotkey key combination in Carbon terms, the representation `RegisterEventHotKey`
/// (and so KeyboardShortcuts) uses. OtterCore can't import Carbon, so the few constants the
/// hotkey rules need are mirrored from HIToolbox/Events.h.
public struct HotkeyCombo: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        // Carbon `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
        public static let command = Modifiers(rawValue: 0x0100)
        public static let shift = Modifiers(rawValue: 0x0200)
        public static let option = Modifiers(rawValue: 0x0800)
        public static let control = Modifiers(rawValue: 0x1000)

        static let all: Modifiers = [.command, .shift, .option, .control]
    }

    /// Carbon virtual key codes (`kVK_*`) used by the hotkey rules.
    public enum KeyCode {
        public static let tab = 0x30
        public static let space = 0x31
    }

    public let carbonKeyCode: Int
    public let modifiers: Modifiers

    public init(carbonKeyCode: Int, modifiers: Modifiers) {
        self.carbonKeyCode = carbonKeyCode
        // Keep only the four chord modifiers so caps lock and friends never break equality.
        self.modifiers = modifiers.intersection(.all)
    }

    public init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.init(carbonKeyCode: carbonKeyCode, modifiers: Modifiers(rawValue: carbonModifiers))
    }

    public var carbonModifiers: Int { modifiers.rawValue }

    public static let commandSpace = HotkeyCombo(carbonKeyCode: KeyCode.space, modifiers: .command)
    public static let optionSpace = HotkeyCombo(carbonKeyCode: KeyCode.space, modifiers: .option)
    public static let controlSpace = HotkeyCombo(carbonKeyCode: KeyCode.space, modifiers: .control)
    public static let controlCommandSpace = HotkeyCombo(carbonKeyCode: KeyCode.space, modifiers: [.control, .command])
    public static let commandTab = HotkeyCombo(carbonKeyCode: KeyCode.tab, modifiers: .command)
}
