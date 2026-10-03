import Foundation
import Testing
@testable import OtterCore

private let commandFlag = 1 << 20
private let optionFlag = 1 << 19

private func entry(enabled: Any?, parameters: Any? = nil) -> [String: Any] {
    var entry: [String: Any] = [:]
    if let enabled {
        entry["enabled"] = enabled
    }
    if let parameters {
        entry["value"] = ["parameters": parameters, "type": "standard"]
    }
    return entry
}

private func state(_ hotKeys: Any?) -> SpotlightShortcutState {
    SpotlightShortcutState(appleSymbolicHotKeys: hotKeys)
}

// MARK: - Missing means the macOS default (on, ⌘Space)

@Test func missingDomainMeansDefaultEnabled() {
    #expect(state(nil) == .enabled)
}

@Test func missingEntryMeansDefaultEnabled() {
    #expect(state([String: Any]()) == .enabled)
    #expect(state(["60": entry(enabled: false)]) == .enabled)
}

@Test func enabledWithoutBindingMeansDefaultBinding() {
    #expect(state(["64": entry(enabled: true)]) == .enabled)
}

// MARK: - The enabled flag

@Test func enabledOnCommandSpace() {
    #expect(state(["64": entry(enabled: true, parameters: [32, 49, commandFlag])]) == .enabled)
    // Some macOS versions store 65535 as the character for Space.
    #expect(state(["64": entry(enabled: true, parameters: [65535, 49, commandFlag])]) == .enabled)
}

@Test func disabledFlag() {
    #expect(state(["64": entry(enabled: false)]) == .disabled)
    #expect(state(["64": entry(enabled: false, parameters: [32, 49, commandFlag])]) == .disabled)
}

@Test func integerFlags() {
    #expect(state(["64": entry(enabled: 1)]) == .enabled)
    #expect(state(["64": entry(enabled: 0)]) == .disabled)
    #expect(state(["64": entry(enabled: NSNumber(value: 1))]) == .enabled)
    #expect(state(["64": entry(enabled: NSNumber(value: 0))]) == .disabled)
}

// MARK: - Moved off ⌘Space (ADR-010 allows this instead of unchecking)

@Test func movedToAnotherChordFreesCommandSpace() {
    #expect(state(["64": entry(enabled: true, parameters: [32, 49, optionFlag])]) == .disabled)
    #expect(state(["64": entry(enabled: true, parameters: [32, 49, commandFlag | optionFlag])]) == .disabled)
    #expect(state(["64": entry(enabled: true, parameters: [107, 40, commandFlag])]) == .disabled)
}

@Test func nonChordModifierFlagsAreIgnored() {
    let capsLock = 1 << 16
    let function = 1 << 23
    #expect(state(["64": entry(enabled: true, parameters: [32, 49, commandFlag | capsLock | function])]) == .enabled)
}

// MARK: - Unreadable shapes

@Test func unreadableTopLevel() {
    #expect(state("garbage") == .unknown)
    #expect(state([1, 2, 3]) == .unknown)
}

@Test func unreadableEntry() {
    #expect(state(["64": "on"]) == .unknown)
    #expect(state(["64": [String: Any]()]) == .unknown)
    #expect(state(["64": entry(enabled: "1")]) == .unknown)
    #expect(state(["64": entry(enabled: 2)]) == .unknown)
}

@Test func unreadableBinding() {
    #expect(state(["64": ["enabled": true, "value": "⌘Space"]]) == .unknown)
    #expect(state(["64": entry(enabled: true, parameters: [32, 49])]) == .unknown)
    #expect(state(["64": entry(enabled: true, parameters: ["32", "49", "1048576"])]) == .unknown)
    #expect(state(["64": ["enabled": true, "value": ["type": "standard"]]]) == .unknown)
}

// MARK: - Real plist bytes

/// Decodes a plist the way `UserDefaults` hands it over, so the NSNumber/Bool bridging
/// matches what the probe sees at runtime.
private func decodePlist(_ xml: String) throws -> Any {
    try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil)
}

private func plist(enabled: String, modifiers: Int) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>64</key>
        <dict>
            <key>enabled</key>
            \(enabled)
            <key>value</key>
            <dict>
                <key>parameters</key>
                <array>
                    <integer>32</integer>
                    <integer>49</integer>
                    <integer>\(modifiers)</integer>
                </array>
                <key>type</key>
                <string>standard</string>
            </dict>
        </dict>
    </dict>
    </plist>
    """
}

@Test func realPlistShapeFromMacOS27() throws {
    #expect(state(try decodePlist(plist(enabled: "<true/>", modifiers: 1048576))) == .enabled)
    #expect(state(try decodePlist(plist(enabled: "<false/>", modifiers: 1048576))) == .disabled)
    #expect(state(try decodePlist(plist(enabled: "<integer>1</integer>", modifiers: 1048576))) == .enabled)
    #expect(state(try decodePlist(plist(enabled: "<true/>", modifiers: 524288))) == .disabled)
}
