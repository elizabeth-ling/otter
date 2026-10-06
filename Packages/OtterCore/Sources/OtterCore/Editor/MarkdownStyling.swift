import Foundation

/// One complete inline Markdown span in the editor's text (ADR-016). Ranges are UTF-16, as
/// `NSTextView` counts them.
public struct MarkdownSpan: Hashable, Sendable {
    public var kind: MarkdownStyle
    /// The whole span, markers included.
    public var range: NSRange
    /// The text shown: `range` without the markers. A link's text, without its `[` and `](url)`.
    public var contentRange: NSRange
    /// A link's URL, inside its `(…)`; `nil` for other kinds.
    public var destinationRange: NSRange?

    public init(kind: MarkdownStyle, range: NSRange, contentRange: NSRange, destinationRange: NSRange? = nil) {
        self.kind = kind
        self.range = range
        self.contentRange = contentRange
        self.destinationRange = destinationRange
    }

    /// `**`, `` ` ``, a link's `[`…
    public var openingMarker: NSRange {
        NSRange(location: range.location, length: contentRange.location - range.location)
    }

    /// `**`, `` ` ``, a link's `](url)`…
    public var closingMarker: NSRange {
        NSRange(location: NSMaxRange(contentRange), length: NSMaxRange(range) - NSMaxRange(contentRange))
    }

    /// `range` minus `contentRange`: what the editor hides.
    public var markerRanges: [NSRange] {
        [openingMarker, closingMarker]
    }
}

/// Finds the inline Markdown the panel's editor styles: bold, italic, strikethrough, inline code
/// and links (UX_SPEC §1 "Inline Markdown styling"). It only reads the text; styling and hiding
/// are the editor's job.
///
/// The rules are CommonMark/GFM emphasis as Obsidian renders it, limited to one line:
/// - `*`/`_` italic and `**`/`__` bold, with CommonMark's flanking rules, so a marker with a space
///   just inside it, or `_` inside a word (`snake_case_name`), stays plain. `~~` strikethrough only.
/// - Backtick runs of any length make code; nothing inside code is parsed.
/// - `[text](url)` links, with an optional title. Images, wikilinks and bare URLs aren't styled,
///   and nothing inside them is.
/// - `\` escapes the next punctuation character (the backslash stays visible).
/// - An unclosed span or an empty pair is plain. No span crosses a line break, and lines inside a
///   ```` ``` ```` or `~~~` fence get none.
public enum MarkdownStyling {
    /// Every complete span, sorted by start, the outer of two spans at the same start first. Spans
    /// nest: `***x***` is an italic span around a bold one.
    public static func spans(in text: String) -> [MarkdownSpan] {
        let ns = text as NSString
        var characters = [unichar](repeating: 0, count: ns.length)
        ns.getCharacters(&characters, range: NSRange(location: 0, length: ns.length))
        var parser = InlineParser(characters: characters)
        parser.parseDocument()
        return parser.spans.sorted {
            $0.range.location != $1.range.location ? $0.range.location < $1.range.location : $0.range.length > $1.range.length
        }
    }

    /// The link whose destination holds `selection` (both ends inclusive): it shows raw while
    /// the selection is there, after `⌘K`.
    public static func link(in spans: [MarkdownSpan], withDestinationHolding selection: NSRange) -> MarkdownSpan? {
        spans.first { span in
            guard span.kind == .link, let destination = span.destinationRange else {
                return false
            }
            return selection.location >= destination.location && NSMaxRange(selection) <= NSMaxRange(destination)
        }
    }

