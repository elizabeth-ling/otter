import Foundation
import Testing
@testable import OtterCore

/// `marked` without its `‸` caret or `⟨…⟩` selection, and the selection.
private func unmark(_ marked: String) -> (text: String, selection: NSRange) {
    var text = marked as NSString
    let caret = text.range(of: "‸")
    if caret.location != NSNotFound {
        return (text.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0))
    }
    let open = text.range(of: "⟨")
    text = text.replacingCharacters(in: open, with: "") as NSString
    let close = text.range(of: "⟩")
    text = text.replacingCharacters(in: close, with: "") as NSString
    return (text as String, NSRange(location: open.location, length: close.location - open.location))
}

/// `text` with `selection` marked as `unmark` reads it.
private func mark(_ text: String, _ selection: NSRange) -> String {
    let ns = text as NSString
    if selection.length == 0 {
        return ns.replacingCharacters(in: selection, with: "‸")
    }
    let closed = ns.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "⟩") as NSString
    return closed.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "⟨")
}

private func editing(_ text: String) -> HiddenMarkerEditing {
    HiddenMarkerEditing(text: text)
}

/// The edited text, marked with the edit's selection.
private func applied(_ edit: MarkdownEdit?, to text: String) -> String? {
    edit.map { mark((text as NSString).replacingCharacters(in: $0.range, with: $0.replacement), $0.selection) }
}

private func stop(_ marked: String) -> String {
    let (text, selection) = unmark(marked)
    return mark(text, NSRange(location: editing(text).caretStop(selection.location), length: 0))
}

private func trimmed(_ marked: String) -> String {
    let (text, selection) = unmark(marked)
    return mark(text, editing(text).trimmedSelection(selection))
}

private func deleted(_ marked: String, backward: Bool = true) -> String? {
    let (text, selection) = unmark(marked)
    let rules = editing(text)
    let edit = selection.length > 0 ? rules.deletion(of: selection) : rules.deletion(backward: backward, from: selection.location)
    return applied(edit, to: text)
}

private func replaced(_ marked: String, with string: String) -> String? {
    let (text, selection) = unmark(marked)
    return applied(editing(text).replacement(of: selection, with: string), to: text)
}

private func broken(_ marked: String) -> String? {
    let (text, selection) = unmark(marked)
    return applied(editing(text).lineBreak(at: selection), to: text)
}

private func copied(_ marked: String) -> String {
    let (text, selection) = unmark(marked)
    return editing(text).copiedMarkdown(for: selection)
}

/// What the editor shows: the text without its hidden runs.
private func shown(_ text: String) -> String {
    let ns = text as NSString
    var result = ""
    var cursor = 0
    for run in editing(text).hiddenRuns {
        result += ns.substring(with: NSRange(location: cursor, length: run.location - cursor))
        cursor = NSMaxRange(run)
    }
    return result + ns.substring(from: cursor)
}

// MARK: - Caret stops

@Test(arguments: [
    ("‸**bold**", "‸**bold**"),
    ("*‸*bold**", "‸**bold**"),
    ("**‸bold**", "‸**bold**"),
    ("**bo‸ld**", "**bo‸ld**"),
    ("**bold‸**", "**bold‸**"),
    ("**bold*‸*", "**bold‸**"),
    ("**bold**‸", "**bold‸**"),
    ("**bold**‸ x", "**bold‸** x"),
])
func aCaretInOrAtEitherEndOfAHiddenRunSnapsToItsStart(input: String, expected: String) {
    #expect(stop(input) == expected)
}

@Test(arguments: [
    // Adjacent spans share one run: the caret stays in the left one.
    ("**a**~‸~b~~", "**a‸**~~b~~"),
    ("**a**~~‸b~~", "**a‸**~~b~~"),
    // Nested spans.
    ("***x***‸", "***x‸***"),
    ("*‸**x***", "‸***x***"),
    // Links hide `[` and `](url)`.
    ("‸[text](url)", "‸[text](url)"),
    ("[‸text](url)", "‸[text](url)"),
    ("[text](u‸rl)", "[text‸](url)"),
    ("[text](url)‸", "[text‸](url)"),
    // Unhidden text isn't touched.
    ("**ab‸c", "**ab‸c"),
    ("**‸**", "**‸**"),
])
func caretStopsBetweenAdjacentAndNestedSpansAndAroundLinks(input: String, expected: String) {
    #expect(stop(input) == expected)
}

