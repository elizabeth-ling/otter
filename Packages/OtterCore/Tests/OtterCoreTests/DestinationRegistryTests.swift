import Foundation
import Testing
@testable import OtterCore

/// A throwaway `UserDefaults` suite. Call `remove()` with `defer`.
private struct TestDefaults {
    let name = "OtterCoreTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: name)! }
    func remove() { defaults.removePersistentDomain(forName: name) }
}

private func folder(_ name: String) -> DestinationConfig {
    DestinationConfig(name: name, options: .folder(FolderOptions(bookmark: Data(name.utf8), displayPath: "~/\(name)")))
}

private func fakeFactory(clock: TestClock = TestClock()) -> DestinationFactory {
    var factory = DestinationFactory()
    factory.register(.folder) { config in FakeDestination(id: config.id, name: config.name, clock: clock) }
    return factory
}

@Test func configsAndDefaultPersistAcrossInstances() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let inbox = folder("Inbox")
    let journal = folder("Journal")

    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    registry.add(inbox)
    registry.add(journal)
    registry.setDefault(journal.id)

    let reloaded = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    #expect(reloaded.configs == [inbox, journal])
    #expect(reloaded.defaultID == journal.id)
}

@Test func firstDestinationBecomesDefaultAndRemovingTheDefaultFallsBackToTheFirst() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    #expect(registry.defaultID == nil)

    let a = folder("A"), b = folder("B"), c = folder("C")
    registry.add(a)
    registry.add(b)
    registry.add(c)
    #expect(registry.defaultID == a.id)

    registry.setDefault(c.id)
    registry.remove(c.id)
    #expect(registry.defaultID == a.id)
    #expect(registry.configs.map(\.id) == [a.id, b.id])
}

@Test func shortcutNumbersFollowTheOrder() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    let a = folder("A"), b = folder("B"), c = folder("C")
    [a, b, c].forEach(registry.add)

    registry.move(c.id, to: 0)

    #expect(registry.config(forShortcut: 1) == c)
    #expect(registry.config(forShortcut: 2) == a)
    #expect(registry.config(forShortcut: 3) == b)
    #expect(registry.config(forShortcut: 4) == nil)
    #expect(registry.config(forShortcut: 0) == nil)
    #expect(registry.config(forShortcut: 10) == nil)
}

@Test func factoryBuildsRegisteredKindsOnceAndRebuildsAfterAnUpdate() throws {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: fakeFactory())
    var inbox = folder("Inbox")
    registry.add(inbox)

    let first = try #require(registry.destination(for: inbox.id) as? FakeDestination)
    #expect(first.displayName == "Inbox")
    #expect(registry.destination(for: inbox.id) as? FakeDestination === first)

    inbox.name = "Renamed"
    registry.update(inbox)
    let rebuilt = try #require(registry.destination(for: inbox.id) as? FakeDestination)
    #expect(rebuilt !== first)
    #expect(rebuilt.displayName == "Renamed")
}

@Test func unknownIDsAndKindsWithoutABuilderResolveToNothing() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    let inbox = folder("Inbox")
    registry.add(inbox)

    #expect(registry.destination(for: inbox.id) == nil, "no folder builder until T06")
    #expect(registry.destination(for: DestinationID()) == nil)
}

@Test func destinationConfigRoundTripsThroughJSON() throws {
    let config = folder("Inbox")
    let data = try JSONEncoder().encode([config])
    #expect(try JSONDecoder().decode([DestinationConfig].self, from: data) == [config])
    #expect(config.kind == .folder)
}

// MARK: - Folder destinations (T06)

@Test func modifyChangesOneConfigAndRebuildsItsDestination() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: fakeFactory())
    let inbox = folder("Inbox")
    registry.add(inbox)
    let before = registry.destination(for: inbox.id)

    registry.modify(inbox.id) { $0.name = "Renamed" }

    #expect(registry.config(for: inbox.id)?.name == "Renamed")
    #expect(registry.destination(for: inbox.id)?.displayName == "Renamed")
    #expect(before?.displayName == "Inbox")
}

