import AppKit
import Observation
import OtterCore
import os
import ServiceManagement

/// The Settings window's state (T10, UX_SPEC §5): Otter's preferences (`AppSettings`), the
/// destinations (`DestinationRegistry`) and the outbox status. Every change applies straight away;
/// there's no Save button. Health checks run when the Destinations tab appears and after edits,
/// never on a timer.
@MainActor
@Observable
final class SettingsModel {
    /// The last Test of one destination.
    enum TestState: Equatable {
        case running
        case passed(DeliveryReceipt)
        case failed(DestinationProblem)
    }

    @ObservationIgnored let hotkeys: HotkeyService
    @ObservationIgnored let folderChooser: FolderChooser
    /// For sheets: the folder picker, confirmations.
    @ObservationIgnored weak var window: NSWindow?

    @ObservationIgnored private let settings = AppSettings()
    @ObservationIgnored private let registry: DestinationRegistry
    @ObservationIgnored private let outbox: Outbox
    @ObservationIgnored private let delivery: DeliveryService
    @ObservationIgnored private let recents: RecentStore
    @ObservationIgnored private let panel: PanelController
    @ObservationIgnored private let updates: UpdateController
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    // MARK: General

    var keepPanelOpen: Bool {
        didSet { settings.keepPanelOpenWhenClickingElsewhere = keepPanelOpen }
    }

    var fontFamily: EditorFontFamily {
        didSet {
            settings.fontFamily = fontFamily
            panel.applyEditorSettings()
        }
    }

    var fontSize: Double {
        didSet {
            settings.fontSize = fontSize
            panel.applyEditorSettings()
        }
    }

    var smartQuotesAndDashes: Bool {
        didSet {
            settings.smartQuotesAndDashes = smartQuotesAndDashes
            panel.applyEditorSettings()
        }
    }

    /// The login item as macOS has it (T12). Read when the window opens and whenever Otter comes
    /// back to the front, e.g. from approving it in System Settings.
    private(set) var loginItemStatus = SMAppService.Status.notRegistered

    /// "Launch at login": on while Otter is a login item, including while macOS waits for approval.
    /// A change adds or removes the login item straight away.
    var launchAtLogin: Bool {
        get { LoginItem.isOn(loginItemStatus) }
        set {
            settings.launchAtLogin = newValue
            loginItemStatus = LoginItem.setEnabled(newValue)
        }
    }

    // MARK: Destinations

    /// In `⌘1…⌘9` order.
    private(set) var destinations: [DestinationConfig] = []
    private(set) var defaultID: DestinationID?
    private(set) var health: [DestinationID: DestinationHealth] = [:]
    /// Destinations whose folder is in an Obsidian vault, for the list's icon.
    private(set) var vaultIDs: Set<DestinationID> = []
    private(set) var tests: [DestinationID: TestState] = [:]
    /// The Add menu's vaults, most recently opened first. Read when the window opens.
    private(set) var discoveredVaults: [DiscoveredVault] = []
    var selection: DestinationID?

    // MARK: Advanced

    private(set) var deliveryStatus = DeliveryStatus.idle

    var remembersRecents: Bool {
        didSet {
            settings.remembersRecents = remembersRecents
            Task { [recents, remembersRecents] in
                await recents.setEnabled(remembersRecents)
            }
        }
    }

