import AppKit

extension NSColor {
    /// Grey for the panel's de-emphasised marks: Markdown markers, list bullets and rings, the
    /// placeholder and the footer hints. Tertiary label in Light; secondary label in Dark, where
    /// tertiary is too faint against the panel to read.
    static let dimmedLabel = NSColor(name: "dimmedLabel") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .secondaryLabelColor : .tertiaryLabelColor
    }

    /// Code's text: a little greyer than the label colour, to set it apart from the text around it.
    static let codeLabel = NSColor(name: "codeLabel") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.7) : NSColor(white: 0, alpha: 0.7)
    }
}
