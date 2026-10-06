import Foundation

/// How editing treats hidden markers (ADR-016, UX_SPEC §1 "Caret and typing" and "Deleting,
/// replacing, copying"): as part of their span, never as characters on their own. The caret skips
/// them, `⌫` / `⌦` never delete one alone, a partly deleted span keeps its markers and copy writes
/// balanced Markdown.
///
/// Each rule is a function of the text, its spans and a selection. Ranges are UTF-16, as
/// `NSTextView` counts them. Edits are `MarkdownEdit`s, applied by the editor as one undo step.
public struct HiddenMarkerEditing {
    public let text: String
    public let spans: [MarkdownSpan]
    /// The markers on screen as zero-width runs, sorted and merged (`MarkdownStyling.hiddenRuns`).
    public let hiddenRuns: [NSRange]
    private let ns: NSString

    /// - Parameters:
    ///   - spans: `MarkdownStyling.spans(in: text)`, if the caller has them already.
    ///   - selection: A selection inside a link's destination reveals that link: its markers show,
    ///     so they aren't hidden runs.
    public init(text: String, spans: [MarkdownSpan]? = nil, revealing selection: NSRange? = nil) {
        self.text = text
        self.ns = text as NSString
        self.spans = spans ?? MarkdownStyling.spans(in: text)
        self.hiddenRuns = MarkdownStyling.hiddenRuns(of: self.spans, revealing: selection)
    }

    // MARK: - Caret and selection

    /// Where a caret at `position` sits: inside or at either end of a hidden run it moves to the
    /// run's start, so typing at a span's edge takes the style on its left.
    public func caretStop(_ position: Int) -> Int {
        let position = clamped(position)
        if position > 0, let run = lastRun(startingAtOrBefore: position - 1), position <= NSMaxRange(run) {
            return run.location
        }
        return position
    }

    /// `→`: one visible character on, skipping hidden runs. Stays put only at the end.
    public func nextCaretStop(after position: Int) -> Int {
        let stop = caretStop(position)
        var index = stop
        if let run = run(startingAt: index) {
            index = NSMaxRange(run)
        }
        guard index < ns.length else {
            return stop
        }
        return caretStop(NSMaxRange(ns.rangeOfComposedCharacterSequence(at: index)))
    }

    /// `←`: one visible character back, skipping hidden runs. Stays put only at the start.
    public func previousCaretStop(before position: Int) -> Int {
        let stop = caretStop(position)
        guard stop > 0 else {
            return stop
        }
        return caretStop(ns.rangeOfComposedCharacterSequence(at: stop - 1).location)
    }

    /// A non-empty selection with its ends moved out of hidden runs onto visible text: the start
    /// forward, the end back. One that covers only hidden markers becomes a caret.
    public func trimmedSelection(_ selection: NSRange) -> NSRange {
        let range = clamped(selection)
        guard range.length > 0 else {
            return NSRange(location: caretStop(range.location), length: 0)
        }
        var start = range.location
        var end = NSMaxRange(range)
        if let run = lastRun(startingAtOrBefore: start), start < NSMaxRange(run) {
            start = NSMaxRange(run)
        }
        if let run = lastRun(startingAtOrBefore: end - 1), end <= NSMaxRange(run) {
            end = run.location
        }
        guard start < end else {
            return NSRange(location: caretStop(range.location), length: 0)
        }
        return NSRange(location: start, length: end - start)
    }

    // MARK: - Deleting

    /// `⌫` (`backward`) or `⌦` with the caret at `caret`: the visible character before or after it,
    /// plus the markers of any span left with no visible text. `nil` at the start or end.
    public func deletion(backward: Bool, from caret: Int) -> MarkdownEdit? {
        let stop = caretStop(caret)
        let character: NSRange
        if backward {
            guard stop > 0 else {
                return nil
            }
            character = ns.rangeOfComposedCharacterSequence(at: stop - 1)
        } else {
            var index = stop
            if let run = run(startingAt: index) {
                index = NSMaxRange(run)
            }
            guard index < ns.length else {
                return nil
            }
            character = ns.rangeOfComposedCharacterSequence(at: index)
        }
        let range = plan(deleting: character).hull
        // `⌦` leaves the caret where it was, unless a span before it went too.
        let caret = backward ? range.location : min(stop, range.location)
        return MarkdownEdit(range: range, replacement: "", selection: NSRange(location: caret, length: 0))
    }