    /// The markers to hide, adjacent ones merged into one run (`**a**~~b~~` hides `**~~` as one),
    /// sorted. A link revealed by `selection` keeps its markers; spans inside its text don't.
    public static func hiddenRuns(of spans: [MarkdownSpan], revealing selection: NSRange? = nil) -> [NSRange] {
        let revealed = selection.flatMap { link(in: spans, withDestinationHolding: $0) }
        let markers = spans
            .filter { $0 != revealed }
            .flatMap(\.markerRanges)
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
        var runs: [NSRange] = []
        for marker in markers {
            if let last = runs.last, marker.location <= NSMaxRange(last) {
                runs[runs.count - 1] = NSRange(location: last.location, length: max(NSMaxRange(last), NSMaxRange(marker)) - last.location)
            } else {
                runs.append(marker)
            }
        }
        return runs
    }
}

// MARK: - Parser

/// A one-pass inline parser over UTF-16 code units, line by line. Emphasis follows CommonMark's
/// delimiter algorithm ("process emphasis"), links its bracket stack.
private struct InlineParser {
    let characters: [unichar]
    var spans: [MarkdownSpan] = []

    init(characters: [unichar]) {
        self.characters = characters
    }

    // MARK: Lines and fences

    mutating func parseDocument() {
        var lineStart = 0
        var fence: (marker: unichar, count: Int)?
        while true {
            var lineEnd = lineStart
            while lineEnd < characters.count, !isNewline(characters[lineEnd]) {
                lineEnd += 1
            }
            if let open = fence {
                if closesFence(open, from: lineStart, to: lineEnd) {
                    fence = nil
                }
            } else if let open = opensFence(from: lineStart, to: lineEnd) {
                fence = open
            } else {
                parseLine(from: lineStart, to: lineEnd)
            }
            guard lineEnd < characters.count else {
                break
            }
            let isCRLF = characters[lineEnd] == cr && lineEnd + 1 < characters.count && characters[lineEnd + 1] == lf
            lineStart = lineEnd + (isCRLF ? 2 : 1)
        }
    }

    /// Up to three spaces, then three or more backticks or tildes. A backtick fence's info string
    /// can't hold a backtick.
    private func opensFence(from start: Int, to end: Int) -> (marker: unichar, count: Int)? {
        let index = skippingIndent(from: start, to: end)
        guard index < end, characters[index] == backtick || characters[index] == tilde else {
            return nil
        }
        let marker = characters[index]
        let count = run(of: marker, from: index, to: end)
        guard count >= 3 else {
            return nil
        }
        if marker == backtick, characters[(index + count)..<end].contains(backtick) {
            return nil
        }
        return (marker, count)
    }

    /// The same marker, at least as many, and nothing after but spaces.
    private func closesFence(_ fence: (marker: unichar, count: Int), from start: Int, to end: Int) -> Bool {
        let index = skippingIndent(from: start, to: end)
        let count = run(of: fence.marker, from: index, to: end)
        guard count >= fence.count else {
            return false
        }
        return characters[(index + count)..<end].allSatisfy { $0 == space || $0 == tab }
    }

    private func skippingIndent(from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, index - start < 3, characters[index] == space {
            index += 1
        }
        return index
    }

    // MARK: Inlines

    private struct Delimiter {
        let marker: unichar
        /// Where the run's unused markers start. An opener's used markers come off its end, a
        /// closer's off its start.
        var start: Int
        var count: Int
        let originalCount: Int
        let canOpen: Bool
        let canClose: Bool
        var isActive = true
    }

    private struct Bracket {
        /// The `[`, or the `!` of `![`.
        let position: Int
        let isImage: Bool
        var isActive = true
        /// How many delimiters there were when it was pushed: the ones after belong to its text.
        let delimiterBottom: Int
    }

    private struct BottomKey: Hashable {
        let marker: unichar
        let canOpen: Bool
        let lengthModulo: Int
    }

