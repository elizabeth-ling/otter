import os

/// `os_signpost` intervals from ARCHITECTURE §9. They are logged to Points of Interest so they
/// show up in Instruments without extra setup. Each interval uses the `.exclusive` signpost ID
/// (only one runs at a time), so the code that ends it doesn't need an ID from the code that began it.
public enum Signpost {
    public static let log = OSLog(subsystem: Logger.subsystem, category: .pointsOfInterest)

    /// Begun by `PanelController` when a toggle press shows the panel; ended once the panel is key.
    public static let hotkeyToVisible: StaticString = "hotkey→visible"
}
