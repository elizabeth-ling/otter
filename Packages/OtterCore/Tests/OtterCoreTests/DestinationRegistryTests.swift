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
