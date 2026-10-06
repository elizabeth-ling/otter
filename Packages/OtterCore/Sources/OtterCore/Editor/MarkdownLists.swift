import Foundation

/// A `- ` bullet or a `- [ ]` / `- [x]` task: one line of the editor's text (ADR-017, UX_SPEC §1
/// "Lists and tasks"). Ranges are UTF-16, as in `MarkdownSpan`.
public struct MarkdownListItem: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case bullet
        case task(checked: Bool)
    }

    /// The whole line, with its line break.
    public var lineRange: NSRange
    /// The indentation, `- ` and, for a task, `[ ] `. Spaces after it belong to the text.
    public var prefixRange: NSRange
    /// From the start of the item's text to the end of the line, without the line break.
    public var contentRange: NSRange
    /// The spaces and tabs before the `-`.
    public var indentRange: NSRange
    /// The indentation's width: a space is one column, and a tab moves to the next multiple of 4
    /// (so a leading tab is 4 columns, as in CommonMark).
    public var indentColumns: Int
    /// 0 for a top-level item, otherwise one more than its parent's.
    public var level: Int
    public var kind: Kind
    /// A task's `[ ]`, `[x]` or `[X]`.
    public var checkboxRange: NSRange?

    public init(
        lineRange: NSRange,
        prefixRange: NSRange,
        contentRange: NSRange,
        indentRange: NSRange,
        indentColumns: Int,
        level: Int,
        kind: Kind,
        checkboxRange: NSRange?
    ) {
        self.lineRange = lineRange
        self.prefixRange = prefixRange
        self.contentRange = contentRange
        self.indentRange = indentRange
        self.indentColumns = indentColumns
        self.level = level
        self.kind = kind
        self.checkboxRange = checkboxRange
    }

    /// The marker without the indentation: `- `, or `- [ ] ` for a task.
    public var markerRange: NSRange {
        NSRange(location: NSMaxRange(indentRange), length: NSMaxRange(prefixRange) - NSMaxRange(indentRange))
    }

    public var isTask: Bool {
        if case .task = kind {
            return true
        }
        return false
    }

    public var isChecked: Bool {
        kind == .task(checked: true)
    }

    /// Whether `selection` touches the item's line: a caret anywhere on it, or a selection with
    /// a character on it. A selection that ends just after the line break before it doesn't.
    /// These are the lines `Tab` and `⇧Tab` act on.
    public func isOnLine(touchedBy selection: NSRange) -> Bool {
        guard selection.location <= NSMaxRange(contentRange) else {
            return false
        }
        if selection.length == 0 {
            return selection.location >= lineRange.location
        }
        return NSMaxRange(selection) > lineRange.location
    }

    /// Whether `selection` shows the item's raw marker (ADR-018): a caret in its prefix, before
    /// the start of its text, or a selection with a character of the marker. A caret at the start
    /// of the text, where typing goes, doesn't, so the bullet or box stays drawn there.
    public func revealsMarker(for selection: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= prefixRange.location && selection.location < NSMaxRange(prefixRange)
        }
        let marker = markerRange
        return selection.location < NSMaxRange(marker) && NSMaxRange(selection) > marker.location
    }
}

/// What `⌘L`, `⇧⌘8`, `Tab` and `⇧Tab` do to the list items in a selection (UX_SPEC §2).
public enum ListCommand: Sendable {
    /// `⌘L`: make a task, or check or uncheck one.
    case toggleTask
    /// `⇧⌘8`: add or remove `- `.
    case toggleBullet
    /// `Tab`: nest under the item above.
    case indent
    /// `⇧Tab`: back to the parent's indentation.
    case outdent
}

