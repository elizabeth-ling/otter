import AppKit

/// The Spotlight-style floating panel (ARCHITECTURE §6). Non-activating, so showing it leaves the
/// frontmost app active and hiding it hands keyboard focus straight back. Created once by
/// `PanelController` and only ordered in and out.
final class CapturePanel: NSPanel {
    /// `Esc`. T04's editor routes its own `cancelOperation(_:)` here too.
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        // `.nonactivatingPanel` must be in the mask at init: toggling it later has known quirks.
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Otter"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        level = .floating
        // Current Space, over full-screen apps, never in ⌘` cycling.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        // The content view draws the rounded background; the shadow follows its alpha.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // `PanelController` fades it instead.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
