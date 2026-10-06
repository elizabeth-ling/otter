import CoreGraphics

/// Where the save-clipboard HUD goes (T11, UX_SPEC §3): a pill centred near the bottom of the
/// visible frame of the screen with the pointer, so above the Dock. AppKit screen coordinates.
public enum HUDPlacement {
    public static let height: CGFloat = 40
    /// From the bottom of the visible frame to the bottom of the pill.
    public static let bottomOffset: CGFloat = 72
    /// The pill never comes closer than this to the visible frame's sides; its text truncates instead.
    public static let sideMargin: CGFloat = 16

    /// - Parameter contentWidth: The width the pill's symbol and text need, padding included.
    public static func frame(contentWidth: CGFloat, in visibleFrame: CGRect) -> CGRect {
        let width = max(min(contentWidth.rounded(.up), visibleFrame.width - 2 * sideMargin), 0)
        // A visible frame too short for the offset still keeps the pill on it.
        let bottom = min(bottomOffset, max(visibleFrame.height - height, 0))
        return CGRect(
            x: (visibleFrame.midX - width / 2).rounded(),
            y: (visibleFrame.minY + bottom).rounded(),
            width: width,
            height: height
        )
    }
}
