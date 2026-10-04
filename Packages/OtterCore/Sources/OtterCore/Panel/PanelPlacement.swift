import CoreGraphics

/// Where the capture panel opens and how big it is (UX_SPEC §1, T15). Rects are in AppKit screen
/// coordinates: the origin is bottom-left and y grows upward.
///
/// A remembered position is an *offset* of the panel's top-left from the top-left of its display's
/// visible frame: `x` grows rightward and `y` grows downward. It survives the menu bar or Dock
/// changing size, and a display being rearranged.
public enum PanelPlacement {
    public static let defaultSize = CGSize(width: 380, height: 300)
    public static let minimumSize = CGSize(width: 300, height: 180)
    public static let maximumSize = CGSize(width: 720, height: 640)
    /// The default top edge sits this far down the visible frame.
    public static let topOffsetFraction: CGFloat = 0.22

    /// The first screen whose frame contains `point` (edges included), or `nil` if none does.
    public static func screenIndex(containing point: CGPoint, screenFrames: [CGRect]) -> Int? {
        screenFrames.firstIndex { frame in
            point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
        }
    }

    /// `size` clamped to `minimumSize`…`maximumSize`, then capped to `visibleFrame` (the screen wins
    /// over the minimum on a tiny display). Whole points, so the text doesn't land on half pixels.
    public static func clampedSize(_ size: CGSize, in visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(min(max(size.width, minimumSize.width), maximumSize.width), visibleFrame.width).rounded(.down),
            height: min(min(max(size.height, minimumSize.height), maximumSize.height), visibleFrame.height).rounded(.down)
        )
    }

    /// The size to use in place of T03's saved `panelWidth`: that width, clamped, at the default height.
    public static func migratedSize(legacyWidth: CGFloat) -> CGSize {
        CGSize(
            width: min(max(legacyWidth, minimumSize.width), maximumSize.width).rounded(.down),
            height: defaultSize.height
        )
    }

    /// The frame for a show: at `offset` if the display has one, otherwise the default placement
    /// (centered horizontally, top edge 22% down). Always fully inside `visibleFrame`.
    public static func frame(size: CGSize, offset: CGPoint?, in visibleFrame: CGRect) -> CGRect {
        let size = clampedSize(size, in: visibleFrame)
        guard let offset else {
            return defaultFrame(size: size, in: visibleFrame)
        }
        return clamp(
            CGRect(
                x: visibleFrame.minX + offset.x,
                y: visibleFrame.maxY - offset.y - size.height,
                width: size.width,
                height: size.height
            ),
            to: visibleFrame
        )
    }

    /// Centered horizontally with the top edge 22% down `visibleFrame`, clamped inside it.
    public static func defaultFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let size = clampedSize(size, in: visibleFrame)
        let top = visibleFrame.maxY - visibleFrame.height * topOffsetFraction
        return clamp(
            CGRect(x: visibleFrame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
            to: visibleFrame
        )
    }

    /// The offset of `frame`'s top-left from `visibleFrame`'s top-left, for saving.
    public static func offset(of frame: CGRect, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX - visibleFrame.minX, y: visibleFrame.maxY - frame.maxY)
    }

    /// `frame` shrunk to fit `visibleFrame` if needed, then moved the least distance that puts it fully
    /// inside. Origin rounded to whole points.
    public static func clamp(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.minX.rounded(), visibleFrame.minX), visibleFrame.maxX - width)
        // Keep the top edge where it was when shrinking, so a taller-than-screen panel loses its bottom.
        let top = min(max(frame.maxY.rounded(), visibleFrame.minY + height), visibleFrame.maxY)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}
