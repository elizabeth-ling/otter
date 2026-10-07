import Foundation
import Testing
@testable import OtterCore

/// A throwaway `UserDefaults` suite. Call `remove()` with `defer`.
private struct TestDefaults {
    let name = "OtterCoreTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: name)! }
    func remove() { defaults.removePersistentDomain(forName: name) }
}

private func folderConfig(_ name: String, displayPath: String? = nil, mode: FolderOptions.Mode = .newFilePerNote) -> DestinationConfig {
    let options = FolderOptions(bookmark: Data(name.utf8), displayPath: displayPath ?? "~/\(name)", mode: mode)
    return DestinationConfig(name: name, options: .folder(options))
}

// MARK: - AppSettings

@Test func settingsHaveTheSpecDefaults() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let settings = AppSettings(defaults: suite.defaults)

    #expect(settings.keepPanelOpenWhenClickingElsewhere == false)
    #expect(settings.fontFamily == .system)
    #expect(settings.fontSize == 15)
    #expect(settings.smartQuotesAndDashes == false)
    #expect(settings.launchAtLogin == true)
    #expect(settings.remembersRecents == true)
    #expect(settings.hasOnboarded == false)
}

@Test func settingsPersistAndFontSizeIsClamped() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let settings = AppSettings(defaults: suite.defaults)
    settings.fontFamily = .monospaced
    settings.fontSize = 99
    settings.launchAtLogin = false
    settings.remembersRecents = false

    let reread = AppSettings(defaults: suite.defaults)
    #expect(reread.fontFamily == .monospaced)
    #expect(reread.fontSize == AppSettings.fontSizes.upperBound)
    #expect(reread.launchAtLogin == false)
    #expect(reread.remembersRecents == false)

    settings.fontSize = 3
    #expect(reread.fontSize == AppSettings.fontSizes.lowerBound)
    settings.fontSize = 13.4
    #expect(reread.fontSize == 13)
}

@Test func resetAllClearsEverythingButOnboarding() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let settings = AppSettings(defaults: suite.defaults)
    settings.hasOnboarded = true
    settings.fontSize = 20
    suite.defaults.set(Data([1]), forKey: DestinationRegistry.configsKey)
    suite.defaults.set("x", forKey: "KeyboardShortcuts_togglePanel")

    settings.resetAll(domain: suite.name)

    #expect(settings.fontSize == 15)
    #expect(settings.hasOnboarded)
    #expect(suite.defaults.object(forKey: DestinationRegistry.configsKey) == nil)
    #expect(suite.defaults.object(forKey: "KeyboardShortcuts_togglePanel") == nil)
}

@Test func resetAllBeforeOnboardingLeavesItToShow() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let settings = AppSettings(defaults: suite.defaults)
    settings.fontSize = 20

    settings.resetAll(domain: suite.name)

    #expect(settings.hasOnboarded == false)
}

// MARK: - Destination status

@Test func healthMapsToTheDotColour() {
    #expect(DestinationHealth.ok.level == .good)
    #expect(DestinationHealth.needsPermission.level == .warning)
    #expect(DestinationHealth.unreachable("Folder missing").level == .failing)
}

@Test func healthProblemsOfferAFix() {
    #expect(DestinationProblem(health: .ok, destinationName: "Inbox") == nil)
    #expect(DestinationProblem(health: .needsPermission, destinationName: "Inbox")?.fix == .grantAccess)
    let missing = DestinationProblem(health: .unreachable(FolderDestinationError.folderMissing.localizedDescription), destinationName: "Inbox")
    #expect(missing?.fix == .chooseFolder)
    #expect(missing?.message == "Can't write to ‘Inbox’: the folder is missing. Choose it again.")
    #expect(DestinationProblem(health: .unreachable("Offline"), destinationName: "Inbox")?.fix == nil)
}

