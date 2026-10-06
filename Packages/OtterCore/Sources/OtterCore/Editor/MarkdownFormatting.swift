import Foundation

/// An inline Markdown style: what a formatting shortcut in the panel's editor adds or removes
/// (UX_SPEC §2), and what `MarkdownStyling` finds for the editor to show (ADR-016). The text stays
/// plain, so a shortcut only adds or removes Markdown markers.
public enum MarkdownStyle: Sendable, CaseIterable {
    /// `⌘B`: `**…**`.
    case bold
    /// `⌘I`: `*…*`.
    case italic
    /// `⇧⌘X`: `~~…~~`.
    case strikethrough
    /// `⌘E`: `` `…` ``.
    case code
    /// `⌘K`: `[…](url)`.
    case link
}

/// One replacement in the editor's text. Ranges are UTF-16, as `NSTextView` counts them.
public struct MarkdownEdit: Equatable, Sendable {
    /// The range of the original text to replace.
    public var range: NSRange
    public var replacement: String
    /// The selection afterwards, in the edited text.
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

public enum MarkdownFormatting {
    /// The placeholder put in a new link's destination, selected so typing replaces it.
    public static let urlPlaceholder = "url"

    /// The edit a shortcut makes, or `nil` if it has nothing to work on (a selection of only
    /// whitespace, a link across lines, or a range outside the text).
    ///
    /// Bold, italic, strikethrough and code toggle:
    /// - A selection is trimmed of surrounding whitespace and wrapped, staying selected. If it's
    ///   already wrapped, by markers just outside it or at its own ends, they're removed instead.
    /// - A selection across lines is done line by line, skipping blank lines and leaving list,
    ///   quote and heading prefixes outside the markers. If every line is already wrapped, they're
    ///   all unwrapped; otherwise the lines that aren't are wrapped.
    /// - With no selection, a caret at the end of a span of the style moves after its closing
    ///   marker, with no change to the text, so what's typed next is plain (ADR-016). A caret
    ///   inside a span of the style removes that span's markers. A caret inside a word toggles that
    ///   word and stays where it was in it. A caret between an empty pair removes the pair; anywhere
    ///   else an empty pair is inserted with the caret between. The editor hides complete spans'
    ///   markers, so a caret at either edge of a hidden run counts as inside the span next to it.
    /// - Bold and italic share `*`, so a run of three is both: `⌘I` on `**x**` gives `***x***`,
    ///   and taking either off `***x***` leaves the other.
    ///
    /// A link uses the selection, or the word at the caret, as its text, with the `url` placeholder
    /// selected. A single http(s) URL on the clipboard is used instead, with the caret after the
    /// link. A selection (or the text at the caret) that is itself a URL becomes the destination,
    /// with the caret in the empty brackets. Otherwise an empty link is inserted, caret in the brackets.
    /// With the caret or selection in an existing link, nothing changes and its URL is selected,
    /// which shows the link raw in the editor.
    ///
    /// - Parameter clipboard: The clipboard's plain text; only links read it.
    public static func apply(_ style: MarkdownStyle, to text: String, selection: NSRange, clipboard: String? = nil) -> MarkdownEdit? {
        let ns = text as NSString
        guard selection.location >= 0, selection.length >= 0, NSMaxRange(selection) <= ns.length else {
            return nil
        }
        switch style {
        case .bold: return toggle(.bold, style, in: text, selection: selection)
        case .italic: return toggle(.italic, style, in: text, selection: selection)
        case .strikethrough: return toggle(.strikethrough, style, in: text, selection: selection)
        case .code: return toggle(.code, style, in: text, selection: selection)
        case .link: return link(in: text, selection: selection, clipboard: clipboard)
        }
    }

    /// `string`, trimmed, if it's one http or https URL with a host.
    static func webURL(in string: String) -> String? {
        let candidate = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else {
            return nil
        }
        return candidate
    }

    // MARK: - Emphasis and code

    /// A style made of one marker character repeated `width` times on each side.
    private struct Wrapper: Sendable {
        let marker: unichar
        let width: Int
        /// Whether a run of `count` markers includes this style. `*` serves bold and italic, so
        /// bold is any run of two or more and italic any odd run.
        let isPresent: @Sendable (Int) -> Bool

        static let bold = Wrapper(marker: 0x2A, width: 2) { $0 >= 2 }
        static let italic = Wrapper(marker: 0x2A, width: 1) { $0 % 2 == 1 }
        static let strikethrough = Wrapper(marker: 0x7E, width: 2) { $0 >= 2 }
        static let code = Wrapper(marker: 0x60, width: 1) { $0 >= 1 }

        var markers: String {
            String(repeating: Character(Unicode.Scalar(marker)!), count: width)
        }
    }