    private mutating func parseLine(from start: Int, to end: Int) {
        var delimiters: [Delimiter] = []
        var brackets: [Bracket] = []
        var images: [NSRange] = []
        var index = start
        while index < end {
            let character = characters[index]
            switch character {
            case backslash:
                index += index + 1 < end && isASCIIPunctuation(characters[index + 1]) ? 2 : 1
            case backtick:
                let count = run(of: backtick, from: index, to: end)
                if let close = closingBackticks(count, from: index + count, to: end) {
                    spans.append(MarkdownSpan(
                        kind: .code,
                        range: NSRange(location: index, length: close + count - index),
                        contentRange: NSRange(location: index + count, length: close - index - count)
                    ))
                    index = close + count
                } else {
                    index += count
                }
            case asterisk, underscore, tilde:
                let count = run(of: character, from: index, to: end)
                // Strikethrough is `~~` only.
                if character != tilde || count == 2 {
                    delimiters.append(delimiter(character, from: index, count: count, lineStart: start, lineEnd: end))
                }
                index += count
            case openBracket:
                if index + 1 < end, characters[index + 1] == openBracket, let close = wikilinkEnd(from: index + 2, to: end) {
                    index = close
                } else {
                    brackets.append(Bracket(position: index, isImage: false, delimiterBottom: delimiters.count))
                    index += 1
                }
            case exclamation where index + 1 < end && characters[index + 1] == openBracket:
                brackets.append(Bracket(position: index, isImage: true, delimiterBottom: delimiters.count))
                index += 2
            case closeBracket:
                guard let opener = brackets.popLast() else {
                    index += 1
                    break
                }
                guard opener.isActive, let tail = linkTail(from: index + 1, to: end) else {
                    index += 1
                    break
                }
                processEmphasis(&delimiters, bottom: opener.delimiterBottom)
                delimiters.removeSubrange(opener.delimiterBottom...)
                let whole = NSRange(location: opener.position, length: tail.end - opener.position)
                if opener.isImage {
                    images.append(whole)
                } else {
                    let textStart = opener.position + 1
                    if index > textStart {
                        spans.append(MarkdownSpan(
                            kind: .link,
                            range: whole,
                            contentRange: NSRange(location: textStart, length: index - textStart),
                            destinationRange: tail.destination
                        ))
                    }
                    // Links don't contain links.
                    for bracket in brackets.indices where !brackets[bracket].isImage {
                        brackets[bracket].isActive = false
                    }
                }
                index = tail.end
            case openAngle:
                index = autolinkEnd(from: index, to: end) ?? index + 1
            case lowercaseH, uppercaseH, lowercaseW, uppercaseW:
                index = bareURLEnd(from: index, lineStart: start, to: end) ?? index + 1
            default:
                index += 1
            }
        }
        processEmphasis(&delimiters, bottom: 0)
        if !images.isEmpty {
            // Images show as typed, alt text included.
            spans.removeAll { span in
                images.contains { NSLocationInRange(span.range.location, $0) && NSMaxRange(span.range) <= NSMaxRange($0) }
            }
        }
    }

