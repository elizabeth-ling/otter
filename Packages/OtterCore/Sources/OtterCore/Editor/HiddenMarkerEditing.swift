import Foundation

/// How editing treats hidden markers (ADR-016, UX_SPEC §1 "Caret and typing" and "Deleting,
/// replacing, copying"): as part of their span, never as characters on their own. The caret skips
/// them, `⌫` / `⌦` never delete one alone, a partly deleted span keeps its markers and copy writes
/// balanced Markdown.
///
/// List items (ADR-017) follow their own rules: an item's prefix is hidden except on the lines the
/// selection touches, where only its indentation is. A hidden prefix snaps the caret forward to the
/// item's text, so arriving on an item puts the caret there; once revealed, the marker is ordinary
/// text. `↩`, `⌫` at the start of the text and `⌦` at its end continue, unmark and join items.
///
/// Each rule is a function of the text, its spans and items, and a selection. Ranges are UTF-16, as
/// `NSTextView` counts them. Edits are `MarkdownEdit`s, applied by the editor as one undo step.
public struct HiddenMarkerEditing {
    public let text: String
    public let spans: [MarkdownSpan]
    /// The list items whose rules apply, in order; none unless the caller passes them.
    public let items: [MarkdownListItem]
    /// Inline markers, adjacent ones merged (`MarkdownStyling.hiddenRuns`). A caret in or beside
    /// one moves to its start.
    private let inlineRuns: [NSRange]
    /// Each item's hidden prefix, or its indentation on a revealed line. A caret in or beside one
    /// moves to its end. Never merged with an inline run.
    private let listRuns: [ListRun]
    private let ns: NSString

    private struct ListRun {
        let range: NSRange
        /// The indentation of a revealed item, rather than a whole hidden prefix.
        let isIndentation: Bool
    }

    /// - Parameters:
    ///   - spans: `MarkdownStyling.spans(in: text)`, if the caller has them already.
    ///   - items: `MarkdownLists.items(in: text)`, for the list rules. Without them, list markers
    ///     are plain text, as for pasted text.
    ///   - linkSelection: A selection inside a link's destination reveals that link: its markers
    ///     show, so they aren't hidden runs.
    ///   - selection: The selection on screen. Items on the lines it touches show their marker, so
    ///     only their indentation is hidden.
    public init(
        text: String,
        spans: [MarkdownSpan]? = nil,
        items: [MarkdownListItem] = [],
        revealing linkSelection: NSRange? = nil,
        selection: NSRange? = nil
    ) {
        self.text = text
        self.ns = text as NSString
        self.spans = spans ?? MarkdownStyling.spans(in: text)
        self.items = items
        self.inlineRuns = MarkdownStyling.hiddenRuns(of: self.spans, revealing: linkSelection)
        self.listRuns = items.compactMap { item in
            if let selection, item.isOnLine(touchedBy: selection) {
                return item.indentRange.length > 0 ? ListRun(range: item.indentRange, isIndentation: true) : nil
            }
            return ListRun(range: item.prefixRange, isIndentation: false)
        }
    }

    /// Everything hidden on screen, sorted: the inline markers and the list prefixes.
    public var hiddenRuns: [NSRange] {
        (inlineRuns + listRuns.map(\.range)).sorted { $0.location < $1.location }
    }

    /// The item whose line holds `position`, its line break excluded.
    public func item(onLineOf position: Int) -> MarkdownListItem? {
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].lineRange.location <= position {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0, position <= NSMaxRange(items[low - 1].contentRange) else {
            return nil
        }
        return items[low - 1]
    }

    // MARK: - Caret and selection

    /// Where a caret at `position` sits: inside or at either end of a hidden list prefix (or a
    /// revealed item's indentation) it moves to the run's end, just before the item's text (or
    /// its `-`). Inside or at either end of a hidden inline run it moves to the run's start, so
    /// typing at a span's edge takes the style on its left.
    public func caretStop(_ position: Int) -> Int {
        var position = clamped(position)
        if let run = listRun(touching: position) {
            position = NSMaxRange(run.range)
        }
        if position > 0, let run = lastInlineRun(startingAtOrBefore: position - 1), position <= NSMaxRange(run) {
            return run.location
        }
        return position
    }