    private enum WrapState {
        /// The text starts and ends with the markers.
        case inside
        /// The markers are just outside the text.
        case outside
        case plain
    }

    private static func toggle(_ wrapper: Wrapper, _ style: MarkdownStyle, in text: String, selection: NSRange) -> MarkdownEdit? {
        let ns = text as NSString
        guard selection.length > 0 else {
            return toggleAtCaret(wrapper, style, in: text, caret: selection.location)
        }

        let segments = lines(of: selection, in: ns).compactMap { line -> NSRange? in
            var segment = line
            if line.location == lineStart(of: line.location, in: ns) {
                segment = skippingBlockPrefix(segment, in: ns)
            }
            segment = trimmed(segment, in: ns, .whitespaces)
            return segment.length > 0 ? segment : nil
        }
        guard !segments.isEmpty else {
            return nil
        }

        let states = segments.map { state(of: $0, wrapper, in: ns) }
        let unwrap = !states.contains(.plain)
        var pieces: [(range: NSRange, replacement: String, text: NSRange)] = []
        for (segment, state) in zip(segments, states) {
            let content = ns.substring(with: segment)
            let width = wrapper.width
            switch (unwrap, state) {
            case (true, .inside):
                let inner = NSRange(location: segment.location + width, length: segment.length - 2 * width)
                let replacement = ns.substring(with: inner)
                pieces.append((segment, replacement, NSRange(location: 0, length: inner.length)))
            case (true, .outside):
                let outer = NSRange(location: segment.location - width, length: segment.length + 2 * width)
                pieces.append((outer, content, NSRange(location: 0, length: segment.length)))
            case (false, .plain):
                let replacement = wrapper.markers + content + wrapper.markers
                pieces.append((segment, replacement, NSRange(location: width, length: segment.length)))
            default:
                break
            }
        }

        if segments.count == 1, let piece = pieces.first {
            let selection = NSRange(location: piece.range.location + piece.text.location, length: piece.text.length)
            return MarkdownEdit(range: piece.range, replacement: piece.replacement, selection: selection)
        }
        // Several lines: one edit over the whole selection, which stays selected.
        let edit = merged(pieces.map { ($0.range, $0.replacement) }, covering: selection, in: ns)
        let newSelection = NSRange(location: edit.range.location, length: (edit.replacement as NSString).length)
        return MarkdownEdit(range: edit.range, replacement: edit.replacement, selection: newSelection)
    }

    private static func toggleAtCaret(_ wrapper: Wrapper, _ style: MarkdownStyle, in text: String, caret original: Int) -> MarkdownEdit {
        let ns = text as NSString
        let width = wrapper.width
        let spans = MarkdownStyling.spans(in: text)
        let caret = caretInside(spans, at: original)

        // At the end of a span of this style, with only hidden markers between: step out of it, so
        // typing is plain.
        let hidden = HiddenMarkerEditing(text: text, spans: spans)
        let stop = hidden.caretStop(original)
        if let span = spans.filter({ $0.kind == style && hidden.caretStop(NSMaxRange($0.contentRange)) == stop })
            .min(by: { NSMaxRange($0.range) < NSMaxRange($1.range) }) {
            return MarkdownEdit(range: NSRange(location: original, length: 0), replacement: "", selection: NSRange(location: NSMaxRange(span.range), length: 0))
        }
        // Inside one: take it off, the innermost if they nest.
        if let span = spans.last(where: { $0.kind == style && $0.contentRange.location <= caret && caret < NSMaxRange($0.contentRange) }) {
            let content = ns.substring(with: span.contentRange)
            return MarkdownEdit(range: span.range, replacement: content, selection: NSRange(location: caret - span.openingMarker.length, length: 0))
        }

        // Between an empty pair: remove it.
        let before = run(of: wrapper.marker, in: ns, endingAt: caret)
        let after = run(of: wrapper.marker, in: ns, startingAt: caret)
        if wrapper.isPresent(before), wrapper.isPresent(after) {
            let pair = NSRange(location: caret - width, length: 2 * width)
            return MarkdownEdit(range: pair, replacement: "", selection: NSRange(location: caret - width, length: 0))
        }

        if let word = word(at: caret, in: text, edges: spans) {
            switch state(of: word, wrapper, in: ns) {
            case .outside:
                let outer = NSRange(location: word.location - width, length: word.length + 2 * width)
                return MarkdownEdit(range: outer, replacement: ns.substring(with: word), selection: NSRange(location: caret - width, length: 0))
            case .inside, .plain:
                let replacement = wrapper.markers + ns.substring(with: word) + wrapper.markers
                return MarkdownEdit(range: word, replacement: replacement, selection: NSRange(location: caret + width, length: 0))
            }
        }

        return MarkdownEdit(
            range: NSRange(location: caret, length: 0),
            replacement: wrapper.markers + wrapper.markers,
            selection: NSRange(location: caret + width, length: 0)
        )
    }

