/// Whether Spotlight's "Show Spotlight search" shortcut is holding `⌘Space` (ADR-010).
public enum SpotlightShortcutState: Sendable, Equatable {
    /// Spotlight's shortcut is on and bound to `⌘Space`, so macOS takes the chord before any app sees it.
    case enabled
    /// `⌘Space` is free: Spotlight's shortcut is off, or the user moved it to another chord.
    case disabled
    /// The preference has a shape we don't recognise. Otter tries `⌘Space` and asks the user to confirm it.
    case unknown

    /// Spotlight's entry in `AppleSymbolicHotKeys`. Undocumented; checked on macOS 27.0.1.
    public static let symbolicHotKeyID = "64"

    /// Parses the value stored under `AppleSymbolicHotKeys` in the `com.apple.symbolichotkeys` domain.
    ///
    /// The entry looks like `{enabled = 1; value = {parameters = (32, 49, 1048576); type = standard}}`,
    /// where `parameters` is (character, virtual key code, Cocoa modifier flags). A missing domain or
    /// entry means the user never touched it, so Spotlight still has the macOS default (`⌘Space`, on).
    public init(appleSymbolicHotKeys: Any?) {
        guard let appleSymbolicHotKeys else {
            self = .enabled
            return
        }
        guard let hotKeys = appleSymbolicHotKeys as? [String: Any] else {
            self = .unknown
            return
        }
        guard let rawEntry = hotKeys[Self.symbolicHotKeyID] else {
            self = .enabled
            return
        }
        guard
            let entry = rawEntry as? [String: Any],
            let isEnabled = Self.bool(entry["enabled"])
        else {
            self = .unknown
            return
        }
        guard isEnabled else {
            self = .disabled
            return
        }
        // No binding stored means the default binding, `⌘Space`.
        guard let binding = entry["value"] else {
            self = .enabled
            return
        }
        // ADR-010 lets the user move Spotlight (e.g. to `⌥Space`) instead of turning it off;
        // that frees `⌘Space` just the same.
        switch Self.isCommandSpace(binding) {
        case true?: self = .enabled
        case false?: self = .disabled
        case nil: self = .unknown
        }
    }

    // Cocoa `NSEvent.ModifierFlags` raw values, as stored in `parameters`.
    private static let cocoaShift = 1 << 17
    private static let cocoaControl = 1 << 18
    private static let cocoaOption = 1 << 19
    private static let cocoaCommand = 1 << 20
    private static let cocoaChordModifiers = cocoaShift | cocoaControl | cocoaOption | cocoaCommand

    /// Plist booleans arrive as `Bool`; some writers store `0`/`1` integers instead.
    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as Int where number == 0 || number == 1:
            return number == 1
        default:
            return nil
        }
    }

    /// `nil` when the binding can't be read.
    private static func isCommandSpace(_ binding: Any) -> Bool? {
        guard
            let binding = binding as? [String: Any],
            let parameters = binding["parameters"] as? [Any],
            parameters.count >= 3,
            let keyCode = parameters[1] as? Int,
            let flags = parameters[2] as? Int
        else {
            return nil
        }
        return keyCode == HotkeyCombo.KeyCode.space && flags & cocoaChordModifiers == cocoaCommand
    }
}