    /// `→`: one visible character on, skipping hidden runs. Stays put only at the end.
    public func nextCaretStop(after position: Int) -> Int {
        let stop = caretStop(position)
        var index = stop
        if let run = inlineRun(startingAt: index) {
            index = NSMaxRange(run)
        }
        guard index < ns.length else {
            return stop
        }
        return caretStop(NSMaxRange(ns.rangeOfComposedCharacterSequence(at: index)))
    }

    /// `←`: one visible character back, skipping hidden runs. Stays put only at the start. From
    /// just after hidden indentation or a hidden prefix, it goes to the end of the line above.
    public func previousCaretStop(before position: Int) -> Int {
        let stop = caretStop(position)
        guard stop > 0 else {
            return stop
        }
        let candidate = ns.rangeOfComposedCharacterSequence(at: stop - 1).location
        if let run = listRun(containing: candidate) {
            guard run.range.location > 0 else {
                return stop
            }
            return caretStop(lineEnd(before: run.range.location))
        }
        return caretStop(candidate)
    }

    /// A non-empty selection with its ends moved out of hidden runs onto visible text: the start
    /// forward, the end back. One that covers only hidden markers becomes a caret. A selection
    /// that includes an item's `-` takes its indentation too, and a hidden prefix goes whole.
    public func trimmedSelection(_ selection: NSRange) -> NSRange {
        let range = clamped(selection)
        guard range.length > 0 else {
            return NSRange(location: caretStop(range.location), length: 0)
        }
        var start = range.location
        var end = NSMaxRange(range)
        if let run = lastListRun(startingAtOrBefore: start) {
            let runEnd = NSMaxRange(run.range)
            if run.isIndentation ? start <= runEnd : start < runEnd {
                guard end > runEnd else {
                    return NSRange(location: caretStop(range.location), length: 0)
                }
                start = run.range.location
            }
        }
        if let run = lastListRun(startingAtOrBefore: end - 1), end < NSMaxRange(run.range) {
            end = run.range.location
        }
        if let run = lastInlineRun(startingAtOrBefore: start), start < NSMaxRange(run) {
            start = NSMaxRange(run)
        }
        if let run = lastInlineRun(startingAtOrBefore: end - 1), end <= NSMaxRange(run) {
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
    ///
    /// In a list: `⌫` at the start of an item's text takes its marker off (all of `- [ ] `),
    /// keeping the indentation; `⌫` just after hidden indentation deletes the line break before
    /// it, with the indentation. `⌦` at the end of an item whose next line is an item joins that
    /// item's text on, its prefix deleted with the line break.
    public func deletion(backward: Bool, from caret: Int) -> MarkdownEdit? {
        let stop = caretStop(caret)
        let character: NSRange
        if backward {
            if let item = item(onLineOf: stop), stop == item.contentRange.location {
                let marker = item.markerRange
                return MarkdownEdit(range: marker, replacement: "", selection: NSRange(location: marker.location, length: 0))
            }
            guard stop > 0 else {
                return nil
            }
            character = ns.rangeOfComposedCharacterSequence(at: stop - 1)
            if let run = listRun(containing: character.location) {
                guard run.range.location > 0 else {
                    return nil
                }
                let start = lineEnd(before: run.range.location)
                return MarkdownEdit(range: NSRange(location: start, length: stop - start), replacement: "", selection: NSRange(location: start, length: 0))
            }
        } else {
            var index = stop
            if let run = inlineRun(startingAt: index) {
                index = NSMaxRange(run)
            }
            guard index < ns.length else {
                return nil
            }
            if let item = item(onLineOf: stop), index == NSMaxRange(item.contentRange),
               let next = self.item(onLineOf: NSMaxRange(item.lineRange)), next.lineRange.location == NSMaxRange(item.lineRange) {
                let joined = NSRange(location: index, length: next.contentRange.location - index)
                return MarkdownEdit(range: joined, replacement: "", selection: NSRange(location: stop, length: 0))
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
    /// a span's end the break goes after the closing marker. A selection is replaced first, by a
    /// plain line break.
    ///
    /// In a list item with text, the new line starts with the same indentation and `- `, or
    /// `- [ ] ` for a task (always unchecked), put before any markers opened again. With the caret
    /// at the start of the text, or before or inside the marker, an empty item goes in above and
    /// the item moves down, caret at the start of its text. In an empty item (only whitespace)
    /// there's no line break: a nested item outdents, and a top-level one's line is emptied.
    public func lineBreak(at selection: NSRange) -> MarkdownEdit {
        let selection = clamped(selection)
        guard selection.length == 0 else {
            return replacement(of: selection, with: "\n")
        }
        let caret = selection.location
        guard let item = item(onLineOf: caret) else {
            return lineBreakEdit(at: caret, terminator: "\n").edit
        }
        let content = ns.substring(with: item.contentRange)
        if content.allSatisfy({ $0 == " " || $0 == "\t" }) {
            if item.level > 0, let outdent = MarkdownLists.apply(.outdent, to: text, selection: selection) {
                return outdent
            }
            let line = NSRange(location: item.lineRange.location, length: NSMaxRange(item.contentRange) - item.lineRange.location)
            return MarkdownEdit(range: line, replacement: "", selection: NSRange(location: line.location, length: 0))
        }
        let prefix = ns.substring(with: item.indentRange) + (item.isTask ? "- [ ] " : "- ")
        if caret <= item.contentRange.location {
            let above = prefix + "\n"
            let textStart = item.contentRange.location + (above as NSString).length
            return MarkdownEdit(range: NSRange(location: item.lineRange.location, length: 0), replacement: above, selection: NSRange(location: textStart, length: 0))
        }
        return lineBreakEdit(at: caret, terminator: "\n", prefix: prefix).edit
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
    /// start their content (after their markers; the edit's caret is before them). `prefix` starts
    /// the new line, right after the break: a list item's marker.
    private func lineBreakEdit(at caret: Int, terminator: String, prefix: String = "") -> (edit: MarkdownEdit, contentStart: Int) {
        let lineBreak = terminator + prefix
        let breakLength = (lineBreak as NSString).length
        var position = clamped(caret)
        let plain = { (at: Int) in
            (MarkdownEdit(range: NSRange(location: at, length: 0), replacement: lineBreak, selection: NSRange(location: at + breakLength, length: 0)), at + breakLength)
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
        let head = closers + before + lineBreak + after
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

    /// The last inline run starting at or before `position`.
    private func lastInlineRun(startingAtOrBefore position: Int) -> NSRange? {
        let index = Self.count(of: inlineRuns, startingAtOrBefore: position, location: \.location)
        return index > 0 ? inlineRuns[index - 1] : nil
    }

    private func inlineRun(startingAt position: Int) -> NSRange? {
        lastInlineRun(startingAtOrBefore: position).flatMap { $0.location == position ? $0 : nil }
    }

    /// The last list run starting at or before `position`.
    private func lastListRun(startingAtOrBefore position: Int) -> ListRun? {
        let index = Self.count(of: listRuns, startingAtOrBefore: position, location: \.range.location)
        return index > 0 ? listRuns[index - 1] : nil
    }

    /// The list run `position` is in or at either end of.
    private func listRun(touching position: Int) -> ListRun? {
        lastListRun(startingAtOrBefore: position).flatMap { position <= NSMaxRange($0.range) ? $0 : nil }
    }

    /// The list run holding the character at `position`.
    private func listRun(containing position: Int) -> ListRun? {
        lastListRun(startingAtOrBefore: position).flatMap { position < NSMaxRange($0.range) ? $0 : nil }
    }

    /// How many of `elements` (sorted by location) start at or before `position`.
    private static func count<Element>(of elements: [Element], startingAtOrBefore position: Int, location: (Element) -> Int) -> Int {
        var low = 0
        var high = elements.count
        while low < high {
            let middle = (low + high) / 2
            if location(elements[middle]) <= position {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// The end of the line before the one starting at `lineStart`, before its line break.
    private func lineEnd(before lineStart: Int) -> Int {
        var end = lineStart - 1
        if end > 0, ns.character(at: end) == 0x0A, ns.character(at: end - 1) == 0x0D {
            end -= 1
        }
        return end
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