@Test func defaultInboxIsAddedOnlyWhenNothingIsConfigured() throws {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    let documents = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)

    registry.addDefaultInboxIfEmpty(documents: documents)
    registry.addDefaultInboxIfEmpty(documents: documents)

    #expect(registry.configs.count == 1)
    let inbox = try #require(registry.configs.first)
    #expect(registry.defaultID == inbox.id)
    #expect(inbox.name == "Otter Inbox")
    guard case let .folder(options) = inbox.options else {
        Issue.record("The default inbox is a folder destination")
        return
    }
    #expect(options.bookmark.isEmpty)
    #expect(options.fallbackPath == "/Users/me/Documents/Otter Inbox")
    #expect(options.mode == .newFilePerNote)
}

@Test func choosingAFolderRepointsTheDefaultFolderDestinationKeepingItsID() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    registry.addDefaultInboxIfEmpty(documents: URL(fileURLWithPath: "/Users/me/Documents"))
    let inboxID = registry.defaultID

    let chosen = registry.chooseFolder(bookmark: Data("vault".utf8), displayPath: "~/Vault", name: "Vault")

    #expect(chosen == inboxID)
    #expect(registry.configs.count == 1)
    let config = registry.config(for: chosen)
    #expect(config?.name == "Vault")
    guard case let .folder(options)? = config?.options else {
        Issue.record("Still a folder destination")
        return
    }
    #expect(options.bookmark == Data("vault".utf8))
    #expect(options.displayPath == "~/Vault")
    #expect(options.fallbackPath == nil)
}

@Test func choosingAFolderWithNoDestinationAddsOneAsTheDefault() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())

    let chosen = registry.chooseFolder(bookmark: Data("vault".utf8), displayPath: "~/Vault", name: "Vault")

    #expect(registry.defaultID == chosen)
    #expect(registry.config(for: chosen)?.name == "Vault")
}

@Test func updatingABookmarkFollowsAFolderRename() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    let config = DestinationConfig(name: "Old", options: .folder(FolderOptions(bookmark: Data("old".utf8), displayPath: "~/Notes/Old")))
    registry.add(config)

    registry.updateFolderBookmark(config.id, bookmark: Data("new".utf8), displayPath: "~/Notes/New")

    #expect(registry.config(for: config.id)?.name == "New")
}

@Test func updatingABookmarkKeepsTheOtherSettings() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    let options = FolderOptions(bookmark: Data("old".utf8), displayPath: "~/Old", mode: .appendToFile(name: "Inbox.md"), subfolder: "Daily", frontmatter: false)
    let config = DestinationConfig(name: "Journal", options: .folder(options))
    registry.add(config)

    registry.updateFolderBookmark(config.id, bookmark: Data("new".utf8), displayPath: "~/New")

    var expected = options
    expected.bookmark = Data("new".utf8)
    expected.displayPath = "~/New"
    #expect(registry.config(for: config.id)?.options == .folder(expected))
    #expect(registry.config(for: config.id)?.name == "Journal")
}

@Test func folderOptionsSavedBeforeT06DecodeWithDefaults() throws {
    let json = #"{"bookmark":"AQID","displayPath":"~/Notes"}"#
    let options = try JSONDecoder().decode(FolderOptions.self, from: Data(json.utf8))

    #expect(options == FolderOptions(bookmark: Data([1, 2, 3]), displayPath: "~/Notes"))
    #expect(options.mode == .newFilePerNote)
    #expect(options.filenameTemplate == "{date} {time} {title}")
    #expect(options.frontmatter)
    #expect(options.appendTemplate == AppendTemplate.default)
    #expect(options.attachmentsFolder == "attachments")
}

@Test func folderOptionsRoundTripThroughJSON() throws {
    let options = FolderOptions(bookmark: Data([9]), displayPath: "~/V", fallbackPath: "/V", mode: .appendToFile(name: "Inbox.md"), subfolder: "Daily", filenameTemplate: "{title}", frontmatter: false, appendTemplate: "{{text}}", attachmentsFolder: "files")
    let decoded = try JSONDecoder().decode(FolderOptions.self, from: JSONEncoder().encode(options))
    #expect(decoded == options)
}
