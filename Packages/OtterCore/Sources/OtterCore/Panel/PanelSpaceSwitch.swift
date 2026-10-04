import Foundation

/// Whether the panel losing key status was a Space switch rather than a click elsewhere.
/// Switching Spaces activates the app on the new Space, so the panel resigns key even though
/// `.canJoinAllSpaces` carries it along. The two events arrive in no documented order, so they
/// count as one switch when they land within `graceInterval` of each other, either way round.
public enum PanelSpaceSwitch {
    public static let graceInterval: TimeInterval = 0.5

    /// Both times are `ProcessInfo.systemUptime` readings.
    public static func isSpaceSwitch(resignedAt: TimeInterval?, spaceChangedAt: TimeInterval?) -> Bool {
        guard let resignedAt, let spaceChangedAt else {
            return false
        }
        return abs(resignedAt - spaceChangedAt) <= graceInterval
    }
}