/// Finds the `- ` bullets and `- [ ]` tasks the panel's editor shows as a list, and makes the
/// edits its list keys ask for (ADR-017). It only reads the text; drawing and hiding are the
/// editor's job, and the caret and line-break rules are `HiddenMarkerEditing`'s.
///
/// Outside a fenced code block, a line is an item when it has optional indentation (spaces and
/// tabs), then `-`, then one space or tab. `[ ] `, `[x] ` or `[X] ` straight after makes it a
/// task (the space after `]` is needed, as in GFM). A rule (`---`, `- - -`) isn't an item, nor
/// are `*`, `+` and numbered lists or lists in a quote.
///
/// Consecutive item lines form a list, and any other line ends it. An item's level is one more
/// than the level of the nearest item above it in the same list with less indentation, or 0.
public enum MarkdownLists {
    /// Every item, in order.
    public static func items(in text: String) -> [MarkdownListItem] {
        let characters = Self.characters(of: text)
        var items: [MarkdownListItem] = []
        // The chain of possible parents: strictly increasing indentation.
        var parents: [(columns: Int, level: Int)] = []
        MarkdownLines(characters: characters).forEach { line in
            guard line.isProse, var item = item(on: line, in: characters) else {
                parents.removeAll()
                return
            }
            while let last = parents.last, last.columns >= item.indentColumns {
                parents.removeLast()
            }
            item.level = parents.last.map { $0.level + 1 } ?? 0
            parents.append((item.indentColumns, item.level))
            items.append(item)
        }
        return items
    }

    /// Each item's hidden run: its whole prefix, or only its indentation (if any) when `selection`
    /// touches its line, which shows the marker raw.
    public static func hiddenRuns(of items: [MarkdownListItem], selection: NSRange?) -> [NSRange] {
        items.compactMap { item in
            if let selection, item.isOnLine(touchedBy: selection) {
                return item.indentRange.length > 0 ? item.indentRange : nil
            }
            return item.prefixRange
        }
    }

    /// The edit a list key makes, as one replacement with the caret or selection kept where it
    /// was in the text. `nil` where the editor should beep.
    ///
    /// - `toggleTask` (`⌘L`) works on the lines the selection touches, blank lines skipped
    ///   (unless it's only the caret's line): if any isn't a task, those become unchecked tasks
    ///   (`- [ ] ` after the indentation, or `[ ] ` after a bullet's `- `); otherwise, if any task
    ///   is unchecked, all are checked; otherwise all are unchecked.
    /// - `toggleBullet` (`⇧⌘8`): if every line is an item, their markers come off (task markers
    ///   too), keeping the indentation; otherwise each plain line gets `- ` after its indentation.
    /// - `indent` (`Tab`) puts a tab before each item on the lines the selection touches. `nil`
    ///   unless the line above the first is an item at the same level or deeper.
    /// - `outdent` (`⇧Tab`) cuts each nested item's indentation back to its parent's. `nil` if
    ///   they're all top-level, or there are none.
    public static func apply(_ command: ListCommand, to text: String, selection: NSRange) -> MarkdownEdit? {
        let ns = text as NSString
        guard selection.location >= 0, selection.length >= 0, NSMaxRange(selection) <= ns.length else {
            return nil
        }
        let characters = Self.characters(of: text)
        let items = items(in: text)
        let replacements: [Replacement]
        switch command {
        case .toggleTask:
            guard let lines = targetLines(touching: selection, in: characters) else {
                return nil
            }
            replacements = toggleTask(lines.map { line in (line, items.first { $0.lineRange.location == line.start }) }, in: characters)
        case .toggleBullet:
            guard let lines = targetLines(touching: selection, in: characters) else {
                return nil
            }
            replacements = toggleBullet(lines.map { line in (line, items.first { $0.lineRange.location == line.start }) }, in: characters)
        case .indent:
            replacements = indent(items, touchedBy: selection)
        case .outdent:
            replacements = outdent(items, touchedBy: selection, in: ns)
        }
        return edit(applying: replacements, in: ns, selection: selection)
    }

    /// Ticks or unticks a task's box (a click on it): `[x]` when checking, `[ ]` when unchecking,
    /// `[X]` included. The selection stays as it is. `nil` for a bullet.
    public static func toggleCheckbox(_ item: MarkdownListItem, in text: String, selection: NSRange) -> MarkdownEdit? {
        guard let box = item.checkboxRange, NSMaxRange(box) <= (text as NSString).length else {
            return nil
        }
        return MarkdownEdit(range: box, replacement: item.isChecked ? "[ ]" : "[x]", selection: selection)
    }