    /// Whether `range`, which has no surrounding whitespace, is already wrapped.
    private static func state(of range: NSRange, _ wrapper: Wrapper, in ns: NSString) -> WrapState {
        let end = NSMaxRange(range)

        // At its own ends, with no other run of the style in between: `**a** b **c**` is two spans.
        let leading = run(of: wrapper.marker, in: ns, startingAt: range.location, limit: end)
        if leading < range.length {
            let trailing = run(of: wrapper.marker, in: ns, endingAt: end, limit: range.location + leading)
            let inner = NSRange(location: range.location + leading, length: range.length - leading - trailing)
            if wrapper.isPresent(leading), wrapper.isPresent(trailing), inner.length > 0,
               !containsRun(of: wrapper, in: inner, of: ns) {
                return .inside
            }
        }

        let before = run(of: wrapper.marker, in: ns, endingAt: range.location)
        let after = run(of: wrapper.marker, in: ns, startingAt: end)
        if wrapper.isPresent(before), wrapper.isPresent(after) {
            return .outside
        }
        return .plain
    }

    private static func containsRun(of wrapper: Wrapper, in range: NSRange, of ns: NSString) -> Bool {
        var index = range.location
        while index < NSMaxRange(range) {
            let count = run(of: wrapper.marker, in: ns, startingAt: index, limit: NSMaxRange(range))
            if count > 0, wrapper.isPresent(count) {
                return true
            }
            index += max(count, 1)
        }
        return false
    }

    /// Joins non-overlapping replacements, in order, into one over `range` and them, keeping the
    /// text between them.
    private static func merged(_ pieces: [(range: NSRange, replacement: String)], covering range: NSRange, in ns: NSString) -> (range: NSRange, replacement: String) {
        let start = min(range.location, pieces.first?.range.location ?? range.location)
        let end = max(NSMaxRange(range), pieces.last.map { NSMaxRange($0.range) } ?? NSMaxRange(range))
        var replacement = ""
        var cursor = start
        for piece in pieces {
            replacement += ns.substring(with: NSRange(location: cursor, length: piece.range.location - cursor))
            replacement += piece.replacement
            cursor = NSMaxRange(piece.range)
        }
        replacement += ns.substring(with: NSRange(location: cursor, length: end - cursor))
        return (NSRange(location: start, length: end - start), replacement)
    }

    /// Where a caret at the edge of a hidden run counts as being: at the content edge of the span
    /// on the visible side. Before an opening marker it's at the content's start; after a closing
    /// marker (where the editor leaves it after `⌘B` at a span's end), at the content's end.
    private static func caretInside(_ spans: [MarkdownSpan], at caret: Int) -> Int {
        if spans.contains(where: { NSMaxRange($0.contentRange) == caret || $0.contentRange.location == caret }) {
            return caret
        }
        let runs = MarkdownStyling.hiddenRuns(of: spans)
        if let run = runs.first(where: { $0.location == caret }) {
            return NSMaxRange(run)
        }
        if let run = runs.first(where: { NSMaxRange($0) == caret }) {
            return run.location
        }
        return caret
    }

    // MARK: - Links

    private static func link(in text: String, selection: NSRange, clipboard: String?) -> MarkdownEdit? {
        let ns = text as NSString
        let clipboardURL = clipboard.flatMap(webURL(in:))

        // In an existing link, at either edge included: select its URL to show it and type over it.
        let existing = MarkdownStyling.spans(in: text).last { span in
            span.kind == .link && span.range.location <= selection.location && NSMaxRange(selection) <= NSMaxRange(span.range)
        }
        if let destination = existing?.destinationRange {
            return MarkdownEdit(range: NSRange(location: selection.location, length: 0), replacement: "", selection: destination)
        }

        let target: NSRange?
        if selection.length > 0 {
            let range = trimmed(selection, in: ns, .whitespacesAndNewlines)
            // Link text can't span lines.
            guard range.length > 0, ns.rangeOfCharacter(from: .newlines, options: [], range: range).location == NSNotFound else {
                return nil
            }
            target = range
        } else if let token = token(at: selection.location, in: ns), webURL(in: ns.substring(with: token)) != nil {
            target = token
        } else {
            target = word(at: selection.location, in: text)
        }

        guard let target else {
            let destination = clipboardURL ?? urlPlaceholder
            return MarkdownEdit(
                range: NSRange(location: selection.location, length: 0),
                replacement: "[](\(destination))",
                selection: NSRange(location: selection.location + 1, length: 0)
            )
        }

        let content = ns.substring(with: target)
        if let url = webURL(in: content) {
            return MarkdownEdit(range: target, replacement: "[](\(url))", selection: NSRange(location: target.location + 1, length: 0))
        }
        if let clipboardURL {
            let replacement = "[\(content)](\(clipboardURL))"
            let end = target.location + (replacement as NSString).length
            return MarkdownEdit(range: target, replacement: replacement, selection: NSRange(location: end, length: 0))
        }
        let replacement = "[\(content)](\(urlPlaceholder))"
        let placeholder = NSRange(location: target.location + 1 + target.length + 2, length: (urlPlaceholder as NSString).length)
        return MarkdownEdit(range: target, replacement: replacement, selection: placeholder)
    }

