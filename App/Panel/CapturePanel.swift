import AppKit

/// The floating sticky-note panel (ARCHITECTURE §6, ADR-012). Non-activating, so showing it leaves the
/// frontmost app active and hiding it hands keyboard focus straight back. Created once by
/// `PanelController` and only ordered in and out.
final class CapturePanel: NSPanel {
    /// `Esc`. T04's editor routes its own `cancelOperation(_:)` here too.
    var onCancel: (() -> Void)?
    /// Whether a key-down is the toggle hotkey's chord. See `sendEvent(_:)`.
    var isToggleChord: ((NSEvent) -> Bool)?
    /// The toggle chord was pressed while the panel had keyboard focus.
    var onToggleChord: (() -> Void)?

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

    /// While the panel has keyboard focus the toggle hotkey is suspended and its chord arrives
    /// here as a key-down (`HotkeyService.setToggleSuspended(_:)`). Caught before the editor, which
    /// would type it. macOS's autocorrect bubble passes key presses on to here too. Repeats, from
    /// the chord held down past the show, are swallowed.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, isToggleChord?(event) == true {
            if !event.isARepeat {
                onToggleChord?()
            }
            return
        }
        super.sendEvent(event)
    }
}
