import Foundation
import OtterCore

/// Checks whether Spotlight's "Show Spotlight search" shortcut holds `⌘Space` (ADR-010).
///
/// Read-only. Otter never writes to `com.apple.symbolichotkeys`: editing another domain is
/// fragile, only applies after logout, and users rightly distrust it.
struct SpotlightShortcutProbe {
    private static let domain = "com.apple.symbolichotkeys"
    private static let hotKeysKey = "AppleSymbolicHotKeys"

    private let symbolicHotKeys = UserDefaults(suiteName: Self.domain)

    func probe() -> SpotlightShortcutState {
        guard let symbolicHotKeys else {
            return .unknown
        }
        return SpotlightShortcutState(appleSymbolicHotKeys: symbolicHotKeys.object(forKey: Self.hotKeysKey))
    }
}
