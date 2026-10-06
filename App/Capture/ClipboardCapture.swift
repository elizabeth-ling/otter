import AppKit
import OtterCore
import os

/// The save-clipboard hotkey and the menu bar's "Save Clipboard" (T11): what's on the clipboard
/// becomes a note for the default destination without opening the panel, and the HUD says what
/// happened. The clipboard is read in the same order as a paste into the panel (T09): files, then
/// an image, then text. Concealed or transient content is skipped without being read.
///
/// The HUD's ✓ comes once the outbox has the note; delivery happens in the background, as for the
/// panel (ADR-005). Never logs what was copied, file names included.
@MainActor
final class ClipboardCapture {
    private let captureService: CaptureService
    private let destinations: DestinationRegistry
    private let stager: AttachmentStager
    private let hud: HUDController
    /// Shared by the hotkey and the menu bar item.
    private var dedup = ClipboardDedup()

    /// - Parameter stager: The panel's, so its launch sweep of `drafts/files/` never removes a file
    ///   staged here before the outbox takes it.
    init(captureService: CaptureService, destinations: DestinationRegistry, stager: AttachmentStager, hud: HUDController) {
        self.captureService = captureService
        self.destinations = destinations
        self.stager = stager
        self.hud = hud
    }

    /// Reads the clipboard straight away, so a copy made while files are still being staged can't
    /// change what's saved.
    func save() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        let content = ClipboardRules.content(
            types: pasteboard.types?.map(\.rawValue) ?? [],
            hasFileURLs: pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
            hasText: Self.hasText(on: pasteboard)
        )
        switch content {
        case .private:
            Logger.pipeline.info("Clipboard skipped: it's marked concealed or transient")
            show(.skippedPrivate)
            return
        case .empty:
            show(.empty)
            return
        case .files, .image, .text:
            break
        }

        switch dedup.begin(changeCount: changeCount, now: ProcessInfo.processInfo.systemUptime) {
        case .inProgress:
            // The save already under way shows its own HUD.
            return
        case .alreadySaved:
            show(.alreadySaved)
            return
        case .save:
            break
        }

        let payload = Self.payload(content, on: pasteboard)
        Task {
            let outcome = await save(payload)
            var saved = false
            if case .saved = outcome {
                saved = true
            }
            dedup.finish(changeCount: changeCount, saved: saved, at: ProcessInfo.processInfo.systemUptime)
            show(outcome)
        }
    }

    // MARK: - Private

    /// What's saved, read from the pasteboard before anything is awaited.
    private enum Payload: Sendable {
        case text(String)
        case files([URL])
        case image(Data, uti: String)
    }

    /// Stages any files or image, then puts the note in the outbox for the default destination.
    private func save(_ payload: Payload?) async -> ClipboardSaveOutcome {
        guard let payload else {
            return .empty
        }
        guard let destinationID = destinations.defaultID, let config = destinations.config(for: destinationID) else {
            Logger.pipeline.error("Clipboard not saved: no destination is configured")
            return .noDestination
        }

        var text = ""
        var attachments: [StagedAttachment] = []
        var skipped = 0
        switch payload {
        case let .text(string):
            text = string
        case let .files(urls):
            guard config.kind.supportsAttachments else {
                return .attachmentsUnsupported(destinationName: config.name)
            }
            // Like the panel: in order, refused files skipped, until the note is full.
            var firstRefusal: AttachmentError?
            for url in urls {
                guard attachments.count < AttachmentLimits.maxCount else {
                    skipped += 1
                    continue
                }
                do {
                    attachments.append(try await stager.stageFile(at: url))
                } catch {
                    skipped += 1
                    firstRefusal = firstRefusal ?? Self.attachmentError(error, name: url.lastPathComponent)
                }
            }
            guard !attachments.isEmpty else {
                Logger.pipeline.info("Clipboard not saved: none of its \(urls.count, privacy: .public) file(s) could be attached")
                return .notAttached(firstRefusal ?? .unreadable(name: urls.first?.lastPathComponent ?? ""))
            }
        case let .image(data, uti):
            guard config.kind.supportsAttachments else {
                return .attachmentsUnsupported(destinationName: config.name)
            }
            do {
                attachments = [try await stager.stageImage(data, uti: uti)]
            } catch {
                Logger.pipeline.info("Clipboard not saved: its image couldn't be attached")
                return .notAttached(Self.attachmentError(error, name: "Pasted image"))
            }
        }

        switch await captureService.enqueue(text: text, attachments: attachments, destinationID: destinationID, source: .clipboard) {
        case .success:
            if skipped > 0 {
                Logger.pipeline.info("Clipboard saved without \(skipped, privacy: .public) file(s) that couldn't be attached")
            }
            return .saved(destinationName: config.name, skippedFiles: skipped)
        case .failure(.noDestination):
            return .noDestination
        case let .failure(.outbox(error)):
            // The outbox kept nothing, so the staged copies would only wait for the next launch's sweep.
            await stager.remove(attachments.map(\.attachment))
            return .notSaved(error)
        }
    }

    private func show(_ outcome: ClipboardSaveOutcome) {
        hud.show(outcome.message, success: outcome.isSuccess)
    }

    /// `nil` if the files or image the types promised can't be read after all.
    private static func payload(_ content: ClipboardContent, on pasteboard: NSPasteboard) -> Payload? {
        switch content {
        case .text:
            return pasteboard.string(forType: .string).map(Payload.text)
        case .files:
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            return urls.isEmpty ? nil : .files(urls)
        case let .image(uti):
            // The raw data, so PNG, JPEG and HEIC keep their format (T09).
            return pasteboard.data(forType: NSPasteboard.PasteboardType(uti)).map { .image($0, uti: uti) }
        case .private, .empty:
            return nil
        }
    }

    /// Plain text that isn't only whitespace.
    private static func hasText(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.string(forType: .string).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
    }

    private static func attachmentError(_ error: any Error, name: String) -> AttachmentError {
        error as? AttachmentError ?? .unreadable(name: name)
    }
}
