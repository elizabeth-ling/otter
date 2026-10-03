import Foundation

/// The time source for retry scheduling. It's injected so tests can check backoff without waiting.
public protocol DeliveryClock: Sendable {
    var now: Date { get }
    /// Suspends until `deadline`. Throws `CancellationError` if the task is cancelled first.
    func sleep(until deadline: Date) async throws
}

/// Wall-clock time. The sleep uses `Task.sleep`, whose clock keeps running while the Mac sleeps, so
/// an overdue retry fires on wake. The wake notification kicks delivery as well.
public struct SystemDeliveryClock: DeliveryClock {
    public init() {}

    public var now: Date {
        Date()
    }

    public func sleep(until deadline: Date) async throws {
        let interval = deadline.timeIntervalSinceNow
        guard interval > 0 else {
            try Task.checkCancellation()
            return
        }
        try await Task.sleep(for: .seconds(interval))
    }
}
