import Foundation
import Testing
@testable import OtterCore

private let paris = TimeZone(identifier: "Europe/Paris")!

// MARK: - New files

@Test func newFileHasFrontmatterWithTheCaptureOffset() {
    let content = MarkdownWriter.newFile(text: "Buy oat milk", createdAt: referenceDate, timeZone: paris, frontmatter: true)
    #expect(content == "---\ncreated: 2026-09-21T16:13:20+02:00\nsource: otter\n---\nBuy oat milk\n")
}

@Test func newFileOffsetIsNumericEvenInUTC() {
    let content = MarkdownWriter.newFile(text: "x", createdAt: referenceDate, timeZone: TimeZone(identifier: "UTC")!, frontmatter: true)
    #expect(content.contains("created: 2026-09-21T14:13:20+00:00\n"))
}

@Test func newFileWithoutFrontmatterIsJustTheText() {
    #expect(MarkdownWriter.newFile(text: "Buy oat milk", createdAt: referenceDate, timeZone: paris, frontmatter: false) == "Buy oat milk\n")
}

@Test func newFileNormalizesLineEndingsAndEndsWithOneNewline() {
    let text = "\n\nFirst\r\nSecond\rThird\n\n\n"
    #expect(MarkdownWriter.newFile(text: text, createdAt: referenceDate, timeZone: paris, frontmatter: false) == "First\nSecond\nThird\n")
}

@Test func newFileKeepsIndentationAndInnerBlankLines() {
    let text = "  - indented\n\n    code\n"
    #expect(MarkdownWriter.newFile(text: text, createdAt: referenceDate, timeZone: paris, frontmatter: false) == "  - indented\n\n    code\n")
}

@Test func newFileIsUTF8WithoutABOM() {
    let data = Data(MarkdownWriter.newFile(text: "Café 🎉", createdAt: referenceDate, timeZone: paris, frontmatter: false).utf8)
    #expect(!data.starts(with: [0xEF, 0xBB, 0xBF]))
    #expect(String(data: data, encoding: .utf8) == "Café 🎉\n")
}

@Test func namedNewFileHasATitleInTheFrontmatter() {
    let content = MarkdownWriter.newFile(text: "oat milk", title: "Groceries", createdAt: referenceDate, timeZone: paris, frontmatter: true)
    #expect(content == "---\ntitle: \"Groceries\"\ncreated: 2026-09-21T16:13:20+02:00\nsource: otter\n---\noat milk\n")
}

@Test func frontmatterTitleIsQuotedAndStaysOnOneLine() {
    let content = MarkdownWriter.newFile(text: "x", title: #"Q4: "plan" \ #1"# + "\nnext\u{07}", createdAt: referenceDate, timeZone: paris, frontmatter: true)
    #expect(content.hasPrefix(#"---"# + "\n" + #"title: "Q4: \"plan\" \\ #1 next ""# + "\ncreated: "))
}

@Test func namedNoteWithoutFrontmatterIsJustTheText() {
    #expect(MarkdownWriter.newFile(text: "oat milk", title: "Groceries", createdAt: referenceDate, timeZone: paris, frontmatter: false) == "oat milk\n")
}

// MARK: - Append blocks

@Test func defaultTemplateRendersAOneLineNoteAsAListItem() {
    let block = MarkdownWriter.appendBlock(template: AppendTemplate.default, text: "  Buy oat milk \n", createdAt: referenceDate, timeZone: paris)
    #expect(block == "- 16:13 Buy oat milk")
}

@Test func defaultTemplateRendersALongerNoteUnderAHeading() {
    let block = MarkdownWriter.appendBlock(template: AppendTemplate.default, text: "Line one\r\nLine two\n\n", createdAt: referenceDate, timeZone: paris)
    #expect(block == "### 16:13\nLine one\nLine two")
}

@Test func customTemplateFillsEveryVariable() {
    let template = "## {{date}} {{time}} — {{title}}\n{{text}}\n{{attachments}}"
    let block = MarkdownWriter.appendBlock(template: template, text: "# Plan\nstep 1", createdAt: referenceDate, timeZone: paris, embeds: ["![[img.png]]"])
    #expect(block == "## 2026-09-21 16:13 — Plan\n# Plan\nstep 1\n![[img.png]]")
}

@Test func noteTextIsNeverTreatedAsTemplate() {
    let block = MarkdownWriter.appendBlock(template: AppendTemplate.default, text: "literal {{time}} and {{#multi_line}}", createdAt: referenceDate, timeZone: paris)
    #expect(block == "- 16:13 literal {{time}} and {{#multi_line}}")
}

@Test func unknownTagsAreLeftAsTheyAre() {
    #expect(AppendTemplate.render("{{nope}} {{text}} {{", isMultiLine: false, values: ["text": "hi"]) == "{{nope}} hi {{")
}

@Test func sectionsInsideALineKeepTheRestOfTheLine() {
    let template = "* {{time}}{{#multi_line}} (long){{/multi_line}}{{#single_line}} (short){{/single_line}}"
    #expect(AppendTemplate.render(template, isMultiLine: true, values: ["time": "09:00"]) == "* 09:00 (long)")
    #expect(AppendTemplate.render(template, isMultiLine: false, values: ["time": "09:00"]) == "* 09:00 (short)")
}

@Test func standaloneSectionTagLinesLeaveNoBlankLines() {
    let template = "top\n{{#multi_line}}\nmulti\n{{/multi_line}}\n{{#single_line}}\nsingle\n{{/single_line}}\nbottom"
    #expect(AppendTemplate.render(template, isMultiLine: true, values: [:]) == "top\nmulti\nbottom")
    #expect(AppendTemplate.render(template, isMultiLine: false, values: [:]) == "top\nsingle\nbottom")
}

@Test func templateLineEndingsAreNormalized() {
    let block = MarkdownWriter.appendBlock(template: "{{time}}\r\n{{text}}", text: "a\nb", createdAt: referenceDate, timeZone: paris)
    #expect(block == "16:13\na\nb")
}

// MARK: - Separating blocks

@Test(arguments: [
    ("", "- a\n"),
    ("x", "\n\n- a\n"),
    ("x\n", "\n- a\n"),
    ("\n\n", "- a\n"),
])
func appendTextLeavesOneBlankLineBetweenBlocks(tail: String, expected: String) {
    #expect(MarkdownWriter.appendText("- a", toFileEndingWith: Data(tail.utf8)) == expected)
}
