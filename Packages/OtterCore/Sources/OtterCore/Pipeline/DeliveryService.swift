import Foundation
import os

/// Delivery state for the UI: the menu bar badge (T12), the footer badge (T03) and Settings (T10).
public struct DeliveryStatus: Sendable, Equatable {
    public var pendingCount: Int
    /// Destinations whose oldest pending capture failed its last attempt.
    public var failingDestinations: Set<DestinationID>
    /// Destinations whose oldest pending capture has failed `DeliveryAlert.failureThreshold` times
    /// or more, with how many captures wait for each: the menu bar's amber badge and the
    /// notification (ARCHITECTURE §4 rule 5).
    public var alertingDestinations: [DestinationID: Int] = [:]
    /// Destinations that pending captures point to but that can't be built (deleted, or no builder
    /// for the kind yet). Those captures wait for re-routing (T10).
    public var missingDestinations: Set<DestinationID>
    public var lastError: String?

    public static let idle = DeliveryStatus(pendingCount: 0, failingDestinations: [], missingDestinations: [], lastError: nil)
}

/// One capture a destination accepted, for onboarding's "Try it" step (T10).
public struct Delivery: Sendable, Equatable {
    public var captureID: UUID
    public var destinationID: DestinationID
    public var destinationName: String
    public var receipt: DeliveryReceipt
}

/// How long to wait after a failed attempt: 2 s, 10 s, 60 s, then every 5 minutes.
public enum RetryPolicy {
    public static func delay(afterFailures failures: Int) -> TimeInterval {
        switch failures {
        case ...1:
            2
        case 2:
            10
        case 3:
            60
        default:
            5 * 60
        }
    }
}

