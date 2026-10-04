import CoreGraphics
import Testing
@testable import OtterCore

private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
/// To the right of the laptop, taller, and offset upward.
private let external = CGRect(x: 1512, y: -200, width: 2560, height: 1440)

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

@Test func centersHorizontallyWithTopEdgeAt22Percent() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let frame = PanelPlacement.frame(width: 640, height: 56, in: visible)
    #expect(frame.width == 640)
    #expect(frame.height == 56)
    #expect(frame.midX == visible.midX)
    #expect(frame.maxY == (950 - 950 * 0.22).rounded())
}

@Test func usesTheVisibleFrameOrigin() {
    let visible = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
    let frame = PanelPlacement.frame(width: 640, height: 56, in: visible)
    #expect(frame.minX == CGFloat(1512 + (2560 - 640) / 2))
    #expect(frame.maxY == (visible.maxY - 1415 * 0.22).rounded())
}

@Test func clampsWidthToTheScreenAndTheMinimum() {
    let narrow = CGRect(x: 0, y: 0, width: 500, height: 800)
    #expect(PanelPlacement.frame(width: 900, height: 56, in: narrow).width == 500)
    #expect(PanelPlacement.frame(width: 900, height: 56, in: narrow).minX == 0)
    #expect(PanelPlacement.frame(width: 100, height: 56, in: laptop).width == PanelPlacement.minimumWidth)
}

@Test func staysOnScreenWhenTallerThanTheSpaceBelowTheTopEdge() {
    let short = CGRect(x: 0, y: 100, width: 1200, height: 300)
    let frame = PanelPlacement.frame(width: 640, height: 280, in: short)
    #expect(frame.minY == 100)
    #expect(frame.maxY <= short.maxY)
    #expect(PanelPlacement.frame(width: 640, height: 500, in: short).height == 300)
}

@Test func roundsToWholePoints() {
    let visible = CGRect(x: 0, y: 0, width: 1001, height: 777)
    let frame = PanelPlacement.frame(width: 640.6, height: 56.2, in: visible)
    #expect(frame.minX == frame.minX.rounded())
    #expect(frame.minY == frame.minY.rounded())
    #expect(frame.width == 640)
    #expect(frame.height == 57)
}
