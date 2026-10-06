import AppKit
import OtterCore
import os

/// Styles inline Markdown in the panel's editor and hides the markers of complete spans (ADR-016,
/// UX_SPEC §1 "Inline Markdown styling"). It's the text storage's delegate: after each edit it
/// parses the whole note with `MarkdownStyling` and re-attributes only the lines whose styling
/// changed, so layout is invalidated locally.
///
/// It only sets attributes: the characters, the undo stack and the draft never see it. A hidden
/// marker gets a near-zero font and a clear colour, which needs no layout-manager code and works
/// the same on TextKit 1 and 2 (the spike found no visible gap, and caret and line heights unchanged).
///
/// `- ` bullets and `- [ ]` tasks (ADR-017, ADR-018) are indented by level with a hanging indent.
/// Their indentation is always hidden. While the selection is in an item's marker, the marker
/// shows raw and dim; otherwise it's hidden too and `EditorTextView` draws a bullet or circle.
/// Item paragraphs have no tab stops and a 0.001 pt tab interval, so hidden tabs take no space (the
/// T18 spike: default stops push the text up to 80 pt; this lines up within 0.04 pt on TextKit 1
/// and 2; an interval of 0 breaks TextKit 2's layout). A tab inside an item's text takes none either.
@MainActor
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    /// The editor's font. Bold and italic are its faces; changing it restyles everything.
    var font: NSFont {
        didSet {
            fonts.removeAll()
            markerWidths.removeAll()
            paragraphStyles.removeAll()
            restyleAll()
        }
    }

    /// What unstyled text, and text typed before it's restyled, looks like.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor]
    }

    /// Asked before restyling: nothing restyles while an input method is composing.
    weak var textView: NSTextView?

    private weak var textStorage: NSTextStorage?
    /// The spans of the text as last parsed.
    private var spans: [MarkdownSpan] = []
    /// The selection that reveals a link (`⌘K` selected its URL), or `nil`.
    private var revealSelection: NSRange?
    /// Each line's styling as applied, by the line's start.
    private var appliedLines: [Int: LineStyle] = [:]
    /// Edits were skipped (while composing), so `spans` and `appliedLines` are out of date.
    private var isStale = true
    /// Set while restyling outside an edit, whose attribute-only `processEditing` it ignores.
    private var isApplying = false
    private var fonts: [Traits: NSFont] = [:]
    /// The list items of the text as last parsed.
    private var items: [MarkdownListItem] = []
    /// The editor's selection: items whose marker it's in show their raw marker.
    private var itemSelection = NSRange(location: 0, length: 0)
    private var markerWidths: [String: CGFloat] = [:]
    private var paragraphStyles: [ListStyle: NSParagraphStyle] = [:]

    init(font: NSFont) {
        self.font = font
    }

    func attach(to textStorage: NSTextStorage) {
        self.textStorage = textStorage
        textStorage.delegate = self
        restyleAll()
    }

    /// The text's spans, parsed again if edits were skipped.
    func currentSpans() -> [MarkdownSpan] {
        if isStale, let textStorage {
            spans = MarkdownStyling.spans(in: textStorage.string)
        }
        return spans
    }

    /// The text's list items, parsed again if edits were skipped.
    func currentItems() -> [MarkdownListItem] {
        if isStale, let textStorage {
            items = MarkdownLists.items(in: textStorage.string)
        }
        return items
    }

    /// Whether `item` shows its raw marker: the selection is in it.
    func isRevealed(_ item: MarkdownListItem) -> Bool {
        item.revealsMarker(for: itemSelection)
    }

    /// Where an item at `level` starts, from the text container's edge: one step per level. The
    /// step is the indent from plain text to a bullet's text, 1.34 em, as in Obsidian (ADR-018).
    func levelStart(level: Int) -> CGFloat {
        CGFloat(level) * Self.bulletTextOffset * font.pointSize
    }

    /// Where an item's text starts: 1.34 em past its level's start for a bullet, 1.75 em for a
    /// task, measured from Obsidian (ADR-018).
    func textStart(of item: MarkdownListItem) -> CGFloat {
        textStart(level: item.level, isTask: item.isTask)
    }

    private func textStart(level: Int, isTask: Bool) -> CGFloat {
        levelStart(level: level) + (isTask ? Self.taskTextOffset : Self.bulletTextOffset) * font.pointSize
    }

    private static let bulletTextOffset: CGFloat = 1.34
    private static let taskTextOffset: CGFloat = 1.75

    /// `string`'s width in the editor's font, tabs taking no space as in an item.
    func width(of string: String) -> CGFloat {
        if let cached = markerWidths[string] {
            return cached
        }
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .paragraphStyle: Self.tablessParagraph])
        let width = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
        markerWidths[string] = width
        return width
    }

    /// Moves the list reveal to the items whose marker `selection` is in, re-attributing only the
    /// items that start or stop showing their marker. Not an edit: no undo step. Returns whether
    /// any line changed, so the editor redraws its bullets and circles.
    @discardableResult
    func revealItems(on selection: NSRange) -> Bool {
        let old = itemSelection
        itemSelection = selection
        guard let textStorage, !isComposing, !isStale, old != selection, !items.isEmpty else {
            return false
        }
        let changed = items.filter { $0.revealsMarker(for: old) != $0.revealsMarker(for: selection) }
        guard !changed.isEmpty else {
            return false
        }
        os_signpost(.begin, log: Signpost.log, name: Signpost.restyle)
        let ns = textStorage.string as NSString
        isApplying = true
        textStorage.beginEditing()
        for item in changed where NSMaxRange(item.lineRange) <= ns.length {
            let line = ns.lineRange(for: NSRange(location: item.lineRange.location, length: 0))
            let lineSpans = spans(startingIn: line)
            let lineRuns = MarkdownStyling.hiddenRuns(of: Array(lineSpans), revealing: revealSelection)
            let style = lineStyle(for: line, spans: lineSpans, hiddenRuns: lineRuns, item: item, in: ns)
            apply(style, to: line, in: textStorage)
            appliedLines[line.location] = style
        }
        textStorage.endEditing()
        isApplying = false
        os_signpost(.end, log: Signpost.log, name: Signpost.restyle)
        return true
    }

    /// Restyles the whole text: after a draft is restored, the font changes or composition ends.
    func restyleAll() {
        guard let textStorage, !isComposing else {
            return
        }
        os_signpost(.begin, log: Signpost.log, name: Signpost.restyle)
        isApplying = true
        textStorage.beginEditing()
        restyle(textStorage, editedRange: NSRange(location: 0, length: textStorage.length), changeInLength: 0, everything: true)
        textStorage.endEditing()
        isApplying = false
        os_signpost(.end, log: Signpost.log, name: Signpost.restyle)
    }

    /// Shows a link raw while `selection` is inside its URL, and hides the one shown before.
    func reveal(_ selection: NSRange?) {
        guard let textStorage, !isComposing else {
            return
        }
        let spans = currentSpans()
        let old = revealSelection.flatMap { MarkdownStyling.link(in: spans, withDestinationHolding: $0) }
        let new = selection.flatMap { MarkdownStyling.link(in: spans, withDestinationHolding: $0) }
        revealSelection = new == nil ? nil : selection
        guard old != new else {
            return
        }
        let ns = textStorage.string as NSString
        let hiddenRuns = MarkdownStyling.hiddenRuns(of: spans, revealing: revealSelection)
        isApplying = true
        textStorage.beginEditing()
        for link in [old, new].compactMap({ $0 }) where NSMaxRange(link.range) <= ns.length {
            let line = ns.lineRange(for: NSRange(location: link.range.location, length: 0))
            let lineSpans = spans.filter { NSLocationInRange($0.range.location, line) }
            let lineRuns = hiddenRuns.filter { NSLocationInRange($0.location, line) }
            let style = lineStyle(for: line, spans: lineSpans, hiddenRuns: lineRuns, item: item(startingAt: line.location), in: ns)
            apply(style, to: line, in: textStorage)
            appliedLines[line.location] = style
        }
        textStorage.endEditing()
        isApplying = false
    }

    // MARK: NSTextStorageDelegate

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else {
            return
        }
        // Only the editor's own storage, on the main thread, has this delegate.
        MainActor.assumeIsolated {
            guard !isApplying, let textStorage = self.textStorage else {
                return
            }
            guard !isComposing else {
                isStale = true
                return
            }
            // Attributes may change here, not characters; the layout sees them with this edit.
            os_signpost(.begin, log: Signpost.log, name: Signpost.restyle)
            if let selection = revealSelection, selection.location >= NSMaxRange(editedRange) - delta {
                revealSelection = NSRange(location: selection.location + delta, length: selection.length)
            }
            // Until the editor sets the selection after this edit.
            if itemSelection.location >= NSMaxRange(editedRange) - delta {
                itemSelection.location += delta
            }
            restyle(textStorage, editedRange: editedRange, changeInLength: delta, everything: isStale)
            os_signpost(.end, log: Signpost.log, name: Signpost.restyle)
        }
    }

    // MARK: - Private

    private var isComposing: Bool {
        textView?.hasMarkedText() ?? false
    }

    /// Parses the text, then applies the styling of every line in `editedRange` (new coordinates)
    /// and of every other line whose styling differs from what was applied (or all, if `everything`).
    private func restyle(_ textStorage: NSTextStorage, editedRange: NSRange, changeInLength delta: Int, everything: Bool) {
        let ns = textStorage.string as NSString
        spans = MarkdownStyling.spans(in: ns as String)
        items = MarkdownLists.items(in: ns as String)
        isStale = false
        if let selection = revealSelection, MarkdownStyling.link(in: spans, withDestinationHolding: selection) == nil {
            revealSelection = nil
        }
        let selectionStart = min(itemSelection.location, ns.length)
        itemSelection = NSRange(location: selectionStart, length: min(itemSelection.length, ns.length - selectionStart))
        let hiddenRuns = MarkdownStyling.hiddenRuns(of: spans, revealing: revealSelection)
        let editedEnd = NSMaxRange(editedRange)

        var lines: [Int: LineStyle] = [:]
        var spanIndex = 0
        var runIndex = 0
        var itemIndex = 0
        var start = 0
        repeat {
            let line = ns.lineRange(for: NSRange(location: start, length: 0))
            // Spans and runs never cross a line break, so each belongs to the line it starts in.
            let spanStart = spanIndex
            while spanIndex < spans.count, spans[spanIndex].range.location < NSMaxRange(line) {
                spanIndex += 1
            }
            let runStart = runIndex
            while runIndex < hiddenRuns.count, hiddenRuns[runIndex].location < NSMaxRange(line) {
                runIndex += 1
            }
            while itemIndex < items.count, items[itemIndex].lineRange.location < line.location {
                itemIndex += 1
            }
            let item = itemIndex < items.count && items[itemIndex].lineRange.location == line.location ? items[itemIndex] : nil
            let style = lineStyle(for: line, spans: spans[spanStart..<spanIndex], hiddenRuns: hiddenRuns[runStart..<runIndex], item: item, in: ns)
            lines[line.location] = style

            let isEdited = line.location <= editedEnd && editedRange.location <= NSMaxRange(line)
            let previous: LineStyle?
            if line.location >= editedEnd {
                previous = appliedLines[line.location - delta]
            } else {
                previous = line.location < editedRange.location ? appliedLines[line.location] : nil
            }
            if everything || isEdited || previous != style {
                apply(style, to: line, in: textStorage)
            }
            start = NSMaxRange(line)
        } while start < ns.length
        appliedLines = lines
    }

    /// One line's attribute runs, relative to its start, and its list layout if it's an item.
    private func lineStyle(
        for line: NSRange,
        spans: some Collection<MarkdownSpan>,
        hiddenRuns: some Collection<NSRange>,
        item: MarkdownListItem?,
        in ns: NSString
    ) -> LineStyle {
        guard !spans.isEmpty || item != nil else {
            return LineStyle(runs: [], toolTips: [], list: nil)
        }
        var traits = [Traits](repeating: [], count: line.length)
        func mark(_ range: NSRange, _ trait: Traits) {
            let lower = max(range.location - line.location, 0)
            let upper = min(NSMaxRange(range) - line.location, line.length)
            guard lower < upper else {
                return
            }
            for index in lower..<upper {
                traits[index].insert(trait)
            }
        }
        var toolTips: [LineStyle.ToolTip] = []
        let revealed = revealSelection.flatMap { MarkdownStyling.link(in: Array(spans), withDestinationHolding: $0) }
        for span in spans {
            switch span.kind {
            case .bold: mark(span.contentRange, .bold)
            case .italic: mark(span.contentRange, .italic)
            case .strikethrough: mark(span.contentRange, .strikethrough)
            case .code: mark(span.contentRange, .code)
            case .link:
                mark(span.contentRange, .link)
                if let destination = span.destinationRange {
                    if span == revealed {
                        mark(destination, .url)
                    }
                    let relative = NSRange(location: span.contentRange.location - line.location, length: span.contentRange.length)
                    toolTips.append(LineStyle.ToolTip(range: relative, text: ns.substring(with: destination)))
                }
            }
        }
        for run in hiddenRuns {
            mark(run, .hidden)
        }
        var list: ListStyle?
        if let item {
            // Indentation is always hidden; the marker unless the selection is in it.
            let revealed = isRevealed(item)
            mark(revealed ? item.indentRange : item.prefixRange, .hidden)
            if revealed {
                mark(item.markerRange, .marker)
            }
            if item.isChecked {
                mark(item.contentRange, .checked)
            }
            list = ListStyle(level: item.level, isTask: item.isTask, revealedMarker: revealed ? ns.substring(with: item.markerRange) : nil)
        }

        var runs: [LineStyle.Run] = []
        var index = 0
        while index < traits.count {
            let current = traits[index]
            var end = index + 1
            while end < traits.count, traits[end] == current {
                end += 1
            }
            if !current.isEmpty {
                runs.append(LineStyle.Run(range: NSRange(location: index, length: end - index), traits: current))
            }
            index = end
        }
        return LineStyle(runs: runs, toolTips: toolTips, list: list)
    }

    private func apply(_ style: LineStyle, to line: NSRange, in textStorage: NSTextStorage) {
        // The base first, so text typed after a span doesn't keep its style or its hiding.
        textStorage.setAttributes(baseAttributes, range: line)
        for run in style.runs {
            let range = NSRange(location: line.location + run.range.location, length: run.range.length)
            textStorage.setAttributes(attributes(for: run.traits), range: range)
        }
        for toolTip in style.toolTips {
            let range = NSRange(location: line.location + toolTip.range.location, length: toolTip.range.length)
            textStorage.addAttribute(.toolTip, value: toolTip.text, range: range)
        }
        if let list = style.list {
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle(for: list), range: line)
        }
    }

    /// An item's paragraph: wrapped lines hang at its text start. A revealed marker ends at the
    /// text start if it fits after the level's start (`- `); otherwise (`- [ ] `) it starts there
    /// and pushes the first line's text right, as in Obsidian.
    private func paragraphStyle(for list: ListStyle) -> NSParagraphStyle {
        if let cached = paragraphStyles[list] {
            return cached
        }
        let style = Self.tablessParagraph.mutableCopy() as! NSMutableParagraphStyle
        let textStart = textStart(level: list.level, isTask: list.isTask)
        style.headIndent = textStart
        let markerWidth = list.revealedMarker.map { width(of: $0) } ?? 0
        style.firstLineHeadIndent = max(textStart - markerWidth, levelStart(level: list.level))
        paragraphStyles[list] = style
        return style
    }

    /// The spans that start in `line`, found by binary search (`spans` is sorted by start).
    private func spans(startingIn line: NSRange) -> ArraySlice<MarkdownSpan> {
        var low = 0
        var high = spans.count
        while low < high {
            let middle = (low + high) / 2
            if spans[middle].range.location < line.location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var end = low
        while end < spans.count, spans[end].range.location < NSMaxRange(line) {
            end += 1
        }
        return spans[low..<end]
    }

    /// The item whose line starts at `location`.
    private func item(startingAt location: Int) -> MarkdownListItem? {
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].lineRange.location < location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < items.count && items[low].lineRange.location == location ? items[low] : nil
    }

    private func attributes(for traits: Traits) -> [NSAttributedString.Key: Any] {
        if traits.contains(.hidden) {
            // Takes (almost) no space and draws nothing; no underline, strikethrough or background.
            return [.font: Self.hiddenFont, .foregroundColor: NSColor.clear]
        }
        var attributes: [NSAttributedString.Key: Any] = [.font: font(for: traits), .foregroundColor: NSColor.labelColor]
        if traits.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if traits.contains(.code) {
            attributes[.backgroundColor] = NSColor.quaternarySystemFill
        }
        if traits.contains(.link) {
            attributes[.foregroundColor] = NSColor.linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if traits.contains(.url) {
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        }
        if traits.contains(.marker) {
            attributes[.foregroundColor] = NSColor.tertiaryLabelColor
        }
        if traits.contains(.checked) {
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    /// The editor's font with the traits' faces; code in the monospaced system font at the same
    /// size, unless the editor's font is monospaced already.
    private func font(for traits: Traits) -> NSFont {
        let key = traits.intersection([.bold, .italic, .code])
        if let cached = fonts[key] {
            return cached
        }
        var result = key.contains(.code) && !font.isFixedPitch ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
        if key.contains(.bold) {
            result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask)
        }
        if key.contains(.italic) {
            result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask)
        }
        fonts[key] = result
        return result
    }

    private static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    /// No tab stops and a 0.001 pt interval: a tab takes (almost) no space, so hidden indentation
    /// doesn't push an item's text or its revealed marker (T18 spike).
    private static let tablessParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = 0.001
        return style
    }()

    private struct Traits: OptionSet, Hashable {
        let rawValue: UInt16

        static let bold = Traits(rawValue: 1 << 0)
        static let italic = Traits(rawValue: 1 << 1)
        static let strikethrough = Traits(rawValue: 1 << 2)
        static let code = Traits(rawValue: 1 << 3)
        static let link = Traits(rawValue: 1 << 4)
        /// A revealed link's URL.
        static let url = Traits(rawValue: 1 << 5)
        static let hidden = Traits(rawValue: 1 << 6)
        /// A list marker shown raw, while the selection is in it.
        static let marker = Traits(rawValue: 1 << 7)
        /// A checked task's text.
        static let checked = Traits(rawValue: 1 << 8)
    }

    /// An item line's layout: its level and kind, and its raw marker if it's revealed.
    private struct ListStyle: Hashable {
        let level: Int
        let isTask: Bool
        let revealedMarker: String?
    }

    /// One line's styling, relative to the line's start, compared to skip unchanged lines.
    private struct LineStyle: Equatable {
        struct Run: Equatable {
            let range: NSRange
            let traits: Traits
        }

        struct ToolTip: Equatable {
            let range: NSRange
            let text: String
        }

        let runs: [Run]
        let toolTips: [ToolTip]
        let list: ListStyle?
    }
}
