import Foundation

/// What the save-clipboard hotkey finds on the pasteboard (T11).
public enum ClipboardContent: Equatable, Sendable {
    /// Marked concealed or transient, e.g. a password manager's copy. Skipped without being read.
    case `private`
    /// Nothing to save: no file, no image and no text that isn't only whitespace.
    case empty
    /// One attachment per file URL, copied.
    case files
    /// An image attachment from the data of this type.
    case image(uti: String)
    /// The plain text, saved as it is.
    case text
}

public enum ClipboardRules {
    /// The same order as a paste into the panel (T09, `PasteRules.kind`): files, then image data,
    /// then text. Text next to files or an image is left out, as it is there.
    ///
    /// The flags are only evaluated once the types show the pasteboard isn't private, so a
    /// password is never read.
    ///
    /// - Parameters:
    ///   - types: The pasteboard's type identifiers.
    ///   - hasFileURLs: It holds at least one `file://` URL.
    ///   - hasText: It holds plain text that isn't only whitespace.
    public static func content(
        types: [String],
        hasFileURLs: @autoclosure () -> Bool,
        hasText: @autoclosure () -> Bool
    ) -> ClipboardContent {
        guard !PasteRules.isPrivate(types: types) else {
            return .private
        }
        let hasText = hasText()
        switch PasteRules.kind(types: types, hasFileURLs: hasFileURLs(), hasText: hasText) {
        case .files:
            return .files
        case let .image(uti):
            return .image(uti: uti)
        case .text:
            return hasText ? .text : .empty
        }
    }
}

/// What the save-clipboard hotkey did, as the HUD shows it (T11, UX_SPEC §3).
public enum ClipboardSaveOutcome: Equatable, Sendable {
    /// In the outbox. Delivery happens in the background, as for the panel. `skippedFiles` couldn't
    /// be attached (a folder, over 200 MB, unreadable, or past the 10-attachment limit).
    case saved(destinationName: String, skippedFiles: Int)
    /// This clipboard was saved less than `ClipboardDedup.window` ago.
    case alreadySaved
    case empty
    /// Marked concealed or transient.
    case skippedPrivate
    case noDestination
    case outOfSpace
    /// The outbox couldn't be written for another reason.
    case outboxFailed
    /// No file or image could be attached; the first one's reason.
    case notAttached(AttachmentError)
    /// The default destination can't keep attachments. No v1 destination does this; Apple Notes
    /// will (T08).
    case attachmentsUnsupported(destinationName: String)

    /// A failure to put the note in the outbox.
    public static func notSaved(_ error: any Error) -> Self {
        CaptureFailure.isOutOfSpace(error) ? .outOfSpace : .outboxFailed
    }

    /// Shown with a ✓ rather than a ✕: the clipboard is safe.
    public var isSuccess: Bool {
        switch self {
        case .saved, .alreadySaved:
            true
        case .empty, .skippedPrivate, .noDestination, .outOfSpace, .outboxFailed, .notAttached, .attachmentsUnsupported:
            false
        }
    }

    /// The HUD's text, without its ✓ or ✕, which the HUD draws as a symbol. Also what VoiceOver says.
    public var message: String {
        switch self {
        case let .saved(name, skipped):
            switch skipped {
            case 0:
                "Saved to \(name)"
            case 1:
                "Saved to \(name) · 1 file skipped"
            default:
                "Saved to \(name) · \(skipped) files skipped"
            }
        case .alreadySaved:
            "Already saved"
        case .empty:
            "Clipboard is empty"
        case .skippedPrivate:
            "Skipped — copied from a password manager"
        case .noDestination:
            "Not saved — no destination set up"
        case .outOfSpace:
            "Not saved — disk is full"
        case .outboxFailed:
            "Not saved — couldn't write to Otter's outbox"
        case let .notAttached(error):
            error.localizedDescription
        case let .attachmentsUnsupported(name):
            "Not saved — \(name) can't take attachments"
        }
    }
}

/// Shows "Already saved" instead of saving the same clipboard twice within `window` (T11). Keyed on
/// the pasteboard's `changeCount`, which changes with every copy. Kept in memory and shared by the
/// hotkey and the menu bar item. Times are `systemUptime`, which doesn't jump with the clock.
public struct ClipboardDedup: Sendable {
    public enum Decision: Equatable, Sendable {
        case save
        case alreadySaved
        /// This clipboard is still being saved (a large file being copied); its HUD will answer.
        case inProgress
    }

    public static let window: TimeInterval = 10

    private struct Saved: Sendable {
        var changeCount: Int
        var at: TimeInterval
    }

    private var lastSaved: Saved?
    private var saving: Set<Int> = []

    public init() {}

    /// Call before saving. On `.save`, call `finish` once the save is done, whatever happened.
    public mutating func begin(changeCount: Int, now: TimeInterval) -> Decision {
        if saving.contains(changeCount) {
            return .inProgress
        }
        if let lastSaved, lastSaved.changeCount == changeCount, now - lastSaved.at < Self.window {
            return .alreadySaved
        }
        saving.insert(changeCount)
        return .save
    }

    /// Only a save that reached the outbox counts; after a failure the same clipboard can be tried again.
    public mutating func finish(changeCount: Int, saved: Bool, at time: TimeInterval) {
        saving.remove(changeCount)
        if saved {
            lastSaved = Saved(changeCount: changeCount, at: time)
        }
    }
}
