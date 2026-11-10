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

private func mark(_ text: String, _ selection: NSRange) -> String {
    let ns = text as NSString
    if selection.length == 0 {
        return ns.replacingCharacters(in: selection, with: "‸")
    }
    let closed = ns.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "⟩") as NSString
    return closed.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "⟨")
}

/// The text after `command`, marked with the edit's selection, or `nil` for a beep.
private func run(_ command: ListCommand, _ marked: String) -> String? {
    let (text, selection) = unmark(marked)
    return MarkdownLists.apply(command, to: text, selection: selection).map {
        mark((text as NSString).replacingCharacters(in: $0.range, with: $0.replacement), $0.selection)
    }
}

/// Each item as "prefix|text", plus " [x]" / " [ ]" for tasks, in order.
private func described(_ text: String) -> [String] {
    let ns = text as NSString
    return MarkdownLists.items(in: text).map { item in
        let base = "\(ns.substring(with: item.prefixRange))|\(ns.substring(with: item.contentRange))"
        switch item.kind {
        case .bullet: return base
        case let .task(checked): return base + (checked ? " [x]" : " [ ]")
        case let .ordered(number, delimiter): return base + " #\(number)\(delimiter)"
        }
    }
}

private func levels(_ text: String) -> [Int] {
    MarkdownLists.items(in: text).map(\.level)
}

// MARK: - Parsing

@Test(arguments: [
    ("- milk", ["- |milk"]),
    ("- [ ] jam", ["- [ ] |jam [ ]"]),
    ("- [x] done", ["- [x] |done [x]"]),
    ("- [X] done", ["- [X] |done [x]"]),
    ("-\tmilk", ["-\t|milk"]),
    ("- ", ["- |"]),
    ("- [ ] ", ["- [ ] | [ ]"]),
    // Extra spaces after the prefix belong to the text.
    ("-   milk", ["- |  milk"]),
    ("- [ ]  jam", ["- [ ] | jam [ ]"]),
    ("\t\t- a", ["\t\t- |a"]),
    ("  - [x] b", ["  - [x] |b [x]"]),
])
func bulletsAndTasksAreItems(text: String, expected: [String]) {
    #expect(described(text) == expected)
}

@Test(arguments: [
    ("1. milk", ["1. |milk #1."]),
    ("2) jam", ["2) |jam #2)"]),
    ("10.\tten", ["10.\t|ten #10."]),
    ("007. bond", ["007. |bond #7."]),
    ("123456789. a", ["123456789. |a #123456789."]),
    ("1. ", ["1. | #1."]),
    ("1.   a", ["1. |  a #1."]),
    ("\t2. b", ["\t2. |b #2."]),
    // Never a task: the box is text.
    ("1. [ ] a", ["1. |[ ] a #1."]),
])
func numberedLinesAreItems(text: String, expected: [String]) {
    #expect(described(text) == expected)
}

@Test(arguments: ["1.", "1.a", "1 a", "1: a", ". a", "a. b", "1234567890. a", "-1. a", "1.5 a", "#1. a", "> 1. a"])
func theseAreNotNumberedItems(text: String) {
    #expect(described(text) == [])
}

@Test func numberedRangesCoverTheNumber() throws {
    let text = "x\n\t12) jam\n"
    let item = try #require(MarkdownLists.items(in: text).first)
    #expect(item.indentRange == NSRange(location: 2, length: 1))
    #expect(item.markerRange == NSRange(location: 3, length: 4))
    #expect(item.numberRange == NSRange(location: 3, length: 2))
    #expect(item.contentRange == NSRange(location: 7, length: 3))
    #expect(item.checkboxRange == nil)
    #expect(MarkdownLists.items(in: "- a").first?.numberRange == nil)
}

@Test(arguments: ["-", "-x", "---", "- - -", " - - - ", "-- -", "* a", "+ a", "> - a", "", "   ", "a - b"])
func theseAreNotItems(text: String) {
    #expect(described(text) == [])
}

@Test(arguments: [
    // A task needs the space after `]`.
    ("- [ ]", ["- |[ ]"]),
    ("- [x](u)", ["- |[x](u)"]),
    ("- [y] a", ["- |[y] a"]),
    ("- [] a", ["- |[] a"]),
])
func theseAreBulletsNotTasks(text: String, expected: [String]) {
    #expect(described(text) == expected)
}

@Test func linesInAFenceAreNotItems() {
    #expect(described("```\n- a\n- [ ] b\n```\n- c") == ["- |c"])
    #expect(described("~~~\n- a") == [])
}