@Test func aRevealedLinksMarkersAreCaretStops() {
    let text = "[text](url)"
    let rules = HiddenMarkerEditing(text: text, revealing: NSRange(location: 7, length: 3))
    #expect(rules.caretStop(8) == 8)
    #expect(rules.caretStop(11) == 11)
    #expect(rules.hiddenRuns.isEmpty)
}

// MARK: - Arrow keys

/// Every caret stop from the start, pressing `→` until it stops moving.
private func stopsForward(_ text: String) -> [Int] {
    let rules = editing(text)
    var stops = [rules.caretStop(0)]
    while true {
        let next = rules.nextCaretStop(after: stops.last!)
        guard next != stops.last else {
            return stops
        }
        stops.append(next)
    }
}

private func stopsBackward(_ text: String) -> [Int] {
    let rules = editing(text)
    var stops = [rules.caretStop((text as NSString).length)]
    while true {
        let previous = rules.previousCaretStop(before: stops.last!)
        guard previous != stops.last else {
            return stops
        }
        stops.append(previous)
    }
}

@Test func arrowsStepOneVisibleCharacterSkippingHiddenRuns() {
    #expect(stopsForward("a**b**c") == [0, 1, 4, 7])
    #expect(stopsBackward("a**b**c") == [7, 4, 1, 0])
    #expect(stopsForward("x [ab](u) y") == [0, 1, 2, 4, 5, 10, 11])
    #expect(stopsForward("**a**\n**b**") == [0, 3, 6, 9])
}

@Test(arguments: [
    "a**b**c", "**bold** and ~~gone~~ `code` [link](https://x.org) end", "***x*** y", "**a**~~b~~",
    "🎉 **é🎉** 👩‍👩‍👧", "cafe\u{301} *x*", "**a**\n\n*b*", "plain", "",
])
func everyArrowPressMovesOneVisibleCharacter(text: String) {
    // As many presses as visible characters, each one moving, both ways.
    let visible = shown(text).count
    let forward = stopsForward(text)
    let backward = stopsBackward(text)
    #expect(forward.count == visible + 1)
    #expect(backward == forward.reversed())
    #expect(zip(forward, forward.dropFirst()).allSatisfy { $0 < $1 })
}

@Test func arrowsFromAPinnedCaretAfterAClosingMarker() {
    // After `⌘B` at a span's end the caret sits after the marker; the arrows still move one character.
    let rules = editing("**bold**x")
    #expect(rules.nextCaretStop(after: 8) == 9)
    #expect(rules.previousCaretStop(before: 8) == 5)
}

// MARK: - Selections

@Test(arguments: [
    ("⟨**bold**⟩", "**⟨bold⟩**"),
    ("a ⟨**bold**⟩ b", "a **⟨bold⟩** b"),
    ("**⟨bo⟩ld**", "**⟨bo⟩ld**"),
    ("*⟨*bold**⟩", "**⟨bold⟩**"),
    ("⟨x **ab⟩c**", "⟨x **ab⟩c**"),
    ("**a**⟨~~⟩b~~", "**a‸**~~b~~"),
    ("[⟨text](url)⟩ more", "[⟨text⟩](url) more"),
])
func aSelectionsEndsMoveOutOfHiddenRuns(input: String, expected: String) {
    #expect(trimmed(input) == expected)
}

// MARK: - ⌫ and ⌦

@Test(arguments: [
    ("**ab‸**", "**a‸**"),
    ("**a‸b**", "**‸b**"),
    ("x **ab**‸", "x **a‸**"),
    // The last visible character takes its markers with it.
    ("**a‸**", "‸"),
    ("x **a‸** y", "x ‸ y"),
    ("***x‸***", "‸"),
    ("[a‸](url) b", "‸ b"),
    ("**[a‸](u)**", "‸"),
    ("**a *b‸* c**", "**a ‸ c**"),
    ("**a**~~b‸~~", "**a**‸"),
    // Never a hidden marker on its own.
    ("**a**‸~~b~~", "‸~~b~~"),
    ("x‸**b**", "‸**b**"),
])
func backspaceDeletesTheVisibleCharacterBefore(input: String, expected: String) {
    #expect(deleted(input) == expected)
}

