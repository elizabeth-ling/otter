import Testing
@testable import OtterCore

private let suggestedClipboard = HotkeyCombo(carbonKeyCode: 49, modifiers: [.option, .shift]) // ⌥⇧Space

@Test func reservedChordsAreWarnedAbout() {
    #expect(ShortcutValidation(recorded: .controlSpace, other: nil) == .reserved(.inputSourceSwitching))
    #expect(ShortcutValidation(recorded: .commandTab, other: nil) == .reserved(.appSwitcher))
    #expect(ShortcutValidation(recorded: .controlCommandSpace, other: nil) == .reserved(.emojiPicker))
}

@Test func commandSpaceIsNotWarnedAbout() {
    #expect(ReservedShortcut(.commandSpace) == nil)
    #expect(ShortcutValidation(recorded: .commandSpace, other: suggestedClipboard) == .ok)
}

@Test func ordinaryChordsAreFine() {
    #expect(ShortcutValidation(recorded: .optionSpace, other: suggestedClipboard) == .ok)
    #expect(ShortcutValidation(recorded: suggestedClipboard, other: .commandSpace) == .ok)
    // Extra modifiers make it a different chord.
    let controlShiftSpace = HotkeyCombo(carbonKeyCode: 49, modifiers: [.control, .shift])
    #expect(ShortcutValidation(recorded: controlShiftSpace, other: nil) == .ok)
}

@Test func sameShortcutForBothActionsIsRefused() {
    #expect(ShortcutValidation(recorded: suggestedClipboard, other: suggestedClipboard) == .duplicate)
    #expect(ShortcutValidation(recorded: .commandSpace, other: .commandSpace) == .duplicate)
    // A duplicate is refused even when it is also reserved.
    #expect(ShortcutValidation(recorded: .controlSpace, other: .controlSpace) == .duplicate)
}

@Test func clearingIsAlwaysAllowed() {
    #expect(ShortcutValidation(recorded: nil, other: nil) == .ok)
    #expect(ShortcutValidation(recorded: nil, other: .commandSpace) == .ok)
}

@Test func everyReservedCaseMapsBackFromItsCombo() {
    for reserved in ReservedShortcut.allCases {
        #expect(ReservedShortcut(reserved.combo) == reserved)
    }
}
