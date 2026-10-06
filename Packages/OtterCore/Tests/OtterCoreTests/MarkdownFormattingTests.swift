import Foundation
import Testing
@testable import OtterCore

/// Applies `style` to `marked`, where `‸` is the caret or `⟨…⟩` the selection, and returns the
/// edited text marked the same way. `nil` if there's no edit.
private func format(_ style: MarkdownStyle, _ marked: String, clipboard: String? = nil) -> String? {
    var text = marked as NSString
    let selection: NSRange
    let caret = text.range(of: "‸")
    if caret.location != NSNotFound {
        text = text.replacingCharacters(in: caret, with: "") as NSString
        selection = NSRange(location: caret.location, length: 0)
    } else {
        let open = text.range(of: "⟨")
        text = text.replacingCharacters(in: open, with: "") as NSString
        let close = text.range(of: "⟩")
        text = text.replacingCharacters(in: close, with: "") as NSString
        selection = NSRange(location: open.location, length: close.location - open.location)
    }
    guard let edit = MarkdownFormatting.apply(style, to: text as String, selection: selection, clipboard: clipboard) else {
        return nil
    }
    let result = text.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
    if edit.selection.length == 0 {
        return result.replacingCharacters(in: edit.selection, with: "‸")
    }
    let closed = result.replacingCharacters(in: NSRange(location: NSMaxRange(edit.selection), length: 0), with: "⟩") as NSString
    return closed.replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "⟨")
}

// MARK: - Wrap and unwrap a selection