    // MARK: - Parsing

    private static func characters(of text: String) -> [unichar] {
        let ns = text as NSString
        var characters = [unichar](repeating: 0, count: ns.length)
        ns.getCharacters(&characters, range: NSRange(location: 0, length: ns.length))
        return characters
    }

    /// The item on `line`, with level 0 for now.
    private static func item(on line: MarkdownLines.Line, in characters: [unichar]) -> MarkdownListItem? {
        var index = line.start
        var columns = 0
        while index < line.end, isSpaceOrTab(characters[index]) {
            columns = characters[index] == tab ? columns + 4 - columns % 4 : columns + 1
            index += 1
        }
        let dash = index
        guard dash + 1 < line.end, characters[dash] == hyphen, isSpaceOrTab(characters[dash + 1]) else {
            return nil
        }
        // A rule: three or more `-` and nothing else but spaces and tabs.
        let rest = characters[dash..<line.end]
        if rest.allSatisfy({ $0 == hyphen || isSpaceOrTab($0) }), rest.filter({ $0 == hyphen }).count >= 3 {
            return nil
        }
        var contentStart = dash + 2
        var kind = MarkdownListItem.Kind.bullet
        var checkbox: NSRange?
        if contentStart + 3 < line.end, characters[contentStart] == openBracket, characters[contentStart + 2] == closeBracket,
           [space, lowercaseX, uppercaseX].contains(characters[contentStart + 1]), isSpaceOrTab(characters[contentStart + 3]) {
            kind = .task(checked: characters[contentStart + 1] != space)
            checkbox = NSRange(location: contentStart, length: 3)
            contentStart += 4
        }
        return MarkdownListItem(
            lineRange: NSRange(location: line.start, length: line.next - line.start),
            prefixRange: NSRange(location: line.start, length: contentStart - line.start),
            contentRange: NSRange(location: contentStart, length: line.end - contentStart),
            indentRange: NSRange(location: line.start, length: dash - line.start),
            indentColumns: columns,
            level: 0,
            kind: kind,
            checkboxRange: checkbox
        )
    }

    // MARK: - Commands

    private typealias Replacement = (range: NSRange, string: String)
    private typealias TargetLine = (line: MarkdownLines.Line, item: MarkdownListItem?)

    /// The lines `selection` touches that aren't blank, or the caret's line if that's all there
    /// is. `nil` for a selection of only blank lines.
    private static func targetLines(touching selection: NSRange, in characters: [unichar]) -> [MarkdownLines.Line]? {
        var touched: [MarkdownLines.Line] = []
        MarkdownLines(characters: characters).forEach { line in
            let touches = selection.length == 0
                ? line.start <= selection.location && selection.location <= line.end
                : selection.location <= line.end && NSMaxRange(selection) > line.start
            if touches {
                touched.append(line)
            }
        }
        let lines = touched.filter { line in !characters[line.start..<line.end].allSatisfy(isSpaceOrTab) }
        if !lines.isEmpty {
            return lines
        }
        return touched.count == 1 ? touched : nil
    }

    private static func toggleTask(_ lines: [TargetLine], in characters: [unichar]) -> [Replacement] {
        if lines.contains(where: { $0.item?.isTask != true }) {
            return lines.compactMap { line, item in
                switch item?.kind {
                case nil:
                    return (NSRange(location: indentEnd(of: line, in: characters), length: 0), "- [ ] ")
                case .bullet?:
                    return (NSRange(location: item!.contentRange.location, length: 0), "[ ] ")
                case .task?:
                    return nil
                }
            }
        }
        let check = lines.contains { $0.item?.isChecked == false }
        return lines.compactMap { _, item in
            guard let item, let box = item.checkboxRange, item.isChecked != check else {
                return nil
            }
            return (box, check ? "[x]" : "[ ]")
        }
    }