    /// Deleting (or cutting) `selection`: every span whose visible text is all selected goes with
    /// its markers; a span only partly selected keeps them. `nil` if nothing visible is selected.
    public func deletion(of selection: NSRange) -> MarkdownEdit? {
        let range = trimmedSelection(selection)
        guard range.length > 0 else {
            return nil
        }
        if MarkdownStyling.link(in: spans, withDestinationHolding: range) != nil {
            return MarkdownEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
        }
        let plan = plan(deleting: range)
        return MarkdownEdit(range: plan.hull, replacement: plan.kept, selection: NSRange(location: plan.hull.location, length: 0))
    }

    // MARK: - Typing and pasting

    /// Typing or pasting `string` over `selection` (or at a caret). The selection is deleted as by
    /// `deletion(of:)`, and the new text takes the style of the first selected character: a style
    /// whose span went with the selection is put back around it. Line breaks in `string` split
    /// the spans around them, as `lineBreak(at:)` does.
    public func replacement(of selection: NSRange, with string: String) -> MarkdownEdit {
        let selection = clamped(selection)
        let range = selection.length > 0 ? trimmedSelection(selection) : selection
        var first = MarkdownEdit(range: NSRange(location: range.location, length: 0), replacement: "", selection: NSRange(location: range.location, length: 0))
        var restyle: [MarkdownSpan] = []
        if range.length > 0 {
            if MarkdownStyling.link(in: spans, withDestinationHolding: range) != nil {
                first = MarkdownEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
            } else {
                let plan = plan(deleting: range)
                first = MarkdownEdit(range: plan.hull, replacement: plan.kept, selection: NSRange(location: plan.hull.location, length: 0))
                restyle = plan.removed.filter { $0.contentRange.location <= range.location && range.location < NSMaxRange($0.contentRange) }
            }
        }

        let lines = Self.lines(of: string)
        var current = ns.replacingCharacters(in: first.range, with: first.replacement) as NSString
        var position = first.range.location
        // The common case: no style to put back, and no line break or none inside a span.
        let plainInsert = { () -> MarkdownEdit in
            let length = (string as NSString).length
            return MarkdownEdit(range: first.range, replacement: string + first.replacement, selection: NSRange(location: first.range.location + length, length: 0))
        }
        if restyle.isEmpty, lines.count == 1 {
            return plainInsert()
        }
        if restyle.isEmpty, !MarkdownStyling.spans(in: current as String).contains(where: {
            $0.contentRange.location < position && position <= NSMaxRange($0.contentRange)
        }) {
            return plainInsert()
        }

        for (index, line) in lines.enumerated() {
            let editing = HiddenMarkerEditing(text: current as String)
            let inEffect = Set(editing.spans.filter { $0.contentRange.location <= position && position <= NSMaxRange($0.contentRange) }.map(\.kind))
            let piece = wrapped(line.text, in: restyle.filter { !inEffect.contains($0.kind) })
            current = current.replacingCharacters(in: NSRange(location: position, length: 0), with: piece.text) as NSString
            position += piece.caret
            if index < lines.count - 1 {
                let lineBreak = HiddenMarkerEditing(text: current as String).lineBreakEdit(at: position, terminator: line.terminator)
                current = current.replacingCharacters(in: lineBreak.edit.range, with: lineBreak.edit.replacement) as NSString
                // The next line goes inside the spans opened again.
                position = lineBreak.contentStart
            }
        }
        position = HiddenMarkerEditing(text: current as String).caretStop(position)
        return Self.edit(from: ns, to: current, covering: first.range, caret: position)
    }

    /// `↩` at `selection`. Inside a span the break closes it and opens it again on the new line
    /// (`**ab‸c**` gives `**ab**⏎**c**`), keeping spaces next to the break outside the markers. At
    /// a span's end the break goes after the closing marker. A selection is replaced first.
    public func lineBreak(at selection: NSRange) -> MarkdownEdit {
        let selection = clamped(selection)
        guard selection.length == 0 else {
            return replacement(of: selection, with: "\n")
        }
        return lineBreakEdit(at: selection.location, terminator: "\n").edit
    }

    /// After typing `inserted`: where the caret stays if the insertion completed a span's closing
    /// marker, so what's typed next is plain. `nil` otherwise (the caret snaps as usual).
    public func caretAfterClosingMarker(completedBy inserted: NSRange) -> Int? {
        let end = NSMaxRange(inserted)
        let closes = spans.contains { span in
            NSMaxRange(span.range) == end && NSIntersectionRange(span.closingMarker, inserted).length > 0
        }
        return closes ? end : nil
    }

