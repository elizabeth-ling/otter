import AppKit
import OtterCore
import os

/// Shows, hides and positions the capture panel (T03, T15). The panel is built once here and only
/// ordered in and out, so showing it costs one `makeKeyAndOrderFront` (ARCHITECTURE §9).
///
/// Never calls `NSApp.activate`: the panel is non-activating, so the app the user came from stays
/// active and gets keyboard focus back on hide.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let fadeDuration: TimeInterval = 0.08

    /// "Keep panel open when clicking elsewhere". Hard-coded until Settings (T10).
    private let keepOpenWhenClickingElsewhere = false

    private let panel: CapturePanel
    private let content = PanelContentView()
    private let frameStore: PanelFrameStore
    private let destinationName: @MainActor () -> String

    /// Fading out: still on screen but already counted as hidden.
    private var isHiding = false
    /// Bumped on every show and hide, so a stale fade-out doesn't order out a re-shown panel.
    private var fadeGeneration = 0
    /// A `hotkey→visible` interval is open and ends when the panel becomes key.
    private var awaitingVisible = false
    /// Otter is setting the frame itself, so `windowDidMove` mustn't save it as the user's position.
    private var isPlacing = false

    private var isShown: Bool { panel.isVisible && !isHiding }

    init(defaults: UserDefaults = .standard, destinationName: @escaping @MainActor () -> String) {
        frameStore = PanelFrameStore(defaults: defaults)
        self.destinationName = destinationName
        panel = CapturePanel(contentRect: NSRect(origin: .zero, size: PanelPlacement.defaultSize))
        super.init()

        panel.contentView = content
        panel.initialFirstResponder = content.editor
        panel.minSize = PanelPlacement.minimumSize
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
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
        // Placed while still ordered out, so the move isn't mistaken for a drag. A press during the
        // fade-out brings the panel back where it is.
        if !wasHiding {
            place(on: screenUnderPointer())
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

    /// Menu bar "Reset Panel Position" (T10 moves it to Settings › General): default size and
    /// placement on every display from the next show.
    @objc func resetPanelPosition(_ sender: Any?) {
        frameStore.reset()
        if isShown, let screen = panel.screen {
            place(on: screen)
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

    /// A drag of the header or footer. Live resizes from the top or left edge move the window too;
    /// `windowDidEndLiveResize` saves those once at the end.
    func windowDidMove(_ notification: Notification) {
        guard !isPlacing, isShown, !panel.inLiveResize else {
            return
        }
        savePosition()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        frameStore.saveSize(panel.frame.size)
        savePosition()
        panel.invalidateShadow()
    }

    // MARK: - Private

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

    /// The saved size, at this display's saved position or the default placement, clamped on-screen.
    private func place(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let size = frameStore.size ?? PanelPlacement.defaultSize
        let offset = screen.displayUUID.flatMap { frameStore.offset(forDisplay: $0) }
        let frame = PanelPlacement.frame(size: size, offset: offset, in: visible)

        panel.maxSize = PanelPlacement.clampedSize(PanelPlacement.maximumSize, in: visible)
        isPlacing = true
        panel.setFrame(frame, display: true)
        isPlacing = false
        panel.invalidateShadow()
    }

    /// Saved against the display holding most of the panel, as an offset from its visible frame.
    private func savePosition() {
        guard let screen = panel.screen, let uuid = screen.displayUUID else {
            return
        }
        frameStore.saveOffset(PanelPlacement.offset(of: panel.frame, in: screen.visibleFrame), forDisplay: uuid)
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

private extension NSScreen {
    /// Stable across reboots and reconnects, unlike `NSScreenNumber` (the `CGDirectDisplayID`).
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
