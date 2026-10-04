import AppKit
import OtterCore
import os

/// Builds the capture pipeline (T05) and drains the outbox 1 s after launch and on every wake from
/// sleep (ARCHITECTURE §4 rule 4). `CaptureService` triggers the drain after each enqueue. Nothing
/// polls: with an empty outbox there is no timer.
@MainActor
final class CapturePipeline {
    let destinations: DestinationRegistry
    let outbox: Outbox
    let recents: RecentStore
    let delivery: DeliveryService
    let captureService: CaptureService

    private var wakeObserver: (any NSObjectProtocol)?

    /// No file I/O: the outbox and recents are read on first use, and the default inbox folder is
    /// created on the first save.
    init() {
        // The builder saves re-created bookmarks back to the registry it's registered with.
        let registryReference = RegistryReference()
        var factory = DestinationFactory()
        factory.registerFolder { id, bookmark, displayPath in
            registryReference.registry?.updateFolderBookmark(id, bookmark: bookmark, displayPath: displayPath)
        }
        let destinations = DestinationRegistry(defaults: .standard, factory: factory)
        registryReference.registry = destinations
        destinations.addDefaultInboxIfEmpty()
        let outbox = Outbox(directory: StorageLocations.outbox)
        let recents = RecentStore(fileURL: StorageLocations.recents)
        let delivery = DeliveryService(
            outbox: outbox,
            destinations: { destinations.destination(for: $0) },
            recents: recents
        )
        self.destinations = destinations
        self.outbox = outbox
        self.recents = recents
        self.delivery = delivery
        captureService = CaptureService(outbox: outbox, delivery: delivery, destinations: destinations)
    }

    /// Call once at launch.
    func start() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [delivery] _ in
            Logger.pipeline.info("Woke from sleep; draining the outbox")
            Task { await delivery.kick() }
        }

        // Deferred to keep the drain off the cold-launch path (ARCHITECTURE §9).
        Task { [delivery] in
            try? await Task.sleep(for: .seconds(1))
            Logger.pipeline.info("Draining the outbox after launch")
            await delivery.kick()
        }
    }
}

/// Lets the folder builder reach the registry, which is created after the factory it's given.
/// Set once, on the main thread, before any destination is built.
private final class RegistryReference: @unchecked Sendable {
    weak var registry: DestinationRegistry?
}
