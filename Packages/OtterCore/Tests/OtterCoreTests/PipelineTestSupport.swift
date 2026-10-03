import Foundation
import os
@testable import OtterCore

// MARK: - Fixtures

/// A whole-second date, so it survives the outbox's ISO 8601 encoding (second precision) unchanged.
let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)

/// A fresh directory under the system temp directory. Remove it with `defer`.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("OtterCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeCapture(
    _ text: String = "Buy oat milk",
    destination: DestinationID,
    createdAt: Date = referenceDate,
    attachments: [Attachment] = []
) -> Capture {
    Capture(
        createdAt: createdAt,
        timeZone: TimeZone(identifier: "Europe/Paris")!,
        text: text,
        attachments: attachments,
        destinationID: destination,
        source: .panel
    )
}

/// Writes a file the way the draft would stage a pasted attachment (T09).
func stageAttachment(named name: String, in directory: URL, bytes: Int) throws -> StagedAttachment {
    let staging = directory.appendingPathComponent("staging", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let file = staging.appendingPathComponent(name)
    try Data(count: bytes).write(to: file)
    let attachment = Attachment(originalName: name, uti: "public.png", relativePath: name, byteCount: bytes)
    return StagedAttachment(attachment: attachment, file: file)
}

// MARK: - TestClock

private struct Sleeper: Sendable {
    let id: UUID
    let deadline: Date
    let continuation: CheckedContinuation<Void, any Error>
}

private enum SleepOutcome: Sendable {
    case resume
    case cancel
    case wait(wakeWatchers: [CheckedContinuation<Void, Never>])
}

/// A clock that moves only when the test calls `advance(to:)`. `sleep(until:)` suspends until then,
/// so backoff can be checked to the second without waiting.
final class TestClock: DeliveryClock {
    private struct State: Sendable {
        var now: Date
        var sleepers: [Sleeper] = []
        var cancelledBeforeSleeping: Set<UUID> = []
        var sleepWatchers: [CheckedContinuation<Void, Never>] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(now: Date = referenceDate) {
        state = OSAllocatedUnfairLock(initialState: State(now: now))
    }

    var now: Date {
        state.withLock { $0.now }
    }

    /// Deadlines of everything currently sleeping on this clock.
    var sleepDeadlines: [Date] {
        state.withLock { $0.sleepers.map(\.deadline) }
    }

    func sleep(until deadline: Date) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome = state.withLock { state -> SleepOutcome in
                    if state.cancelledBeforeSleeping.remove(id) != nil {
                        return .cancel
                    }
                    if deadline <= state.now {
                        return .resume
                    }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    defer { state.sleepWatchers = [] }
                    return .wait(wakeWatchers: state.sleepWatchers)
                }
                switch outcome {
                case .resume:
                    continuation.resume()
                case .cancel:
                    continuation.resume(throwing: CancellationError())
                case .wait(let watchers):
                    watchers.forEach { $0.resume() }
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                if let index = state.sleepers.firstIndex(where: { $0.id == id }) {
                    return state.sleepers.remove(at: index)
                }
                state.cancelledBeforeSleeping.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline has passed.
    func advance(to date: Date) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = date
            let due = state.sleepers.filter { $0.deadline <= date }
            state.sleepers.removeAll { $0.deadline <= date }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }

    /// Waits until something sleeps on this clock, then returns the earliest deadline. The delivery
    /// service sleeps only after a pass has finished, so this also means "the last attempt is done".
    func nextSleepDeadline() async -> Date {
        while true {
            if let deadline = sleepDeadlines.min() {
                return deadline
            }
            await withCheckedContinuation { (watcher: CheckedContinuation<Void, Never>) in
                let isWatching = state.withLock { state -> Bool in
                    guard state.sleepers.isEmpty else {
                        return false
                    }
                    state.sleepWatchers.append(watcher)
                    return true
                }
                if !isWatching {
                    watcher.resume()
                }
            }
        }
    }
}

// MARK: - FakeDestination

enum FakeDeliveryError: Error, Equatable {
    case offline
    case permissionDenied
}

/// A destination for pipeline tests: fails a set number of times with a chosen error, can sleep
/// for real before answering, or can be held until the test releases it.
actor FakeDestination: Destination {
    nonisolated let id: DestinationID
    nonisolated let displayName: String
    nonisolated let supportsAttachments = true

    private let clock: any DeliveryClock
    private var failuresLeft: Int
    private let error: any Error
    private let delay: Duration?
    private var isHeld: Bool
    private var heldDeliveries: [CheckedContinuation<Void, Never>] = []
    private var deliveryWatchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// `clock.now` at the start of every `deliver` call, failed or not.
    private(set) var attemptTimes: [Date] = []
    /// Successful deliveries, in order.
    private(set) var delivered: [Capture] = []
    /// For each successful delivery: were all the capture's attachments in `files`?
    private(set) var sawAllAttachments: [Bool] = []

    init(
        id: DestinationID = DestinationID(),
        name: String = "Fake",
        failTimes: Int = 0,
        error: any Error = FakeDeliveryError.offline,
        delay: Duration? = nil,
        held: Bool = false,
        clock: any DeliveryClock
    ) {
        self.id = id
        displayName = name
        failuresLeft = failTimes
        self.error = error
        self.delay = delay
        isHeld = held
        self.clock = clock
    }

    func healthCheck() async -> DestinationHealth {
        .ok
    }

    func deliver(_ capture: Capture, files: URL) async throws -> DeliveryReceipt {
        attemptTimes.append(clock.now)
        if let delay {
            try await Task.sleep(for: delay)
        }
        if isHeld {
            await withCheckedContinuation { heldDeliveries.append($0) }
        }
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw error
        }

        sawAllAttachments.append(capture.attachments.allSatisfy {
            FileManager.default.fileExists(atPath: files.appendingPathComponent($0.relativePath).path)
        })
        delivered.append(capture)
        let ready = deliveryWatchers.filter { $0.count <= delivered.count }
        deliveryWatchers.removeAll { $0.count <= delivered.count }
        ready.forEach { $0.continuation.resume() }

        return DeliveryReceipt(location: .file(URL(fileURLWithPath: "/fake/\(capture.id).md")), deliveredAt: clock.now)
    }

    /// Lets held deliveries finish, and stops holding new ones.
    func release() {
        isHeld = false
        heldDeliveries.forEach { $0.resume() }
        heldDeliveries = []
    }

    /// Returns once at least `count` captures have been delivered.
    func waitForDeliveries(_ count: Int) async {
        guard delivered.count < count else {
            return
        }
        await withCheckedContinuation { deliveryWatchers.append((count, $0)) }
    }
}

// MARK: - Destination lookup

/// A destination table the test can change while the service runs.
final class DestinationTable: Sendable {
    private let table = OSAllocatedUnfairLock<[DestinationID: FakeDestination]>(initialState: [:])
    private let lookupCount = OSAllocatedUnfairLock(initialState: 0)

    var lookups: Int {
        lookupCount.withLock { $0 }
    }

    func set(_ destination: FakeDestination?, for id: DestinationID) {
        table.withLock { $0[id] = destination }
    }

    func lookup(_ id: DestinationID) -> (any Destination)? {
        lookupCount.withLock { $0 += 1 }
        return table.withLock { $0[id] }
    }
}
