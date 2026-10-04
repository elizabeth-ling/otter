import CoreGraphics
import Foundation
import Testing
@testable import OtterCore

/// A throwaway `UserDefaults` suite. Call `remove()` with `defer`.
private struct TestDefaults {
    let name = "OtterCoreTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: name)! }
    func remove() { defaults.removePersistentDomain(forName: name) }
}

private let laptopUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
private let externalUUID = "1E6E23D6-9F5B-4B0C-A2C5-1F6B9C1D7E44"

@Test func nothingSavedMeansDefaults() {
    let test = TestDefaults()
    defer { test.remove() }
    let store = PanelFrameStore(defaults: test.defaults)
    #expect(store.size == nil)
    #expect(store.offset(forDisplay: laptopUUID) == nil)
}

@Test func sizeAndPositionsSurviveARelaunch() {
    let test = TestDefaults()
    defer { test.remove() }
    let store = PanelFrameStore(defaults: test.defaults)
    store.saveSize(CGSize(width: 420, height: 360))
    store.saveOffset(CGPoint(x: 40, y: 60), forDisplay: laptopUUID)
    store.saveOffset(CGPoint(x: 1800, y: 200), forDisplay: externalUUID)

    let relaunched = PanelFrameStore(defaults: test.defaults)
    #expect(relaunched.size == CGSize(width: 420, height: 360))
    #expect(relaunched.offset(forDisplay: laptopUUID) == CGPoint(x: 40, y: 60))
    #expect(relaunched.offset(forDisplay: externalUUID) == CGPoint(x: 1800, y: 200))
}

@Test func aDisplayWithNoSavedPositionGetsNone() {
    let test = TestDefaults()
    defer { test.remove() }
    let store = PanelFrameStore(defaults: test.defaults)
    store.saveOffset(CGPoint(x: 40, y: 60), forDisplay: laptopUUID)
    #expect(store.offset(forDisplay: externalUUID) == nil)
}

@Test func migratesT03sWidthOnceAndDropsIt() {
    let test = TestDefaults()
    defer { test.remove() }
    test.defaults.set(640.0, forKey: PanelFrameStore.legacyWidthKey)

    let store = PanelFrameStore(defaults: test.defaults)
    #expect(store.size == CGSize(width: 640, height: 300))
    #expect(test.defaults.object(forKey: PanelFrameStore.legacyWidthKey) == nil)
    #expect(PanelFrameStore(defaults: test.defaults).size == CGSize(width: 640, height: 300))
}

@Test func anExistingSizeWinsOverALegacyWidth() {
    let test = TestDefaults()
    defer { test.remove() }
    test.defaults.set(["width": 500.0, "height": 400.0], forKey: PanelFrameStore.sizeKey)
    test.defaults.set(640.0, forKey: PanelFrameStore.legacyWidthKey)
    #expect(PanelFrameStore(defaults: test.defaults).size == CGSize(width: 500, height: 400))
}

@Test func resetClearsSizeAndEveryPosition() {
    let test = TestDefaults()
    defer { test.remove() }
    let store = PanelFrameStore(defaults: test.defaults)
    store.saveSize(CGSize(width: 420, height: 360))
    store.saveOffset(CGPoint(x: 40, y: 60), forDisplay: laptopUUID)
    store.reset()

    #expect(store.size == nil)
    #expect(store.offset(forDisplay: laptopUUID) == nil)
    #expect(test.defaults.object(forKey: PanelFrameStore.sizeKey) == nil)
    #expect(test.defaults.object(forKey: PanelFrameStore.positionsKey) == nil)
}

@Test func ignoresMalformedValues() {
    let test = TestDefaults()
    defer { test.remove() }
    test.defaults.set(["width": 0.0, "height": 400.0], forKey: PanelFrameStore.sizeKey)
    test.defaults.set([laptopUUID: ["x": 10.0], externalUUID: ["x": 5.0, "y": 6.0]], forKey: PanelFrameStore.positionsKey)

    let store = PanelFrameStore(defaults: test.defaults)
    #expect(store.size == nil)
    #expect(store.offset(forDisplay: laptopUUID) == nil)
    #expect(store.offset(forDisplay: externalUUID) == CGPoint(x: 5, y: 6))
}
