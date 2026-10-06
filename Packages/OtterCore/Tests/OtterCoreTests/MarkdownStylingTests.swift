import Foundation
import Testing
@testable import OtterCore

/// Each span as "kind content", plus "→ destination" for links, in `spans(in:)` order.
private func styles(_ text: String) -> [String] {
    let ns = text as NSString
    return MarkdownStyling.spans(in: text).map { span in
        let content = "\(span.kind) \(ns.substring(with: span.contentRange))"
        return span.destinationRange.map { "\(content) → \(ns.substring(with: $0))" } ?? content
    }
}

/// The hidden runs' text, in order.
private func hidden(_ text: String, revealing selection: NSRange? = nil) -> [String] {
    let ns = text as NSString
    return MarkdownStyling.hiddenRuns(of: MarkdownStyling.spans(in: text), revealing: selection).map(ns.substring(with:))
}

/// What the editor shows: the text without its hidden runs.
private func shown(_ text: String) -> String {
    let ns = text as NSString
    var result = ""
    var cursor = 0
    for run in MarkdownStyling.hiddenRuns(of: MarkdownStyling.spans(in: text)) {
        result += ns.substring(with: NSRange(location: cursor, length: run.location - cursor))
        cursor = NSMaxRange(run)
    }
    return result + ns.substring(from: cursor)
}

// MARK: - Each style

@Test(arguments: [
    ("**bold**", ["bold bold"]),
    ("__bold__", ["bold bold"]),
    ("*italic*", ["italic italic"]),
    ("_italic_", ["italic italic"]),
    ("~~struck~~", ["strikethrough struck"]),
    ("`code`", ["code code"]),
    ("[text](https://example.com)", ["link text → https://example.com"]),
    ("a **b** c", ["bold b"]),
])
func eachStyleIsFound(text: String, expected: [String]) {
    #expect(styles(text) == expected)
}

@Test func rangesAreTheWholeSpanAndItsContent() {
    let spans = MarkdownStyling.spans(in: "x **bold** [a](u)")
    #expect(spans == [
        MarkdownSpan(kind: .bold, range: NSRange(location: 2, length: 8), contentRange: NSRange(location: 4, length: 4)),
        MarkdownSpan(kind: .link, range: NSRange(location: 11, length: 6), contentRange: NSRange(location: 12, length: 1), destinationRange: NSRange(location: 15, length: 1)),
    ])
    #expect(spans[1].markerRanges == [NSRange(location: 11, length: 1), NSRange(location: 13, length: 4)])
}

// MARK: - Combinations and nesting

@Test(arguments: [
    ("***both***", ["italic **both**", "bold both"]),
    ("**_both_**", ["bold _both_", "italic both"]),
    ("_**both**_", ["italic **both**", "bold both"]),
    ("**a *b* c**", ["bold a *b* c", "italic b"]),
    ("*foo**bar**baz*", ["italic foo**bar**baz", "bold bar"]),
    ("~~*struck italic*~~", ["strikethrough *struck italic*", "italic struck italic"]),
    ("[**bold** link](u)", ["link **bold** link → u", "bold bold"]),
    ("**[link](u) in bold**", ["bold [link](u) in bold", "link link → u"]),
    ("*a `code` b*", ["italic a `code` b", "code code"]),
])
func stylesCombineAndNest(text: String, expected: [String]) {
    #expect(styles(text) == expected)
}

@Test(arguments: [
    ("`**x**`", ["code **x**"]),
    ("`[a](u)`", ["code [a](u)"]),
    // Code that starts first wins over emphasis that would close inside it.
    ("**a `b**` c", ["code b**"]),
    ("*a `*` b*", ["italic a `*` b", "code *"]),
])
func nothingInsideCodeIsStyled(text: String, expected: [String]) {
    #expect(styles(text) == expected)
}

@Test(arguments: [
    ("``a`b``", ["code a`b"]),
    ("``` x `` y ```", ["code  x `` y "]),
    ("a ```b``` c", ["code b"]),
    // A run only closes a run of the same length.
    ("``a`", [String]()),
    ("`a``", [String]()),
])
func backtickRunsOfAnyLengthMakeCode(text: String, expected: [String]) {
    #expect(styles(text) == expected)
}

// MARK: - Plain text that looks close

@Test(arguments: [
    "**abc", "abc**", "*abc", "`abc", "~~abc", "[a](u", "[a] (u)",
    // Space-flanked.
    "** x **", "* x *", "__ x __", "_ x _", "~~ x ~~", "a ** b ** c",
    // Empty pairs.
    "****", "``", "~~~~", "[](u)", "__",
    // Strikethrough is `~~` only.
    "~a~", "~~~a~~~",
    // `_` doesn't open or close inside a word.
    "snake_case_name", "a_b_c", "__init__x",
    // Punctuation after a letter doesn't open.
    "a**\"b\"**",
])
func plainTextHasNoSpans(text: String) {
    #expect(styles(text) == [])
}

