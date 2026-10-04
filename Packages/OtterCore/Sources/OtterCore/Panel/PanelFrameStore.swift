import CoreGraphics
import Foundation

/// The panel's remembered size and per-display positions (T15), in `UserDefaults`:
///
/// - `panelSize`: `["width": Double, "height": Double]`
/// - `panelPositions`: `[displayUUID: ["x": Double, "y": Double]]`, each a `PanelPlacement` offset
///
/// Read once and cached, so showing the panel never touches `UserDefaults`. Values are stored as
/// saved; `PanelPlacement` clamps them to the screen at every show. Not thread-safe: use it from
/// one actor (the panel's, the main actor).
public final class PanelFrameStore {
    public static let sizeKey = "panelSize"
    public static let positionsKey = "panelPositions"
    /// T03's width-only key, migrated into `panelSize` on first read.
    public static let legacyWidthKey = "panelWidth"

    private let defaults: UserDefaults
    private var cache: (size: CGSize?, positions: [String: CGPoint])?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved size, or `nil` for the default.
    public var size: CGSize? {
        load().size
    }

    /// The saved offset on the display with this UUID, or `nil` for the default placement.
    public func offset(forDisplay displayUUID: String) -> CGPoint? {
        load().positions[displayUUID]
    }

    public func saveSize(_ size: CGSize) {
        var state = load()
        guard state.size != size else {
            return
        }
        state.size = size
        cache = state
        defaults.set(["width": Double(size.width), "height": Double(size.height)], forKey: Self.sizeKey)
    }

    public func saveOffset(_ offset: CGPoint, forDisplay displayUUID: String) {
        var state = load()
        guard state.positions[displayUUID] != offset else {
            return
        }
        state.positions[displayUUID] = offset
        cache = state
        defaults.set(state.positions.mapValues { ["x": Double($0.x), "y": Double($0.y)] }, forKey: Self.positionsKey)
    }

    /// "Reset Panel Position": back to the default size and placement on every display.
    public func reset() {
        cache = (nil, [:])
        defaults.removeObject(forKey: Self.sizeKey)
        defaults.removeObject(forKey: Self.positionsKey)
        defaults.removeObject(forKey: Self.legacyWidthKey)
    }

    // MARK: - Private

    private func load() -> (size: CGSize?, positions: [String: CGPoint]) {
        if let cache {
            return cache
        }
        var size = (defaults.dictionary(forKey: Self.sizeKey) as? [String: Double]).flatMap { dict -> CGSize? in
            guard let width = dict["width"], let height = dict["height"], width > 0, height > 0 else {
                return nil
            }
            return CGSize(width: width, height: height)
        }
        // T03 saved only a width. Read it once, then `panelSize` replaces it.
        let legacyWidth = defaults.double(forKey: Self.legacyWidthKey)
        if size == nil, legacyWidth > 0 {
            let migrated = PanelPlacement.migratedSize(legacyWidth: legacyWidth)
            defaults.set(["width": Double(migrated.width), "height": Double(migrated.height)], forKey: Self.sizeKey)
            size = migrated
        }
        defaults.removeObject(forKey: Self.legacyWidthKey)

        let stored = defaults.dictionary(forKey: Self.positionsKey) as? [String: [String: Double]] ?? [:]
        let positions = stored.compactMapValues { dict -> CGPoint? in
            guard let x = dict["x"], let y = dict["y"] else {
                return nil
            }
            return CGPoint(x: x, y: y)
        }
        let state = (size: size, positions: positions)
        cache = state
        return state
    }
}