@Test(arguments: [
    ("‸**ab**", "‸**b**"),
    ("‸**a** y", "‸ y"),
    ("**a‸**b", "**a‸**"),
    ("**a‸**~~b~~", "**a‸**"),
    ("x ‸[a](url)", "x ‸"),
])
func forwardDeleteDeletesTheVisibleCharacterAfter(input: String, expected: String) {
    #expect(deleted(input, backward: false) == expected)
}

@Test func nothingToDeleteAtTheEnds() {
    #expect(deleted("‸**a**") == nil)
    #expect(deleted("**a‸**", backward: false) == nil)
    #expect(deleted("‸") == nil)
}

@Test func backspaceRightAfterTypingAClosingMarkerDeletesTheLastCharacter() {
    // The editor keeps the caret after `**` once it's typed; `⌫` still takes the visible `c`.
    #expect(deleted("**abc**‸") == "**ab‸**")
}

@Test(arguments: ["**ab** c", "a **b** ~~cd~~ `e` [fg](h) i", "***x*** y", "🎉 **é🎉** z", "**a**~~b~~"])
func deletingAtEveryStopRemovesExactlyOneVisibleCharacter(text: String) {
    // Whatever else goes is hidden markers, of spans left with no visible text.
    let rules = editing(text)
    let visible = Array(shown(text))
    for (index, stop) in stopsForward(text).enumerated() {
        if let edit = rules.deletion(backward: true, from: stop) {
            #expect(edit.replacement.isEmpty)
            #expect(shownText(of: text, in: edit.range, rules: rules) == String(visible[index - 1]), "⌫ at \(stop) in \(text)")
        }
        if let edit = rules.deletion(backward: false, from: stop) {
            #expect(edit.replacement.isEmpty)
            #expect(shownText(of: text, in: edit.range, rules: rules) == String(visible[index]), "⌦ at \(stop) in \(text)")
        }
    }
}

// MARK: - Deleting a selection

@Test(arguments: [
    // Whole spans go with their markers.
    ("a ⟨**bold**⟩ b", "a ‸ b"),
    ("a **⟨bold⟩** b", "a ‸ b"),
    ("⟨**a** ~~b~~⟩", "‸"),
    ("**a ⟨*b*⟩ c**", "**a ‸ c**"),
    ("⟨[link](url)⟩ x", "‸ x"),
    // Partly selected spans keep theirs.
    ("⟨x **ab⟩c**", "‸**c**"),
    ("**a⟨b**c ~~d⟩e~~", "**a‸**~~e~~"),
    ("**a⟨b⟩c**", "**a‸c**"),
    ("[ab⟨c](u) d⟩", "[ab‸](u)"),
    ("⟨x [ab⟩c](url)", "‸[c](url)"),
])
func deletingASelection(input: String, expected: String) {
    #expect(deleted(input) == expected)
}

@Test func deletingOnlyHiddenMarkersDoesNothing() {
    #expect(deleted("**a**⟨~~⟩b~~") == nil)
}

@Test func editingARevealedLinksURLIsPlainText() {
    let text = "[a](https://x.org)"
    let rules = HiddenMarkerEditing(text: text, revealing: NSRange(location: 4, length: 13))
    #expect(applied(rules.deletion(of: NSRange(location: 4, length: 13)), to: text) == "[a](‸)")
    #expect(applied(rules.replacement(of: NSRange(location: 4, length: 13), with: "https://y.org"), to: text) == "[a](https://y.org‸)")
    #expect(applied(rules.deletion(backward: true, from: 17), to: text) == "[a](https://x.or‸)")
}

// MARK: - Typing and pasting over a selection

@Test(arguments: [
    // The new text takes the style of the first selected character.
    ("a ⟨**bold**⟩ b", "x", "a **x‸** b"),
    ("a **⟨bold⟩** b", "new", "a **new‸** b"),
    ("**a⟨bc⟩**", "x", "**ax‸**"),
    ("⟨x **ab⟩c**", "y", "y‸**c**"),
    ("**⟨a** b⟩", "x", "**x‸**"),
    ("a ⟨b⟩ c", "x", "a x‸ c"),
    ("⟨[link](url)⟩", "new", "[new‸](url)"),
    ("⟨***x***⟩", "y", "***y‸***"),
    // Spaces stay outside the markers.
    ("⟨**bold**⟩", "x ", "**x** ‸"),
    ("⟨**bold**⟩", " ", " ‸"),
    // Nothing to put back if the style is still there.
    ("**a ⟨**b**⟩ c**", "x", "**a x‸ c**"),
])
func typingOverASelection(input: String, string: String, expected: String) {
    #expect(replaced(input, with: string) == expected)
}