@Test func asteriskWorksInsideAWord() {
    #expect(styles("un*frigging*believable") == ["italic frigging"])
    #expect(styles("a**b**c") == ["bold b"])
}

@Test(arguments: [
    ("\\*not italic\\*", [String]()),
    ("\\*a*", [String]()),
    ("**a\\*b**", ["bold a\\*b"]),
    ("\\`not code`", [String]()),
    ("\\[a](u)", [String]()),
    // A backslash before a letter isn't an escape.
    ("\\a*b*", ["italic b"]),
])
func backslashEscapesPunctuation(text: String, expected: [String]) {
    #expect(styles(text) == expected)
}

@Test func backslashesStayVisible() {
    #expect(shown("**a\\*b**") == "a\\*b")
}

// MARK: - Lines and fences

@Test func spansNeverCrossALineBreak() {
    #expect(styles("**a\nb**") == [])
    #expect(styles("*a\r\nb*") == [])
    #expect(styles("`a\nb`") == [])
    #expect(styles("[a\nb](u)") == [])
    #expect(styles("*a*\n*b*\r\n**c**") == ["italic a", "italic b", "bold c"])
}

@Test func linesInsideAFencedBlockAreNotStyled() {
    #expect(styles("```\n**a**\n```\n**b**") == ["bold b"])
    #expect(styles("~~~ swift\n*a*\n~~~\n*b*") == ["italic b"])
    #expect(styles("  ```\n`a`\n  ```") == [])
    // A fence closes only with as many markers or more, of the same kind.
    #expect(styles("````\n*a*\n```\n*b*\n````\n*c*") == ["italic c"])
    #expect(styles("```\n*a*\n~~~\n*b*") == [])
}

@Test func anUnclosedFenceRunsToTheEnd() {
    #expect(styles("*a*\n```\n*b*\n*c*") == ["italic a"])
}

@Test func backticksThatArentAFenceAreInline() {
    // Four spaces of indent, or a backtick in the info string.
    #expect(styles("    ```\n*a*") == ["italic a"])
    #expect(styles("``` a`b\n*c*") == ["italic c"])
}

// MARK: - Links

@Test(arguments: [
    ("[a](u \"title\")", ["link a → u"]),
    ("[a](<with space>)", ["link a → with space"]),
    ("[a](https://x.org/a_(b))", ["link a → https://x.org/a_(b)"]),
    ("[a]()", ["link a → "]),
    ("[a [b] c](u)", ["link a [b] c → u"]),
    // A link can't contain a link: the inner one wins.
    ("[a [b](u) c](v)", ["link b → u"]),
    // Emphasis can't close across a link's edge.
    ("*a [b* c](u)", ["link b* c → u"]),
])
func linksAreFound(text: String, expected: [String]) {
    #expect(styles(text) == expected)
}

@Test(arguments: [
    "![alt](x.png)", "![**alt**](x.png)", "[[wiki_link_]]", "[[a]]", "https://x.org/_a_", "www.x.org/_a_b",
    "<https://x.org/_a_>", "[a][ref]", "[a]",
])
func imagesWikilinksAndBareURLsAreNotStyled(text: String) {
    #expect(styles(text) == [])
}

@Test func emphasisAroundABareURLStillWorks() {
    #expect(styles("*https://x.org/a_b*") == ["italic https://x.org/a_b"])
    #expect(styles("see https://x.org, then *this*") == ["italic this"])
}

// MARK: - Hidden runs

@Test func eachSpansMarkersAreHidden() {
    #expect(hidden("a **b** c") == ["**", "**"])
    #expect(hidden("[text](https://x.org)") == ["[", "](https://x.org)"])
    #expect(shown("a **b** ~~c~~ `d` [e](f) *g*") == "a b c d e g")
}

@Test func adjacentMarkersMergeIntoOneRun() {
    #expect(hidden("**a**~~b~~") == ["**", "**~~", "~~"])
    #expect(hidden("***x***") == ["***", "***"])
    #expect(hidden("[**a**](u)") == ["[**", "**](u)"])
}

@Test func aLinkRevealedByTheSelectionKeepsItsMarkers() {
    let text = "[**a**](url) b"
    // The selection in "url", or a caret at either end of it.
    #expect(hidden(text, revealing: NSRange(location: 8, length: 3)) == ["**", "**"])
    #expect(hidden(text, revealing: NSRange(location: 8, length: 0)) == ["**", "**"])
    #expect(hidden(text, revealing: NSRange(location: 11, length: 0)) == ["**", "**"])
    // Anywhere else, it's hidden.
    #expect(hidden(text, revealing: NSRange(location: 4, length: 0)) == ["[**", "**](url)"])
    #expect(hidden(text, revealing: NSRange(location: 13, length: 0)) == ["[**", "**](url)"])
}

