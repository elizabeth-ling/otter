import CoreGraphics
import Testing
@testable import OtterCore

private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
/// To the right of the laptop, taller, and offset upward.
private let external = CGRect(x: 1512, y: -200, width: 2560, height: 1440)

// MARK: - Screen under the pointer

@Test func picksTheScreenUnderThePointer() {
    let screens = [laptop, external]
    #expect(PanelPlacement.screenIndex(containing: CGPoint(x: 100, y: 100), screenFrames: screens) == 0)
    #expect(PanelPlacement.screenIndex(containing: CGPoint(x: 2000, y: -100), screenFrames: screens) == 1)
}

@Test func pointerOnTheTopEdgeCountsAsOnScreen() {
    // NSEvent.mouseLocation reports y == maxY when the pointer is on the top row (the menu bar).
    #expect(PanelPlacement.screenIndex(containing: CGPoint(x: 100, y: 982), screenFrames: [laptop]) == 0)
}

@Test func pointerOffEveryScreenHasNoScreen() {
    #expect(PanelPlacement.screenIndex(containing: CGPoint(x: -50, y: 100), screenFrames: [laptop, external]) == nil)
}

// MARK: - Default placement

@Test func firstOpenIsDefaultSizeCenteredWithTopEdgeAt22Percent() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let frame = PanelPlacement.frame(size: PanelPlacement.defaultSize, offset: nil, in: visible)
    #expect(frame.size == CGSize(width: 380, height: 300))
    #expect(frame.midX == visible.midX)
    #expect(frame.maxY == (950 - 950 * 0.22).rounded())
}

@Test func defaultPlacementUsesTheVisibleFrameOrigin() {
    let visible = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
    let frame = PanelPlacement.frame(size: PanelPlacement.defaultSize, offset: nil, in: visible)
    #expect(frame.minX == CGFloat(1512 + (2560 - 380) / 2))
    #expect(frame.maxY == (visible.maxY - 1415 * 0.22).rounded())
}

@Test func defaultPlacementStaysOnScreenWhenTallerThanTheSpaceBelowTheTopEdge() {
    let short = CGRect(x: 0, y: 100, width: 1200, height: 400)
    let frame = PanelPlacement.frame(size: CGSize(width: 380, height: 380), offset: nil, in: short)
    #expect(frame.minY == 100)
    #expect(frame.height == 380)
    #expect(short.contains(frame))
}

// MARK: - Restore

@Test func restoresASavedOffset() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let frame = PanelPlacement.frame(size: CGSize(width: 400, height: 320), offset: CGPoint(x: 900, y: 40), in: visible)
    #expect(frame == CGRect(x: 900, y: 950 - 40 - 320, width: 400, height: 320))
}

@Test func offsetRoundTripsOnEveryDisplay() {
    for visible in [CGRect(x: 0, y: 0, width: 1512, height: 950), CGRect(x: 1512, y: -200, width: 2560, height: 1415)] {
        let saved = CGRect(x: visible.minX + 123, y: visible.minY + 456, width: 380, height: 300)
        let offset = PanelPlacement.offset(of: saved, in: visible)
        #expect(PanelPlacement.frame(size: saved.size, offset: offset, in: visible) == saved)
    }
}

@Test func offsetIsMeasuredFromTheTopLeft() {
    let visible = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
    let frame = CGRect(x: 1612, y: 1000, width: 380, height: 300)
    #expect(PanelPlacement.offset(of: frame, in: visible) == CGPoint(x: 100, y: visible.maxY - 1300))
}

@Test func anOffsetFollowsTheTopOfTheVisibleFrame() {
    // The Dock moved from the bottom to the left: the panel keeps its distance from the top-left.
    let dockBottom = CGRect(x: 0, y: 80, width: 1512, height: 870)
    let dockLeft = CGRect(x: 80, y: 0, width: 1432, height: 950)
    let offset = CGPoint(x: 200, y: 100)
    let before = PanelPlacement.frame(size: PanelPlacement.defaultSize, offset: offset, in: dockBottom)
    let after = PanelPlacement.frame(size: PanelPlacement.defaultSize, offset: offset, in: dockLeft)
    #expect(before.maxY == after.maxY)
    #expect(after.minX == before.minX + 80)
}

// MARK: - Clamp

@Test func clampsASavedPositionOntoASmallerScreen() {
    // Saved near the bottom-right of a large display, then the resolution dropped.
    let large = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    let saved = CGRect(x: 2100, y: 20, width: 420, height: 340)
    let offset = PanelPlacement.offset(of: saved, in: large)

    let small = CGRect(x: 0, y: 0, width: 1280, height: 775)
    let frame = PanelPlacement.frame(size: saved.size, offset: offset, in: small)
    #expect(frame.size == saved.size)
    #expect(small.contains(frame))
    #expect(frame.maxX == small.maxX)
    #expect(frame.minY == small.minY)
}

@Test func clampsAPositionAboveOrLeftOfTheScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let frame = PanelPlacement.frame(size: PanelPlacement.defaultSize, offset: CGPoint(x: -50, y: -30), in: visible)
    #expect(frame.minX == 0)
    #expect(frame.maxY == 950)
}

@Test func clampsSizeToTheLimits() {
    #expect(PanelPlacement.clampedSize(CGSize(width: 100, height: 50), in: laptop) == PanelPlacement.minimumSize)
    #expect(PanelPlacement.clampedSize(CGSize(width: 2000, height: 2000), in: laptop) == PanelPlacement.maximumSize)
}

@Test func theScreenWinsOverTheMinimumSize() {
    let tiny = CGRect(x: 0, y: 0, width: 280, height: 160)
    let frame = PanelPlacement.frame(size: PanelPlacement.defaultSize, offset: CGPoint(x: 40, y: 40), in: tiny)
    #expect(frame == tiny)
}

@Test func roundsToWholePoints() {
    let visible = CGRect(x: 0, y: 0, width: 1001, height: 777)
    let frame = PanelPlacement.frame(size: CGSize(width: 380.6, height: 300.4), offset: nil, in: visible)
    #expect(frame.minX == frame.minX.rounded())
    #expect(frame.minY == frame.minY.rounded())
    #expect(frame.size == CGSize(width: 380, height: 300))
}

// MARK: - Size migration

@Test func migratesALegacyWidthAtTheDefaultHeight() {
    #expect(PanelPlacement.migratedSize(legacyWidth: 500) == CGSize(width: 500, height: 300))
}

@Test func migratedWidthIsClamped() {
    // T03's default was 640 and it had no maximum.
    #expect(PanelPlacement.migratedSize(legacyWidth: 1200) == CGSize(width: 720, height: 300))
    #expect(PanelPlacement.migratedSize(legacyWidth: 120) == CGSize(width: 300, height: 300))
}
