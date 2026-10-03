import Testing
@testable import OtterCore

// The mirrored constants must match HIToolbox/Events.h, or conversions to and from
// KeyboardShortcuts would silently compare unequal.
@Test func carbonConstantsMatchEventsHeader() {
    #expect(HotkeyCombo.Modifiers.command.rawValue == 256)
    #expect(HotkeyCombo.Modifiers.shift.rawValue == 512)
    #expect(HotkeyCombo.Modifiers.option.rawValue == 2048)
    #expect(HotkeyCombo.Modifiers.control.rawValue == 4096)
    #expect(HotkeyCombo.KeyCode.tab == 48)
    #expect(HotkeyCombo.KeyCode.space == 49)
}

@Test func carbonModifiersRoundTrip() {
    let combo = HotkeyCombo(carbonKeyCode: 49, carbonModifiers: 256 | 2048)
    #expect(combo.modifiers == [.command, .option])
    #expect(combo.carbonModifiers == 256 | 2048)
}

@Test func nonChordModifierBitsAreIgnored() {
    let alphaLock = 1 << 10
    let combo = HotkeyCombo(carbonKeyCode: 49, carbonModifiers: 256 | alphaLock)
    #expect(combo == .commandSpace)
}

@Test func namedCombos() {
    #expect(HotkeyCombo.commandSpace == HotkeyCombo(carbonKeyCode: 49, carbonModifiers: 256))
    #expect(HotkeyCombo.optionSpace == HotkeyCombo(carbonKeyCode: 49, carbonModifiers: 2048))
    #expect(HotkeyCombo.controlSpace == HotkeyCombo(carbonKeyCode: 49, carbonModifiers: 4096))
    #expect(HotkeyCombo.controlCommandSpace == HotkeyCombo(carbonKeyCode: 49, carbonModifiers: 4096 | 256))
    #expect(HotkeyCombo.commandTab == HotkeyCombo(carbonKeyCode: 48, carbonModifiers: 256))
}
