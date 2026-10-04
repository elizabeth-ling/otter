import AppKit
import OtterCore
import os

/// Shows, hides and positions the capture panel (T03). The panel is built once here and only
/// ordered in and out, so showing it costs one `makeKeyAndOrderFront` (ARCHITECTURE §9).
///
/// Never calls `NSApp.activate`: the panel is non-activating, so the app the user came from stays
/// active and gets keyboard focus back on hide.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let widthKey = "panelWidth"
    static let fadeDuration: TimeInterval = 0.08

    /// "Keep panel open when clicking elsewhere". Hard-coded until Settings (T10).
    private let keepOpenWhenClickingElsewhere = false

    private let panel: CapturePanel
    private let content = PanelContentView()
    private let defaults: UserDefaults
    private let destinationName: @MainActor () -> String

    /// Fading out: still on screen but already counted as hidden.
    private var isHiding = false
    /// Bumped on every show and hide, so a stale fade-out doesn't order out a re-shown panel.
    private var fadeGeneration = 0
    /// A `hotkey→visible` interval is open and ends when the panel becomes key.
    private var awaitingVisible = false

    private var isShown: Bool { panel.isVisible && !isHiding }

    init(defaults: UserDefaults = .standard, destinationName: @escaping @MainActor () -> String) {
        self.defaults = defaults
        self.destinationName = destinationName
        panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: PanelPlacement.defaultWidth, height: PanelContentView.barHeight))
        super.init()

        panel.contentView = content
        panel.initialFirstResponder = content.editor
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        content.onPreferredHeightChange = { [weak self] in self?.updateHeight() }
    }

    /// The toggle hotkey (T02 table).
    func toggle() {
        switch PanelToggleAction(panelIsVisible: isShown, panelIsKey: panel.isKeyWindow) {
        case .showAndMakeKey:
            beginVisibleSignpost()
            show()
        case .makeKey:
            beginVisibleSignpost()
            panel.makeKeyAndOrderFront(nil)
            focusEditor()
        case .hide:
            hide()
        }
    }

    func show() {
        guard !isShown else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        fadeGeneration += 1
        let wasHiding = isHiding
        isHiding = false

        content.setDestinationName(destinationName())
        content.setReduceTransparency(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        if !wasHiding {
            setFrame(PanelPlacement.frame(width: savedWidth, height: content.preferredHeight, in: screenUnderPointer().visibleFrame))
        }

        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !wasHiding {
            panel.alphaValue = animate ? 0 : 1
        }
        panel.makeKeyAndOrderFront(nil)
        focusEditor()
        fade(to: 1, animate: animate, completion: nil)
    }

    func hide() {
        guard isShown else {
            return
        }
        fadeGeneration += 1
        let generation = fadeGeneration
        isHiding = true

        fade(to: 0, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { [weak self] in
            guard let self, generation == fadeGeneration else {
                return
            }
            isHiding = false
            panel.orderOut(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard awaitingVisible else {
            return
        }
        awaitingVisible = false
        os_signpost(.end, log: Signpost.log, name: Signpost.hotkeyToVisible)
    }

    /// Clicking elsewhere closes the panel.
    func windowDidResignKey(_ notification: Notification) {
        guard !keepOpenWhenClickingElsewhere else {
            return
        }
        hide()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        defaults.set(Double(panel.frame.width), forKey: Self.widthKey)
        panel.invalidateShadow()
    }

    // MARK: - Private

    private var savedWidth: CGFloat {
        let width = defaults.double(forKey: Self.widthKey)
        return width > 0 ? width : PanelPlacement.defaultWidth
    }

    /// Begun here rather than on every key press, so presses that hide the panel leave no open interval.
    private func beginVisibleSignpost() {
        awaitingVisible = true
        os_signpost(.begin, log: Signpost.log, name: Signpost.hotkeyToVisible)
    }

    private func focusEditor() {
        panel.makeFirstResponder(content.editor)
        content.moveCaretToEnd()
    }

    private func screenUnderPointer() -> NSScreen {
        let screens = NSScreen.screens
        if let index = PanelPlacement.screenIndex(containing: NSEvent.mouseLocation, screenFrames: screens.map(\.frame)) {
            return screens[index]
        }
        // `screens` is empty only without a display; `main` covers that too.
        return NSScreen.main ?? screens[0]
    }

    /// Only the width is user-resizable; the height follows the content.
    private func setFrame(_ frame: NSRect) {
        panel.minSize = NSSize(width: PanelPlacement.minimumWidth, height: frame.height)
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: frame.height)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// Grows or shrinks downward, keeping the top edge where it is.
    private func updateHeight() {
        var frame = panel.frame
        let height = content.preferredHeight
        frame.origin.y += frame.height - height
        frame.size.height = height
        if let visible = panel.screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        setFrame(frame)
    }

    private func fade(to alpha: CGFloat, animate: Bool, completion: (@MainActor () -> Void)?) {
        guard animate else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated {
                completion?()
            }
        }
    }
}
