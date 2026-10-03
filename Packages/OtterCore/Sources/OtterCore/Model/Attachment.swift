import Foundation

/// A file that travels with a capture (ARCHITECTURE §3).
public struct Attachment: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var originalName: String?
    /// Uniform type identifier, e.g. `public.png`.
    public var uti: String
    /// The file's name inside `outbox/<capture-id>/files/`. A single path component.
    public var relativePath: String
    public var byteCount: Int

    public init(id: UUID = UUID(), originalName: String?, uti: String, relativePath: String, byteCount: Int) {
        self.id = id
        self.originalName = originalName
        self.uti = uti
        self.relativePath = relativePath
        self.byteCount = byteCount
    }
}

/// An attachment that is staged on disk (pastes are staged in `drafts/files/`, T09) and ready to move
/// into the outbox with its capture.
public struct StagedAttachment: Sendable, Equatable {
    public var attachment: Attachment
    public var file: URL

    public init(attachment: Attachment, file: URL) {
        self.attachment = attachment
        self.file = file
    }
}
