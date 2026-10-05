import AppKit

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
}

/// The panel's plain-text editor (T04, ADR-007): an `NSTextView` in a scroll view that fills the text
/// area. The panel keeps its size; long text scrolls.
final class EditorView: NSScrollView {
    /// The keyboard map's commands.
    var onCommand: ((EditorCommand) -> Void)? {
        get { textView.onCommand }
        set { textView.onCommand = newValue }
    }

    /// Every edit by the user, including undo and discard. Not called for `setText` or `clear`.
    var onTextChange: (() -> Void)? {
        get { textView.onTextChange }
        set { textView.onTextChange = newValue }
    }

    /// Takes keyboard focus when the panel shows.
    let textView = EditorTextView()

    var text: String { textView.string }

    init(font: NSFont, inset: CGFloat, placeholder: String) {
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
        textView.string = text
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
/// `EditorCommand`s.
final class EditorTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    fileprivate var onCommand: ((EditorCommand) -> Void)?
    fileprivate var onTextChange: (() -> Void)?

    /// Dragging in the text selects text; it never moves the window.
    override var mouseDownCanMoveWindow: Bool { false }

    /// `NSTextView` turns `Esc` into "complete"; hide the panel instead.
    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
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
            // Reserved for Save as (T16). Swallowed so it never reaches `saveDocument:`.
            return true
        default:
            break
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
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

    // MARK: - Private

    /// Return and keypad Enter.
    private static let returnKeyCodes: Set<UInt16> = [36, 76]
    /// Backspace.
    private static let deleteKeyCode: UInt16 = 51

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
}
