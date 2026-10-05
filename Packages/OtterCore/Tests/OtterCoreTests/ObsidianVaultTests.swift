import Foundation
import Testing
@testable import OtterCore

/// `Tests/Fixtures/Obsidian`.
let obsidianFixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/Obsidian", isDirectory: true)

/// A copy of `Fixtures/Obsidian/Vaults` in a fresh temp directory, so walking up never reaches a
/// real vault above the repo. Remove it with `defer`.
func makeFixtureVaults() throws -> URL {
    let vaults = FileManager.default.temporaryDirectory.appendingPathComponent("OtterCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.copyItem(at: obsidianFixtures.appendingPathComponent("Vaults", isDirectory: true), to: vaults)
    return vaults
}

private func appJSON(_ name: String) throws -> ObsidianVaultSettings {
    ObsidianVaultSettings(appJSON: try Data(contentsOf: obsidianFixtures.appendingPathComponent("app-json/\(name).json")))
}

// MARK: - Finding the vault

@Test func containingFindsTheVaultFromItsRoot() throws {
    let vaults = try makeFixtureVaults()
    defer { try? FileManager.default.removeItem(at: vaults) }
    let notes = vaults.appendingPathComponent("Notes", isDirectory: true)

    let vault = try #require(ObsidianVault.containing(notes))
    #expect(vault.root.path == notes.standardizedFileURL.path)
    #expect(vault.name == "Notes")
}

@Test func containingFindsTheVaultFromADeepSubfolderAndANoteInIt() throws {
    let vaults = try makeFixtureVaults()
    defer { try? FileManager.default.removeItem(at: vaults) }
    let notes = vaults.appendingPathComponent("Notes", isDirectory: true)
    let specs = notes.appendingPathComponent("Projects/Otter/Specs", isDirectory: true)

    #expect(ObsidianVault.containing(specs)?.root.path == notes.standardizedFileURL.path)
    #expect(ObsidianVault.containing(specs.appendingPathComponent("Call Sam.md"))?.root.path == notes.standardizedFileURL.path)
}

@Test func containingPicksTheNearestVaultWhenOneIsInsideAnother() throws {
    let vaults = try makeFixtureVaults()
    defer { try? FileManager.default.removeItem(at: vaults) }
    let archive = vaults.appendingPathComponent("Notes/Archive", isDirectory: true)

    #expect(ObsidianVault.containing(archive.appendingPathComponent("2025", isDirectory: true))?.root.path == archive.standardizedFileURL.path)
    #expect(ObsidianVault.containing(archive)?.name == "Archive")
}

@Test func containingIsNilOutsideAnyVaultAndForAnObsidianFile() throws {
    let vaults = try makeFixtureVaults()
    defer { try? FileManager.default.removeItem(at: vaults) }

    #expect(ObsidianVault.containing(vaults) == nil)
    #expect(ObsidianVault.containing(vaults.appendingPathComponent("NotAVault", isDirectory: true)) == nil)
    #expect(ObsidianVault.containing(vaults.appendingPathComponent("Nowhere/Deeper", isDirectory: true)) == nil)
}

@Test func relativePathIsInsideTheVaultOnly() throws {
    let vaults = try makeFixtureVaults()
    defer { try? FileManager.default.removeItem(at: vaults) }
    let notes = vaults.appendingPathComponent("Notes", isDirectory: true)
    let vault = try #require(ObsidianVault.containing(notes))

    #expect(vault.relativePath(of: notes.appendingPathComponent("Projects/Otter/Call Sam.md")) == "Projects/Otter/Call Sam.md")
    #expect(vault.relativePath(of: notes) == "")
    #expect(vault.relativePath(of: vaults.appendingPathComponent("NotAVault/Note.md")) == nil)
    #expect(vault.relativePath(of: vaults.appendingPathComponent("Notes2/Note.md")) == nil)
}

// MARK: - app.json

@Test(arguments: [
    ("root", "/"),
    ("note-folder", "./"),
    ("note-subfolder", "./assets"),
    ("vault-folder", "Assets/Images"),
])
func settingsReadTheAttachmentFolder(fixture: String, expected: String) throws {
    let settings = try appJSON(fixture)
    #expect(settings == ObsidianVaultSettings(attachmentFolderPath: expected))
}

@Test func settingsReadTheLinkStyle() throws {
    #expect(try appJSON("markdown-links") == ObsidianVaultSettings(useMarkdownLinks: true))
    #expect(try appJSON("absolute-links") == ObsidianVaultSettings(newLinkFormat: .absolute))
}

@Test func settingsFallBackToObsidiansDefaults() throws {
    #expect(ObsidianVaultSettings.defaults == ObsidianVaultSettings(attachmentFolderPath: "/", useMarkdownLinks: false, newLinkFormat: .shortest))
    #expect(try appJSON("malformed") == .defaults)
    #expect(try appJSON("wrong-types") == .defaults)
    #expect(ObsidianVaultSettings(appJSON: Data("[]".utf8)) == .defaults)
    #expect(ObsidianVaultSettings(appJSON: Data(#"{"attachmentFolderPath": ""}"#.utf8)) == .defaults)
}

@Test func settingsLoadFromTheVaultEachTime() throws {
    let vaults = try makeFixtureVaults()
    defer { try? FileManager.default.removeItem(at: vaults) }
    let vault = ObsidianVault(root: vaults.appendingPathComponent("Notes", isDirectory: true))
    // The empty `.obsidian/` has no app.json.
    #expect(ObsidianVaultSettings.load(from: vault) == .defaults)

    try FileManager.default.copyItem(
        at: obsidianFixtures.appendingPathComponent("app-json/vault-folder.json"),
        to: vault.configDirectory.appendingPathComponent("app.json")
    )
    #expect(ObsidianVaultSettings.load(from: vault).attachmentFolderPath == "Assets/Images")
}
