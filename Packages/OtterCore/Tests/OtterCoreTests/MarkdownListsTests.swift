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

@Test(arguments: ["-", "-x", "---", "- - -", " - - - ", "-- -", "* a", "+ a", "1. a", "> - a", "", "   ", "a - b"])
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
])
func commandShift8TogglesABullet(input: String, expected: String) {
    #expect(run(.toggleBullet, input) == expected)
}

@Test func commandShift8AcrossLines() {
    // Not all items: plain lines get `- `, items stay.
    #expect(run(.toggleBullet, "⟨a\n\n- b\n\tc⟩") == "⟨- a\n\n- b\n\t- c⟩")
    // All items: their markers go, task markers included.
    #expect(run(.toggleBullet, "⟨- a\n\n\t- [ ] b⟩") == "⟨a\n\n\tb⟩")
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

// MARK: - Speed

@Test func parsingATwoHundredItemListIsFast() {
    // The editor parses the items on every keystroke too (budget: restyle < 1 ms, ARCHITECTURE §9).
    let lines = ["- item with **bold** text", "\t- [ ] a nested task", "\t\t- [x] done and [a link](https://x.org)", "- plain bullet"]
    let note = (0..<200).map { lines[$0 % lines.count] }.joined(separator: "\n")
    let clock = ContinuousClock()
    var samples: [Duration] = []
    for _ in 0..<50 {
        let start = clock.now
        _ = MarkdownLists.items(in: note)
        samples.append(clock.now - start)
    }
    samples.sort()
    let p95 = samples[samples.count * 95 / 100 - 1]
    print("Items of a 200-item note (\(note.utf16.count / 1024) KB): p50 \(samples[samples.count / 2]), p95 \(p95)")
    // Generous, so a debug build on a busy CI machine passes.
    #expect(p95 < .milliseconds(10))
}
