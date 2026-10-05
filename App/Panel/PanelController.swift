import AppKit
import OtterCore
import os

/// Shows, hides and positions the capture panel (T03, T15), and runs its editor: the keyboard map,
/// submitting, the saved draft (T04), saving under a name with `⌘S` (T16) and pasted or dropped
/// attachments (T09). The panel is built once here and only ordered in and out,
/// so showing it costs one `makeKeyAndOrderFront` (ARCHITECTURE §9).
///
/// Never calls `NSApp.activate` itself: the panel is non-activating, so the app the user came from
/// stays active and gets keyboard focus back on hide. The folder picker (T17) and the Save panel (T16)
/// are the exceptions; see `appToReactivate`.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let fadeDuration: TimeInterval = 0.08

    /// "Keep panel open when clicking elsewhere". Hard-coded until Settings (T10).
    private let keepOpenWhenClickingElsewhere = false

    private let panel: CapturePanel
    private let content = PanelContentView()
    private let frameStore: PanelFrameStore
    private let draftStore: DraftStore
    private let stager: AttachmentStager
    private let destination: @MainActor () -> PanelDestination
    private let refreshDestination: @MainActor () async -> Void
    private let submitNote: @MainActor (_ text: String, _ file: URL?, _ attachments: [StagedAttachment]) async -> Bool
    private let pickFolder: (@MainActor (_ above: NSWindow) async -> Bool)?
    private let pickSaveFile: (@MainActor (_ above: NSWindow, _ defaultName: String) async -> URL?)?

    /// What the header shows now.
    private var shownDestination: PanelDestination?
    /// The note's attachments, staged in `drafts/files/`, in the order they were added.
    private var attachments: [StagedAttachment] = []
    /// Attachments still being copied in; they count towards the limit already.
    private var stagingCount = 0
    /// Why the last paste or drop wasn't attached. Shown in the footer until the next edit or hide.
    private var attachmentNotice: String?

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
    /// The folder picker or the Save panel is open. It takes key, which mustn't hide the panel.
    private var isShowingDialog = false
    /// The app that was frontmost before the folder picker or the Save panel activated Otter. It's
    /// activated again when the panel hides, so focus lands where it would have without them.
    private var appToReactivate: NSRunningApplication?

    private var isShown: Bool { panel.isVisible && !isHiding }

    /// - Parameters:
    ///   - destination: The destination the header shows.
    ///   - refreshDestination: Checks the default destination, so a renamed folder's new name is
    ///     saved before `destination` is read again.
    ///   - attachmentStager: Keeps pasted and dropped files in `drafts/files/` until the note is submitted.
    ///   - submit: Puts the note and its attachments in the outbox, to be written to the file chosen
    ///     in the Save panel if there is one. Returns `true` once it's safe there.
    ///   - chooseFolder: Shows the folder picker above the panel. Returns `true` if the folder changed.
    ///   - chooseSaveFile: Shows the Save panel above the panel, offering `defaultName`.
    ///     Returns the file chosen, or `nil` for Cancel.
    init(
        defaults: UserDefaults = .standard,
        draftStore: DraftStore,
        attachmentStager: AttachmentStager,
        destination: @escaping @MainActor () -> PanelDestination,
        refreshDestination: @escaping @MainActor () async -> Void = {},
        submit: @escaping @MainActor (_ text: String, _ file: URL?, _ attachments: [StagedAttachment]) async -> Bool,
        chooseFolder: (@MainActor (_ above: NSWindow) async -> Bool)? = nil,
        chooseSaveFile: (@MainActor (_ above: NSWindow, _ defaultName: String) async -> URL?)? = nil
    ) {
        frameStore = PanelFrameStore(defaults: defaults)
        self.draftStore = draftStore
        stager = attachmentStager
        self.destination = destination
        self.refreshDestination = refreshDestination
        submitNote = submit
        pickFolder = chooseFolder
        pickSaveFile = chooseSaveFile
        panel = CapturePanel(contentRect: NSRect(origin: .zero, size: PanelPlacement.defaultSize))
        super.init()

        panel.contentView = content
        panel.initialFirstResponder = content.editor.textView
        panel.minSize = PanelPlacement.minimumSize
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        content.editor.onCommand = { [weak self] command in self?.perform(command) }
        content.editor.onTextChange = { [weak self] in self?.saveDraft() }
        content.editor.onAttach = { [weak self] pasted in self?.attach(pasted) }
        content.attachmentChips.onRemove = { [weak self] attachment in self?.removeAttachments([attachment]) }
        if chooseFolder != nil {
            content.onChooseFolder = { [weak self] in self?.chooseFolder() }
        }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.activeSpaceDidChange()
            }
        }

        // Read off the main thread now, so the first show finds it in memory. Then staged files the
        // draft no longer refers to are swept up.
        Task.detached(priority: .utility) {
            let draft = draftStore.load()
            await attachmentStager.removeOrphans(keeping: draft?.attachmentRefs ?? [])
        }
    }

    /// The toggle hotkey (T02 table).
    func toggle() {
        switch PanelToggleAction(panelIsVisible: isShown, panelIsKey: panel.isKeyWindow) {
        case .showAndMakeKey:
            beginVisibleSignpost()
            show()
        case .makeKey:
            guard !isShowingDialog else {
                // The dialog has key; bring it back rather than taking key from it.
                NSApp.activate()
                return
            }
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

        updateDestination()
        // The folder may have been renamed in Finder since; checking it is disk work, so it's done
        // off the show path and the name updated after.
        Task {
            await refreshDestination()
            updateDestination()
        }
        if !didRestoreDraft {
            didRestoreDraft = true
            let draft = draftStore.load()
            content.editor.setText(draft?.text ?? "")
            attachments = stager.staged(draft?.attachmentRefs ?? [])
            content.setAttachments(attachments)
        }
        content.attachmentChips.loadThumbnails()
        updateFooter()
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
        attachmentNotice = nil
        content.attachmentChips.releaseThumbnails()
        if let app = appToReactivate {
            appToReactivate = nil
            // Only if Otter still has focus; a click elsewhere has already put it somewhere else.
            if NSApp.isActive {
                NSApp.yieldActivation(to: app)
                app.activate(from: .current, options: [])
            }
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
        guard !keepOpenWhenClickingElsewhere, isShown, !isShowingDialog else {
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
        // The user clicked into another app, so that's where focus goes.
        appToReactivate = nil
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
        Draft(text: content.editor.text, attachmentRefs: attachments.map(\.attachment))
    }

    /// Every edit. Written once typing pauses.
    private func saveDraft() {
        draftStore.save(currentDraft)
        if attachmentNotice != nil {
            attachmentNotice = nil
            updateFooter()
        }
    }

    // MARK: Attachments (T09)

    /// Copies pasted or dropped files and images into `drafts/files/`, one at a time, and adds a chip
    /// for each. Past the limits, the footer says why and nothing more is attached.
    private func attach(_ pasted: PastedAttachments) {
        Task {
            switch pasted {
            case let .files(urls):
                for url in urls {
                    guard await stage({ [stager] in try await stager.stageFile(at: url) }) else {
                        break
                    }
                }
            case let .image(data, uti):
                await stage { [stager] in try await stager.stageImage(data, uti: uti) }
            }
        }
    }

    /// Returns `false` once nothing more can be attached to this note.
    @discardableResult
    private func stage(_ staging: @escaping @Sendable () async throws -> StagedAttachment) async -> Bool {
        guard attachments.count + stagingCount < AttachmentLimits.maxCount else {
            refuseAttachment(AttachmentError.tooMany)
            return false
        }
        stagingCount += 1
        defer { stagingCount -= 1 }
        do {
            attachments.append(try await staging())
            attachmentNotice = nil
            attachmentsDidChange()
        } catch {
            refuseAttachment(error)
        }
        return true
    }

    private func refuseAttachment(_ error: any Error) {
        NSSound.beep()
        attachmentNotice = error.localizedDescription
        updateFooter()
    }

    /// `✕` on a chip, `⇧⌘⌫`, or a submit that took them. The draft forgets them before their files go.
    private func removeAttachments(_ removed: [Attachment]) {
        let ids = Set(removed.map(\.id))
        attachments.removeAll { ids.contains($0.attachment.id) }
        attachmentsDidChange()
        Task { [stager] in
            await stager.remove(removed)
        }
    }

    /// Saved straight away rather than after a pause: the files are already on disk.
    private func attachmentsDidChange() {
        content.setAttachments(attachments)
        draftStore.saveNow(currentDraft)
        updateFooter()
    }

    /// A refused paste, then a warning about the destination or large files, else the hints.
    private func updateFooter() {
        let warning = AttachmentLimits.footerWarning(
            for: attachments.map(\.attachment),
            destinationName: shownDestination?.name ?? "",
            supportsAttachments: shownDestination?.supportsAttachments ?? true
        )
        content.setFooterWarning(attachmentNotice ?? warning)
    }

    private func perform(_ command: EditorCommand) {
        switch command {
        case let .submit(closeAfter):
            submit(closeAfter: closeAfter)
        case .discard:
            // The text can be brought back with `⌘Z`; the attachments can't.
            content.editor.discardText()
            removeAttachments(attachments.map(\.attachment))
        case let .selectDestination(index):
            Logger.panel.info("Destination \(index + 1, privacy: .public) chosen; destinations are picked here from T10")
        case .openSettings:
            Logger.panel.info("Settings requested; they arrive with T10")
        case .chooseFolder:
            chooseFolder()
        case .saveAs:
            saveAs()
        }
    }

    private func updateDestination() {
        let destination = destination()
        shownDestination = destination
        content.setDestination(name: destination.name, folderPath: destination.folderPath)
        updateFooter()
    }

    /// The header's folder name or `⇧⌘O` (T17).
    private func chooseFolder() {
        guard let pickFolder, isShown, shownDestination?.folderPath != nil else {
            NSSound.beep()
            return
        }
        showDialog { [self] in
            if await pickFolder(panel) {
                updateDestination()
            }
        }
    }

    /// `⌘S`: the Save panel, offering the date and time it opened. Save keeps the panel open for the
    /// next note; Cancel goes back to the text as it was. Nothing to save just beeps.
    private func saveAs() {
        guard let pickSaveFile, isShown, !isNoteEmpty else {
            NSSound.beep()
            return
        }
        let defaultName = FileNamer.defaultTitle(for: Date(), in: .current)
        showDialog { [self] in
            if let file = await pickSaveFile(panel, defaultName) {
                submit(closeAfter: false, saveAs: file)
            }
        }
    }

    /// Runs a dialog that activates Otter: the folder picker (T17) or the Save panel (T16). The panel
    /// stays up while it's open and is key again afterwards, with the text, selection and caret as
    /// they were.
    private func showDialog(_ run: @escaping @MainActor () async -> Void) {
        guard !isShowingDialog else {
            // The dialog hides while Otter is inactive; this brings it back.
            NSApp.activate()
            return
        }
        isShowingDialog = true
        if !NSApp.isActive, let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != NSRunningApplication.current.processIdentifier {
            appToReactivate = frontmost
        }

        Task {
            await run()
            isShowingDialog = false
            guard isShown else {
                return
            }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(content.editor.textView)
        }
    }

    /// No text worth saving and no attachments. A screenshot on its own is a note.
    private var isNoteEmpty: Bool {
        attachments.isEmpty && content.editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `⌘↩`, `⇧⌘↩` and Save in the `⌘S` Save panel (with `file`). The draft is cleared only once the
    /// outbox has the note; if it doesn't, the panel stays open with the text.
    private func submit(closeAfter: Bool, saveAs file: URL? = nil) {
        guard !isSubmitting else {
            return
        }
        let text = content.editor.text
        let submitted = attachments
        guard !isNoteEmpty else {
            if closeAfter {
                hide()
            }
            return
        }

        isSubmitting = true
        Task {
            let saved = await submitNote(text, file, submitted)
            isSubmitting = false
            guard saved else {
                return
            }
            // The outbox has taken the attachments' files. Text typed, and files attached, while the
            // note was being saved stay, rather than being lost with it.
            let submittedIDs = Set(submitted.map(\.attachment.id))
            attachments.removeAll { submittedIDs.contains($0.attachment.id) }
            content.setAttachments(attachments)
            if content.editor.text == text {
                content.editor.clear()
            }
            if isNoteEmpty {
                draftStore.clear()
            } else {
                draftStore.saveNow(currentDraft)
            }
            updateFooter()
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

/// The destination shown in the panel header.
struct PanelDestination {
    var name: String
    /// The full path, for a folder destination; its name then opens the folder picker (T17).
    var folderPath: String?
    /// `false` puts a warning in the footer while the note has attachments (T09).
    var supportsAttachments = true
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
