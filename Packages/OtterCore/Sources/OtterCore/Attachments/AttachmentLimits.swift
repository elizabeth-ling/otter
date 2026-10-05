import Foundation

/// How much a note can carry (T09), and what the panel footer says about it (UX_SPEC §1).
/// Megabytes are decimal, as Finder and the chips show them.
public enum AttachmentLimits {
    public static let maxCount = 10
    /// Above this an attachment is kept, with a warning.
    public static let warningBytes = 25_000_000
    /// Above this an attachment is refused.
    public static let maxBytes = 200_000_000

    public static func isLarge(_ byteCount: Int) -> Bool {
        byteCount > warningBytes
    }

    public static func isTooLarge(_ byteCount: Int) -> Bool {
        byteCount > maxBytes
    }

    /// The footer's standing warning while the note has attachments, or `nil` for the usual hints.
    /// A destination that can't take attachments comes first, since they'd be lost.
    public static func footerWarning(for attachments: [Attachment], destinationName: String, supportsAttachments: Bool) -> String? {
        guard !attachments.isEmpty else {
            return nil
        }
        if !supportsAttachments {
            return "\(destinationName) can't take attachments — they'll be dropped."
        }
        let large = attachments.filter { isLarge($0.byteCount) }
        guard let first = large.first else {
            return nil
        }
        if large.count > 1 {
            return "\(large.count) attachments are over 25 MB."
        }
        return "\(displayName(of: first)) is over 25 MB."
    }

    /// What a chip calls an attachment: its file name, or "Pasted image" for clipboard image data.
    public static func displayName(of attachment: Attachment) -> String {
        attachment.originalName ?? "Pasted image"
    }
}

/// Why something couldn't be attached. Its description is shown in the footer.
public enum AttachmentError: Error, Equatable, LocalizedError {
    case tooMany
    case tooLarge(name: String)
    case folder(name: String)
    /// The file or image couldn't be read or copied.
    case unreadable(name: String)

    public var errorDescription: String? {
        switch self {
        case .tooMany:
            "A note can have up to \(AttachmentLimits.maxCount) attachments."
        case let .tooLarge(name):
            "“\(name)” is over 200 MB, so it can't be attached."
        case let .folder(name):
            "“\(name)” is a folder. Only files can be attached."
        case let .unreadable(name):
            "Couldn't attach “\(name)”."
        }
    }
}