    /// "Automatically check for updates" (T13): Sparkle keeps it. Off, Otter makes no network
    /// requests at all.
    var automaticallyChecksForUpdates: Bool {
        didSet { updates.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    /// False when the updater couldn't start, e.g. a local build without Sparkle's public key.
    var updatesAvailable: Bool {
        updates.isAvailable
    }

    init(pipeline: CapturePipeline, hotkeys: HotkeyService, folderChooser: FolderChooser, panel: PanelController, updates: UpdateController) {
        registry = pipeline.destinations
        outbox = pipeline.outbox
        delivery = pipeline.delivery
        recents = pipeline.recents
        self.hotkeys = hotkeys
        self.folderChooser = folderChooser
        self.panel = panel
        self.updates = updates
        automaticallyChecksForUpdates = updates.automaticallyChecksForUpdates
        keepPanelOpen = settings.keepPanelOpenWhenClickingElsewhere
        fontFamily = settings.fontFamily
        fontSize = settings.fontSize
        smartQuotesAndDashes = settings.smartQuotesAndDashes
        remembersRecents = settings.remembersRecents
        reloadDestinations()
    }

    /// The window opened: subscribe to the outbox status, and re-read Spotlight's shortcut and the
    /// login item.
    func windowDidOpen() {
        hotkeys.refreshSpotlightState()
        loginItemStatus = LoginItem.status
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.loginItemStatus = LoginItem.status
                }
            }
        }
        reloadDestinations()
        Task {
            discoveredVaults = await Task.detached(priority: .utility) { VaultDiscovery.vaults() }.value
        }
        guard statusTask == nil else {
            return
        }
        statusTask = Task { [weak self, delivery] in
            for await status in await delivery.statusUpdates() {
                self?.deliveryStatus = status
            }
        }
    }

    func windowWillClose() {
        statusTask?.cancel()
        statusTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        healthTask?.cancel()
    }

    func resetPanelPosition() {
        panel.resetPanelPosition()
    }

    // MARK: - Destinations

    func config(_ id: DestinationID) -> DestinationConfig? {
        destinations.first { $0.id == id }
    }

    func reloadDestinations() {
        destinations = registry.configs
        defaultID = registry.defaultID
        if selection.map({ id in !destinations.contains { $0.id == id } }) ?? true {
            selection = destinations.first?.id
        }
    }

    /// Checks every destination. Disk work, so it runs off the main thread in the destinations' own
    /// actors; a renamed folder's new name is read back afterwards.
    func checkHealth(after delay: Duration? = nil) {
        healthTask?.cancel()
        let configs = destinations
        healthTask = Task { [registry] in
            if let delay {
                try? await Task.sleep(for: delay)
            }
            var health: [DestinationID: DestinationHealth] = [:]
            for config in configs {
                guard !Task.isCancelled else {
                    return
                }
                health[config.id] = await registry.destination(for: config.id)?.healthCheck() ?? .unreachable("Not available")
            }
            let vaults = await Task.detached(priority: .utility) {
                Set(configs.filter { Self.folderURL(of: $0).flatMap(ObsidianVault.containing) != nil }.map(\.id))
            }.value
            guard !Task.isCancelled else {
                return
            }
            self.health = health
            vaultIDs = vaults
            reloadDestinations()
        }
    }

    /// Changes one destination. The next delivery and Test use the new settings. Health is checked
    /// again once the edits pause.
    func update(_ id: DestinationID, _ change: @escaping @Sendable (inout DestinationConfig) -> Void) {
        registry.modify(id, change)
        tests[id] = nil
        reloadDestinations()
        checkHealth(after: .milliseconds(500))
    }

    /// Changes one folder destination's options.
    func updateFolder(_ id: DestinationID, _ change: @escaping @Sendable (inout FolderOptions) -> Void) {
        update(id) { config in
            guard case var .folder(options) = config.options else {
                return
            }
            change(&options)
            config.options = .folder(options)
        }
    }

    func setDefault(_ id: DestinationID) {
        registry.setDefault(id)
        reloadDestinations()
    }

    /// Drag to reorder: the order is `⌘1…⌘9`.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = destinations
        order.move(fromOffsets: source, toOffset: destination)
        for (index, config) in order.enumerated() {
            registry.move(config.id, to: index)
        }
        reloadDestinations()
    }

    /// Moves one destination up (`-1`) or down (`+1`), for keyboard and VoiceOver users.
    func move(_ id: DestinationID, by offset: Int) {
        guard let index = destinations.firstIndex(where: { $0.id == id }) else {
            return
        }
        let target = index + offset
        guard destinations.indices.contains(target) else {
            return
        }
        registry.move(id, to: target)
        reloadDestinations()
    }

    /// The Add menu's vault: a folder destination at the vault's root (ADR-013).
    func addVault(_ vault: DiscoveredVault) {
        added(folderChooser.addDestination(at: vault.path, name: vault.name))
    }

    /// The Add menu's "Folder…".
    func addFolder() async {
        let folder = await folderChooser.pickFolder(startingAt: nil, prompt: "Add", presentation: presentation)
        guard let folder else {
            return
        }
        added(folderChooser.addDestination(at: folder))
    }

    /// The folder button and the "Choose Folder…" / "Grant Access…" fixes.
    func changeFolder(_ id: DestinationID) async {
        guard await folderChooser.chooseFolder(for: id, presentation: presentation) else {
            return
        }
        tests[id] = nil
        reloadDestinations()
        checkHealth()
    }

    /// Captures waiting in the outbox for `id`.
    func pendingCount(for id: DestinationID) async -> Int {
        await outbox.pending().filter { $0.capture.destinationID == id }.count
    }

    /// Removes `id`. Its waiting captures go to the default (the first remaining destination if `id`
    /// was the default), so nothing is lost (ARCHITECTURE §4 rule 6). The last destination can't go.
    func delete(_ id: DestinationID) async {
        guard destinations.count > 1 else {
            NSSound.beep()
            return
        }
        registry.remove(id)
        tests[id] = nil
        health[id] = nil
        reloadDestinations()
        guard let target = registry.defaultID else {
            return
        }
        do {
            let moved = try await outbox.reroute(from: id, to: target)
            if moved > 0 {
                Logger.pipeline.info("Re-routed \(moved, privacy: .public) capture(s) from deleted \(id, privacy: .public) to \(target, privacy: .public)")
            }
        } catch {
            Logger.pipeline.error("Couldn't re-route the captures of \(id, privacy: .public): \(error.loggableCode, privacy: .public)")
        }
        await delivery.kick()
    }

    /// The Test button: writes "Otter test — you can delete this" there now.
    func test(_ id: DestinationID) async {
        guard let destination = registry.destination(for: id) else {
            tests[id] = .failed(DestinationProblem(message: "This destination isn't available.", fix: nil))
            return
        }
        tests[id] = .running
        let files = FileManager.default.temporaryDirectory.appendingPathComponent("OtterTest-\(UUID().uuidString)", isDirectory: true)
        switch await DestinationTest.run(destination, files: files) {
        case let .success(receipt):
            tests[id] = .passed(receipt)
            Logger.pipeline.info("Test note written to \(id, privacy: .public)")
            // A folder that works again lets waiting captures go.
            await delivery.kick()
        case let .failure(problem):
            tests[id] = .failed(problem)
            Logger.pipeline.error("Test of \(id, privacy: .public) failed")
        }
        checkHealth()
    }

    // MARK: - Advanced

    func retryNow() {
        Task { [delivery] in
            await delivery.retryNow()
        }
    }

    func revealOutbox() {
        Self.reveal(StorageLocations.outbox, creating: true)
    }

    func checkForUpdates() {
        updates.checkForUpdates()
    }

    func clearRecents() {
        Task { [recents] in
            await recents.clear()
        }
    }

    /// Writes this run's log (no note contents, ARCHITECTURE §10) to `logs/` and shows it in Finder.
    func revealLogs() {
        Task {
            do {
                let file = try await Task.detached(priority: .userInitiated) { try LogExport.write(to: StorageLocations.logs) }.value
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } catch {
                Logger.pipeline.error("Couldn't export the logs: \(error.loggableCode, privacy: .public)")
                Self.reveal(StorageLocations.logs, creating: true)
            }
        }
    }

    /// "Reset all settings": preferences, shortcuts, panel position and destinations go back to how
    /// they were on first launch. Waiting captures go to the default inbox, so nothing is lost.
    func resetAll() async {
        hotkeys.resetShortcuts { [settings] in
            settings.resetAll(domain: Bundle.main.bundleIdentifier ?? "io.github.elizabeth-ling.otter")
        }

        let inbox = DestinationConfig.defaultInbox()
        let previous = Set(destinations.map(\.id))
        registry.reset(to: inbox)
        for id in previous {
            _ = try? await outbox.reroute(from: id, to: inbox.id)
        }
        await recents.setEnabled(true)

        keepPanelOpen = settings.keepPanelOpenWhenClickingElsewhere
        fontFamily = settings.fontFamily
        fontSize = settings.fontSize
        smartQuotesAndDashes = settings.smartQuotesAndDashes
        remembersRecents = settings.remembersRecents
        updates.settingsDidReset()
        automaticallyChecksForUpdates = updates.automaticallyChecksForUpdates
        // The login item stays as it is; the stored preference follows it.
        settings.launchAtLogin = launchAtLogin
        panel.resetPanelPosition()
        tests = [:]
        reloadDestinations()
        checkHealth()
        await delivery.kick()
        Logger.pipeline.info("Reset all settings")
    }

    // MARK: - Private

    private var presentation: FolderChooser.Presentation {
        window.map { .sheet(on: $0) } ?? .window(above: nil)
    }

    private func added(_ id: DestinationID?) {
        guard let id else {
            return
        }
        reloadDestinations()
        selection = id
        checkHealth()
    }

    /// Where a folder destination points, without touching the disk beyond resolving its bookmark.
    nonisolated private static func folderURL(of config: DestinationConfig) -> URL? {
        guard case let .folder(options) = config.options else {
            return nil
        }
        if !options.bookmark.isEmpty, let url = try? FolderBookmark.resolve(options.bookmark).url {
            return url
        }
        return options.fallbackPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func reveal(_ directory: URL, creating: Bool) {
        if creating {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(directory)
    }
}
