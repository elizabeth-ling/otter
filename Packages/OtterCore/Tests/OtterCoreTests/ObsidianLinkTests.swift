import Foundation
import Testing
@testable import OtterCore

private func openURL(vault: String, _ path: String) -> String {
    ObsidianLink.openURL(vault: ObsidianVault(root: URL(fileURLWithPath: "/Users/sam/\(vault)", isDirectory: true)), relativePath: path).absoluteString
}

@Test func openURLDropsTheMarkdownExtension() {
    #expect(openURL(vault: "Notes", "Inbox.md") == "obsidian://open?vault=Notes&file=Inbox")
    #expect(openURL(vault: "Notes", "Diagram.canvas.md") == "obsidian://open?vault=Notes&file=Diagram.canvas")
    #expect(openURL(vault: "Notes", "report.pdf") == "obsidian://open?vault=Notes&file=report.pdf")
}

@Test func openURLEncodesEverythingButUnreservedCharacters() {
    #expect(openURL(vault: "My Notes", "Projects/Q&A = done #1.md") == "obsidian://open?vault=My%20Notes&file=Projects%2FQ%26A%20%3D%20done%20%231")
    #expect(openURL(vault: "Work & Life", "a-b_c.d~e.md") == "obsidian://open?vault=Work%20%26%20Life&file=a-b_c.d~e")
}

@Test func openURLEncodesEmojiAsUTF8() {
    #expect(openURL(vault: "🦦", "Ideas/🎉 Party.md") == "obsidian://open?vault=%F0%9F%A6%A6&file=Ideas%2F%F0%9F%8E%89%20Party")
}
