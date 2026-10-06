import AppKit
import OtterCore

/// What the panel's keyboard map asks for (UX_SPEC §2). `PanelController` acts on it.
enum EditorCommand {
    /// `⌘↩` closes after saving; `⇧⌘↩` keeps the panel open for the next note.
    case submit(closeAfter: Bool)
    /// `⇧⌘⌫`.
    case discard
    /// `⌘1…⌘9`, zero-based.
    case selectDestination(index: Int)
    /// `⌘,`.
    case openSettings
    /// `⇧⌘O`: change the save folder, as clicking the folder name in the header does (T17).
    case chooseFolder
    /// `⌘S`: save the note under a name and in a folder picked in the Save panel (T16).
    case saveAs
}

/// Files or an image pasted or dropped into the editor (T09). Text is pasted by the editor itself.
enum PastedAttachments {
    case files([URL])
    case image(Data, uti: String)
}

/// The panel's plain-text editor (T04, ADR-007): an `NSTextView` in a scroll view that fills the text
/// area. The panel keeps its size; long text scrolls. Inline Markdown is styled and its markers
/// hidden on screen only (ADR-016); the text stays plain Markdown.
final class EditorView: NSScrollView {
    /// The keyboard map's commands.
    var onCommand: ((EditorCommand) -> Void)? {
        get { textView.onCommand }
        set { textView.onCommand = newValue }
    }

    /// Files and images pasted (`⌘V`) or dropped (T09).
    var onAttach: ((PastedAttachments) -> Void)? {
        get { textView.onAttach }
        set { textView.onAttach = newValue }
    }

    /// Every edit by the user, including undo and discard. Not called for `setText` or `clear`.
    var onTextChange: (() -> Void)? {
        get { textView.onTextChange }
        set { textView.onTextChange = newValue }
    }

    /// Takes keyboard focus when the panel shows.
    let textView = EditorTextView()

    var text: String { textView.string }

    /// The editor's font (the Font setting). Changing it restyles the text.
    var font: NSFont {
        get { styler.font }
        set {
            textView.font = newValue
            styler.font = newValue
            textView.listMarkersDidChange()
        }
    }

    private let styler: MarkdownStyler

    init(font: NSFont, inset: CGFloat, placeholder: String) {
        styler = MarkdownStyler(font: font)
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay

        textView.placeholder = placeholder
        textView.font = font
        textView.textColor = .labelColor
        textView.drawsBackground = false
        // Plain text only: pastes from Safari and the like arrive as plain text (ADR-007).
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        // Off by default; a setting can turn them on later.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: inset, height: inset)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Note")
        documentView = textView

        // Display-only styling: attributes on the text storage, never characters (ADR-016).
        styler.textView = textView
        textView.styler = styler
        if let textStorage = textView.textStorage {
            styler.attach(to: textStorage)
        }
        textView.typingAttributes = styler.baseAttributes
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Dragging in the text selects text; it never moves the window.
    override var mouseDownCanMoveWindow: Bool { false }

    /// Keeps the text view at least as tall as the visible area, so a click below the last line lands
    /// in the text (caret, selection) rather than on the window background, which would drag the panel.
    override func tile() {
        super.tile()
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.sizeToFit()
    }

    /// Replaces the text without an undo step, e.g. restoring the saved draft.
    func setText(_ text: String) {
        textView.resetHiddenMarkerState()
        textView.string = text
        styler.restyleAll()
        textView.typingAttributes = styler.baseAttributes
        textView.undoManager?.removeAllActions(withTarget: textView)
        textView.needsDisplay = true
    }

    /// Empties the editor once its note is saved. Not undoable: the note has gone to the outbox.
    func clear() {
        setText("")
    }

    /// `⇧⌘⌫`: deletes everything as one edit, so `⌘Z` brings it back.
    func discardText() {
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        guard all.length > 0, textView.shouldChangeText(in: all, replacementString: "") else {
            return
        }
        textView.replaceCharacters(in: all, with: "")
        textView.undoManager?.setActionName("Discard")
        textView.didChangeText()
    }

    /// Puts the caret at the end without selecting, so typing appends to what's there.
    func moveCaretToEnd() {
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        textView.setSelectedRange(end)
        textView.scrollRangeToVisible(end)
    }
}

/// A plain-text `NSTextView` that draws a placeholder while empty and turns the panel's shortcuts into
/// `EditorCommand`s. Caret movement, selection, deleting, typing over a selection, line breaks and
/// copy treat hidden Markdown markers as part of their span (ADR-016, `HiddenMarkerEditing`).
final class EditorTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    fileprivate var onCommand: ((EditorCommand) -> Void)?
    fileprivate var onTextChange: (() -> Void)?
    fileprivate var onAttach: ((PastedAttachments) -> Void)?
    /// Styles the text and knows its spans. Set by `EditorView`.
    fileprivate var styler: MarkdownStyler?