@Test(arguments: [
    ("⟨**bold**⟩", "x\ny", "**x**\n**y‸**"),
    ("**ab‸c**", "x\ny", "**abx**\n**y‸c**"),
    ("**ab‸**", "x\n", "**abx**\n‸"),
    ("a‸b", "x\r\ny", "ax\r\ny‸b"),
    ("**a⟨b⟩c**", "\n", "**a**\n‸**c**"),
])
func pastedLineBreaksSplitSpans(input: String, string: String, expected: String) {
    #expect(replaced(input, with: string) == expected)
}

@Test func pastingAtACaretOutsideSpansIsAPlainInsert() {
    let (text, selection) = unmark("**a** ‸b")
    let edit = editing(text).replacement(of: selection, with: "xy")
    #expect(edit == MarkdownEdit(range: selection, replacement: "xy", selection: NSRange(location: selection.location + 2, length: 0)))
    let lines = editing(text).replacement(of: selection, with: "x\n**y")
    #expect(lines == MarkdownEdit(range: selection, replacement: "x\n**y", selection: NSRange(location: selection.location + 5, length: 0)))
}

// MARK: - Line breaks

@Test(arguments: [
    ("**ab‸c**", "**ab**\n‸**c**"),
    ("a *b‸c* d", "a *b*\n‸*c* d"),
    ("~~ab‸c~~", "~~ab~~\n‸~~c~~"),
    ("`ab‸c`", "`ab`\n‸`c`"),
    ("[ab‸c](u)", "[ab](u)\n‸[c](u)"),
    ("***ab‸c***", "***ab***\n‸***c***"),
    // At a span's end the break goes after the closing marker.
    ("**abc‸**", "**abc**\n‸"),
    ("***x‸*** y", "***x***\n‸ y"),
    ("**abc**‸", "**abc**\n‸"),
    ("**a**‸~~b~~", "**a**\n‸~~b~~"),
    // Spaces next to the break stay outside the markers.
    ("**ab ‸cd**", "**ab** \n‸**cd**"),
    ("**ab‸ cd**", "**ab**\n ‸**cd**"),
    // An inner span ending at the break closes there; the outer one splits.
    ("**a *b‸* c**", "**a *b***\n ‸**c**"),
    // Outside spans, a plain break.
    ("a‸b", "a\n‸b"),
    ("‸**a**", "\n‸**a**"),
])
func aLineBreakSplitsTheSpanAroundIt(input: String, expected: String) {
    #expect(broken(input) == expected)
}

@Test func bothHalvesOfASplitSpanKeepTheirStyle() throws {
    let result = try #require(broken("**a *b‸* c**"))
    let text = unmark(result).text
    let kinds = MarkdownStyling.spans(in: text).map(\.kind)
    #expect(kinds == [.bold, .italic, .bold])
}

@Test func aLineBreakInARevealedLinksURLIsPlain() {
    let text = "[a](url)"
    let rules = HiddenMarkerEditing(text: text, revealing: NSRange(location: 5, length: 0))
    #expect(applied(rules.lineBreak(at: NSRange(location: 5, length: 0)), to: text) == "[a](u\n‸rl)")
}

// MARK: - Closing marker just typed

@Test func typingAClosingMarkerKeepsTheCaretAfterIt() {
    #expect(editing("**abc**").caretAfterClosingMarker(completedBy: NSRange(location: 6, length: 1)) == 7)
    #expect(editing("*abc*").caretAfterClosingMarker(completedBy: NSRange(location: 4, length: 1)) == 5)
    #expect(editing("[a](u)").caretAfterClosingMarker(completedBy: NSRange(location: 5, length: 1)) == 6)
    // `**abc*` is `*` then italic `abc`: the first closing `*` closes that.
    #expect(editing("**abc*").caretAfterClosingMarker(completedBy: NSRange(location: 5, length: 1)) == 6)
}

