import Foundation

/// Somewhere a capture can be delivered: a folder, an Obsidian vault, Apple Notes (ARCHITECTURE §3, §5).
public protocol Destination: Sendable {
    var id: DestinationID { get }
    var displayName: String { get }
    var supportsAttachments: Bool { get }
    func healthCheck() async -> DestinationHealth
    /// Writes `capture` and says where it landed. `files` is the capture's `outbox/<id>/files/`
    /// directory, which exists only when the capture has attachments. Throwing leaves the capture
    /// in the outbox for a retry.
    func deliver(_ capture: Capture, files: URL) async throws -> DeliveryReceipt
}

public enum DestinationHealth: Sendable, Equatable {
    case ok
    case needsPermission
    case unreachable(String)
}

/// Where a delivered capture ended up, for the Recent menu and "open the note".
public struct DeliveryReceipt: Codable, Sendable, Equatable {
    public enum Location: Codable, Sendable, Equatable {
        case file(URL)
        case obsidian(vault: String, path: String)
        case appleNote(id: String?)
    }

    public var location: Location
    public var deliveredAt: Date

    public init(location: Location, deliveredAt: Date) {
        self.location = location
        self.deliveredAt = deliveredAt
    }
}
