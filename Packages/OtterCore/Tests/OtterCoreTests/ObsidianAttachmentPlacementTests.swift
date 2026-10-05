import Foundation
import Testing
@testable import OtterCore

private let vault = ObsidianVault(root: URL(fileURLWithPath: "/Vaults/Notes", isDirectory: true))
private let notePath = "Projects/Otter/2026-10-04 0912 Call Sam.md"
private let image = "Pasted image 20261004091200.png"

private func place(_ fileName: String = image, folder: String, markdown: Bool = false, format: ObsidianVaultSettings.LinkFormat = .shortest, note: String = notePath) -> ObsidianAttachmentPlacement {
    let settings = ObsidianVaultSettings(attachmentFolderPath: folder, useMarkdownLinks: markdown, newLinkFormat: format)
    return ObsidianAttachmentPlacement(vault: vault, settings: settings, notePath: note, fileName: fileName)
}

@Test(arguments: [
    ("/", "/Vaults/Notes", "![[Pasted image 20261004091200.png]]", "![](../../Pasted%20image%2020261004091200.png)"),
    ("./", "/Vaults/Notes/Projects/Otter", "![[Pasted image 20261004091200.png]]", "![](Pasted%20image%2020261004091200.png)"),
    ("./assets", "/Vaults/Notes/Projects/Otter/assets", "![[Pasted image 20261004091200.png]]", "![](assets/Pasted%20image%2020261004091200.png)"),
    ("Assets/Images", "/Vaults/Notes/Assets/Images", "![[Pasted image 20261004091200.png]]", "![](../../Assets/Images/Pasted%20image%2020261004091200.png)"),
])
func placesAnImageForEachFolderSetting(folder: String, directory: String, wikilink: String, markdown: String) {
    #expect(place(folder: folder).directory.path == directory)
    #expect(place(folder: folder).embed == wikilink)
    #expect(place(folder: folder, markdown: true).directory.path == directory)
    #expect(place(folder: folder, markdown: true).embed == markdown)
}

@Test(arguments: [
    ("/", "![[Pasted image 20261004091200.png]]"),
    ("./", "![[Projects/Otter/Pasted image 20261004091200.png]]"),
    ("./assets", "![[Projects/Otter/assets/Pasted image 20261004091200.png]]"),
    ("Assets/Images", "![[Assets/Images/Pasted image 20261004091200.png]]"),
])
func absoluteWikilinksUseTheVaultPath(folder: String, embed: String) {
    #expect(place(folder: folder, format: .absolute).embed == embed)
}

@Test func relativeWikilinksUseThePathFromTheNote() {
    #expect(place(folder: "Assets/Images", format: .relative).embed == "![[../../Assets/Images/Pasted image 20261004091200.png]]")
    #expect(place(folder: "./assets", format: .relative).embed == "![[assets/Pasted image 20261004091200.png]]")
}

@Test(arguments: ["/", "./", "./assets", "Assets/Images"])
func aHashInTheNameAlwaysGetsAnEncodedMarkdownLink(folder: String) {
    let wikilink = place("Plan #2.png", folder: folder)
    let markdown = place("Plan #2.png", folder: folder, markdown: true)
    #expect(wikilink.embed == markdown.embed)
    #expect(markdown.embed.hasPrefix("![]("))
    #expect(markdown.embed.hasSuffix("Plan%20%232.png)"))
    #expect(!markdown.embed.contains("#"))
    #expect(!markdown.embed.contains(" "))
}

@Test func filesThatArentImagesAreLinkedNotEmbedded() {
    #expect(place("spec v2.pdf", folder: "./assets").embed == "[[spec v2.pdf]]")
    #expect(place("spec v2.pdf", folder: "./assets", markdown: true).embed == "[spec v2.pdf](assets/spec%20v2.pdf)")
    #expect(place("notes [old].txt", folder: "./", markdown: true).embed == #"[notes \[old\].txt](notes%20%5Bold%5D.txt)"#)
}

@Test func aNoteAtTheVaultRootLinksWithoutDotDot() {
    #expect(place(folder: "/", markdown: true, note: "Call Sam.md").embed == "![](Pasted%20image%2020261004091200.png)")
    #expect(place(folder: "./", markdown: true, note: "Call Sam.md").directory.path == "/Vaults/Notes")
}

@Test(arguments: ["../Elsewhere", "Assets/../../Out", "./../up", "/Users/someone/Pictures", "~/Pictures", "./sub/./x"])
func folderSettingsThatLeaveTheVaultFallBackToTheRoot(folder: String) {
    #expect(place(folder: folder).directory.path == "/Vaults/Notes")
    #expect(place(folder: folder, markdown: true).embed == "![](../../Pasted%20image%2020261004091200.png)")
}
