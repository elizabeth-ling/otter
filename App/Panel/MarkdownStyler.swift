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
@MainActor
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    /// The editor's font. Bold and italic are its faces; changing it restyles everything.
    var font: NSFont {
        didSet {
            fonts.removeAll()
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
            let style = lineStyle(for: line, spans: lineSpans, hiddenRuns: lineRuns, in: ns)
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
        isStale = false
        if let selection = revealSelection, MarkdownStyling.link(in: spans, withDestinationHolding: selection) == nil {
            revealSelection = nil
        }
        let hiddenRuns = MarkdownStyling.hiddenRuns(of: spans, revealing: revealSelection)
        let editedEnd = NSMaxRange(editedRange)

        var lines: [Int: LineStyle] = [:]
        var spanIndex = 0
        var runIndex = 0
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
            let style = lineStyle(for: line, spans: spans[spanStart..<spanIndex], hiddenRuns: hiddenRuns[runStart..<runIndex], in: ns)
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

    /// One line's attribute runs, relative to its start.
    private func lineStyle(for line: NSRange, spans: some Collection<MarkdownSpan>, hiddenRuns: some Collection<NSRange>, in ns: NSString) -> LineStyle {
        guard !spans.isEmpty else {
            return LineStyle(runs: [], toolTips: [])
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
        return LineStyle(runs: runs, toolTips: toolTips)
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

    private struct Traits: OptionSet, Hashable {
        let rawValue: UInt8

        static let bold = Traits(rawValue: 1 << 0)
        static let italic = Traits(rawValue: 1 << 1)
        static let strikethrough = Traits(rawValue: 1 << 2)
        static let code = Traits(rawValue: 1 << 3)
        static let link = Traits(rawValue: 1 << 4)
        /// A revealed link's URL.
        static let url = Traits(rawValue: 1 << 5)
        static let hidden = Traits(rawValue: 1 << 6)
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
    }
}