@Test func deliveryErrorsBecomeActionableProblems() {
    #expect(DestinationProblem(error: FolderDestinationError.folderMissing, destinationName: "Vault").fix == .chooseFolder)
    #expect(DestinationProblem(error: FolderDestinationError.unsafePath, destinationName: "Vault").fix == nil)
    #expect(DestinationProblem(error: CocoaError(.fileWriteNoPermission), destinationName: "Vault").fix == .grantAccess)
    #expect(DestinationProblem(error: POSIXError(.EPERM), destinationName: "Vault").fix == .grantAccess)
    let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue, userInfo: [NSUnderlyingErrorKey: POSIXError(.EACCES) as NSError])
    #expect(DestinationProblem(error: wrapped, destinationName: "Vault").fix == .grantAccess)
    let full = DestinationProblem(error: CocoaError(.fileWriteOutOfSpace), destinationName: "Vault")
    #expect(full.message == "Can't write to ‘Vault’: the disk is full.")
    #expect(full.fix == nil)
    #expect(DestinationProblem(error: FakeDeliveryError.offline, destinationName: "Vault").fix == nil)
}

@Test func modeSummaryNamesTheAppendFile() {
    #expect(folderConfig("Inbox").modeSummary == "New file per note")
    #expect(folderConfig("Inbox", mode: .appendToFile(name: "Inbox")).modeSummary == "Appends to Inbox.md")
    #expect(folderConfig("Inbox", mode: .appendToFile(name: "Log.txt")).modeSummary == "Appends to Log.txt")
}

@Test func testButtonWritesARealNote() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let options = FolderOptions(bookmark: try FolderBookmark.make(for: root), displayPath: root.path, frontmatter: false)
    let destination = FolderDestination(id: DestinationID(), name: "Notes", options: options)

    let result = await DestinationTest.run(destination, files: root.appendingPathComponent("none"), now: referenceDate)

    guard case let .success(receipt) = result, case let .file(file) = receipt.location else {
        Issue.record("Expected a written file, got \(result)")
        return
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == DestinationTest.text + "\n")
}

@Test func testButtonReportsAMissingFolder() async throws {
    let root = try makeTemporaryDirectory()
    let folder = root.appendingPathComponent("Gone", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let options = FolderOptions(bookmark: try FolderBookmark.make(for: folder), displayPath: folder.path)
    let destination = FolderDestination(id: DestinationID(), name: "Gone", options: options)
    try FileManager.default.removeItem(at: root)

    let result = await DestinationTest.run(destination, files: root)

    #expect(result == .failure(DestinationProblem(error: FolderDestinationError.folderMissing, destinationName: "Gone")))
}

// MARK: - Registry

@Test func resetLeavesOnlyTheGivenDestination() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    registry.add(folderConfig("A"))
    registry.add(folderConfig("B"))
    let inbox = DestinationConfig.defaultInbox()

    registry.reset(to: inbox)

    #expect(registry.configs == [inbox])
    #expect(registry.defaultID == inbox.id)
    #expect(DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory()).configs == [inbox])
}

@Test func setFolderKeepsTheIDAndFollowsTheFolderNameUnlessRenamed() {
    let suite = TestDefaults()
    defer { suite.remove() }
    let registry = DestinationRegistry(defaults: suite.defaults, factory: DestinationFactory())
    let followsFolder = folderConfig("Notes", displayPath: "~/Notes")
    var named = folderConfig("Work", displayPath: "~/Projects")
    named.name = "Work"
    registry.add(followsFolder)
    registry.add(named)

    registry.setFolder(followsFolder.id, bookmark: Data("new".utf8), displayPath: "~/Journal")
    registry.setFolder(named.id, bookmark: Data("new".utf8), displayPath: "~/Elsewhere")

    #expect(registry.config(for: followsFolder.id)?.name == "Journal")
    #expect(registry.config(for: followsFolder.id)?.folderDisplayPath == "~/Journal")
    #expect(registry.config(for: named.id)?.name == "Work")
    #expect(registry.config(for: named.id)?.folderDisplayPath == "~/Elsewhere")
    #expect(registry.defaultID == followsFolder.id)
}

// MARK: - Outbox and delivery

