import CoreGraphics

/// Where the capture panel opens (UX_SPEC §1, T03 scope 4). Rects are in AppKit screen coordinates:
/// the origin is bottom-left and y grows upward.
public enum PanelPlacement {
    public static let defaultWidth: CGFloat = 640
    /// Narrowest the user can resize to.
    public static let minimumWidth: CGFloat = 400
    /// The top edge sits this far down the visible frame.
    public static let topOffsetFraction: CGFloat = 0.22

    /// The first screen whose frame contains `point` (edges included), or `nil` if none does.
    public static func screenIndex(containing point: CGPoint, screenFrames: [CGRect]) -> Int? {
        screenFrames.firstIndex { frame in
            point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
        }
    }

    /// The panel's frame: centered horizontally in `visibleFrame` with its top edge at 22% from the
    /// top, the width clamped to `minimumWidth`…`visibleFrame.width`, and kept fully inside
    /// `visibleFrame`. Whole points, so the text doesn't land on half pixels.
    public static func frame(width: CGFloat, height: CGFloat, in visibleFrame: CGRect) -> CGRect {
        let width = min(max(width, minimumWidth), visibleFrame.width).rounded(.down)
        let height = min(height, visibleFrame.height).rounded(.up)
        let x = (visibleFrame.midX - width / 2).rounded()
        let top = (visibleFrame.maxY - visibleFrame.height * topOffsetFraction).rounded()
        let y = max(top - height, visibleFrame.minY)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