@Test func typingContentOrPlainTextDoesNot() {
    #expect(editing("**abc**").caretAfterClosingMarker(completedBy: NSRange(location: 4, length: 1)) == nil)
    #expect(editing("**abc** x").caretAfterClosingMarker(completedBy: NSRange(location: 8, length: 1)) == nil)
    #expect(editing("**abc").caretAfterClosingMarker(completedBy: NSRange(location: 4, length: 1)) == nil)
}

// MARK: - Copy

@Test(arguments: [
    ("**a⟨b⟩c**", "**b**"),
    ("⟨**abc**⟩", "**abc**"),
    ("**⟨abc⟩**", "**abc**"),
    ("**a⟨bc** d⟩", "**bc** d"),
    ("x ⟨y **a⟩bc**", "y **a**"),
    ("[li⟨nk](url) more⟩", "[nk](url) more"),
    ("***a⟨b⟩c***", "***b***"),
    ("`co⟨d⟩e`", "`d`"),
    ("``a⟨b⟩c``", "``b``"),
    ("**a ~~b⟨c~~ d⟩e**", "**~~c~~ d**"),
    // Spaces at the ends stay outside.
    ("**a⟨b ⟩c**", "**b** "),
    ("**a⟨ b⟩**", " **b**"),
    // Nothing partly selected: the raw text.
    ("⟨a **b** c⟩", "a **b** c"),
    ("⟨**a**\n**b**⟩", "**a**\n**b**"),
])
func copyingWritesBalancedMarkdown(input: String, expected: String) {
    #expect(copied(input) == expected)
}

@Test func copyingFromARevealedLinksURLIsThePlainURL() {
    let text = "[a](https://x.org)"
    let rules = HiddenMarkerEditing(text: text, revealing: NSRange(location: 4, length: 5))
    #expect(rules.copiedMarkdown(for: NSRange(location: 4, length: 5)) == "https")
}

@Test func copiedMarkdownPastesLookingTheSame() {
    // Pasted into plain text, the copy shows exactly what was selected.
    for marked in ["**a⟨b⟩c**", "x ⟨y **a⟩bc**", "[li⟨nk](url) more⟩", "**a ~~b⟨c~~ d⟩e**"] {
        let (text, selection) = unmark(marked)
        let rules = editing(text)
        let trimmedSelection = rules.trimmedSelection(selection)
        let visibleSelected = shown((text as NSString).substring(with: trimmedSelection))
        let shownSelection = shownText(of: text, in: trimmedSelection, rules: rules)
        #expect(shown(copied(marked)) == shownSelection, "\(marked) → \(visibleSelected)")
    }
}

/// The visible characters of `text` inside `range`.
private func shownText(of text: String, in range: NSRange, rules: HiddenMarkerEditing) -> String {
    let ns = text as NSString
    var result = ""
    var cursor = range.location
    for run in rules.hiddenRuns where NSMaxRange(run) > cursor && run.location < NSMaxRange(range) {
        result += ns.substring(with: NSRange(location: cursor, length: max(run.location - cursor, 0)))
        cursor = max(cursor, NSMaxRange(run))
    }
    if cursor < NSMaxRange(range) {
        result += ns.substring(with: NSRange(location: cursor, length: NSMaxRange(range) - cursor))
    }
    return result
}

// MARK: - UTF-16

@Test func rangesAreUTF16AfterEmoji() {
    #expect(stop("🎉 **é🎉**‸") == "🎉 **é🎉‸**")
    #expect(deleted("🎉 **é🎉‸**") == "🎉 **é‸**")
    #expect(deleted("👩‍👩‍👧 **🎉‸**") == "👩‍👩‍👧 ‸")
    #expect(deleted("‸**🎉** 👩‍👩‍👧", backward: false) == "‸ 👩‍👩‍👧")
    #expect(copied("🎉 **é⟨🎉⟩**") == "**🎉**")
    #expect(broken("**🎉‸é**") == "**🎉**\n‸**é**")
    #expect(replaced("🎉 ⟨**é**⟩", with: "👍") == "🎉 **👍‸**")
    #expect(stopsForward("🎉**👩‍👩‍👧**") == [0, 2, 12])
}
