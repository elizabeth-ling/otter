import Foundation

/// What a paste or a drop into the panel becomes (UX_SPEC §2, T09). Works on pasteboard type
/// identifiers, so it's testable without AppKit.
public enum PasteKind: Equatable, Sendable {
    /// One attachment per file URL, each copied.
    case files
    /// An image attachment from the data of this type.
    case image(uti: String)
    /// Plain text at the caret: the editor's own paste.
    case text
}

public enum PasteRules {
    /// Marks passwords and other secrets that password managers put on the pasteboard
    /// (nspasteboard.org). Never kept as an attachment.
    public static let concealedType = "org.nspasteboard.ConcealedType"

    /// Image types in the order they're preferred. TIFF comes last: apps often add it next to a
    /// PNG, and it's converted to PNG anyway.
    public static let imageTypes = ["public.png", "public.jpeg", "public.heic", "public.tiff"]

    /// Formatted text. Apps such as Word and Pages put a picture of copied text next to it, which
    /// must not become an attachment.
    static let richTextTypes: Set<String> = ["public.rtf", "com.apple.flat-rtfd", "public.html", "com.apple.webarchive"]

    /// In order: files, then image data, then text.
    ///
    /// - Concealed content is only ever text.
    /// - Image data alongside formatted text and plain text is a copied text selection, so it's
    ///   text. Image data alone, or with only a URL or HTML (a browser's "Copy Image"), is an image.
    ///
    /// - Parameters:
    ///   - types: The pasteboard's type identifiers.
    ///   - hasFileURLs: It holds at least one `file://` URL.
    ///   - hasText: It holds plain text that isn't only whitespace.
    public static func kind(types: [String], hasFileURLs: Bool, hasText: Bool) -> PasteKind {
        guard !types.contains(concealedType) else {
            return .text
        }
        if hasFileURLs {
            return .files
        }
        guard let image = imageTypes.first(where: types.contains) else {
            return .text
        }
        if hasText, types.contains(where: richTextTypes.contains) {
            return .text
        }
        return .image(uti: image)
    }
}
