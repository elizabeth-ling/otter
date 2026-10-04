import Testing
@testable import OtterCore

@Test func resignKeyThenSpaceChangeIsASwitch() {
    #expect(PanelSpaceSwitch.isSpaceSwitch(resignedAt: 100, spaceChangedAt: 100.2))
}

@Test func spaceChangeThenResignKeyIsASwitch() {
    #expect(PanelSpaceSwitch.isSpaceSwitch(resignedAt: 100.2, spaceChangedAt: 100))
}

@Test func graceIntervalIsInclusive() {
    let edge = 100 + PanelSpaceSwitch.graceInterval
    #expect(PanelSpaceSwitch.isSpaceSwitch(resignedAt: 100, spaceChangedAt: edge))
    #expect(!PanelSpaceSwitch.isSpaceSwitch(resignedAt: 100, spaceChangedAt: edge + 0.01))
}

@Test func farApartEventsAreAClickElsewhere() {
    #expect(!PanelSpaceSwitch.isSpaceSwitch(resignedAt: 100, spaceChangedAt: 50))
}

@Test func missingEventIsNotASwitch() {
    #expect(!PanelSpaceSwitch.isSpaceSwitch(resignedAt: 100, spaceChangedAt: nil))
    #expect(!PanelSpaceSwitch.isSpaceSwitch(resignedAt: nil, spaceChangedAt: 100))
    #expect(!PanelSpaceSwitch.isSpaceSwitch(resignedAt: nil, spaceChangedAt: nil))
}
