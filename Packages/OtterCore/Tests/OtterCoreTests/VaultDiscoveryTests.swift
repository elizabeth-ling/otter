import Foundation
import Testing
@testable import OtterCore

/// `Fixtures/Obsidian/obsidian.json` with its `{ROOT}` paths pointed at `vaults`, written next to them.
private func writeObsidianJSON(for vaults: URL) throws -> URL {
    let template = try String(contentsOf: obsidianFixtures.appendingPathComponent("obsidian.json"), encoding: .utf8)
    let file = vaults.appendingPathComponent("obsidian.json")
    try template.replacingOccurrences(of: "{ROOT}", with: vaults.path).write(to: file, atomically: true, encoding: .utf8)
    return file
}

@Test func discoveryListsExistingVaultsNewestFirst() throws {
    let vaults = try makeFixtureVaults()
    defer { try? FileManager.default.removeItem(at: vaults) }

    let found = VaultDiscovery.vaults(configURL: try writeObsidianJSON(for: vaults))

    // `Gone` doesn't exist and `NotAVault` has a `.obsidian` file rather than a folder.
    #expect(found.map(\.name) == ["Archive", "Notes"])
    #expect(found.map(\.id) == ["1122334455667788", "a1b2c3d4e5f60708"])
    #expect(found.first?.path.path == vaults.appendingPathComponent("Notes/Archive").standardizedFileURL.path)
    #expect(found.first?.lastOpened == Date(timeIntervalSince1970: 1_759_500_000))
}

@Test func discoveryPutsVaultsWithoutATimestampLast() throws {
    let vaults = try makeFixtureVaults()
    defer { try? FileManager.default.removeItem(at: vaults) }
    let file = vaults.appendingPathComponent("obsidian.json")
    let json = #"{"vaults": {"x": {"path": "\#(vaults.path)/Notes"}, "y": {"path": "\#(vaults.path)/Notes/Archive", "ts": 1}, "z": {"ts": 2}}}"#
    try json.write(to: file, atomically: true, encoding: .utf8)

    #expect(VaultDiscovery.vaults(configURL: file).map(\.name) == ["Archive", "Notes"])
}

@Test func discoveryIsEmptyForAMissingOrMalformedFile() throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("obsidian.json")

    #expect(VaultDiscovery.vaults(configURL: file).isEmpty)
    try Data(#"{"vaults": {"x": "#.utf8).write(to: file)
    #expect(VaultDiscovery.vaults(configURL: file).isEmpty)
    try Data(#"{"vaults": []}"#.utf8).write(to: file)
    #expect(VaultDiscovery.vaults(configURL: file).isEmpty)
}
