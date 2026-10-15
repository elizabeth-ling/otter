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
/// An item with no text yet (`- `) is all hidden characters, which TextKit 2 lays out 0 pt tall,
/// so item paragraphs have a minimum line height of one line of the editor's font.
///
/// `#` headings are bold and larger by level. Their `#`s show, dimmed, on a line the selection
/// touches, and hide on every other line, as in Obsidian. The caret is never in a hidden one, so
/// the caret and editing rules don't know about them. Fenced code blocks are in the monospaced
/// font, inset so `EditorTextView` can draw a block behind them. Their fences show, dimmed, while
/// the selection touches the block; otherwise they hide, each line kept as the block's padding.
///
/// An inline code span's hidden backticks take the room of the padding of the box drawn around its
/// text, so the box doesn't reach past the text container's edge or into the text beside it.
@MainActor
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    /// The editor's font. Bold and italic are its faces; changing it restyles everything.
    var font: NSFont {
        didSet {
            fonts.removeAll()
            markerWidths.removeAll()
            measuredLine = nil
            resetParagraphStyles()
        }
    }

    /// What unstyled text, and text typed before it's restyled, looks like.
    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: baseParagraph]
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
    private var fonts: [FontKey: NSFont] = [:]
    /// The list items of the text as last parsed.
    private var items: [MarkdownListItem] = []
    /// The headings and code blocks of the text as last parsed.
    private var headings: [MarkdownHeading] = []
    private var codeBlocks: [MarkdownCodeBlock] = []
    /// The editor's selection: items whose marker it's in, headings on lines it touches and code
    /// blocks it touches show their raw marker or fences.
    private var markerSelection = NSRange(location: 0, length: 0)
    private var markerWidths: [String: CGFloat] = [:]
    private var paragraphStyles: [ListStyle: NSParagraphStyle] = [:]
    private var measuredLine: LineMetrics?
    private var codeParagraph: NSParagraphStyle?
    private var fenceParagraphs: [Bool: NSParagraphStyle] = [:]
    private var plainParagraph: NSParagraphStyle?

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

    /// The text's fenced code blocks, parsed again if edits were skipped.
    func currentCodeBlocks() -> [MarkdownCodeBlock] {
        if isStale, let textStorage {
            codeBlocks = MarkdownBlocks.codeBlocks(in: textStorage.string)
        }
        return codeBlocks
    }

    /// Whether `item` shows its raw marker: the selection is in it.
    func isRevealed(_ item: MarkdownListItem) -> Bool {
        item.revealsMarker(for: markerSelection)
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

    /// A line of the editor's font as TextKit 2 lays it out: its height, and its baseline from its top.
    struct LineMetrics {
        let height: CGFloat
        let baseline: CGFloat
    }

    /// One line of the editor's font, measured in a scratch TextKit 2 layout. An item with no text
    /// has no glyphs to take a baseline from, so its bullet or circle sits on this one.
    var lineMetrics: LineMetrics {
        if let measuredLine {
            return measuredLine
        }
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        layout.textContainer = NSTextContainer(size: CGSize(width: 1000, height: 1000))
        content.attributedString = NSAttributedString(string: "x", attributes: [.font: font, .paragraphStyle: Self.tablessParagraph])
        layout.ensureLayout(for: layout.documentRange)
        let metrics: LineMetrics
        if let fragment = layout.textLayoutFragment(for: layout.documentRange.location), let line = fragment.textLineFragments.first {
            metrics = LineMetrics(height: fragment.layoutFragmentFrame.height, baseline: line.typographicBounds.minY + line.glyphOrigin.y)
        } else {
            metrics = LineMetrics(height: ceil(font.ascender - font.descender + font.leading), baseline: ceil(font.ascender))
        }
        measuredLine = metrics
        return metrics
    }

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

    /// Moves the marker reveal to the items whose marker `selection` is in, the headings on lines
    /// it touches and the code blocks it touches, re-attributing only the lines that start or stop
    /// showing their marker or fences.
    /// Not an edit: no undo step. Returns whether any line changed, so the editor redraws its
    /// bullets and circles.
    @discardableResult
    func revealMarkers(on selection: NSRange) -> Bool {
        let old = markerSelection
        markerSelection = selection
        guard let textStorage, !isComposing, !isStale, old != selection, !items.isEmpty || !headings.isEmpty || !codeBlocks.isEmpty else {
            return false
        }
        let changed = items
            .filter { $0.revealsMarker(for: old) != $0.revealsMarker(for: selection) }
            .map(\.lineRange)
            + headings
            .filter { revealsMarker(of: $0, for: old) != revealsMarker(of: $0, for: selection) }
            .map(\.lineRange)
            + codeBlocks
            .filter { $0.isTouched(by: old) != $0.isTouched(by: selection) }
            .flatMap { [$0.openingFence] + ($0.closingFence.map { [$0] } ?? []) }
        guard !changed.isEmpty else {
            return false
        }
        os_signpost(.begin, log: Signpost.log, name: Signpost.restyle)
        let ns = textStorage.string as NSString
        isApplying = true
        textStorage.beginEditing()
        for lineRange in changed where NSMaxRange(lineRange) <= ns.length {
            let line = ns.lineRange(for: NSRange(location: lineRange.location, length: 0))
            let lineSpans = spans(startingIn: line)
            let lineRuns = MarkdownStyling.hiddenRuns(of: Array(lineSpans), revealing: revealSelection)
            let style = lineStyle(for: line, spans: lineSpans, hiddenRuns: lineRuns, item: item(startingAt: line.location), block: block(forLineAt: line.location), in: ns)
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
            let style = lineStyle(for: line, spans: lineSpans, hiddenRuns: lineRuns, item: item(startingAt: line.location), block: block(forLineAt: line.location), in: ns)
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
            if markerSelection.location >= NSMaxRange(editedRange) - delta {
                markerSelection.location += delta
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
        headings = MarkdownBlocks.headings(in: ns as String)
        codeBlocks = MarkdownBlocks.codeBlocks(in: ns as String)
        isStale = false
        if let selection = revealSelection, MarkdownStyling.link(in: spans, withDestinationHolding: selection) == nil {
            revealSelection = nil
        }
        let selectionStart = min(markerSelection.location, ns.length)
        markerSelection = NSRange(location: selectionStart, length: min(markerSelection.length, ns.length - selectionStart))
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
            let style = lineStyle(for: line, spans: spans[spanStart..<spanIndex], hiddenRuns: hiddenRuns[runStart..<runIndex], item: item, block: block(forLineAt: line.location), in: ns)
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

    /// One line's attribute runs, relative to its start, its list layout if it's an item, and
    /// its block if it's a heading or in a code block.
    private func lineStyle(
        for line: NSRange,
        spans: some Collection<MarkdownSpan>,
        hiddenRuns: some Collection<NSRange>,
        item: MarkdownListItem?,
        block: LineBlock?,
        in ns: NSString
    ) -> LineStyle {
        guard !spans.isEmpty || item != nil || block != nil else {
            return LineStyle(runs: [], toolTips: [], list: nil, block: nil)
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
            case .code:
                mark(span.contentRange, .code)
                // The last backtick of each marker: its width pads the box drawn around the text.
                for end in [span.contentRange.location, NSMaxRange(span.range)] {
                    mark(NSRange(location: end - 1, length: 1), .codePadding)
                }
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
        var blockStyle: BlockStyle?
        switch block {
        case let .heading(heading):
            // The line break too, so the line is as tall as the heading's font.
            mark(line, .heading)
            mark(heading.markerRange, revealsMarker(of: heading, for: markerSelection) ? .marker : .hidden)
            blockStyle = .heading(level: heading.level)
        case let .fence(codeBlock):
            if codeBlock.isTouched(by: markerSelection) {
                mark(line, .codeBlock)
                mark(line, .marker)
                blockStyle = .code
            } else {
                mark(line, .hidden)
                blockStyle = .hiddenFence(isOpening: line.location == codeBlock.openingFence.location)
            }
        case .code:
            mark(line, .codeBlock)
            blockStyle = .code
        case nil:
            break
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
        return LineStyle(runs: runs, toolTips: toolTips, list: list, block: blockStyle)
    }

    private func apply(_ style: LineStyle, to line: NSRange, in textStorage: NSTextStorage) {
        // The base first, so text typed after a span doesn't keep its style or its hiding.
        textStorage.setAttributes(baseAttributes, range: line)
        let headingLevel: Int?
        if case let .heading(level) = style.block {
            headingLevel = level
        } else {
            headingLevel = nil
        }
        for run in style.runs {
            let range = NSRange(location: line.location + run.range.location, length: run.range.length)
            textStorage.setAttributes(attributes(for: run.traits, headingLevel: headingLevel), range: range)
        }
        for toolTip in style.toolTips {
            let range = NSRange(location: line.location + toolTip.range.location, length: toolTip.range.length)
            textStorage.addAttribute(.toolTip, value: toolTip.text, range: range)
        }
        // The whole line, runs included: TextKit takes a paragraph's style from its first
        // character, which may be a hidden marker.
        let paragraph = switch style.block {
        case .code: codeBlockParagraph
        case let .hiddenFence(isOpening): fenceParagraph(isOpening: isOpening)
        case .heading, nil: style.list.map(paragraphStyle(for:)) ?? baseParagraph
        }
        textStorage.addAttribute(.paragraphStyle, value: paragraph, range: line)
    }

    /// The space between a code block and the line above it, in points. `EditorTextView` draws
    /// the block this far below its first line's top.
    var codeBlockMargin: CGFloat {
        (Self.codeBlockMargin * font.pointSize).rounded()
    }

    /// Every other line's paragraph.
    private var baseParagraph: NSParagraphStyle {
        if let plainParagraph {
            return plainParagraph
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacingPoints
        plainParagraph = style
        return style
    }

    private var lineSpacingPoints: CGFloat {
        (Self.lineSpacing * font.pointSize).rounded()
    }

    /// Paragraph styles depend on the font: after it changes, they're made again and everything
    /// restyles.
    private func resetParagraphStyles() {
        paragraphStyles.removeAll()
        codeParagraph = nil
        fenceParagraphs.removeAll()
        plainParagraph = nil
        restyleAll()
    }

    /// A hidden fence's paragraph: all hidden characters, which TextKit 2 lays out 0 pt tall, so
    /// it's given the height of the block's padding, and the opening one the margin above it too.
    /// The bottom padding is the taller: TextKit 2 puts a paragraph's line spacing above its line,
    /// so the code's first line has room above it already.
    private func fenceParagraph(isOpening: Bool) -> NSParagraphStyle {
        if let cached = fenceParagraphs[isOpening] {
            return cached
        }
        let padding = (isOpening ? Self.codeBlockTopPadding : Self.codeBlockBottomPadding) * font.pointSize
        let height = (padding.rounded() + (isOpening ? codeBlockMargin : 0))
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        fenceParagraphs[isOpening] = style
        return style
    }

    /// A code block's paragraph: inset from the block drawn behind it.
    private var codeBlockParagraph: NSParagraphStyle {
        if let codeParagraph {
            return codeParagraph
        }
        let inset = Self.codeBlockInset * font.pointSize
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacingPoints
        style.firstLineHeadIndent = inset
        style.headIndent = inset
        style.tailIndent = -inset
        codeParagraph = style
        return style
    }

    /// An item's paragraph: wrapped lines hang at its text start. A revealed marker ends at the
    /// text start if it fits after the level's start (`- `); otherwise (`- [ ] `) it starts there
    /// and pushes the first line's text right, as in Obsidian.
    private func paragraphStyle(for list: ListStyle) -> NSParagraphStyle {
        if let cached = paragraphStyles[list] {
            return cached
        }
        let style = Self.tablessParagraph.mutableCopy() as! NSMutableParagraphStyle
        style.lineSpacing = lineSpacingPoints
        let textStart = textStart(level: list.level, isTask: list.isTask)
        style.headIndent = textStart
        let markerWidth = list.revealedMarker.map { width(of: $0) } ?? 0
        style.firstLineHeadIndent = max(textStart - markerWidth, levelStart(level: list.level))
        style.minimumLineHeight = lineMetrics.height
        paragraphStyles[list] = style
        return style
    }

    /// A heading shows its `#`s while the selection touches its line, or while it has no text,
    /// whose line would otherwise be all hidden and collapse.
    private func revealsMarker(of heading: MarkdownHeading, for selection: NSRange) -> Bool {
        heading.contentRange.length == 0 || heading.isOnLine(touchedBy: selection)
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

    /// The block of the line starting at `location`: a heading, a code block's fence, or a line
    /// inside one.
    private func block(forLineAt location: Int) -> LineBlock? {
        var low = 0
        var high = headings.count
        while low < high {
            let middle = (low + high) / 2
            if headings[middle].lineRange.location < location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        if low < headings.count, headings[low].lineRange.location == location {
            return .heading(headings[low])
        }
        // The last block starting at or before the line.
        low = 0
        high = codeBlocks.count
        while low < high {
            let middle = (low + high) / 2
            if codeBlocks[middle].range.location <= location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0, location <= NSMaxRange(codeBlocks[low - 1].range) else {
            return nil
        }
        let block = codeBlocks[low - 1]
        return location == block.openingFence.location || location == block.closingFence?.location ? .fence(block) : .code
    }

    private func attributes(for traits: Traits, headingLevel: Int?) -> [NSAttributedString.Key: Any] {
        if traits.contains(.hidden) {
            // Takes (almost) no space and draws nothing; no underline, strikethrough or background.
            // A code span's padding backtick is as wide as the padding instead. Not a kern: TextKit 2
            // puts the caret, and so the box's edge, halfway through one, and drops one at a line's end.
            return [.font: traits.contains(.codePadding) ? Self.codePaddingFont : Self.hiddenFont, .foregroundColor: NSColor.clear]
        }
        let font = font(for: traits, headingLevel: headingLevel)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        if !traits.isDisjoint(with: [.code, .codeBlock]) {
            attributes[.foregroundColor] = NSColor.codeLabel
            if !self.font.isFixedPitch {
                attributes[.kern] = Self.codeTracking * font.pointSize
            }
        }
        if traits.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if traits.contains(.link) {
            attributes[.foregroundColor] = NSColor.linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if traits.contains(.url) {
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        }
        if traits.contains(.marker) {
            attributes[.foregroundColor] = NSColor.dimmedLabel
        }
        if traits.contains(.checked) {
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    /// The editor's font with the traits' faces; code in the monospaced system font, a little
    /// smaller, unless the editor's font is monospaced already. A heading is bold, and larger by level.
    private func font(for traits: Traits, headingLevel: Int?) -> NSFont {
        let level = traits.contains(.heading) ? headingLevel : nil
        let key = FontKey(traits: traits.intersection([.bold, .italic, .code, .codeBlock]), headingLevel: level ?? 0)
        if let cached = fonts[key] {
            return cached
        }
        let size = font.pointSize * (level.map { Self.headingScales[$0 - 1] } ?? 1)
        let isCode = key.traits.contains(.code) || key.traits.contains(.codeBlock)
        var result: NSFont
        if isCode, !font.isFixedPitch {
            result = NSFont.monospacedSystemFont(ofSize: size * Self.codeScale, weight: .regular)
        } else {
            result = size == font.pointSize ? font : NSFont(descriptor: font.fontDescriptor, size: size) ?? font
        }
        if key.traits.contains(.bold) || level != nil {
            result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask)
        }
        if key.traits.contains(.italic) {
            result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask)
        }
        fonts[key] = result
        return result
    }

    /// `#` to `######` in em of the editor's font: Obsidian's default heading sizes.
    private static let headingScales: [CGFloat] = [1.802, 1.602, 1.424, 1.266, 1.125, 1]
    /// The monospaced system font's size against the editor's, and the space it loses between
    /// letters, in em of its own size: SF Mono is wide next to the system font. Obsidian's code is
    /// 0.875 em.
    private static let codeScale: CGFloat = 0.9
    private static let codeTracking: CGFloat = -0.03
    /// The space added after each line, in em: 5 pt at the default 15 pt, Obsidian's line height
    /// (`context/ui/line-spacing-ref.png`).
    private static let lineSpacing: CGFloat = 0.35
    /// How far a code block's text sits inside the block drawn behind it, in em.
    private static let codeBlockInset: CGFloat = 1
    /// The height hidden fences keep above and below a code block's text, in em, and the space
    /// between a block and the line above it, measured from Obsidian (`line-spacing-ref.png`).
    private static let codeBlockTopPadding: CGFloat = 0.3
    private static let codeBlockBottomPadding: CGFloat = 0.8
    private static let codeBlockMargin: CGFloat = 0.25

    private static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    /// How much taller the box around an inline code span is than its text's font: as tall as the
    /// code font would be at the editor's size, so the smaller code doesn't shrink the box.
    var inlineCodeBoxScale: CGFloat {
        font.isFixedPitch ? 1 : 1 / Self.codeScale
    }

    /// The padding either side of an inline code span's text, inside the box `EditorTextView`
    /// draws around it: the width of a backtick in `codePaddingFont`, about 4 pt.
    static let inlineCodePadding = backtickWidth(in: codePaddingFont)

    /// A backtick in it is about 4 pt wide. Not exactly: the system font's tracking varies by size.
    private static let codePaddingFont: NSFont = {
        let size: CGFloat = 10
        return NSFont.systemFont(ofSize: size * 4 / backtickWidth(in: .systemFont(ofSize: size)))
    }()

    private static func backtickWidth(in font: NSFont) -> CGFloat {
        let backtick = NSAttributedString(string: "`", attributes: [.font: font])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(backtick), nil, nil, nil))
    }

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
        /// A heading's line, at its level's size.
        static let heading = Traits(rawValue: 1 << 9)
        /// A code block's line, fences included: monospaced, its background drawn by the editor.
        static let codeBlock = Traits(rawValue: 1 << 10)
        /// The last backtick of an inline code span's marker: hidden, it still takes the width of
        /// the padding of the box drawn around the span's text.
        static let codePadding = Traits(rawValue: 1 << 11)
    }

    private struct FontKey: Hashable {
        let traits: Traits
        /// 0 outside a heading.
        let headingLevel: Int
    }

    /// What a line is, block-wise: a heading, a code block's fence, or a line inside one.
    private enum LineBlock {
        case heading(MarkdownHeading)
        case fence(MarkdownCodeBlock)
        case code
    }

    /// A line's block layout, compared to skip unchanged lines.
    private enum BlockStyle: Hashable {
        case heading(level: Int)
        /// A shown fence or a line inside a code block.
        case code
        /// A fence while the selection isn't in its block: the block's padding.
        case hiddenFence(isOpening: Bool)
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
        let block: BlockStyle?
    }
}