// MARK: - UTF-16

@Test func rangesCountUTF16AfterEmoji() {
    // 🎉 is two UTF-16 units.
    let spans = MarkdownStyling.spans(in: "🎉 **b** 👩‍👩‍👧 `c`")
    #expect(spans.map(\.range) == [NSRange(location: 3, length: 5), NSRange(location: 18, length: 3)])
    #expect(spans.map(\.contentRange) == [NSRange(location: 5, length: 1), NSRange(location: 19, length: 1)])
}

@Test func emojiAndAccentsNextToMarkers() {
    #expect(styles("**🎉**") == ["bold 🎉"])
    #expect(styles("*cafe\u{301}*") == ["italic cafe\u{301}"])
    #expect(styles("🎉*a*🎉") == ["italic a"])
    #expect(styles("日本*語*です") == ["italic 語"])
}

// MARK: - Every shortcut's output is styled as what it added

/// Applies `style` with `selection` and returns the edited text.
private func formatted(_ style: MarkdownStyle, _ text: String, _ selection: NSRange, clipboard: String? = nil) throws -> String {
    let edit = try #require(MarkdownFormatting.apply(style, to: text, selection: selection, clipboard: clipboard))
    return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

@Test(arguments: [MarkdownStyle.bold, .italic, .strikethrough, .code])
func aWrappedSelectionIsStyled(style: MarkdownStyle) throws {
    let text = try formatted(style, "say hello there", NSRange(location: 4, length: 5))
    #expect(styles(text) == ["\(style) hello"])
    let word = try formatted(style, "say hello there", NSRange(location: 6, length: 0))
    #expect(styles(word) == ["\(style) hello"])
    let spaced = try formatted(style, "say hello there", NSRange(location: 3, length: 7))
    #expect(styles(spaced) == ["\(style) hello"])
}

@Test(arguments: [MarkdownStyle.bold, .italic, .strikethrough, .code])
func eachLineOfAMultiLineSelectionIsStyled(style: MarkdownStyle) throws {
    let text = try formatted(style, "- one\n\n> two three", NSRange(location: 0, length: 18))
    #expect(styles(text) == ["\(style) one", "\(style) two three"])
}

@Test(arguments: [MarkdownStyle.bold, .italic, .strikethrough, .code])
func typingIntoAnInsertedEmptyPairIsStyled(style: MarkdownStyle) throws {
    let edit = try #require(MarkdownFormatting.apply(style, to: "a  b", selection: NSRange(location: 2, length: 0)))
    let pair = ("a  b" as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    #expect(styles(pair) == [])
    let typed = (pair as NSString).replacingCharacters(in: edit.selection, with: "x")
    #expect(styles(typed) == ["\(style) x"])
}

@Test func boldAndItalicStackAsBoth() throws {
    let both = try formatted(.italic, "**word**", NSRange(location: 2, length: 4))
    #expect(Set(styles(both)) == ["bold word", "italic **word**"])
    let back = try formatted(.bold, both, NSRange(location: 3, length: 4))
    #expect(styles(back) == ["italic word"])
}

@Test func aLinkShortcutMakesALink() throws {
    #expect(styles(try formatted(.link, "see the docs", NSRange(location: 4, length: 8))) == ["link the docs → url"])
    #expect(styles(try formatted(.link, "see docs", NSRange(location: 5, length: 0), clipboard: "https://x.org")) == ["link docs → https://x.org"])
    // Empty link text shows as typed until something is typed in the brackets.
    #expect(styles(try formatted(.link, "https://x.org", NSRange(location: 0, length: 13))) == [])
}

// MARK: - Speed

@Test func parsingATenKilobyteNoteIsFast() {
    // The editor parses the whole note on each keystroke (budget: restyle < 1 ms, ARCHITECTURE §9).
    let line = "Some **bold** and *italic* text, `code`, ~~gone~~ and a [link](https://example.com/a_b) here.\n"
    let note = String(repeating: line, count: 10_240 / line.utf16.count + 1)
    let clock = ContinuousClock()
    var samples: [Duration] = []
    for _ in 0..<50 {
        let start = clock.now
        _ = MarkdownStyling.spans(in: note)
        samples.append(clock.now - start)
    }
    samples.sort()
    let p95 = samples[samples.count * 95 / 100 - 1]
    print("Parse of a \(note.utf16.count / 1024) KB note: p50 \(samples[samples.count / 2]), p95 \(p95)")
    // Generous, so a debug build on a busy CI machine passes; release builds are far faster.
    #expect(p95 < .milliseconds(20))
}
