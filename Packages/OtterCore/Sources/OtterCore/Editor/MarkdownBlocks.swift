import Foundation

/// A `#` heading: one line of the editor's text (UX_SPEC §1 "Headings and code blocks"). Ranges
/// are UTF-16, as in `MarkdownSpan`.
public struct MarkdownHeading: Hashable, Sendable {
    /// 1 for `#`, up to 6 for `######`.
    public var level: Int
    /// The line, without its line break.
    public var lineRange: NSRange
    /// The indentation, the `#`s and the spaces after them. Hidden unless the selection touches
    /// the line (`isOnLine(touchedBy:)`), when it shows dimmed.
    public var markerRange: NSRange
    /// The rest of the line.
    public var contentRange: NSRange

    public init(level: Int, lineRange: NSRange, markerRange: NSRange, contentRange: NSRange) {
        self.level = level
        self.lineRange = lineRange
        self.markerRange = markerRange
        self.contentRange = contentRange
    }

    /// Whether `selection` touches the heading's line, which shows its `#`s: a caret anywhere on
    /// it, or a selection with a character on it. A selection that ends just after the line break
    /// before it doesn't.
    public func isOnLine(touchedBy selection: NSRange) -> Bool {
        guard selection.location <= NSMaxRange(lineRange) else {
            return false
        }
        if selection.length == 0 {
            return selection.location >= lineRange.location
        }
        return NSMaxRange(selection) > lineRange.location
    }
}

/// A fenced code block, from its opening ```` ``` ```` or `~~~` line to its closing one.
public struct MarkdownCodeBlock: Hashable, Sendable {
    /// From the opening fence's start to the end of the closing fence, or of the text while the
    /// block isn't closed. No line break at the end.
    public var range: NSRange
    /// The opening fence's line, info string included, without its line break.
    public var openingFence: NSRange
    /// The closing fence's line, without its line break; `nil` while the block isn't closed.
    public var closingFence: NSRange?

    public init(range: NSRange, openingFence: NSRange, closingFence: NSRange?) {
        self.range = range
        self.openingFence = openingFence
        self.closingFence = closingFence
    }
}

/// Finds the block Markdown the panel's editor styles: `#` headings and fenced code blocks. It
/// only reads the text; styling is the editor's job.
///
/// - A heading is a line outside a fence with up to three spaces, one to six `#`s, then a space or
///   tab. `#tag` and a lone `#` aren't headings, so typing a tag never flashes one. A closing run
///   of `#`s is part of the text.
/// - A code block runs from a fence to the next fence with the same marker and at least as many
///   (CommonMark's rules, in `MarkdownLines`). An unclosed block runs to the end of the text.
public enum MarkdownBlocks {
    /// Every heading, in order.
    public static func headings(in text: String) -> [MarkdownHeading] {
        let characters = Self.characters(of: text)
        var headings: [MarkdownHeading] = []
        MarkdownLines(characters: characters).forEach { line in
            if line.isProse, let heading = heading(on: line, in: characters) {
                headings.append(heading)
            }
        }
        return headings
    }

    /// Every fenced code block, in order.
    public static func codeBlocks(in text: String) -> [MarkdownCodeBlock] {
        let characters = Self.characters(of: text)
        var blocks: [MarkdownCodeBlock] = []
        var opening: NSRange?
        var lastEnd = 0
        MarkdownLines(characters: characters).forEach { line in
            let lineRange = NSRange(location: line.start, length: line.end - line.start)
            lastEnd = line.end
            guard line.isFence else {
                return
            }
            if let open = opening {
                blocks.append(MarkdownCodeBlock(
                    range: NSRange(location: open.location, length: line.end - open.location),
                    openingFence: open,
                    closingFence: lineRange
                ))
                opening = nil
            } else {
                opening = lineRange
            }
        }
        if let open = opening {
            blocks.append(MarkdownCodeBlock(range: NSRange(location: open.location, length: lastEnd - open.location), openingFence: open, closingFence: nil))
        }
        return blocks
    }

    private static func heading(on line: MarkdownLines.Line, in characters: [unichar]) -> MarkdownHeading? {
        var index = line.start
        while index < line.end, index - line.start < 3, characters[index] == space {
            index += 1
        }
        let hashes = index
        while index < line.end, characters[index] == hash {
            index += 1
        }
        let level = index - hashes
        guard (1...6).contains(level), index < line.end, characters[index] == space || characters[index] == tab else {
            return nil
        }
        while index < line.end, characters[index] == space || characters[index] == tab {
            index += 1
        }
        return MarkdownHeading(
            level: level,
            lineRange: NSRange(location: line.start, length: line.end - line.start),
            markerRange: NSRange(location: line.start, length: index - line.start),
            contentRange: NSRange(location: index, length: line.end - index)
        )
    }

    private static func characters(of text: String) -> [unichar] {
        let ns = text as NSString
        var characters = [unichar](repeating: 0, count: ns.length)
        ns.getCharacters(&characters, range: NSRange(location: 0, length: ns.length))
        return characters
    }
}

private let tab: unichar = 0x09
private let space: unichar = 0x20
private let hash: unichar = 0x23