    /// A caret position snapping leaves alone, after a closing marker: one just typed, or `⌘B`…
    /// at a span's end. Cleared by the next different selection.
    private var pinnedCaret: Int?
    /// Set by `⌘K` just before it selects a link's URL, so the link shows raw.
    private var revealsNextLink = false
    /// Whether the selection is in a revealed link's URL. Only `⌘K` reveals a link; a click into
    /// a hidden URL snaps out of it like any hidden marker.
    private var isLinkRevealed = false
    /// The fixed end of a selection extended with `⇧←` / `⇧→`.
    private var selectionAnchor: Int?
    private var isExtendingSelection = false
    /// Set while a movement runs only to measure what a word or line delete would remove.
    private var isMeasuring = false
    /// Set while an edit's computed selection is applied: list markers on its lines count as
    /// revealed, so it isn't snapped as an arrival.
    private var isSelectingEditResult = false
    /// SF Symbol boxes for tasks, at the editor font's size.
    private var checkboxImages: (pointSize: CGFloat, empty: NSImage, checked: NSImage)?

    /// Dragging in the text selects text; it never moves the window.
    override var mouseDownCanMoveWindow: Bool { false }

    /// `NSTextView` turns `Esc` into "complete"; hide the panel instead.
    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }

    // MARK: Paste and drop (T09)

    /// Files and images become attachments; anything else is pasted as plain text. Over a styled
    /// selection, or with line breaks inside a span, the text is placed by the hidden-marker rules.
    override func paste(_ sender: Any?) {
        if let attachments = Self.attachments(on: .general) {
            onAttach?(attachments)
            return
        }
        if !hasMarkedText(), let text = NSPasteboard.general.string(forType: .string), let rules = hiddenMarkerRules() {
            let selection = selectedRange()
            let edit = rules.replacement(of: selection, with: text)
            if edit.range != selection || edit.replacement != text {
                apply(edit, actionName: "Paste")
                return
            }
        }
        super.paste(sender)
    }

    /// Lets files and images be dropped, not only text.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL] + PasteRules.imageTypes.map { NSPasteboard.PasteboardType($0) }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.kind(of: sender.draggingPasteboard) == .text ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.kind(of: sender.draggingPasteboard) == .text ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let attachments = Self.attachments(on: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        onAttach?(attachments)
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        listMarkersDidChange()
        onTextChange?()
    }

    /// The panel's shortcuts. Key equivalents reach the window before `keyDown`, so these never
    /// insert text. While an input method is composing, every key goes to it instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, !hasMarkedText() else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if Self.returnKeyCodes.contains(event.keyCode) {
            switch flags {
            case .command:
                onCommand?(.submit(closeAfter: true))
                return true
            case [.command, .shift]:
                onCommand?(.submit(closeAfter: false))
                return true
            default:
                return super.performKeyEquivalent(with: event)
            }
        }
        if event.keyCode == Self.deleteKeyCode, flags == [.command, .shift] {
            onCommand?(.discard)
            return true
        }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, key) {
        case (.command, "1"..."9"):
            if let digit = Int(key) {
                onCommand?(.selectDestination(index: digit - 1))
            }
            return true
        case (.command, ","):
            onCommand?(.openSettings)
            return true
        case ([.command, .shift], "o"):
            onCommand?(.chooseFolder)
            return true
        case (.command, "s"):
            // Handled here so it never reaches `saveDocument:`.
            onCommand?(.saveAs)
            return true
        default:
            break
        }
        if let style = Self.formattingShortcuts[EditShortcut(flags: flags.rawValue, key: key)] {
            applyFormatting(style)
            return true
        }
        // `⌘L` toggles a task, `⇧⌘8` a bullet (T18). The `8` key by code: some layouts give `*`.
        if flags == .command, key == "l" {
            applyListCommand(.toggleTask, actionName: "Task")
            return true
        }
        if flags == [.command, .shift], event.keyCode == Self.eightKeyCode {
            applyListCommand(.toggleBullet, actionName: "Bullet")
            return true
        }

        // Otter is never the active app, so the Edit menu may not see these. Sent to the first
        // responder (this view, then the window for undo and redo).
        if let action = Self.editActions[EditShortcut(flags: flags.rawValue, key: key)] {
            return NSApp.sendAction(action, to: nil, from: self)
        }
        return super.performKeyEquivalent(with: event)
    }

    /// The fallback for `⌘↩` if it arrives as a command rather than a key equivalent. Plain `↩`
    /// still inserts a newline.
    override func doCommand(by selector: Selector) {
        let isNewline = selector == #selector(insertNewline(_:)) || selector == #selector(insertNewlineIgnoringFieldEditor(_:))
        if isNewline, !hasMarkedText(), let flags = NSApp.currentEvent?.modifierFlags, flags.contains(.command) {
            onCommand?(.submit(closeAfter: !flags.contains(.shift)))
            return
        }
        super.doCommand(by: selector)
    }

    /// `⌘B`, `⌘I`, `⇧⌘X`, `⌘E` and `⌘K`: adds or removes Markdown markers as one edit, so `⌘Z`
    /// undoes it and the draft is saved. The styling follows from the markers (ADR-016).
    private func applyFormatting(_ style: MarkdownStyle) {
        let clipboard = style == .link ? Self.clipboardText() : nil
        guard let edit = MarkdownFormatting.apply(style, to: string, selection: selectedRange(), clipboard: clipboard) else {
            NSSound.beep()
            return
        }
        // `⌘K` that selects a link's URL shows the link raw.
        let prepareSelection: () -> Void = { [weak self] in
            self?.revealsNextLink = style == .link
        }
        if edit.range.length == 0, edit.replacement.isEmpty {
            // Only the selection moves: out of a span after its closing marker (`⌘B`… at its end),
            // or onto a link's URL (`⌘K` in a link).
            prepareSelection()
            if style != .link {
                pinnedCaret = edit.selection.location
            }
            setSelectedRange(edit.selection)
            scrollRangeToVisible(edit.selection)
            return
        }
        breakUndoCoalescing()
        apply(edit, actionName: Self.actionNames[style] ?? "Format", beforeSelecting: prepareSelection)
    }

    // MARK: Lists (ADR-017)

    /// `⌘L`, `⇧⌘8`, `Tab` and `⇧Tab` as one edit, or a beep if `MarkdownLists` refuses.
    private func applyListCommand(_ command: ListCommand, actionName: String) {
        guard let edit = MarkdownLists.apply(command, to: string, selection: selectedRange()) else {
            NSSound.beep()
            return
        }
        applyListEdit(edit, actionName: actionName)
    }

    /// Whether the caret or selection is on a list item's line, where `Tab` and `⇧Tab` nest.
    private func selectionTouchesItems() -> Bool {
        guard let styler, !hasMarkedText() else {
            return false
        }
        let selection = selectedRange()
        return styler.currentItems().contains { $0.isOnLine(touchedBy: selection) }
    }

    /// In a list item, `Tab` nests it under the item above (or beeps); elsewhere it inserts a tab.
    override func insertTab(_ sender: Any?) {
        guard selectionTouchesItems() else {
            super.insertTab(sender)
            return
        }
        applyListCommand(.indent, actionName: "Indent")
    }

    /// In a list item, `⇧Tab` outdents it (or beeps at the top level); elsewhere it does nothing.
    override func insertBacktab(_ sender: Any?) {
        guard selectionTouchesItems() else {
            super.insertBacktab(sender)
            return
        }
        applyListCommand(.outdent, actionName: "Outdent")
    }

    /// Redraws the bullets and boxes, and their arrow cursor, after the text, the reveal or the
    /// font changed.
    fileprivate func listMarkersDidChange() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Hidden markers (ADR-016)

    /// The editing rules for the text as it is now, or `nil` while an input method is composing.
    private func hiddenMarkerRules() -> HiddenMarkerEditing? {
        guard let styler, !hasMarkedText() else {
            return nil
        }
        let selection = selectedRange()
        return HiddenMarkerEditing(
            text: string,
            spans: styler.currentSpans(),
            items: styler.currentItems(),
            revealing: isLinkRevealed ? selection : nil,
            selection: selection
        )
    }

    /// Forgets the caret exceptions and the revealed link, e.g. when the text is replaced.
    fileprivate func resetHiddenMarkerState() {
        pinnedCaret = nil
        revealsNextLink = false
        isLinkRevealed = false
        selectionAnchor = nil
        styler?.reveal(nil)
    }

    /// Every selection change, from clicks, keys or code: a caret snaps to a caret stop (`caretStop`),
    /// a selection's ends move onto visible text (`trimmedSelection`), and a link shows raw while
    /// the selection is in its URL. Nothing snaps while an input method is composing.
    ///
    /// List markers snap as they looked before the move: arriving on an item from another line
    /// lands at the start of its text, because its marker was still hidden. Then the lines the new
    /// selection touches show their raw marker (ADR-017). An edit's own selection isn't an
    /// arrival: it's placed as computed.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        guard !isMeasuring, !hasMarkedText(), let styler, ranges.count == 1, let proposed = ranges.first?.rangeValue else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
            return
        }
        let spans = styler.currentSpans()
        let reveal = (isLinkRevealed || revealsNextLink) && MarkdownStyling.link(in: spans, withDestinationHolding: proposed) != nil
        revealsNextLink = false
        let rules = HiddenMarkerEditing(
            text: string,
            spans: spans,
            items: styler.currentItems(),
            revealing: reveal ? proposed : nil,
            selection: isSelectingEditResult ? proposed : selectedRange()
        )

        let selection: NSRange
        if proposed.length == 0 {
            selection = proposed.location == pinnedCaret ? proposed : NSRange(location: rules.caretStop(proposed.location), length: 0)
        } else {
            selection = rules.trimmedSelection(proposed)
        }
        if selection.length > 0 || selection.location != pinnedCaret {
            pinnedCaret = nil
        }
        if !isExtendingSelection {
            if selection.length == 0 {
                selectionAnchor = selection.location
            } else if let anchor = selectionAnchor, anchor > selection.location, anchor < NSMaxRange(selection) {
                selectionAnchor = nil
            }
        }

        super.setSelectedRanges([NSValue(range: selection)], affinity: affinity, stillSelecting: stillSelectingFlag)
        isLinkRevealed = reveal
        styler.reveal(reveal ? selection : nil)
        if styler.revealItems(on: selection) {
            listMarkersDidChange()
        }
        // `NSTextView` takes the typing attributes from the text at the caret, which may be hidden.
        typingAttributes = styler.baseAttributes
    }

    /// `⌘←` on an item line goes to the start of its text, not to its revealed marker.
    override func moveToLeftEndOfLine(_ sender: Any?) {
        super.moveToLeftEndOfLine(sender)
        moveToItemTextIfBeforeIt()
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        super.moveToBeginningOfLine(sender)
        moveToItemTextIfBeforeIt()
    }

    private func moveToItemTextIfBeforeIt() {
        let selection = selectedRange()
        guard selection.length == 0, let rules = hiddenMarkerRules(), let item = rules.item(onLineOf: selection.location),
              selection.location < item.contentRange.location else {
            return
        }
        setSelectedRange(NSRange(location: item.contentRange.location, length: 0))
    }

    override func moveLeft(_ sender: Any?) {
        moveCaret(forward: false, extending: false) { super.moveLeft(sender) }
    }

    override func moveRight(_ sender: Any?) {
        moveCaret(forward: true, extending: false) { super.moveRight(sender) }
    }

    override func moveBackward(_ sender: Any?) {
        moveCaret(forward: false, extending: false) { super.moveBackward(sender) }
    }

    override func moveForward(_ sender: Any?) {
        moveCaret(forward: true, extending: false) { super.moveForward(sender) }
    }

    override func moveLeftAndModifySelection(_ sender: Any?) {
        moveCaret(forward: false, extending: true) { super.moveLeftAndModifySelection(sender) }
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
        moveCaret(forward: true, extending: true) { super.moveRightAndModifySelection(sender) }
    }

    override func moveBackwardAndModifySelection(_ sender: Any?) {
        moveCaret(forward: false, extending: true) { super.moveBackwardAndModifySelection(sender) }
    }

    override func moveForwardAndModifySelection(_ sender: Any?) {
        moveCaret(forward: true, extending: true) { super.moveForwardAndModifySelection(sender) }
    }

    /// `←` / `→` (and with `⇧`) by one visible character, so every press moves the caret. Logical
    /// order: left is backward. Word, line, click and `↑` / `↓` movement rely on the snapping.
    private func moveCaret(forward: Bool, extending: Bool, fallback: () -> Void) {
        guard let rules = hiddenMarkerRules() else {
            fallback()
            return
        }
        let selection = selectedRange()
        guard extending else {
            let caret: Int
            if selection.length > 0 {
                caret = forward ? NSMaxRange(selection) : selection.location
            } else {
                caret = forward ? rules.nextCaretStop(after: selection.location) : rules.previousCaretStop(before: selection.location)
            }
            setSelectedRange(NSRange(location: caret, length: 0))
            scrollRangeToVisible(NSRange(location: caret, length: 0))
            return
        }

        let anchor: Int
        let moving: Int
        if let fixed = selectionAnchor, fixed <= selection.location {
            (anchor, moving) = (fixed, NSMaxRange(selection))
        } else if let fixed = selectionAnchor, fixed >= NSMaxRange(selection) {
            (anchor, moving) = (fixed, selection.location)
        } else {
            (anchor, moving) = forward ? (selection.location, NSMaxRange(selection)) : (NSMaxRange(selection), selection.location)
        }
        let target = forward ? rules.nextCaretStop(after: moving) : rules.previousCaretStop(before: moving)
        isExtendingSelection = true
        setSelectedRange(NSRange(location: min(anchor, target), length: abs(target - anchor)))
        isExtendingSelection = false
        selectionAnchor = anchor
        scrollRangeToVisible(NSRange(location: target, length: 0))
    }

    override func deleteBackward(_ sender: Any?) {
        deleteCharacter(backward: true) { super.deleteBackward(sender) }
    }

    override func deleteForward(_ sender: Any?) {
        deleteCharacter(backward: false) { super.deleteForward(sender) }
    }

    override func deleteBackwardByDecomposingPreviousCharacter(_ sender: Any?) {
        deleteCharacter(backward: true) { super.deleteBackwardByDecomposingPreviousCharacter(sender) }
    }

    override func deleteWordBackward(_ sender: Any?) {
        deleteMeasured(by: { super.moveWordBackwardAndModifySelection(nil) }, native: { super.deleteWordBackward(sender) })
    }

    override func deleteWordForward(_ sender: Any?) {
        deleteMeasured(by: { super.moveWordForwardAndModifySelection(nil) }, native: { super.deleteWordForward(sender) })
    }

    override func deleteToBeginningOfLine(_ sender: Any?) {
        deleteMeasured(by: { super.moveToBeginningOfLineAndModifySelection(nil) }, native: { super.deleteToBeginningOfLine(sender) })
    }

    override func deleteToEndOfLine(_ sender: Any?) {
        deleteMeasured(by: { super.moveToEndOfLineAndModifySelection(nil) }, native: { super.deleteToEndOfLine(sender) })
    }

    override func deleteToBeginningOfParagraph(_ sender: Any?) {
        deleteMeasured(by: { super.moveToBeginningOfParagraphAndModifySelection(nil) }, native: { super.deleteToBeginningOfParagraph(sender) })
    }

    override func deleteToEndOfParagraph(_ sender: Any?) {
        deleteMeasured(by: { super.moveToEndOfParagraphAndModifySelection(nil) }, native: { super.deleteToEndOfParagraph(sender) })
    }

    /// `⌫` / `⌦`: the visible character, never a hidden marker alone, and the span's markers with
    /// its last visible character. A plain delete is left to `NSTextView`, which coalesces undo.
    private func deleteCharacter(backward: Bool, native: () -> Void) {
        guard let rules = hiddenMarkerRules() else {
            native()
            return
        }
        let selection = selectedRange()
        guard selection.length == 0 else {
            deleteSelection(selection, rules: rules, native: native)
            return
        }
        guard let edit = rules.deletion(backward: backward, from: selection.location) else {
            // Only hidden markers (or nothing) on that side.
            return
        }
        let ns = string as NSString
        let plain: NSRange? = backward
            ? (selection.location > 0 ? ns.rangeOfComposedCharacterSequence(at: selection.location - 1) : nil)
            : (selection.location < ns.length ? ns.rangeOfComposedCharacterSequence(at: selection.location) : nil)
        if edit.replacement.isEmpty, edit.range == plain {
            native()
        } else if rules.item(onLineOf: selection.location) != nil {
            // Taking a marker off, or joining items.
            applyListEdit(edit, actionName: nil)
        } else {
            apply(edit, actionName: nil)
        }
    }

    /// Word and line deletes: the range the movement would select, deleted by the hidden-marker rules.
    private func deleteMeasured(by measure: () -> Void, native: () -> Void) {
        guard let rules = hiddenMarkerRules() else {
            native()
            return
        }
        let selection = selectedRange()
        guard selection.length == 0 else {
            deleteSelection(selection, rules: rules, native: native)
            return
        }
        isMeasuring = true
        measure()
        let range = selectedRange()
        super.setSelectedRanges([NSValue(range: selection)], affinity: selectionAffinity, stillSelecting: false)
        isMeasuring = false
        guard range.length > 0, let edit = rules.deletion(of: range) else {
            return
        }
        if edit.range == range, edit.replacement.isEmpty {
            // Nothing hidden involved: `NSTextView`'s own delete, which also feeds `⌃Y` after `⌃K`.
            native()
        } else {
            apply(edit, actionName: nil)
        }
    }

    private func deleteSelection(_ selection: NSRange, rules: HiddenMarkerEditing, native: () -> Void) {
        guard let edit = rules.deletion(of: selection) else {
            return
        }
        if edit.range == selection, edit.replacement.isEmpty {
            native()
        } else {
            apply(edit, actionName: nil)
        }
    }

    /// Typing over a selection keeps the first selected character's style, and the caret stays
    /// after a closing marker just typed. When an input method commits, the text is restyled.
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        let typed = (insertString as? NSAttributedString)?.string ?? insertString as? String ?? ""
        let target = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if !wasComposing, target.length > 0, let rules = hiddenMarkerRules() {
            let edit = rules.replacement(of: target, with: typed)
            if edit.range != target || edit.replacement != typed {
                apply(edit, actionName: nil)
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
        if wasComposing {
            if !hasMarkedText() {
                composingDidEnd()
            }
            return
        }
        let inserted = NSRange(location: target.location, length: (typed as NSString).length)
        if inserted.length > 0, let caret = hiddenMarkerRules()?.caretAfterClosingMarker(completedBy: inserted) {
            pinnedCaret = caret
            setSelectedRange(NSRange(location: caret, length: 0))
        }
    }

    override func unmarkText() {
        let wasComposing = hasMarkedText()
        super.unmarkText()
        if wasComposing {
            composingDidEnd()
        }
    }

    private func composingDidEnd() {
        styler?.restyleAll()
        setSelectedRange(selectedRange())
    }

    /// `↩` inside a span closes it and opens it again on the new line; at its end, the break goes
    /// after the closing marker. In a list item it continues the list, or ends it on an empty item.
    override func insertNewline(_ sender: Any?) {
        insertLineBreak { super.insertNewline(sender) }
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        insertLineBreak { super.insertNewlineIgnoringFieldEditor(sender) }
    }

    private func insertLineBreak(native: () -> Void) {
        guard let rules = hiddenMarkerRules() else {
            native()
            return
        }
        let selection = selectedRange()
        let edit = rules.lineBreak(at: selection)
        if edit.range == selection, edit.replacement == "\n" {
            native()
        } else if selection.length == 0, rules.item(onLineOf: selection.location) != nil {
            applyListEdit(edit, actionName: nil)
        } else {
            apply(edit, actionName: nil)
        }
    }

    /// Copy and drag write balanced Markdown: a partly selected span is closed and opened again.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.string), selectedRanges.count == 1, let rules = hiddenMarkerRules() else {
            return super.writeSelection(to: pboard, types: types)
        }
        let markdown = rules.copiedMarkdown(for: selectedRange())
        guard !markdown.isEmpty else {
            return super.writeSelection(to: pboard, types: types)
        }
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(markdown, forType: .string)
    }

    /// Cut writes what copy writes, then deletes as a selection delete does.
    override func cut(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length > 0, selectedRanges.count == 1, let rules = hiddenMarkerRules() else {
            super.cut(sender)
            return
        }
        guard let edit = rules.deletion(of: selection) else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(rules.copiedMarkdown(for: selection), forType: .string)
        apply(edit, actionName: "Cut")
    }

    /// One undoable edit through `shouldChangeText` / `replaceCharacters` / `didChangeText`, so
    /// `⌘Z` undoes it and the draft is saved, then its selection (scrolled to unless `scrolls` is
    /// false).
    @discardableResult
    private func apply(_ edit: MarkdownEdit, actionName: String?, scrolls: Bool = true, beforeSelecting prepare: () -> Void = {}) -> Bool {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else {
            return false
        }
        replaceCharacters(in: edit.range, with: edit.replacement)
        if let actionName {
            undoManager?.setActionName(actionName)
        }
        didChangeText()
        prepare()
        isSelectingEditResult = true
        setSelectedRange(edit.selection)
        isSelectingEditResult = false
        if scrolls {
            scrollRangeToVisible(edit.selection)
        }
        return true
    }

    /// A list edit (ADR-017) as its own `⌘Z` step, apart from the typing around it.
    private func applyListEdit(_ edit: MarkdownEdit, actionName: String?, scrolls: Bool = true) {
        breakUndoCoalescing()
        apply(edit, actionName: actionName, scrolls: scrolls)
        breakUndoCoalescing()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for marker in listMarkers(in: dirtyRect) {
            draw(marker)
        }
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else {
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 15),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: attributes)
    }

    // MARK: Bullets and checkboxes (ADR-017)

    /// A drawn bullet or box: an item whose line isn't revealed, where its first line sits.
    private struct ListMarker {
        let item: MarkdownListItem
        /// The x of the item's text start, in view coordinates.
        let textStart: CGFloat
        /// The first line's baseline, in view coordinates.
        let baseline: CGFloat
    }

    /// The bullets and boxes to draw in `rect`: the items there whose line the selection doesn't
    /// touch. Uses TextKit 2's layout fragments only; touching `layoutManager` would switch the
    /// view to TextKit 1.
    private func listMarkers(in rect: NSRect) -> [ListMarker] {
        guard let styler, let layoutManager = textLayoutManager, let content = layoutManager.textContentManager else {
            return []
        }
        let items = styler.currentItems()
        guard !items.isEmpty else {
            return []
        }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        let documentStart = content.documentRange.location
        let top = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(rect.minY - origin.y, 0)))?.rangeInElement.location ?? documentStart
        var markers: [ListMarker] = []
        layoutManager.enumerateTextLayoutFragments(from: top, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY + origin.y <= rect.maxY else {
                return false
            }
            let location = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            if let item = Self.item(startingAt: location, in: items), !styler.isRevealed(item), let line = fragment.textLineFragments.first {
                markers.append(ListMarker(
                    item: item,
                    textStart: origin.x + padding + styler.textStart(level: item.level),
                    baseline: origin.y + frame.minY + line.typographicBounds.minY + line.glyphOrigin.y
                ))
            }
            return true
        }
        return markers
    }

    private static func item(startingAt location: Int, in items: [MarkdownListItem]) -> MarkdownListItem? {
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].lineRange.location < location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < items.count && items[low].lineRange.location == location ? items[low] : nil
    }

    /// `•` in `secondaryLabelColor` where the `-` would be, or a box in the accent colour, sized
    /// from the editor font and sitting on the first line's baseline.
    private func draw(_ marker: ListMarker) {
        guard let styler else {
            return
        }
        switch marker.item.kind {
        case .bullet:
            let bullet = "•"
            let x = marker.textStart - styler.width(of: "- ") + (styler.width(of: "-") - styler.width(of: bullet)) / 2
            drawText(bullet, at: CGPoint(x: x, y: marker.baseline), color: .secondaryLabelColor, font: styler.font)
        case let .task(checked):
            guard let images = checkboxImages(for: styler.font) else {
                return
            }
            (checked ? images.checked : images.empty).draw(in: boxRect(for: marker), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    /// Draws `string` with its baseline at `point` (this view is flipped).
    private func drawText(_ string: String, at point: CGPoint, color: NSColor, font: NSFont) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// A task's box: in the gutter, 0.4 em left of the text, centred on the capitals.
    private func boxRect(for marker: ListMarker) -> NSRect {
        guard let styler, let images = checkboxImages(for: styler.font) else {
            return .zero
        }
        let size = images.empty.size
        let font = styler.font
        let midX = marker.textStart - 0.4 * font.pointSize - size.width / 2
        let midY = marker.baseline - font.capHeight / 2
        return NSRect(x: midX - size.width / 2, y: midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Where a press on a box ticks it: the box, grown to at least 20 × 20 pt.
    private func hitRect(for marker: ListMarker) -> NSRect {
        let box = boxRect(for: marker)
        return box.insetBy(dx: min(0, (box.width - 20) / 2), dy: min(0, (box.height - 20) / 2))
    }

    private func checkboxImages(for font: NSFont) -> (empty: NSImage, checked: NSImage)? {
        if let cached = checkboxImages, cached.pointSize == font.pointSize {
            return (cached.empty, cached.checked)
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor]))
        guard let empty = NSImage(systemSymbolName: "square", accessibilityDescription: nil)?.withSymbolConfiguration(configuration),
              let checked = NSImage(systemSymbolName: "checkmark.square.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            return nil
        }
        checkboxImages = (font.pointSize, empty, checked)
        return (empty, checked)
    }

    /// The drawn box under `point`, if any. None while an input method is composing.
    private func checkbox(at point: NSPoint) -> ListMarker? {
        guard !hasMarkedText() else {
            return nil
        }
        return listMarkers(in: visibleRect).first { $0.item.isTask && hitRect(for: $0).contains(point) }
    }

    /// A press on a drawn box ticks or unticks it on mouse-up inside the box, without moving the
    /// caret. A press that turns into a drag selects text as usual.
    override func mouseDown(with event: NSEvent) {
        guard let window, let marker = checkbox(at: convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                if hitRect(for: marker).contains(convert(next.locationInWindow, from: nil)) {
                    toggleCheckbox(marker.item)
                }
                return
            }
            let dx = next.locationInWindow.x - event.locationInWindow.x
            let dy = next.locationInWindow.y - event.locationInWindow.y
            if dx * dx + dy * dy > 9 {
                super.mouseDown(with: event)
                return
            }
        }
    }

    /// `[ ]` ↔ `[x]` as one undo step, the selection (and the scroll position) left alone.
    private func toggleCheckbox(_ item: MarkdownListItem) {
        guard let edit = MarkdownLists.toggleCheckbox(item, in: string, selection: selectedRange()) else {
            return
        }
        applyListEdit(edit, actionName: item.isChecked ? "Uncheck" : "Check", scrolls: false)
    }

    /// The arrow over each drawn box.
    override func resetCursorRects() {
        super.resetCursorRects()
        for marker in listMarkers(in: visibleRect) where marker.item.isTask {
            addCursorRect(hitRect(for: marker), cursor: .arrow)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if checkbox(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if checkbox(at: convert(event.locationInWindow, from: nil)) != nil {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Private

    /// What the pasteboard holds, by `PasteRules`, without reading any image data.
    private static func kind(of pasteboard: NSPasteboard) -> PasteKind {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        let hasFileURLs = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasText = pasteboard.string(forType: .string).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        return PasteRules.kind(types: types, hasFileURLs: hasFileURLs, hasText: hasText)
    }

    /// The files or the image on the pasteboard, or `nil` if it should be pasted as text.
    private static func attachments(on pasteboard: NSPasteboard) -> PastedAttachments? {
        switch kind(of: pasteboard) {
        case .files:
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            return urls.isEmpty ? nil : .files(urls)
        case let .image(uti):
            // The raw data, so PNG, JPEG and HEIC keep their format; `NSImage` would re-encode it.
            return pasteboard.data(forType: NSPasteboard.PasteboardType(uti)).map { .image($0, uti: uti) }
        case .text:
            return nil
        }
    }

    /// The clipboard's text for `⌘K`. Concealed or transient content (a password) is never put in a note.
    private static func clipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        guard !PasteRules.isPrivate(types: pasteboard.types?.map(\.rawValue) ?? []) else {
            return nil
        }
        return pasteboard.string(forType: .string)
    }

    /// Return and keypad Enter.
    private static let returnKeyCodes: Set<UInt16> = [36, 76]
    /// Backspace.
    private static let deleteKeyCode: UInt16 = 51
    /// The `8` key on the main row (`kVK_ANSI_8`).
    private static let eightKeyCode: UInt16 = 28

    private struct EditShortcut: Hashable {
        let flags: UInt
        let key: String
    }

    private static let editActions: [EditShortcut: Selector] = [
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "z"): Selector(("undo:")),
        EditShortcut(flags: NSEvent.ModifierFlags([.command, .shift]).rawValue, key: "z"): Selector(("redo:")),
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "x"): #selector(cut(_:)),
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "c"): #selector(copy(_:)),
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "v"): #selector(paste(_:)),
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "a"): #selector(selectAll(_:)),
    ]

    private static let formattingShortcuts: [EditShortcut: MarkdownStyle] = [
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "b"): .bold,
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "i"): .italic,
        EditShortcut(flags: NSEvent.ModifierFlags([.command, .shift]).rawValue, key: "x"): .strikethrough,
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "e"): .code,
        EditShortcut(flags: NSEvent.ModifierFlags.command.rawValue, key: "k"): .link,
    ]

    private static let actionNames: [MarkdownStyle: String] = [
        .bold: "Bold", .italic: "Italic", .strikethrough: "Strikethrough", .code: "Code", .link: "Link",
    ]
}