    private static func toggleBullet(_ lines: [TargetLine], in characters: [unichar]) -> [Replacement] {
        if lines.allSatisfy({ $0.item != nil }) {
            return lines.map { ($0.item!.markerRange, "") }
        }
        return lines.compactMap { line, item in
            item == nil ? (NSRange(location: indentEnd(of: line, in: characters), length: 0), "- ") : nil
        }
    }

    private static func indent(_ items: [MarkdownListItem], touchedBy selection: NSRange) -> [Replacement] {
        guard let first = items.firstIndex(where: { $0.isOnLine(touchedBy: selection) }), first > 0 else {
            return []
        }
        let above = items[first - 1]
        guard NSMaxRange(above.lineRange) == items[first].lineRange.location, above.level >= items[first].level else {
            return []
        }
        return items[first...].filter { $0.isOnLine(touchedBy: selection) }.map { (NSRange(location: $0.lineRange.location, length: 0), "\t") }
    }

    private static func outdent(_ items: [MarkdownListItem], touchedBy selection: NSRange, in ns: NSString) -> [Replacement] {
        items.indices.compactMap { index in
            let item = items[index]
            guard item.level > 0, item.isOnLine(touchedBy: selection), let parent = parent(of: index, in: items) else {
                return nil
            }
            return (item.indentRange, ns.substring(with: parent.indentRange))
        }
    }

    /// The nearest item above in the same list with less indentation.
    private static func parent(of index: Int, in items: [MarkdownListItem]) -> MarkdownListItem? {
        var candidate = index - 1
        while candidate >= 0, NSMaxRange(items[candidate].lineRange) == items[candidate + 1].lineRange.location {
            if items[candidate].indentColumns < items[index].indentColumns {
                return items[candidate]
            }
            candidate -= 1
        }
        return nil
    }

    private static func indentEnd(of line: MarkdownLines.Line, in characters: [unichar]) -> Int {
        var index = line.start
        while index < line.end, isSpaceOrTab(characters[index]) {
            index += 1
        }
        return index
    }

    /// The replacements, in order and apart, as one edit over them and the text between, with
    /// `selection` moved along. A caret at an insertion goes after it, staying with its text; a
    /// selection keeps what's inserted at its start, so selected lines stay whole.
    private static func edit(applying replacements: [Replacement], in ns: NSString, selection: NSRange) -> MarkdownEdit? {
        guard let first = replacements.first, let last = replacements.last else {
            return nil
        }
        let start = first.range.location
        let end = NSMaxRange(last.range)
        var replacement = ""
        var cursor = start
        for piece in replacements {
            replacement += ns.substring(with: NSRange(location: cursor, length: piece.range.location - cursor))
            replacement += piece.string
            cursor = NSMaxRange(piece.range)
        }
        func moved(_ position: Int, stickingRight: Bool) -> Int {
            var offset = 0
            for piece in replacements {
                let length = (piece.string as NSString).length
                if piece.range.length == 0 {
                    if piece.range.location < position || (piece.range.location == position && stickingRight) {
                        offset += length
                    }
                } else if NSMaxRange(piece.range) <= position {
                    offset += length - piece.range.length
                } else if piece.range.location < position {
                    // Inside a replaced range: as far in as the new text goes.
                    let into = position - piece.range.location
                    offset += min(into, length) - into
                }
            }
            return position + offset
        }
        let newStart = moved(selection.location, stickingRight: selection.length == 0)
        let newEnd = selection.length == 0 ? newStart : max(newStart, moved(NSMaxRange(selection), stickingRight: false))
        return MarkdownEdit(
            range: NSRange(location: start, length: end - start),
            replacement: replacement,
            selection: NSRange(location: newStart, length: newEnd - newStart)
        )
    }
}

private func isSpaceOrTab(_ unit: unichar) -> Bool {
    unit == space || unit == tab
}

private let tab: unichar = 0x09
private let space: unichar = 0x20
private let hyphen: unichar = 0x2D
private let uppercaseX: unichar = 0x58
private let openBracket: unichar = 0x5B
private let closeBracket: unichar = 0x5D
private let lowercaseX: unichar = 0x78
