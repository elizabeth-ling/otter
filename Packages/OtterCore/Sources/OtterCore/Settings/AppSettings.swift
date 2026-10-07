import Foundation

/// The editor's typeface (UX_SPEC §5, Font).
public enum EditorFontFamily: String, CaseIterable, Sendable {
    case system
    case monospaced
}

/// Otter's preferences in `UserDefaults` (UX_SPEC §5), apart from the destinations
/// (`DestinationRegistry`), the panel's frame (`PanelFrameStore`) and the shortcuts
/// (KeyboardShortcuts). Nothing is cached: each read goes to `defaults`, so a change made in
/// Settings applies the next time it's read.
public struct AppSettings {
    public enum Key {
        public static let keepPanelOpen = "keepPanelOpenWhenClickingElsewhere"
        public static let fontFamily = "editorFontFamily"
        public static let fontSize = "editorFontSize"
        public static let smartQuotesAndDashes = "smartQuotesAndDashes"
        public static let launchAtLogin = "launchAtLogin"
        public static let remembersRecents = "remembersRecentCaptures"
        public static let hasOnboarded = "hasOnboarded"
    }

    public static let defaultFontSize: Double = 15
    public static let fontSizes: ClosedRange<Double> = 10...28

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// "Close panel when clicking elsewhere", stored as its opposite. Off by default: a click
    /// elsewhere closes the panel.
    public var keepPanelOpenWhenClickingElsewhere: Bool {
        get { defaults.bool(forKey: Key.keepPanelOpen) }
        nonmutating set { defaults.set(newValue, forKey: Key.keepPanelOpen) }
    }

    public var fontFamily: EditorFontFamily {
        get { defaults.string(forKey: Key.fontFamily).flatMap(EditorFontFamily.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.fontFamily) }
    }

    /// In points, kept within `fontSizes`.
    public var fontSize: Double {
        get {
            let stored = defaults.double(forKey: Key.fontSize)
            return stored == 0 ? Self.defaultFontSize : Self.clampedFontSize(stored)
        }
        nonmutating set { defaults.set(Self.clampedFontSize(newValue), forKey: Key.fontSize) }
    }

    /// Off by default: notes often contain code.
    public var smartQuotesAndDashes: Bool {
        get { defaults.bool(forKey: Key.smartQuotesAndDashes) }
        nonmutating set { defaults.set(newValue, forKey: Key.smartQuotesAndDashes) }
    }

    /// On by default (UX_SPEC §6). Registering the login item is T12's.
    public var launchAtLogin: Bool {
        get { defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    /// "Remember recent captures". On by default.
    public var remembersRecents: Bool {
        get { defaults.object(forKey: Key.remembersRecents) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.remembersRecents) }
    }

    /// Set once first-run onboarding has been shown (UX_SPEC §6).
    public var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    /// "Reset all settings": removes everything Otter keeps in `domain` (its preferences, the
    /// destinations, the panel's frame and the shortcuts) except `hasOnboarded`, so onboarding
    /// doesn't come back. Objects that cache their settings must be reset too.
    public func resetAll(domain: String) {
        let onboarded = hasOnboarded
        defaults.removePersistentDomain(forName: domain)
        if onboarded {
            hasOnboarded = true
        }
    }

    private static func clampedFontSize(_ size: Double) -> Double {
        min(max(size.rounded(), fontSizes.lowerBound), fontSizes.upperBound)
    }
}
