import Testing
@testable import OtterCore

private let custom = HotkeyCombo(carbonKeyCode: 40, modifiers: [.control, .option]) // ⌃⌥K
private let suggestedClipboard = HotkeyCombo(carbonKeyCode: 49, modifiers: [.option, .shift]) // ⌥⇧Space

// The T02 scope 3 table, row by row.

@Test func commandSpaceWithSpotlightOffRegistersCommandSpace() {
    let result = EffectiveToggleHotkey.resolve(chosen: .commandSpace, spotlight: .disabled, saveClipboard: nil)
    #expect(result == EffectiveToggleHotkey(combo: .commandSpace))
}

@Test func commandSpaceWithSpotlightOnFallsBackToOptionSpace() {
    let result = EffectiveToggleHotkey.resolve(chosen: .commandSpace, spotlight: .enabled, saveClipboard: suggestedClipboard)
    #expect(result.combo == .optionSpace)
    #expect(result.combo == EffectiveToggleHotkey.fallback)
    #expect(result.needsSpotlightHandoff)
    #expect(!result.needsPressToConfirm)
}

@Test func commandSpaceWithUnknownProbeRegistersCommandSpaceAndAsksToConfirm() {
    let result = EffectiveToggleHotkey.resolve(chosen: .commandSpace, spotlight: .unknown, saveClipboard: nil)
    #expect(result == EffectiveToggleHotkey(combo: .commandSpace, needsPressToConfirm: true))
}

@Test(arguments: [SpotlightShortcutState.enabled, .disabled, .unknown])
func anyOtherShortcutIsRegisteredAsIs(spotlight: SpotlightShortcutState) {
    #expect(EffectiveToggleHotkey.resolve(chosen: custom, spotlight: spotlight, saveClipboard: nil) == EffectiveToggleHotkey(combo: custom))
    // Choosing ⌥Space directly is not the fallback: no handoff needed.
    #expect(EffectiveToggleHotkey.resolve(chosen: .optionSpace, spotlight: spotlight, saveClipboard: nil) == EffectiveToggleHotkey(combo: .optionSpace))
}

// Beyond the table.

@Test(arguments: [SpotlightShortcutState.enabled, .disabled, .unknown])
func clearedShortcutRegistersNothing(spotlight: SpotlightShortcutState) {
    #expect(EffectiveToggleHotkey.resolve(chosen: nil, spotlight: spotlight, saveClipboard: nil) == EffectiveToggleHotkey(combo: nil))
}

@Test func fallbackNeverCollidesWithSaveClipboard() {
    let result = EffectiveToggleHotkey.resolve(chosen: .commandSpace, spotlight: .enabled, saveClipboard: .optionSpace)
    #expect(result.combo == .commandSpace)
    #expect(result.needsSpotlightHandoff)
}
