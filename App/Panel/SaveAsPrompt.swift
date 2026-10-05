import AppKit
import UniformTypeIdentifiers

/// The `⌘S` Save panel (T16, ADR-014): the native `NSSavePanel`, in its own window in the middle of
/// the screen, for the note's name and folder. It only picks the file; the note still goes through
/// the outbox, and the folder destination writes it there.
@MainActor
enum SaveAsPrompt {
    private static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText

    /// Activates Otter, because a menu-bar agent's Save panel only comes to the front that way;
    /// `PanelController` hands focus back when the panel hides.
    ///
    /// - Parameters:
    ///   - window: The capture panel. The Save panel is centred on its screen and above it, since the
    ///     capture panel floats.
    ///   - directory: Where the Save panel opens. `nil` leaves it where it was last time.
    ///   - defaultName: The name offered, selected so typing replaces it. `.md` is added.
    /// - Returns: The file to write, or `nil` for Cancel. Replacing an existing file was confirmed in
    ///   the Save panel.
    static func chooseFile(above window: NSWindow, in directory: URL?, defaultName: String) async -> URL? {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [markdown]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = defaultName
        if let directory {
            savePanel.directoryURL = directory
        }
        savePanel.level = max(window.level, .modalPanel)
        if let screen = window.screen {
            let visible = screen.visibleFrame
            savePanel.setFrameOrigin(NSPoint(x: visible.midX - savePanel.frame.width / 2, y: visible.midY - savePanel.frame.height / 2))
        }

        NSApp.activate()
        let response = await withCheckedContinuation { continuation in
            savePanel.begin { response in
                continuation.resume(returning: response)
            }
        }
        return response == .OK ? savePanel.url : nil
    }
}