@Test func rangesCoverTheLineAndItsParts() throws {
    let text = "x\n\t- [ ] jam\n"
    let item = try #require(MarkdownLists.items(in: text).first)
    #expect(item.lineRange == NSRange(location: 2, length: 11))
    #expect(item.indentRange == NSRange(location: 2, length: 1))
    #expect(item.markerRange == NSRange(location: 3, length: 6))
    #expect(item.prefixRange == NSRange(location: 2, length: 7))
    #expect(item.contentRange == NSRange(location: 9, length: 3))
    #expect(item.checkboxRange == NSRange(location: 5, length: 3))
    #expect(item.indentColumns == 4)
}

@Test func rangesAreUTF16WithEmoji() throws {
    // 🎉 is two UTF-16 units, 👩‍👩‍👧 eight.
    let text = "🎉 a\n- 👩‍👩‍👧 b\n  - [x] 🎉"
    let items = MarkdownLists.items(in: text)
    try #require(items.count == 2)
    #expect(items[0].lineRange == NSRange(location: 5, length: 13))
    #expect(items[0].contentRange == NSRange(location: 7, length: 10))
    #expect(items[1].prefixRange == NSRange(location: 18, length: 8))
    #expect(items[1].contentRange == NSRange(location: 26, length: 2))
    #expect(items[1].checkboxRange == NSRange(location: 22, length: 3))
}

// MARK: - Levels

@Test(arguments: [
    ("- a\n  - b\n    - c\n  - d\n- e", [0, 1, 2, 1, 0]),
    ("- a\n    - b\n        - c\n    - d", [0, 1, 2, 1]),
    ("- a\n\t- b\n\t\t- c\n\t- d\n- e", [0, 1, 2, 1, 0]),
    // Mixed: a tab after two spaces reaches column 4, as four spaces do.
    ("- a\n  - b\n  \t- c\n    - d", [0, 1, 2, 2]),
    ("- a\n\t- b\n    - c", [0, 1, 1]),
])
func nestingFollowsIndentation(text: String, expected: [Int]) {
    #expect(levels(text) == expected)
}

@Test func aJumpOfSeveralTabsNestsOneLevel() {
    #expect(levels("- a\n\t\t\t- b\n\t- c\n\t\t- d") == [0, 1, 1, 2])
    #expect(levels("\t\t- a\n- b") == [0, 0])
}

@Test func numberedAndBulletedItemsNestTogether() {
    #expect(levels("1. a\n\t- b\n\t\t1. c\n2. d") == [0, 1, 2, 0])
    #expect(levels("- a\n   1. b\n- c") == [0, 1, 0])
}

@Test func anyOtherLineEndsTheList() {
    #expect(levels("- a\n\t- b\n\n\t- c") == [0, 1, 0])
    #expect(levels("- a\ntext\n\t- b") == [0, 0])
    #expect(levels("- a\n```\n\t- x\n```\n\t- b") == [0, 0])
}

// MARK: - ⌘L

@Test(arguments: [
    ("milk‸", "- [ ] milk‸"),
    ("‸milk", "- [ ] ‸milk"),
    ("\tmi‸lk", "\t- [ ] mi‸lk"),
    ("‸", "- [ ] ‸"),
    ("- mi‸lk", "- [ ] mi‸lk"),
    ("- ‸milk", "- [ ] ‸milk"),
    ("- [ ] mi‸lk", "- [x] mi‸lk"),
    ("- [x] mi‸lk", "- [ ] mi‸lk"),
    ("- [X] mi‸lk", "- [ ] mi‸lk"),
    ("\t- [ ] ‸", "\t- [x] ‸"),
    // A numbered item becomes a task: tasks are never numbered.
    ("1. mi‸lk", "- [ ] mi‸lk"),
    ("\t12) ‸milk", "\t- [ ] ‸milk"),
])
func commandLCyclesOneLine(input: String, expected: String) {
    #expect(run(.toggleTask, input) == expected)
}

@Test func commandLAcrossLines() {
    // Some lines aren't tasks: those become unchecked tasks; blank lines are skipped.
    #expect(run(.toggleTask, "⟨a\n\n\t- b\n- [x] c⟩") == "⟨- [ ] a\n\n\t- [ ] b\n- [x] c⟩")
    // All tasks, some unchecked: all checked.
    #expect(run(.toggleTask, "⟨- [ ] a\n- [x] b\n\t- [ ] c⟩") == "⟨- [x] a\n- [x] b\n\t- [x] c⟩")
    // All checked: all unchecked.
    #expect(run(.toggleTask, "⟨- [x] a\n- [X] b⟩") == "⟨- [ ] a\n- [ ] b⟩")
    // A selection ending just after a line break doesn't take the next line.
    #expect(run(.toggleTask, "⟨a\n⟩b") == "⟨- [ ] a\n⟩b")
}

