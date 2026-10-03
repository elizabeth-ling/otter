import Foundation
import OtterCore
import os

/// Turns a submitted note into a durable outbox entry, then lets delivery happen in the background
/// (ARCHITECTURE §4, ADR-005). The panel hides only once the outbox has the note.
@MainActor
final class CaptureService {
    /// The outbox has the note: clear the draft and hide the panel. The panel wires this (T03/T04).
    var onCaptured: (@MainActor () -> Void)?
    /// The note isn't saved (disk full, no destination…): keep the panel open and show `message` in
    /// the footer. The panel wires this (T03).
    var onCaptureFailed: (@MainActor (_ message: String) -> Void)?

    private let outbox: Outbox
    private let delivery: DeliveryService
    private let destinations: DestinationRegistry

    init(outbox: Outbox, delivery: DeliveryService, destinations: DestinationRegistry) {
        self.outbox = outbox
        self.delivery = delivery
        self.destinations = destinations
    }

    /// Journals the note and starts delivering it.
    /// - Parameter destinationID: The destination picked for this note (`⌘1…⌘9`). `nil` means the default.
    /// - Returns: `true` once the note is safe in the outbox.
    @discardableResult
    func submit(
        text: String,
        attachments: [StagedAttachment] = [],
        destinationID: DestinationID? = nil,
        source: Capture.Source = .panel
    ) async -> Bool {
        guard let destinationID = destinationID ?? destinations.defaultID else {
            Logger.pipeline.error("Capture not saved: no destination is configured")
            onCaptureFailed?(CaptureFailure.noDestinationMessage)
            return false
        }

        let capture = Capture(text: text, attachments: attachments.map(\.attachment), destinationID: destinationID, source: source)
        do {
            try await outbox.enqueue(capture, attachmentFiles: attachments.map(\.file))
        } catch {
            Logger.pipeline.error("Capture \(capture.id, privacy: .public) not saved: \(error.loggableCode, privacy: .public)")
            onCaptureFailed?(CaptureFailure.message(for: error))
            return false
        }

        Logger.pipeline.info("Captured \(capture.id, privacy: .public) (\(capture.text.utf8.count, privacy: .public) bytes, \(capture.attachments.count, privacy: .public) attachment(s)) for \(destinationID, privacy: .public)")
        onCaptured?()
        await delivery.kick()
        return true
    }
}
