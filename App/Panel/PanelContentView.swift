import AppKit

/// The panel's content (UX_SPEC §1): a rounded vibrant background, the 56 pt bar (destination dot,
/// text field, `⌘↩` hint) and a footer that appears once there is text.
///
/// The text field is a placeholder; T04 replaces it with the `NSTextView` editor.
final class PanelContentView: NSVisualEffectView, NSTextFieldDelegate {
    static let barHeight: CGFloat = 56
    static let footerHeight: CGFloat = 37
    static let cornerRadius: CGFloat = 16

    /// The panel's height changed (the footer appeared or went away).
    var onPreferredHeightChange: (() -> Void)?

    var preferredHeight: CGFloat {
        Self.barHeight + (footer.isHidden ? 0 : Self.footerHeight)
    }

    /// The view that takes keyboard focus when the panel shows.
    var editor: NSView { textField }

    private let solidBackground = NSView()
    private let textField = NSTextField()
    private let footer = NSView()
    private let destinationLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: Self.barHeight))
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        solidBackground.wantsLayer = true
        solidBackground.isHidden = true
        pin(solidBackground)

        let bar = makeBar()
        addSubview(bar)
        buildFooter()
        footer.isHidden = true
        addSubview(footer)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight),

            footer.topAnchor.constraint(equalTo: bar.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.heightAnchor.constraint(equalToConstant: Self.footerHeight),
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Call before showing: the default destination may have changed since last time.
    func setDestinationName(_ name: String) {
        destinationLabel.stringValue = name
    }

    /// Reduce Transparency swaps the vibrancy for a solid `windowBackgroundColor`.
    func setReduceTransparency(_ reduce: Bool) {
        solidBackground.isHidden = !reduce
    }

    /// Puts the caret at the end without selecting, so typing appends to what's there.
    func moveCaretToEnd() {
        let length = (textField.stringValue as NSString).length
        textField.currentEditor()?.selectedRange = NSRange(location: length, length: 0)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        let hasContent = !textField.stringValue.isEmpty
        guard footer.isHidden == hasContent else {
            return
        }
        footer.isHidden = !hasContent
        onPreferredHeightChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // The field editor would treat `Esc` as "complete"; send it to the panel instead.
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            window?.cancelOperation(control)
            return true
        }
        return false
    }

    // MARK: - Private

    /// Layer colors are `CGColor`s, which don't follow Light/Dark on their own.
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            solidBackground.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    private func makeBar() -> NSView {
        textField.placeholderString = "Jot something down…"
        textField.font = .systemFont(ofSize: 16)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.delegate = self
        textField.setAccessibilityLabel("Note")

        let hint = NSTextField(labelWithString: "⌘↩")
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .tertiaryLabelColor
        hint.setAccessibilityElement(false)

        let bar = NSStackView(views: [DestinationDot(diameter: 10), textField, hint])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 12
        bar.translatesAutoresizingMaskIntoConstraints = false
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.setContentCompressionResistancePriority(.required, for: .horizontal)
        return bar
    }

    private func buildFooter() {
        footer.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(separator)

        destinationLabel.font = .systemFont(ofSize: 12)
        destinationLabel.textColor = .secondaryLabelColor
        destinationLabel.lineBreakMode = .byTruncatingTail
        destinationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let saveHint = NSTextField(labelWithString: "⌘↩ Save")
        saveHint.font = .systemFont(ofSize: 12)
        saveHint.textColor = .secondaryLabelColor

        let row = NSStackView(views: [DestinationDot(diameter: 6), destinationLabel, NSView(), saveHint])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(row)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),

            // Lines up with the text in the bar: 20 inset + 10 dot + 12 spacing.
            row.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 42),
            row.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20),
            row.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 0.5),
        ])
    }

    private func pin(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

/// The colored destination dot. Accent color until destinations carry their own (T10).
private final class DestinationDot: NSView {
    private let diameter: CGFloat

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        setContentHuggingPriority(.required, for: .horizontal)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: diameter, height: diameter)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