@Test func commandLOnOnlyBlankLinesBeeps() {
    #expect(run(.toggleTask, "⟨\n  \n⟩x") == nil)
}

// MARK: - ⇧⌘8

@Test(arguments: [
    ("mi‸lk", "- mi‸lk"),
    ("  mi‸lk", "  - mi‸lk"),
    ("‸", "- ‸"),
    ("- mi‸lk", "mi‸lk"),
    ("\t- [x] mi‸lk", "\tmi‸lk"),
    ("- [ ] ‸", "‸"),
    ("1. mi‸lk", "- mi‸lk"),
])
func commandShift8TogglesABullet(input: String, expected: String) {
    #expect(run(.toggleBullet, input) == expected)
}

@Test func commandShift8AcrossLines() {
    // Not all items: plain lines get `- `, items stay.
    #expect(run(.toggleBullet, "⟨a\n\n- b\n\tc⟩") == "⟨- a\n\n- b\n\t- c⟩")
    // All items: their markers go, task markers included.
    #expect(run(.toggleBullet, "⟨- a\n\n\t- [ ] b⟩") == "⟨a\n\n\tb⟩")
    // Numbered items aren't bullets: they become bullets.
    #expect(run(.toggleBullet, "⟨- a\n1. b\n\t2) c⟩") == "⟨- a\n- b\n\t- c⟩")
}

// MARK: - ⇧⌘7

@Test(arguments: [
    ("mi‸lk", "1. mi‸lk"),
    ("  mi‸lk", "  1. mi‸lk"),
    ("‸", "1. ‸"),
    ("3. mi‸lk", "mi‸lk"),
    ("\t2) mi‸lk", "\tmi‸lk"),
    ("- mi‸lk", "1. mi‸lk"),
    ("- [x] mi‸lk", "1. mi‸lk"),
    // Goes on from a numbered item just above at the same indentation, with its delimiter.
    ("1. a\n2) b\nc‸", "1. a\n2) b\n3) c‸"),
    ("1. a\n\tb‸", "1. a\n\t1. b‸"),
    ("1. a\n\nb‸", "1. a\n\n1. b‸"),
])
func commandShift7TogglesANumber(input: String, expected: String) {
    #expect(run(.toggleOrdered, input) == expected)
}

@Test func commandShift7AcrossLines() {
    // Numbered from 1 at each indentation, blank lines skipped, every line renumbered.
    #expect(run(.toggleOrdered, "⟨a\n\n- b\n\tc\n\t5. d\ne⟩") == "⟨1. a\n\n2. b\n\t1. c\n\t2. d\n3. e⟩")
    // All numbered: their markers go.
    #expect(run(.toggleOrdered, "⟨1. a\n\n\t2. b⟩") == "⟨a\n\n\tb⟩")
}

// MARK: - Tab and ⇧Tab

@Test(arguments: [
    ("- a\n- b‸", "- a\n\t- b‸"),
    ("- a\n\t- b\n\t- c‸", "- a\n\t- b\n\t\t- c‸"),
    ("- a\n\t- b\n- c‸", "- a\n\t- b\n\t- c‸"),
    ("- [ ] a\n- [ ] ‸b", "- [ ] a\n\t- [ ] ‸b"),
])
func tabNestsUnderTheItemAbove(input: String, expected: String) {
    #expect(run(.indent, input) == expected)
}

@Test func tabIndentsEveryItemTheSelectionTouches() {
    #expect(run(.indent, "- a\n- ⟨b\ntext\n- c⟩") == "- a\n\t- ⟨b\ntext\n\t- c⟩")
}

@Test(arguments: [
    // The first item of a list has no parent to nest under.
    "- a‸",
    "x\n- a‸",
    "- a\n\n- b‸",
    // Already a child of the item above.
    "- a\n\t- b‸",
    // No item touched.
    "te‸xt",
])
func tabIsRefused(input: String) {
    #expect(run(.indent, input) == nil)
}