    /// The run of non-whitespace around the caret, if the caret is in or touching one.
    private static func token(at caret: Int, in ns: NSString) -> NSRange? {
        var start = caret
        while start > 0, !isWhitespace(ns.character(at: start - 1)) {
            start -= 1
        }
        var end = caret
        while end < ns.length, !isWhitespace(ns.character(at: end)) {
            end += 1
        }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    // MARK: - Text helpers

    /// The word the caret is inside, with word characters on both sides. A caret at a word's start
    /// or end isn't inside it, unless that's also the edge of a span's content in `edges`, where
    /// the markers are hidden. Letters, digits and `_` make words, plus an apostrophe between letters.
    private static func word(at caret: Int, in text: String, edges spans: [MarkdownSpan] = []) -> NSRange? {
        guard let index = Range(NSRange(location: caret, length: 0), in: text)?.lowerBound else {
            return nil
        }
        let left = wordLength(text[..<index].reversed())
        let right = wordLength(text[index...])
        let atContentEnd = left > 0 && spans.contains { NSMaxRange($0.contentRange) == caret }
        let atContentStart = right > 0 && spans.contains { $0.contentRange.location == caret }
        guard (left > 0 && right > 0) || atContentEnd || atContentStart else {
            return nil
        }
        return NSRange(location: caret - left, length: left + right)
    }

    /// The UTF-16 length of the word at the start of `characters`.
    private static func wordLength(_ characters: some Sequence<Character>) -> Int {
        var length = 0
        var apostrophe = 0
        for character in characters {
            if character.isLetter || character.isNumber || character == "_" {
                length += apostrophe + character.utf16.count
                apostrophe = 0
            } else if length > 0, apostrophe == 0, character == "'" || character == "\u{2019}" {
                apostrophe = character.utf16.count
            } else {
                break
            }
        }
        return length
    }

    /// The ranges of the lines in `range`, without their line breaks.
    private static func lines(of range: NSRange, in ns: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        var start = range.location
        for index in range.location..<NSMaxRange(range) where isNewline(ns.character(at: index)) {
            lines.append(NSRange(location: start, length: index - start))
            start = index + 1
        }
        lines.append(NSRange(location: start, length: NSMaxRange(range) - start))
        return lines
    }

    private static func lineStart(of index: Int, in ns: NSString) -> Int {
        var start = index
        while start > 0, !isNewline(ns.character(at: start - 1)) {
            start -= 1
        }
        return start
    }

    /// A list item, task, quote or heading marker at the start of a line stays outside the markers.
    private static let blockPrefix = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:>[ \t]?)*(?:#{1,6}[ \t]+|(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?"#
    )

    private static func skippingBlockPrefix(_ range: NSRange, in ns: NSString) -> NSRange {
        guard let match = blockPrefix.firstMatch(in: ns as String, options: [.anchored], range: range), match.range.length > 0 else {
            return range
        }
        return NSRange(location: NSMaxRange(match.range), length: NSMaxRange(range) - NSMaxRange(match.range))
    }

    private static func trimmed(_ range: NSRange, in ns: NSString, _ set: CharacterSet) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isMember(ns.character(at: start), of: set) {
            start += 1
        }
        while end > start, isMember(ns.character(at: end - 1), of: set) {
            end -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    /// How many `marker`s end at `end`, going back no further than `limit`.
    private static func run(of marker: unichar, in ns: NSString, endingAt end: Int, limit: Int = 0) -> Int {
        var index = end
        while index > limit, ns.character(at: index - 1) == marker {
            index -= 1
        }
        return end - index
    }

    /// How many `marker`s start at `start`, going no further than `limit` (the end of the text by default).
    private static func run(of marker: unichar, in ns: NSString, startingAt start: Int, limit: Int? = nil) -> Int {
        let limit = limit ?? ns.length
        var index = start
        while index < limit, ns.character(at: index) == marker {
            index += 1
        }
        return index - start
    }

    private static func isMember(_ unit: unichar, of set: CharacterSet) -> Bool {
        Unicode.Scalar(unit).map(set.contains) ?? false
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        isMember(unit, of: .whitespacesAndNewlines)
    }

    private static func isNewline(_ unit: unichar) -> Bool {
        isMember(unit, of: .newlines)
    }
}