@Test(.timeLimit(.minutes(1)))
func rerouteMovesOnlyTheDeletedDestinationsCapturesAndSurvivesARelaunch() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let outbox = Outbox(directory: root)
    let deleted = DestinationID()
    let other = DestinationID()
    let target = DestinationID()
    let a = makeCapture("a", destination: deleted)
    let b = makeCapture("b", destination: other)
    let c = makeCapture("c", destination: deleted)
    for capture in [a, b, c] {
        try await outbox.enqueue(capture)
    }
    try await outbox.markFailed(a.id, error: "Folder missing", nextAttemptAt: referenceDate + 300)

    #expect(try await outbox.reroute(from: deleted, to: target) == 2)

    let reloaded = await Outbox(directory: root).pending()
    #expect(reloaded.map(\.capture.destinationID) == [target, other, target])
    #expect(reloaded.allSatisfy { $0.nextAttemptAt == nil })
    #expect(reloaded.first?.attempts == 1)
}

@Test(.timeLimit(.minutes(1)))
func retryNowDeliversAWaitingCaptureWithoutWaitingForTheBackoff() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let destination = FakeDestination(failTimes: 1, clock: clock)
    let outbox = Outbox(directory: root)
    let service = DeliveryService(outbox: outbox, destinations: { _ in destination }, clock: clock)
    let capture = makeCapture(destination: destination.id)

    try await outbox.enqueue(capture)
    await service.kick()
    _ = await clock.nextSleepDeadline()

    await service.retryNow()
    await destination.waitForDeliveries(1)
    await service.waitUntilIdle()

    #expect(await destination.attemptTimes == [clock.now, clock.now], "the clock never moved")
    #expect(await outbox.pending().isEmpty)
    #expect(clock.sleepDeadlines.isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func deliveriesStreamReportsEachAcceptedCapture() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let destination = FakeDestination(name: "Vault", clock: clock)
    let outbox = Outbox(directory: root)
    let service = DeliveryService(outbox: outbox, destinations: { _ in destination }, clock: clock)
    let deliveries = await service.deliveries()
    let capture = makeCapture(destination: destination.id)

    try await outbox.enqueue(capture)
    await service.kick()

    var iterator = deliveries.makeAsyncIterator()
    let delivery = try #require(await iterator.next())
    #expect(delivery.captureID == capture.id)
    #expect(delivery.destinationID == destination.id)
    #expect(delivery.destinationName == "Vault")
    #expect(delivery.receipt.location == .file(URL(fileURLWithPath: "/fake/\(capture.id).md")))
}

// MARK: - Onboarding

@Test func onboardingHotkeyStepAsksForAPressOfWhatIsRegistered() {
    let optionSpace = EffectiveToggleHotkey(combo: .optionSpace)
    #expect(OnboardingHotkeyStatus(effective: optionSpace, lastPress: nil) == .pressToConfirm(.optionSpace))
    #expect(OnboardingHotkeyStatus(effective: optionSpace, lastPress: .optionSpace) == .confirmed(.optionSpace))
    #expect(OnboardingHotkeyStatus(effective: EffectiveToggleHotkey(combo: nil), lastPress: nil) == .noShortcut)
}

@Test func onboardingWaitsForSpotlightThenAsksForCommandSpace() {
    let handoff = EffectiveToggleHotkey.resolve(chosen: .commandSpace, spotlight: .enabled, saveClipboard: nil)
    // A press of the ⌥Space fallback doesn't count as confirming ⌘Space.
    #expect(OnboardingHotkeyStatus(effective: handoff, lastPress: .optionSpace) == .waitingForSpotlight)

    let freed = EffectiveToggleHotkey.resolve(chosen: .commandSpace, spotlight: .disabled, saveClipboard: nil)
    #expect(OnboardingHotkeyStatus(effective: freed, lastPress: .optionSpace) == .pressToConfirm(.commandSpace))
    #expect(OnboardingHotkeyStatus(effective: freed, lastPress: .commandSpace).isConfirmed)
}