@Test(arguments: [
    ("\t- p\n\t\t- x‸", "\t- p\n\t- x‸"),
    ("- p\n\t- x‸", "- p\n- x‸"),
    ("- p\n  - q\n      - x‸", "- p\n  - q\n  - x‸"),
    ("- p\n\t\t\t- x‸", "- p\n- x‸"),
])
func shiftTabCutsIndentationBackToTheParents(input: String, expected: String) {
    #expect(run(.outdent, input) == expected)
}

@Test func shiftTabOutdentsEachNestedItemAndSkipsTopLevelOnes() {
    #expect(run(.outdent, "- a\n\t- ⟨b\n\t\t- c\n- d⟩") == "- a\n- ⟨b\n\t- c\n- d⟩")
}

@Test func shiftTabOnTopLevelItemsBeeps() {
    #expect(run(.outdent, "- a‸") == nil)
    #expect(run(.outdent, "⟨- a\n- b⟩") == nil)
    #expect(run(.outdent, "te‸xt") == nil)
}

@Test func tabNestsANumberedItem() {
    #expect(run(.indent, "1. a\n2. b‸") == "1. a\n\t2. b‸")
    #expect(run(.outdent, "1. a\n\t2. b‸") == "1. a\n2. b‸")
}

// MARK: - Numbered siblings

@Test func theSiblingsAfterAnItemAreTheOnesCountingOnFromIt() {
    let text = "1. a\n2. b\n\t1. x\n\t- y\n3. c\n5. d\n6. e"
    let ns = text as NSString
    let items = MarkdownLists.items(in: text)
    func siblings(_ index: Int) -> [String] {
        MarkdownLists.numberedSiblings(after: items[index], in: items).map { ns.substring(with: $0.contentRange) }
    }
    // Children skipped; stops at the gap before 5.
    #expect(siblings(0) == ["b", "c"])
    #expect(siblings(2) == [])
    #expect(siblings(5) == ["e"])
    // Lazy numbering doesn't count up.
    let lazy = MarkdownLists.items(in: "1. a\n1. b")
    #expect(MarkdownLists.numberedSiblings(after: lazy[0], in: lazy).isEmpty)
    // A bullet has none; a shallower item or another line ends the list.
    let mixed = MarkdownLists.items(in: "- a\n2. b\n\t1. c\n2. d\n\n3. e")
    #expect(MarkdownLists.numberedSiblings(after: mixed[0], in: mixed).isEmpty)
    #expect(MarkdownLists.numberedSiblings(after: mixed[1], in: mixed).isEmpty)
    #expect(MarkdownLists.numberedSiblings(after: mixed[2], in: mixed).isEmpty)
}

@Test func aNumberedItemHasNoCheckbox() throws {
    let item = try #require(MarkdownLists.items(in: "1. a").first)
    #expect(MarkdownLists.toggleCheckbox(item, in: "1. a", selection: NSRange(location: 0, length: 0)) == nil)
}

// MARK: - Checkbox click

@Test func aCheckboxClickWritesXOrASpace() throws {
    let text = "- [ ] a\n- [x] b\n- [X] c\n- d"
    let items = MarkdownLists.items(in: text)
    let selection = NSRange(location: 3, length: 0)
    func toggled(_ index: Int) throws -> String {
        let edit = try #require(MarkdownLists.toggleCheckbox(items[index], in: text, selection: selection))
        #expect(edit.selection == selection)
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
    #expect(try toggled(0) == "- [x] a\n- [x] b\n- [X] c\n- d")
    #expect(try toggled(1) == "- [ ] a\n- [ ] b\n- [X] c\n- d")
    #expect(try toggled(2) == "- [ ] a\n- [x] b\n- [ ] c\n- d")
    #expect(MarkdownLists.toggleCheckbox(items[3], in: text, selection: selection) == nil)
}

// MARK: - Hidden runs

@Test func eachItemHidesItsPrefixOrOnARevealedLineItsIndentation() {
    let text = "\t- a\n- [ ] b\n\t\t- [x] c"
    let ns = text as NSString
    let items = MarkdownLists.items(in: text)
    #expect(MarkdownLists.hiddenRuns(of: items, selection: nil).map(ns.substring(with:)) == ["\t- ", "- [ ] ", "\t\t- [x] "])
    // The caret on line 1 shows its marker; line 2 has no indentation to hide.
    #expect(MarkdownLists.hiddenRuns(of: items, selection: NSRange(location: 3, length: 0)).map(ns.substring(with:)) == ["\t", "- [ ] ", "\t\t- [x] "])
    #expect(MarkdownLists.hiddenRuns(of: items, selection: NSRange(location: 8, length: 10)).map(ns.substring(with:)) == ["\t- ", "\t\t"])
}
