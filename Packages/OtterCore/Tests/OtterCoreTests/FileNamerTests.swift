import Foundation
import Testing
@testable import OtterCore

private let paris = TimeZone(identifier: "Europe/Paris")!

// MARK: - Titles

@Test(arguments: [
    ("Buy oat milk", "Buy oat milk"),
    ("# Heading", "Heading"),
    ("### Deep heading", "Deep heading"),
    ("#hashtag idea", "hashtag idea"),
    ("- list item", "list item"),
    ("* starred", "starred"),
    ("> quoted", "quoted"),
    ("- [ ] buy milk", "buy milk"),
    ("- [x] done thing", "done thing"),
    ("> # quoted heading", "quoted heading"),
])
func titleStripsLeadingMarkdownMarkers(text: String, expected: String) {
    #expect(FileNamer.title(from: text) == expected)
}

@Test func titleComesFromTheFirstNonEmptyLine() {
    #expect(FileNamer.title(from: "\n   \n  Second line wins  \nThird") == "Second line wins")
    #expect(FileNamer.title(from: "\r\nWindows line\r\nnext") == "Windows line")
}

@Test func titleRemovesIllegalCharactersAndCollapsesWhitespace() {
    #expect(FileNamer.title(from: #"Call: Sam / "Q4" <deck> | #1 ^ [draft] a\b *? done"#) == "Call Sam Q4 deck 1 draft ab done")
    #expect(FileNamer.title(from: "tabs\tand   spaces") == "tabs and spaces")
}

@Test func titleRemovesControlCharacters() {
    #expect(FileNamer.title(from: "bell\u{07}ring\u{00}null\u{1B}esc") == "bellringnullesc")
}

@Test func titleKeepsEmoji() {
    #expect(FileNamer.title(from: "🎉 Party for 👨‍👩‍👧 at 🇨🇦") == "🎉 Party for 👨‍👩‍👧 at 🇨🇦")
}

@Test(arguments: ["", "   \n\t\n", "???///", "# ", "#", "- [ ] ", "[]^|", "\u{07}\u{08}"])
func titleFallsBackToQuickNote(text: String) {
    #expect(FileNamer.title(from: text) == "Quick note")
}

@Test func longTitleIsCutAtAWordBoundary() {
    let text = "The quick brown fox jumps over the lazy dog and keeps on running far away"
    let title = FileNamer.title(from: text)
    #expect(title == "The quick brown fox jumps over the lazy dog and keeps on")
    #expect(title.count <= 60)
}

@Test func titleExactlyAtTheLimitIsKept() {
    let text = String(repeating: "a", count: 30) + " " + String(repeating: "b", count: 29)
    #expect(FileNamer.title(from: text) == text)
    #expect(FileNamer.title(from: text + " more") == text)
}

@Test func longSingleWordIsCutAtSixtyCharacters() {
    #expect(FileNamer.title(from: String(repeating: "x", count: 100)) == String(repeating: "x", count: 60))
}

@Test func longEmojiTitleIsCutByCharacterNotScalar() {
    let title = FileNamer.title(from: String(repeating: "👨‍👩‍👧", count: 80))
    #expect(title.count == 60)
    #expect(title.allSatisfy { $0 == "👨‍👩‍👧" })
}

// MARK: - File names

@Test func baseNameFillsTheTemplateInTheCaptureTimeZone() {
    // referenceDate is 2026-09-21 14:13:20 UTC: 16:13 in Paris, the next day in Tokyo.
    #expect(FileNamer.baseName(template: "{date} {time} {title}", text: "Buy oat milk", date: referenceDate, timeZone: paris) == "2026-09-21 1613 Buy oat milk")
    let lateEvening = referenceDate.addingTimeInterval(9 * 3600)
    #expect(FileNamer.baseName(template: "{date} {time}", text: "x", date: lateEvening, timeZone: TimeZone(identifier: "Asia/Tokyo")!) == "2026-09-22 0813")
}

@Test(arguments: [
    "../../etc/passwd",
    "/etc/passwd",
    "..",
    "~/Library/LaunchAgents/evil.plist",
    "a/../../b",
    "C:\\Windows\\System32",
])
func baseNameNeverLeavesTheFolder(text: String) {
    for template in ["{title}", "{date} {time} {title}"] {
        let base = FileNamer.baseName(template: template, text: text, date: referenceDate, timeZone: paris)
        #expect(!base.contains("/"))
        #expect(!base.contains(":"))
        #expect(!base.hasPrefix("."))
        #expect(!base.isEmpty)
        let file = URL(fileURLWithPath: "/folder").appendingPathComponent(FileNamer.fileName(base: base, number: 1))
        #expect(file.deletingLastPathComponent().path == "/folder")
    }
}

@Test func baseNameSanitizesTheTemplateToo() {
    #expect(FileNamer.baseName(template: "notes/{title}: draft", text: "Plan", date: referenceDate, timeZone: paris) == "notesPlan draft")
    #expect(FileNamer.baseName(template: "...{title}", text: "Plan", date: referenceDate, timeZone: paris) == "Plan")
    #expect(FileNamer.baseName(template: "{title}", text: "...", date: referenceDate, timeZone: paris) == "Quick note")
}

@Test func baseNameFitsTheFileNameLimit() {
    let template = String(repeating: "👨‍👩‍👧", count: 40) + " {title}"
    let base = FileNamer.baseName(template: template, text: String(repeating: "👨‍👩‍👧", count: 60), date: referenceDate, timeZone: paris)
    #expect(base.utf8.count <= FileNamer.maxBaseNameBytes)
    #expect(FileNamer.fileName(base: base, number: 999).utf8.count <= 255)
}

@Test func collisionsGetANumberSuffix() {
    #expect(FileNamer.fileName(base: "Note", number: 1) == "Note.md")
    #expect(FileNamer.fileName(base: "Note", number: 2) == "Note 2.md")
    #expect(FileNamer.fileName(base: "Note", number: 3) == "Note 3.md")
}

// MARK: - Paths from settings

@Test func safeRelativePathAcceptsPathsInsideTheFolder() {
    #expect(FileNamer.safeRelativePath("") == [])
    #expect(FileNamer.safeRelativePath("Inbox") == ["Inbox"])
    #expect(FileNamer.safeRelativePath("Notes/Inbox/") == ["Notes", "Inbox"])
    #expect(FileNamer.safeRelativePath("a//b") == ["a", "b"])
    #expect(FileNamer.safeRelativePath("Inbox.md") == ["Inbox.md"])
    #expect(FileNamer.safeRelativePath("..hidden..") == ["..hidden.."])
}

@Test(arguments: ["..", "../Inbox", "Inbox/../..", "a/./b", "/Users/me", "~/Documents", "In\u{00}box", "In\nbox"])
func safeRelativePathRejectsEscapes(path: String) {
    #expect(FileNamer.safeRelativePath(path) == nil)
}
