import AppKit
import OtterCore
import os

/// Shows, hides and positions the capture panel (T03, T15), and runs its editor: the keyboard map,
/// submitting and the saved draft (T04). The panel is built once here and only ordered in and out,
/// so showing it costs one `makeKeyAndOrderFront` (ARCHITECTURE §9).
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
    private let draftStore: DraftStore
    private let destinationName: @MainActor () -> String
    private let refreshDestination: @MainActor () async -> Void
    private let submitNote: @MainActor (_ text: String) async -> Bool

    /// Fading out: still on screen but already counted as hidden.
    private var isHiding = false
    /// Bumped on every show and hide, so a stale fade-out doesn't order out a re-shown panel.
    private var fadeGeneration = 0
    /// A `hotkey→visible` interval is open and ends when the panel becomes key.
    private var awaitingVisible = false
    /// Otter is setting the frame itself, so `windowDidMove` mustn't save it as the user's position.
    private var isPlacing = false
    /// The saved draft is put in the editor on the first show; after that the editor keeps its text.
    private var didRestoreDraft = false
    /// A note is on its way to the outbox; further submits wait for it.
    private var isSubmitting = false
    /// When the shown panel last resigned key, and when the active Space last changed (`systemUptime`).
    /// Close together they're a Space switch, not a click elsewhere (`PanelSpaceSwitch`).
    private var lastResignKeyAt: TimeInterval?
    private var lastSpaceChangeAt: TimeInterval?
    private var spaceChangeObserver: (any NSObjectProtocol)?

    private var isShown: Bool { panel.isVisible && !isHiding }

    /// - Parameters:
    ///   - refreshDestination: Checks the default destination, so a renamed folder's new name is
    ///     saved before `destinationName` is read again.
    ///   - submit: Puts the note in the outbox. Returns `true` once it's safe there.
    init(
        defaults: UserDefaults = .standard,
        draftStore: DraftStore,
        destinationName: @escaping @MainActor () -> String,
        refreshDestination: @escaping @MainActor () async -> Void = {},
        submit: @escaping @MainActor (_ text: String) async -> Bool
    ) {
        frameStore = PanelFrameStore(defaults: defaults)
        self.draftStore = draftStore
        self.destinationName = destinationName
        self.refreshDestination = refreshDestination
        submitNote = submit
        panel = CapturePanel(contentRect: NSRect(origin: .zero, size: PanelPlacement.defaultSize))
        super.init()

        panel.contentView = content
        panel.initialFirstResponder = content.editor.textView
        panel.minSize = PanelPlacement.minimumSize
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        content.editor.onCommand = { [weak self] command in self?.perform(command) }
        content.editor.onTextChange = { [weak self] in self?.saveDraft() }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.activeSpaceDidChange()
            }
        }

        // Read off the main thread now, so the first show finds it in memory.
        DispatchQueue.global(qos: .utility).async {
            _ = draftStore.load()
        }
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
        lastResignKeyAt = nil
        fadeGeneration += 1
        let wasHiding = isHiding
        isHiding = false

        content.setDestinationName(destinationName())
        // The folder may have been renamed in Finder since; checking it is disk work, so it's done
        // off the show path and the name updated after.
        Task {
            await refreshDestination()
            content.setDestinationName(destinationName())
        }
        if !didRestoreDraft {
            didRestoreDraft = true
            content.editor.setText(draftStore.load()?.text ?? "")
        }
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
        if didRestoreDraft {
            draftStore.saveNow(currentDraft)
        }

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

    /// Writes the draft to disk before the app quits.
    func flushDraft() {
        draftStore.flush()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard awaitingVisible else {
            return
        }
        awaitingVisible = false
        os_signpost(.end, log: Signpost.log, name: Signpost.hotkeyToVisible)
    }

    /// Clicking elsewhere closes the panel. Switching Spaces doesn't, although it also takes key.
    func windowDidResignKey(_ notification: Notification) {
        // Not shown: an `Esc` or hotkey hide is ordering it out.
        guard !keepOpenWhenClickingElsewhere, isShown else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        Logger.panel.debug("Panel resigned key")
        if PanelSpaceSwitch.isSpaceSwitch(resignedAt: now, spaceChangedAt: lastSpaceChangeAt) {
            // The Space changed first. Take key back once AppKit has finished handing it over.
            DispatchQueue.main.async { [weak self] in
                self?.restoreAfterSpaceSwitch()
            }
            return
        }
        lastResignKeyAt = now
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

    /// A resign-key just before this hid the panel: bring it back.
    private func activeSpaceDidChange() {
        let now = ProcessInfo.processInfo.systemUptime
        Logger.panel.debug("Active Space changed")
        if !isShown, PanelSpaceSwitch.isSpaceSwitch(resignedAt: lastResignKeyAt, spaceChangedAt: now) {
            restoreAfterSpaceSwitch()
        } else {
            lastSpaceChangeAt = now
        }
    }

    /// Back on screen and key where it was, cancelling any fade-out. Unlike `show()` it isn't
    /// re-placed under the pointer and the caret stays put.
    private func restoreAfterSpaceSwitch() {
        lastResignKeyAt = nil
        lastSpaceChangeAt = nil
        fadeGeneration += 1
        isHiding = false
        panel.makeKeyAndOrderFront(nil)
        fade(to: 1, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, completion: nil)
    }

    private func focusEditor() {
        panel.makeFirstResponder(content.editor.textView)
        content.editor.moveCaretToEnd()
    }

    private var currentDraft: Draft {
        Draft(text: content.editor.text)
    }

    /// Every edit. Written once typing pauses.
    private func saveDraft() {
        draftStore.save(currentDraft)
    }

    private func perform(_ command: EditorCommand) {
        switch command {
        case let .submit(closeAfter):
            submit(closeAfter: closeAfter)
        case .discard:
            // Undoable; the edit saves the now-empty draft. Attachments join in T09.
            content.editor.discardText()
        case let .selectDestination(index):
            Logger.panel.info("Destination \(index + 1, privacy: .public) chosen; destinations are picked here from T10")
        case .openSettings:
            Logger.panel.info("Settings requested; they arrive with T10")
        }
    }

    /// `⌘↩` and `⇧⌘↩`. The draft is cleared only once the outbox has the note; if it doesn't, the
    /// panel stays open with the text.
    private func submit(closeAfter: Bool) {
        guard !isSubmitting else {
            return
        }
        let text = content.editor.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if closeAfter {
                hide()
            }
            return
        }

        isSubmitting = true
        Task {
            let saved = await submitNote(text)
            isSubmitting = false
            guard saved else {
                return
            }
            // Text typed while the note was being saved stays, rather than being lost with it.
            if content.editor.text == text {
                content.editor.clear()
                draftStore.clear()
            }
            if closeAfter {
                hide()
            }
        }
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
