import Foundation
import Testing
@testable import OtterCore

/// Each heading as "level marker|text", in order.
private func headings(_ text: String) -> [String] {
    let ns = text as NSString
    return MarkdownBlocks.headings(in: text).map { heading in
        "\(heading.level) \(ns.substring(with: heading.markerRange))|\(ns.substring(with: heading.contentRange))"
    }
}

/// Each code block's text, its fences and what's between.
private func codeBlocks(_ text: String) -> [String] {
    let ns = text as NSString
    return MarkdownBlocks.codeBlocks(in: text).map { ns.substring(with: $0.range) }
}

// MARK: - Headings

@Test(arguments: [
    ("# One", ["1 # |One"]),
    ("## Two", ["2 ## |Two"]),
    ("###### Six", ["6 ###### |Six"]),
    ("#\tTab", ["1 #\t|Tab"]),
    ("#   Spaces", ["1 #   |Spaces"]),
    ("   # Indented", ["1    # |Indented"]),
    ("# ", ["1 # |"]),
    ("# Closing ##", ["1 # |Closing ##"]),
    ("# **Bold** title", ["1 # |**Bold** title"]),
])
func headingsAreFound(text: String, expected: [String]) {
    #expect(headings(text) == expected)
}

@Test(arguments: [
    "#",
    "#tag",
    "####### Seven",
    "    # Four spaces",
    "\t# Tab",
    "a # b",
    "- # In a list",
    "\\# Escaped",
])
func theseAreNotHeadings(text: String) {
    #expect(headings(text).isEmpty)
}

@Test func headingsAreOneLineEach() {
    #expect(headings("# A\ntext\n## B\r\n### C") == ["1 # |A", "2 ## |B", "3 ### |C"])
    let heading = MarkdownBlocks.headings(in: "x\n## B\ny")[0]
    #expect(heading.lineRange == NSRange(location: 2, length: 4))
}

@Test func aSelectionTouchingTheLineShowsTheMarker() {
    // "x\n## B\ny": the heading's line is 2..<6, its line break at 6.
    let heading = MarkdownBlocks.headings(in: "x\n## B\ny")[0]
    #expect(heading.isOnLine(touchedBy: NSRange(location: 2, length: 0)))
    #expect(heading.isOnLine(touchedBy: NSRange(location: 6, length: 0)))
    #expect(!heading.isOnLine(touchedBy: NSRange(location: 1, length: 0)))
    #expect(!heading.isOnLine(touchedBy: NSRange(location: 7, length: 0)))
    #expect(heading.isOnLine(touchedBy: NSRange(location: 0, length: 3)))
    #expect(heading.isOnLine(touchedBy: NSRange(location: 5, length: 3)))
    // Ending just after the line break before it.
    #expect(!heading.isOnLine(touchedBy: NSRange(location: 0, length: 2)))
}

@Test func headingsInsideAFenceAreCode() {
    #expect(headings("```\n# Not a heading\n```\n# Heading") == ["1 # |Heading"])
}

// MARK: - Code blocks

@Test func aCodeBlockRunsFromFenceToFence() {
    let text = "before\n```swift\nlet a = 1\n\nlet b = 2\n```\nafter"
    #expect(codeBlocks(text) == ["```swift\nlet a = 1\n\nlet b = 2\n```"])
    let block = MarkdownBlocks.codeBlocks(in: text)[0]
    #expect(block.openingFence == NSRange(location: 7, length: 8))
    #expect(block.closingFence == NSRange(location: 37, length: 3))
}

@Test func tildeFencesAndLongerFencesWork() {
    #expect(codeBlocks("~~~\na\n~~~") == ["~~~\na\n~~~"])
    // A fence closes only with as many markers or more, of the same kind.
    #expect(codeBlocks("````\n```\n~~~~\n`````") == ["````\n```\n~~~~\n`````"])
}

@Test func anUnclosedCodeBlockRunsToTheEnd() {
    let blocks = MarkdownBlocks.codeBlocks(in: "a\n```\nb\nc\n")
    #expect(blocks == [MarkdownCodeBlock(range: NSRange(location: 2, length: 8), openingFence: NSRange(location: 2, length: 3), closingFence: nil)])
}

@Test func severalCodeBlocks() {
    #expect(codeBlocks("```\na\n```\ntext\n```\nb\n```") == ["```\na\n```", "```\nb\n```"])
}

@Test func inlineBackticksArentACodeBlock() {
    #expect(codeBlocks("```code``` on one line\n`a`").isEmpty)
}