    // MARK: - Copying

    /// The Markdown that copy, cut and drag put on the pasteboard: the selection, with any span
    /// that's only partly selected closed and opened again around it, so it pastes looking the
    /// same (`ab` from `**abc**` gives `**ab**`). Spaces at the ends stay outside the markers.
    public func copiedMarkdown(for selection: NSRange) -> String {
        let range = trimmedSelection(selection)
        guard range.length > 0 else {
            return ""
        }
        let middle = ns.substring(with: range)
        if MarkdownStyling.link(in: spans, withDestinationHolding: range) != nil {
            return middle
        }
        let end = NSMaxRange(range)
        let openers = spans
            .filter { $0.contentRange.location <= range.location && range.location < NSMaxRange($0.contentRange) }
            .map { ns.substring(with: $0.openingMarker) }
            .joined()
        let closers = spans
            .filter { $0.contentRange.location < end && end <= NSMaxRange($0.contentRange) }
            .reversed()
            .map { ns.substring(with: $0.closingMarker) }
            .joined()
        guard !openers.isEmpty || !closers.isEmpty else {
            return middle
        }
        let parts = Self.splitSpaces(middle)
        guard !parts.core.isEmpty else {
            return middle
        }
        return parts.leading + openers + parts.core + closers + parts.trailing
    }

    // MARK: - Private

    /// What deleting `range` removes: the range grown to every span whose visible text is all
    /// inside it, and the markers of the other spans in that range, which stay.
    private func plan(deleting range: NSRange) -> (hull: NSRange, kept: String, removed: [MarkdownSpan]) {
        var hull = range
        var removed: [MarkdownSpan] = []
        var grew = true
        while grew {
            grew = false
            for span in spans where !removed.contains(span) && span.contentRange.length > 0
                && span.contentRange.location >= hull.location && NSMaxRange(span.contentRange) <= NSMaxRange(hull) {
                removed.append(span)
                hull = NSUnionRange(hull, span.range)
                grew = true
            }
        }
        let keptRanges = spans
            .filter { !removed.contains($0) }
            .flatMap(\.markerRanges)
            .map { NSIntersectionRange($0, hull) }
            .filter { $0.length > 0 }
            .sorted { $0.location < $1.location }
        var kept = ""
        var cursor = hull.location
        for marker in keptRanges where NSMaxRange(marker) > cursor {
            let start = max(marker.location, cursor)
            kept += ns.substring(with: NSRange(location: start, length: NSMaxRange(marker) - start))
            cursor = NSMaxRange(marker)
        }
        return (hull, kept, removed)
    }

    /// A line break at `caret`, as `lineBreak(at:)` describes, and where the spans opened again
    /// start their content (after their markers; the edit's caret is before them).
    private func lineBreakEdit(at caret: Int, terminator: String) -> (edit: MarkdownEdit, contentStart: Int) {
        let terminatorLength = (terminator as NSString).length
        var position = clamped(caret)
        let plain = { (at: Int) in
            (MarkdownEdit(range: NSRange(location: at, length: 0), replacement: terminator, selection: NSRange(location: at + terminatorLength, length: 0)), at + terminatorLength)
        }
        if MarkdownStyling.link(in: spans, withDestinationHolding: NSRange(location: position, length: 0)) != nil {
            return plain(position)
        }

        // At a span's end: after its closing marker, and after any outer span's that ends there too.
        var moved = true
        while moved {
            moved = false
            if let span = spans.first(where: { NSMaxRange($0.contentRange) == position && $0.closingMarker.length > 0 }) {
                position = NSMaxRange(span.range)
                moved = true
            }
        }

        let splits = spans.filter { $0.contentRange.location < position && position < NSMaxRange($0.contentRange) }
        guard let innerStart = splits.map(\.contentRange.location).max(),
              let innerEnd = splits.map({ NSMaxRange($0.contentRange) }).min() else {
            return plain(position)
        }
        var left = position
        while left > innerStart, Self.isSpace(ns.character(at: left - 1)) {
            left -= 1
        }
        if left == innerStart {
            left = position
        }
        var right = position
        while right < innerEnd, Self.isSpace(ns.character(at: right)) {
            right += 1
        }
        if right == innerEnd {
            right = position
        }
        let closers = splits.reversed().map { ns.substring(with: $0.closingMarker) }.joined()
        let openers = splits.map { ns.substring(with: $0.openingMarker) }.joined()
        let before = ns.substring(with: NSRange(location: left, length: position - left))
        let after = ns.substring(with: NSRange(location: position, length: right - position))
        let head = closers + before + terminator + after
        let caret = left + (head as NSString).length
        let edit = MarkdownEdit(range: NSRange(location: left, length: right - left), replacement: head + openers, selection: NSRange(location: caret, length: 0))
        return (edit, caret + (openers as NSString).length)
    }