/// Delivers outbox captures in the background (ARCHITECTURE §4).
///
/// - One serial lane per destination. A lane delivers that destination's captures oldest first, and
///   stops at a capture that isn't due yet, so appends to one file keep their order. Lanes run side
///   by side, so a slow destination never holds up another.
/// - `kick()` drains whatever is due. It's called after an enqueue, 1 s after launch, and on wake.
/// - A failed attempt goes back to the outbox with `RetryPolicy`'s delay. The service then sleeps
///   once, until the earliest retry. When nothing is waiting there is no sleep and no timer.
/// - Delivery is at-least-once: a capture leaves the outbox only after its destination returns.
public actor DeliveryService {
    public typealias DestinationLookup = @Sendable (DestinationID) -> (any Destination)?

    private let outbox: Outbox
    private let lookup: DestinationLookup
    private let recents: RecentStore?
    private let clock: any DeliveryClock

    private var lanes: [DestinationID: Task<Void, Never>] = [:]
    private var missing: Set<DestinationID> = []
    /// One pass at a time. A request during a pass makes it run once more, so the last pass always
    /// sees the latest outbox.
    private var drainTask: Task<Void, Never>?
    private var drainAgain = false
    private var retryMissingOnNextDrain = false
    private var wake: (deadline: Date, generation: Int, task: Task<Void, Never>)?
    private var wakeGeneration = 0
    private var lastError: String?
    private var statusObservers: [UUID: AsyncStream<DeliveryStatus>.Continuation] = [:]
    private var deliveryObservers: [UUID: AsyncStream<Delivery>.Continuation] = [:]

    public private(set) var status = DeliveryStatus.idle

    public init(
        outbox: Outbox,
        destinations: @escaping DestinationLookup,
        recents: RecentStore? = nil,
        clock: any DeliveryClock = SystemDeliveryClock()
    ) {
        self.outbox = outbox
        lookup = destinations
        self.recents = recents
        self.clock = clock
    }

    deinit {
        wake?.task.cancel()
    }

    /// Delivers everything that's due, and looks up destinations that were missing again.
    /// Returns once this pass has started the lanes, without waiting for deliveries.
    public func kick() async {
        await requestDrain(retryMissing: true).value
    }

    /// The current status, then every change.
    public func statusUpdates() -> AsyncStream<DeliveryStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: DeliveryStatus.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        statusObservers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusObserver(id) }
        }
        continuation.yield(status)
        return stream
    }

    /// Every delivery from now on.
    public func deliveries() -> AsyncStream<Delivery> {
        let (stream, continuation) = AsyncStream.makeStream(of: Delivery.self)
        let id = UUID()
        deliveryObservers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeDeliveryObserver(id) }
        }
        return stream
    }

    /// "Retry now" in Settings: tries every pending capture straight away, ignoring its backoff.
    public func retryNow() async {
        do {
            try await outbox.makeAllDue()
        } catch {
            Logger.pipeline.error("Couldn't reset the retry times: \(error.loggableCode, privacy: .public)")
        }
        await kick()
    }

    /// Waits until no pass or lane is running. A retry that is sleeping doesn't count. For tests.
    func waitUntilIdle() async {
        while true {
            if let drainTask {
                await drainTask.value
            } else if let lane = lanes.values.first {
                await lane.value
            } else {
                return
            }
        }
    }

    // MARK: - Draining

    @discardableResult
    private func requestDrain(retryMissing: Bool) -> Task<Void, Never> {
        if retryMissing {
            retryMissingOnNextDrain = true
        }
        if let drainTask {
            drainAgain = true
            return drainTask
        }
        let task = Task { await drainLoop() }
        drainTask = task
        return task
    }

    private func drainLoop() async {
        repeat {
            drainAgain = false
            let retryMissing = retryMissingOnNextDrain
            retryMissingOnNextDrain = false
            await drainOnce(retryMissing: retryMissing)
        } while drainAgain
        drainTask = nil
    }

    /// Starts a lane for each destination whose oldest capture is due, sleeps until the earliest one
    /// that isn't, and publishes the status.
    private func drainOnce(retryMissing: Bool) async {
        let pending = await outbox.pending()
        let now = clock.now

        var heads: [DestinationID: OutboxItem] = [:]
        for item in pending where heads[item.capture.destinationID] == nil {
            heads[item.capture.destinationID] = item
        }
        missing.formIntersection(heads.keys)

        var nextWake: Date?
        for (id, head) in heads where lanes[id] == nil {
            guard retryMissing || !missing.contains(id) else {
                continue // Waits for the next kick. Nothing to retry on a timer.
            }
            if head.isDue(at: now) {
                startLane(id)
            } else if let next = head.nextAttemptAt {
                nextWake = min(nextWake ?? next, next)
            }
        }
        scheduleWake(at: nextWake)
        publishStatus(pending: pending, heads: heads)
    }

    private func startLane(_ id: DestinationID) {
        lanes[id] = Task { await runLane(id) }
    }

    /// Delivers `id`'s captures oldest first until none is due, one fails, or the destination is missing.
    private func runLane(_ id: DestinationID) async {
        while let head = await outbox.pending().first(where: { $0.capture.destinationID == id }), head.isDue(at: clock.now) {
            guard let destination = lookup(id) else {
                if missing.insert(id).inserted {
                    Logger.pipeline.error("Destination \(id, privacy: .public) isn't available; its captures stay in the outbox")
                }
                break
            }
            missing.remove(id)

            let captureID = head.capture.id
            let receipt: DeliveryReceipt
            do {
                receipt = try await destination.deliver(head.capture, files: outbox.filesDirectory(for: captureID))
            } catch {
                await recordFailure(of: head, error: error)
                break
            }
            do {
                try await outbox.markDelivered(captureID)
            } catch {
                // Delivered but still journaled. Back off instead of re-delivering in a tight loop;
                // the duplicate is accepted (ADR-005).
                await recordFailure(of: head, error: error)
                break
            }
            Logger.pipeline.info("Delivered \(captureID, privacy: .public) to \(id, privacy: .public) after \(head.attempts + 1, privacy: .public) attempt(s)")
            await recents?.record(head.capture, receipt: receipt, destinationName: destination.displayName)
            let delivery = Delivery(captureID: captureID, destinationID: id, destinationName: destination.displayName, receipt: receipt)
            for observer in deliveryObservers.values {
                observer.yield(delivery)
            }
        }
        lanes[id] = nil
        requestDrain(retryMissing: false)
    }

    private func recordFailure(of item: OutboxItem, error: any Error) async {
        let failures = item.attempts + 1
        let delay = RetryPolicy.delay(afterFailures: failures)
        let message = error.localizedDescription
        lastError = message
        Logger.pipeline.error("Delivery of \(item.capture.id, privacy: .public) to \(item.capture.destinationID, privacy: .public) failed (attempt \(failures, privacy: .public), \(error.loggableCode, privacy: .public)); retrying in \(Int(delay), privacy: .public) s")
        do {
            try await outbox.markFailed(item.capture.id, error: message, nextAttemptAt: clock.now.addingTimeInterval(delay))
        } catch {
            Logger.pipeline.error("Couldn't record the failure of \(item.capture.id, privacy: .public): \(error.loggableCode, privacy: .public)")
        }
    }

    // MARK: - Waking

    /// Keeps at most one sleep, until `deadline`. `nil` cancels it.
    private func scheduleWake(at deadline: Date?) {
        guard wake?.deadline != deadline else {
            return
        }
        wake?.task.cancel()
        wake = nil
        guard let deadline else {
            return
        }
        wakeGeneration += 1
        let generation = wakeGeneration
        let task = Task { [weak self, clock] in
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return // Cancelled: rescheduled or nothing left to retry.
            }
            await self?.wakeFired(generation)
        }
        wake = (deadline, generation, task)
    }

    private func wakeFired(_ generation: Int) {
        guard wake?.generation == generation else {
            return
        }
        wake = nil
        requestDrain(retryMissing: false)
    }

    // MARK: - Status

    private func publishStatus(pending: [OutboxItem], heads: [DestinationID: OutboxItem]) {
        let failingHeads = heads.values.filter { $0.attempts > 0 }
        if failingHeads.isEmpty {
            lastError = nil
        } else if lastError == nil {
            lastError = failingHeads.lazy.compactMap(\.lastError).first // Failures from before a relaunch.
        }
        var alerting: [DestinationID: Int] = [:]
        for head in failingHeads where DeliveryAlert.isAlerting(failures: head.attempts) {
            let id = head.capture.destinationID
            alerting[id] = pending.filter { $0.capture.destinationID == id }.count
        }
        let updated = DeliveryStatus(
            pendingCount: pending.count,
            failingDestinations: Set(failingHeads.map(\.capture.destinationID)),
            alertingDestinations: alerting,
            missingDestinations: missing,
            lastError: lastError
        )
        guard updated != status else {
            return
        }
        status = updated
        for observer in statusObservers.values {
            observer.yield(updated)
        }
    }

    private func removeStatusObserver(_ id: UUID) {
        statusObservers[id] = nil
    }

    private func removeDeliveryObserver(_ id: UUID) {
        deliveryObservers[id] = nil
    }
}