    /// CommonMark's left- and right-flanking rules, with `_` stricter inside words.
    private func delimiter(_ marker: unichar, from start: Int, count: Int, lineStart: Int, lineEnd: Int) -> Delimiter {
        let before = scalar(endingAt: start, lineStart: lineStart)
        let after = scalar(startingAt: start + count, lineEnd: lineEnd)
        let beforeIsSpace = before.map(isUnicodeWhitespace) ?? true
        let afterIsSpace = after.map(isUnicodeWhitespace) ?? true
        let beforeIsPunctuation = before.map(isUnicodePunctuation) ?? false
        let afterIsPunctuation = after.map(isUnicodePunctuation) ?? false
        let leftFlanking = !afterIsSpace && (!afterIsPunctuation || beforeIsSpace || beforeIsPunctuation)
        let rightFlanking = !beforeIsSpace && (!beforeIsPunctuation || afterIsSpace || afterIsPunctuation)
        let canOpen: Bool
        let canClose: Bool
        if marker == underscore {
            canOpen = leftFlanking && (!rightFlanking || beforeIsPunctuation)
            canClose = rightFlanking && (!leftFlanking || afterIsPunctuation)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        return Delimiter(marker: marker, start: start, count: count, originalCount: count, canOpen: canOpen, canClose: canClose)
    }

    /// CommonMark's "process emphasis" over the delimiters from `bottom` on, including the rule
    /// of three. `~~` pairs only with `~~`.
    private mutating func processEmphasis(_ delimiters: inout [Delimiter], bottom: Int) {
        var openersBottom: [BottomKey: Int] = [:]
        var current = bottom
        while current < delimiters.count {
            let closer = delimiters[current]
            guard closer.isActive, closer.canClose, closer.count > 0 else {
                current += 1
                continue
            }
            let key = BottomKey(marker: closer.marker, canOpen: closer.canOpen, lengthModulo: closer.originalCount % 3)
            let lowest = max(bottom, openersBottom[key] ?? bottom)
            var openerIndex: Int?
            var candidate = current - 1
            while candidate >= lowest {
                let opener = delimiters[candidate]
                if opener.isActive, opener.canOpen, opener.marker == closer.marker, opener.count > 0, matches(opener, closer) {
                    openerIndex = candidate
                    break
                }
                candidate -= 1
            }
            guard let openerIndex else {
                openersBottom[key] = current
                if !closer.canOpen {
                    delimiters[current].isActive = false
                }
                current += 1
                continue
            }

            let opener = delimiters[openerIndex]
            let used = closer.marker == tilde ? 2 : (opener.count >= 2 && closer.count >= 2 ? 2 : 1)
            let openerEnd = opener.start + opener.count
            let kind: MarkdownStyle = closer.marker == tilde ? .strikethrough : (used == 2 ? .bold : .italic)
            spans.append(MarkdownSpan(
                kind: kind,
                range: NSRange(location: openerEnd - used, length: closer.start + used - (openerEnd - used)),
                contentRange: NSRange(location: openerEnd, length: closer.start - openerEnd)
            ))
            delimiters[openerIndex].count -= used
            delimiters[current].start += used
            delimiters[current].count -= used
            for between in (openerIndex + 1)..<current {
                delimiters[between].isActive = false
            }
            if delimiters[openerIndex].count == 0 {
                delimiters[openerIndex].isActive = false
            }
            if delimiters[current].count == 0 {
                delimiters[current].isActive = false
                current += 1
            }
        }
    }

    private func matches(_ opener: Delimiter, _ closer: Delimiter) -> Bool {
        if closer.marker == tilde {
            return opener.count == 2 && closer.count == 2
        }
        // The rule of three: `*a**` doesn't pair the `*` with the `**`.
        let eitherBoth = opener.canClose || closer.canOpen
        let sum = opener.originalCount + closer.originalCount
        return !(eitherBoth && sum % 3 == 0 && !(opener.originalCount % 3 == 0 && closer.originalCount % 3 == 0))
    }

    /// Where a run of exactly `count` backticks starts, at or after `start`.
    private func closingBackticks(_ count: Int, from start: Int, to end: Int) -> Int? {
        var index = start
        while index < end {
            if characters[index] == backtick {
                let length = run(of: backtick, from: index, to: end)
                if length == count {
                    return index
                }
                index += length
            } else {
                index += 1
            }
        }
        return nil
    }

    /// `(destination "title")` after a `]`: the destination's range and the index after `)`.
    private func linkTail(from start: Int, to end: Int) -> (destination: NSRange, end: Int)? {
        guard start < end, characters[start] == openParen else {
            return nil
        }
        var index = skippingSpaces(from: start + 1, to: end)
        let destination: NSRange
        if index < end, characters[index] == openAngle {
            let open = index + 1
            index = open
            while index < end, characters[index] != closeAngle {
                if characters[index] == openAngle {
                    return nil
                }
                index += characters[index] == backslash ? 2 : 1
            }
            guard index < end else {
                return nil
            }
            destination = NSRange(location: open, length: index - open)
            index += 1
        } else {
            let open = index
            var depth = 0
            while index < end {
                let character = characters[index]
                if character == backslash, index + 1 < end, isASCIIPunctuation(characters[index + 1]) {
                    index += 2
                    continue
                }
                if character == space || character == tab || character < 0x20 {
                    break
                }
                if character == openParen {
                    depth += 1
                } else if character == closeParen {
                    if depth == 0 {
                        break
                    }
                    depth -= 1
                }
                index += 1
            }
            guard depth == 0 else {
                return nil
            }
            destination = NSRange(location: open, length: index - open)
        }

        let afterDestination = index
        index = skippingSpaces(from: index, to: end)
        if index < end, index > afterDestination, [doubleQuote, singleQuote, openParen].contains(characters[index]) {
            let close = characters[index] == openParen ? closeParen : characters[index]
            index += 1
            while index < end, characters[index] != close {
                index += characters[index] == backslash ? 2 : 1
            }
            guard index < end else {
                return nil
            }
            index = skippingSpaces(from: index + 1, to: end)
        }
        guard index < end, characters[index] == closeParen else {
            return nil
        }
        return (destination, index + 1)
    }

    /// The index after a wikilink's `]]`, searching from after its `[[`.
    private func wikilinkEnd(from start: Int, to end: Int) -> Int? {
        var index = start
        while index + 1 < end {
            if characters[index] == closeBracket, characters[index + 1] == closeBracket {
                return index > start ? index + 2 : nil
            }
            index += 1
        }
        return nil
    }

    /// The index after an autolink such as `<https://example.com/a_b>`.
    private func autolinkEnd(from start: Int, to end: Int) -> Int? {
        var index = start + 1
        let schemeStart = index
        while index < end, isASCIILetter(characters[index]) || isASCIIDigit(characters[index]) || [plus, dot, hyphen].contains(characters[index]) {
            index += 1
        }
        guard index - schemeStart >= 2, index < end, characters[index] == colon, isASCIILetter(characters[schemeStart]) else {
            return nil
        }
        while index < end, characters[index] != closeAngle {
            if characters[index] == openAngle || characters[index] == space || characters[index] < 0x20 {
                return nil
            }
            index += 1
        }
        return index < end ? index + 1 : nil
    }

    /// The index after a bare `http://`, `https://` or `www.` URL, which isn't styled (GFM's autolink
    /// rules: after a space, `(`, an emphasis marker or the line's start, trailing punctuation left out).
    private func bareURLEnd(from start: Int, lineStart: Int, to end: Int) -> Int? {
        if start > lineStart {
            let before = characters[start - 1]
            guard isUnicodeWhitespace(Unicode.Scalar(before) ?? " ") || [openParen, asterisk, underscore, tilde].contains(before) else {
                return nil
            }
        }
        guard hasPrefix("https://", at: start, end: end) || hasPrefix("http://", at: start, end: end) || hasPrefix("www.", at: start, end: end) else {
            return nil
        }
        var index = start
        while index < end, characters[index] != space, characters[index] != tab, characters[index] != openAngle {
            index += 1
        }
        while index > start, [question, exclamation, dot, comma, colon, asterisk, underscore, tilde, singleQuote, doubleQuote, closeParen].contains(characters[index - 1]) {
            if characters[index - 1] == closeParen {
                let opens = characters[start..<index].filter { $0 == openParen }.count
                let closes = characters[start..<index].filter { $0 == closeParen }.count
                if closes <= opens {
                    break
                }
            }
            index -= 1
        }
        return index
    }

    // MARK: Character helpers

    private func hasPrefix(_ prefix: String, at start: Int, end: Int) -> Bool {
        let units = Array(prefix.utf16)
        guard start + units.count <= end else {
            return false
        }
        for (offset, unit) in units.enumerated() {
            let character = characters[start + offset]
            // ASCII case-insensitive.
            let lowered = (0x41...0x5A).contains(character) ? character + 0x20 : character
            if lowered != unit {
                return false
            }
        }
        return true
    }

    private func run(of marker: unichar, from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, characters[index] == marker {
            index += 1
        }
        return index - start
    }

    private func skippingSpaces(from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, characters[index] == space || characters[index] == tab {
            index += 1
        }
        return index
    }

    /// The scalar just before `index`, or `nil` at the line's start.
    private func scalar(endingAt index: Int, lineStart: Int) -> Unicode.Scalar? {
        guard index > lineStart else {
            return nil
        }
        let low = characters[index - 1]
        if UTF16.isTrailSurrogate(low), index - 2 >= lineStart, UTF16.isLeadSurrogate(characters[index - 2]) {
            return Unicode.Scalar(scalarValue(lead: characters[index - 2], trail: low))
        }
        return Unicode.Scalar(low)
    }

    /// The scalar at `index`, or `nil` at the line's end.
    private func scalar(startingAt index: Int, lineEnd: Int) -> Unicode.Scalar? {
        guard index < lineEnd else {
            return nil
        }
        let high = characters[index]
        if UTF16.isLeadSurrogate(high), index + 1 < lineEnd, UTF16.isTrailSurrogate(characters[index + 1]) {
            return Unicode.Scalar(scalarValue(lead: high, trail: characters[index + 1]))
        }
        return Unicode.Scalar(high)
    }
}

private func scalarValue(lead: unichar, trail: unichar) -> UInt32 {
    0x10000 + ((UInt32(lead) - 0xD800) << 10) + (UInt32(trail) - 0xDC00)
}

private func isNewline(_ unit: unichar) -> Bool {
    (0x0A...0x0D).contains(unit) || unit == 0x85 || unit == 0x2028 || unit == 0x2029
}

private func isASCIIPunctuation(_ unit: unichar) -> Bool {
    (0x21...0x2F).contains(unit) || (0x3A...0x40).contains(unit) || (0x5B...0x60).contains(unit) || (0x7B...0x7E).contains(unit)
}

private func isASCIILetter(_ unit: unichar) -> Bool {
    (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
}

private func isASCIIDigit(_ unit: unichar) -> Bool {
    (0x30...0x39).contains(unit)
}

/// CommonMark's Unicode whitespace: `Zs`, tab, line feed, form feed and carriage return.
private func isUnicodeWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == "\t" || scalar == "\n" || scalar == "\u{0C}" || scalar == "\r" || scalar.properties.generalCategory == .spaceSeparator
}

/// CommonMark's Unicode punctuation: the `P` and `S` categories.
private func isUnicodePunctuation(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
         .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
        return true
    default:
        return false
    }
}

private let tab: unichar = 0x09
private let lf: unichar = 0x0A
private let cr: unichar = 0x0D
private let space: unichar = 0x20
private let exclamation: unichar = 0x21
private let doubleQuote: unichar = 0x22
private let singleQuote: unichar = 0x27
private let openParen: unichar = 0x28
private let closeParen: unichar = 0x29
private let asterisk: unichar = 0x2A
private let plus: unichar = 0x2B
private let comma: unichar = 0x2C
private let hyphen: unichar = 0x2D
private let dot: unichar = 0x2E
private let colon: unichar = 0x3A
private let openAngle: unichar = 0x3C
private let closeAngle: unichar = 0x3E
private let question: unichar = 0x3F
private let uppercaseH: unichar = 0x48
private let uppercaseW: unichar = 0x57
private let openBracket: unichar = 0x5B
private let backslash: unichar = 0x5C
private let closeBracket: unichar = 0x5D
private let underscore: unichar = 0x5F
private let backtick: unichar = 0x60
private let lowercaseH: unichar = 0x68
private let lowercaseW: unichar = 0x77
private let tilde: unichar = 0x7E