@Test(arguments: [
    (MarkdownStyle.bold, "a ⟨word⟩ b", "a **⟨word⟩** b"),
    (.italic, "a ⟨word⟩ b", "a *⟨word⟩* b"),
    (.strikethrough, "a ⟨word⟩ b", "a ~~⟨word⟩~~ b"),
    (.code, "a ⟨word⟩ b", "a `⟨word⟩` b"),
    (.bold, "⟨two words⟩", "**⟨two words⟩**"),
])
func aSelectionIsWrappedAndStaysSelected(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test(arguments: [
    // Markers just outside the selection.
    (MarkdownStyle.bold, "a **⟨word⟩** b", "a ⟨word⟩ b"),
    (.italic, "a *⟨word⟩* b", "a ⟨word⟩ b"),
    (.strikethrough, "a ~~⟨word⟩~~ b", "a ⟨word⟩ b"),
    (.code, "a `⟨word⟩` b", "a ⟨word⟩ b"),
    // Markers at the selection's own ends.
    (.bold, "a ⟨**word**⟩ b", "a ⟨word⟩ b"),
    (.italic, "a ⟨*word*⟩ b", "a ⟨word⟩ b"),
    (.strikethrough, "a ⟨~~word~~⟩ b", "a ⟨word⟩ b"),
    (.code, "a ⟨`word`⟩ b", "a ⟨word⟩ b"),
])
func aWrappedSelectionIsUnwrapped(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test(arguments: MarkdownStyle.allCases.filter { $0 != .link })
func wrappingTwiceGivesBackTheOriginal(style: MarkdownStyle) throws {
    let once = try #require(format(style, "say ⟨hello⟩ there"))
    #expect(format(style, once) == "say ⟨hello⟩ there")
}

@Test func twoSpansInOneSelectionAreNotOneWrappedSpan() {
    #expect(format(.bold, "⟨**a** b **c**⟩") == "**⟨**a** b **c**⟩**")
}

// MARK: - Bold and italic share `*`

@Test(arguments: [
    (MarkdownStyle.italic, "**⟨bold⟩**", "***⟨bold⟩***"),
    (.italic, "⟨**bold**⟩", "*⟨**bold**⟩*"),
    (.bold, "*⟨it⟩*", "***⟨it⟩***"),
    (.bold, "⟨*it*⟩", "**⟨*it*⟩**"),
    (.italic, "***⟨x⟩***", "**⟨x⟩**"),
    (.bold, "***⟨x⟩***", "*⟨x⟩*"),
    (.italic, "⟨***x***⟩", "⟨**x**⟩"),
    (.bold, "⟨***x***⟩", "⟨*x*⟩"),
])
func boldAndItalicDontUndoEachOther(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test func italicInsideBoldTogglesOnlyTheItalic() {
    #expect(format(.italic, "⟨*a **b** c*⟩") == "⟨a **b** c⟩")
}

// MARK: - Whitespace

@Test(arguments: [
    (MarkdownStyle.bold, "a⟨ foo ⟩b", "a **⟨foo⟩** b"),
    (.italic, "⟨foo  ⟩bar", "*⟨foo⟩*  bar"),
    (.code, "x⟨\tfoo⟩", "x\t`⟨foo⟩`"),
    (.bold, "a ⟨ **foo** ⟩ b", "a  ⟨foo⟩  b"),
])
func surroundingWhitespaceStaysOutsideTheMarkers(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test func aSelectionOfOnlyWhitespaceDoesNothing() {
    #expect(format(.bold, "a⟨   ⟩b") == nil)
    #expect(format(.bold, "a⟨\n\n⟩b") == nil)
}

// MARK: - No selection

@Test(arguments: [
    (MarkdownStyle.bold, "say hel‸lo there", "say **hel‸lo** there"),
    (.italic, "say hel‸lo there", "say *hel‸lo* there"),
    (.strikethrough, "say hel‸lo there", "say ~~hel‸lo~~ there"),
    (.code, "call snake_ca‸se()", "call `snake_ca‸se`()"),
    (.bold, "do‸n't stop", "**do‸n't** stop"),
    (.bold, "it’s fi‸ne", "it’s **fi‸ne**"),
])
func aCaretInsideAWordAppliesToTheWord(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test(arguments: [
    (MarkdownStyle.bold, "say **hel‸lo** there", "say hel‸lo there"),
    (.italic, "*hel‸lo*", "hel‸lo"),
    (.italic, "**hel‸lo**", "***hel‸lo***"),
    (.bold, "***hel‸lo***", "*hel‸lo*"),
    (.code, "`hel‸lo`", "hel‸lo"),
])
func aCaretInsideAWrappedWordUnwrapsIt(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test(arguments: [
    (MarkdownStyle.bold, "‸", "**‸**"),
    (.bold, "hello ‸", "hello **‸**"),
    // At a word's start or end the caret isn't inside it.
    (.bold, "hello‸", "hello**‸**"),
    (.italic, "‸hello", "*‸*hello"),
    (.bold, "don‸'t", "don**‸**'t"),
    (.strikethrough, "a ‸ b", "a ~~‸~~ b"),
    (.code, "a ‸ b", "a `‸` b"),
])
func aCaretOutsideAWordInsertsAnEmptyPair(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test(arguments: [
    (MarkdownStyle.bold, "a **‸** b", "a ‸ b"),
    (.italic, "a *‸* b", "a ‸ b"),
    (.strikethrough, "~~‸~~", "‸"),
    (.code, "`‸`", "‸"),
    // A run of three is both.
    (.italic, "***‸***", "**‸**"),
    (.bold, "***‸***", "*‸*"),
    // Not the other style's pair: nest inside it.
    (.italic, "**‸**", "***‸***"),
    (.bold, "*‸*", "***‸***"),
])
func aCaretBetweenAnEmptyPairRemovesIt(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

// MARK: - Several lines

@Test func eachLineIsWrappedOnItsOwnSkippingBlankLines() {
    #expect(format(.bold, "⟨one\n\ntwo  \n  three⟩") == "⟨**one**\n\n**two**  \n  **three**⟩")
}

@Test func linesAreUnwrappedOnlyWhenEveryOneIsWrapped() {
    #expect(format(.bold, "⟨**one**\n**two**⟩") == "⟨one\ntwo⟩")
    #expect(format(.bold, "⟨**one**\ntwo⟩") == "⟨**one**\n**two**⟩")
}

@Test func aPartialFirstLineKeepsItsUnselectedStart() {
    #expect(format(.italic, "keep ⟨this\nand that⟩ too") == "keep ⟨*this*\n*and that*⟩ too")
}

@Test func listQuoteAndHeadingMarkersStayOutside() {
    let input = "⟨- milk\n* eggs\n1. bread\n- [ ] jam\n> quoted\n## Heading⟩"
    let expected = "⟨- **milk**\n* **eggs**\n1. **bread**\n- [ ] **jam**\n> **quoted**\n## **Heading**⟩"
    #expect(format(.bold, input) == expected)
    #expect(format(.bold, expected) == input)
}

@Test func aWholeLineSelectedWithItsLineBreakIsOneLine() {
    // A triple-click selects the line break too.
    #expect(format(.bold, "⟨- milk\n⟩eggs") == "- **⟨milk⟩**\neggs")
}

@Test func windowsLineBreaksAreLineBreaks() {
    #expect(format(.code, "⟨a\r\nb⟩") == "⟨`a`\r\n`b`⟩")
}

// MARK: - Links

@Test func aSelectionBecomesTheLinkTextWithThePlaceholderSelected() {
    #expect(format(.link, "see ⟨the docs⟩ now") == "see [the docs](⟨url⟩) now")
}

@Test func theWordAtTheCaretBecomesTheLinkText() {
    #expect(format(.link, "see do‸cs now") == "see [docs](⟨url⟩) now")
}

@Test func aClipboardURLIsUsedWithTheCaretAfterTheLink() {
    #expect(format(.link, "see ⟨the docs⟩ now", clipboard: "https://example.com/a?b=1") == "see [the docs](https://example.com/a?b=1)‸ now")
    #expect(format(.link, "see do‸cs", clipboard: "  http://x.org\n") == "see [docs](http://x.org)‸")
}

@Test(arguments: ["ftp://example.com", "example.com", "https://a.com https://b.com", "two\nlines", "", "https://"])
func clipboardTextThatIsntOneWebURLIsIgnored(clipboard: String) {
    #expect(format(.link, "⟨docs⟩", clipboard: clipboard) == "[docs](⟨url⟩)")
}

@Test func aSelectedURLBecomesTheDestination() {
    #expect(format(.link, "at ⟨https://example.com/x⟩ ok") == "at [‸](https://example.com/x) ok")
    // The selected URL wins over the clipboard's.
    #expect(format(.link, "⟨ https://a.com ⟩", clipboard: "https://b.com") == " [‸](https://a.com) ")
}

@Test func aCaretInOrAtTheEndOfAURLLinksIt() {
    #expect(format(.link, "at https://exa‸mple.com ok") == "at [‸](https://example.com) ok")
    #expect(format(.link, "https://example.com‸") == "[‸](https://example.com)")
}

@Test func withNothingToLinkAnEmptyLinkIsInserted() {
    #expect(format(.link, "a ‸ b") == "a [‸](url) b")
    #expect(format(.link, "‸", clipboard: "https://example.com") == "[‸](https://example.com)")
}

@Test func aLinkCantSpanLines() {
    #expect(format(.link, "⟨one\ntwo⟩") == nil)
    // A trailing line break from a triple-click is trimmed first.
    #expect(format(.link, "⟨one\n⟩two") == "[one](⟨url⟩)\ntwo")
}

// MARK: - UTF-16 ranges

@Test func rangesCountUTF16LikeNSTextView() throws {
    // 🎉 is two UTF-16 units, so "café" starts at 3.
    let edit = try #require(MarkdownFormatting.apply(.bold, to: "🎉 café", selection: NSRange(location: 3, length: 4)))
    #expect(edit == MarkdownEdit(range: NSRange(location: 3, length: 4), replacement: "**café**", selection: NSRange(location: 5, length: 4)))
}

@Test(arguments: [
    (MarkdownStyle.bold, "👩‍👩‍👧 naï‸ve 🎉", "👩‍👩‍👧 **naï‸ve** 🎉"),
    // A decomposed é: "e" + U+0301.
    (.italic, "cafe\u{301}s ca‸fe\u{301}", "cafe\u{301}s *ca‸fe\u{301}*"),
    (.bold, "⟨🎉⟩", "**⟨🎉⟩**"),
    (.code, "x ⟨日本語⟩ y", "x `⟨日本語⟩` y"),
    (.strikethrough, "🇫🇷 ~~⟨ça va⟩~~", "🇫🇷 ⟨ça va⟩"),
    (.link, "→ ⟨naïve 🎉⟩", "→ [naïve 🎉](⟨url⟩)"),
    (.bold, "⟨🎉 one\n二⟩", "⟨**🎉 one**\n**二**⟩"),
])
func nonASCIITextKeepsItsRanges(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test func emojiAreNotWordCharacters() {
    #expect(format(.bold, "🎉‸🎉") == "🎉**‸**🎉")
}

@Test func aSelectionOutsideTheTextIsIgnored() {
    #expect(MarkdownFormatting.apply(.bold, to: "abc", selection: NSRange(location: 2, length: 5)) == nil)
}

// MARK: - Hidden markers (ADR-016)

@Test(arguments: [
    // At a span's end the shortcut steps out of it: no change, caret after the closing marker.
    (MarkdownStyle.bold, "say **bold‸** there", "say **bold**‸ there"),
    (.italic, "*it‸*", "*it*‸"),
    (.strikethrough, "~~gone‸~~", "~~gone~~‸"),
    (.code, "``co`de‸``", "``co`de``‸"),
    (.bold, "**two words‸**", "**two words**‸"),
    // Only out of the span of that style.
    (.bold, "***x‸***", "***x**‸*"),
    (.italic, "***x‸***", "***x***‸"),
    // Pressed again there, it stays out.
    (.bold, "**bold**‸", "**bold**‸"),
])
func theShortcutAtASpansEndMovesTheCaretOut(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test func steppingOutChangesNoText() throws {
    let edit = try #require(MarkdownFormatting.apply(.bold, to: "**bold**", selection: NSRange(location: 6, length: 0)))
    #expect(edit == MarkdownEdit(range: NSRange(location: 6, length: 0), replacement: "", selection: NSRange(location: 8, length: 0)))
}

@Test(arguments: [
    // A caret at a hidden run's edge counts as inside the span next to it.
    (MarkdownStyle.bold, "‸**bold**", "‸bold"),
    (.italic, "**bold‸**", "***bold‸***"),
    (.italic, "‸**bold**", "***‸bold***"),
    (.code, "a ‸~~gone~~", "a ~~`‸gone`~~"),
    // Inside a span of the style, the whole span comes off, however many words.
    (.bold, "**t‸wo words**", "t‸wo words"),
    (.strikethrough, "x ~~a b‸ c~~", "x a b‸ c"),
    (.code, "``a `b‸` c``", "a `b‸` c"),
])
func aCaretAtAHiddenEdgeOrInsideASpanTogglesIt(style: MarkdownStyle, input: String, expected: String) {
    #expect(format(style, input) == expected)
}

@Test(arguments: [
    "[te‸xt](https://a.b)", "[text‸](https://a.b)", "‸[text](https://a.b)", "[text](https://a.b)‸",
    "[⟨text⟩](https://a.b)", "[**te‸xt**](https://a.b)",
])
func linkInAnExistingLinkSelectsItsURL(input: String) {
    #expect(format(.link, input) == "[\(input.contains("**") ? "**text**" : "text")](⟨https://a.b⟩)")
}

@Test func linkInAnEmptyLinksURLSelectsTheEmptyURL() {
    #expect(format(.link, "[a](‸)") == "[a](‸)")
}