    /// `text` wrapped in `spans`' markers (outer first), spaces at its ends left outside, and where
    /// the caret goes: before the closing markers, or at the end if the text ends in a space.
    private func wrapped(_ text: String, in spans: [MarkdownSpan]) -> (text: String, caret: Int) {
        let length = (text as NSString).length
        let parts = Self.splitSpaces(text)
        guard !spans.isEmpty, !parts.core.isEmpty else {
            return (text, length)
        }
        let openers = spans.map { ns.substring(with: $0.openingMarker) }.joined()
        let closers = spans.reversed().map { ns.substring(with: $0.closingMarker) }.joined()
        let head = parts.leading + openers + parts.core
        let result = head + closers + parts.trailing
        return (result, parts.trailing.isEmpty ? (head as NSString).length : (result as NSString).length)
    }

    /// The last hidden run starting at or before `position`.
    private func lastRun(startingAtOrBefore position: Int) -> NSRange? {
        var low = 0
        var high = hiddenRuns.count
        while low < high {
            let middle = (low + high) / 2
            if hiddenRuns[middle].location <= position {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low > 0 ? hiddenRuns[low - 1] : nil
    }

    private func run(startingAt position: Int) -> NSRange? {
        lastRun(startingAtOrBefore: position).flatMap { $0.location == position ? $0 : nil }
    }

    private func clamped(_ position: Int) -> Int {
        min(max(position, 0), ns.length)
    }

    private func clamped(_ range: NSRange) -> NSRange {
        let start = clamped(range.location)
        return NSRange(location: start, length: clamped(start + max(range.length, 0)) - start)
    }

    /// The single edit that turns `original` into `result`, covering at least `covering`.
    private static func edit(from original: NSString, to result: NSString, covering: NSRange, caret: Int) -> MarkdownEdit {
        var prefix = 0
        let maxPrefix = min(covering.location, result.length)
        while prefix < maxPrefix, original.character(at: prefix) == result.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        let maxSuffix = min(original.length - NSMaxRange(covering), result.length - prefix)
        while suffix < maxSuffix, original.character(at: original.length - 1 - suffix) == result.character(at: result.length - 1 - suffix) {
            suffix += 1
        }
        let range = NSRange(location: prefix, length: original.length - suffix - prefix)
        let replacement = result.substring(with: NSRange(location: prefix, length: result.length - suffix - prefix))
        return MarkdownEdit(range: range, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    /// `string`'s lines, each with the line break after it (`""` for the last).
    private static func lines(of string: String) -> [(text: String, terminator: String)] {
        let ns = string as NSString
        var lines: [(String, String)] = []
        var start = 0
        var index = 0
        while index < ns.length {
            let unit = ns.character(at: index)
            guard isNewline(unit) else {
                index += 1
                continue
            }
            let length = unit == 0x0D && index + 1 < ns.length && ns.character(at: index + 1) == 0x0A ? 2 : 1
            lines.append((ns.substring(with: NSRange(location: start, length: index - start)), ns.substring(with: NSRange(location: index, length: length))))
            index += length
            start = index
        }
        lines.append((ns.substring(from: start), ""))
        return lines
    }

    /// Spaces and tabs at either end, and what's between.
    private static func splitSpaces(_ text: String) -> (leading: String, core: String, trailing: String) {
        let ns = text as NSString
        var start = 0
        var end = ns.length
        while start < end, isSpace(ns.character(at: start)) || isNewline(ns.character(at: start)) {
            start += 1
        }
        while end > start, isSpace(ns.character(at: end - 1)) || isNewline(ns.character(at: end - 1)) {
            end -= 1
        }
        return (
            ns.substring(to: start),
            ns.substring(with: NSRange(location: start, length: end - start)),
            ns.substring(from: end)
        )
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0 || unit == 0x3000
    }

    private static func isNewline(_ unit: unichar) -> Bool {
        (0x0A...0x0D).contains(unit) || unit == 0x85 || unit == 0x2028 || unit == 0x2029
    }
}
