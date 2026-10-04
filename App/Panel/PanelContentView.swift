import AppKit
import OtterCore

/// The panel's content (UX_SPEC §1): a rounded vibrant background holding the header strip
/// (destination dot and name, and the drag handle), the editor and the footer hints.
final class PanelContentView: NSVisualEffectView {
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 28
    static let inset: CGFloat = 14
    static let cornerRadius: CGFloat = 12

    let editor = EditorView(font: .systemFont(ofSize: 15), inset: PanelContentView.inset, placeholder: "Jot something down…")

    private let solidBackground = NSView()
    private let destinationLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(origin: .zero, size: PanelPlacement.defaultSize))
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

        let header = makeHeader()
        let footer = makeFooter()
        editor.translatesAutoresizingMaskIntoConstraints = false
        for view in [header, editor, footer] {
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            editor.topAnchor.constraint(equalTo: header.bottomAnchor),
            editor.leadingAnchor.constraint(equalTo: leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    // MARK: - Private

    /// Layer colors are `CGColor`s, which don't follow Light/Dark on their own.
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            solidBackground.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    /// The drag handle: a plain view, so a mouse-down on it moves the window. No separator below.
    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        destinationLabel.font = .systemFont(ofSize: 12, weight: .medium)
        destinationLabel.textColor = .secondaryLabelColor
        destinationLabel.lineBreakMode = .byTruncatingTail
        destinationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [DestinationDot(diameter: 8), destinationLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Self.inset),
            row.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -Self.inset),
            row.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        return header
    }

    /// Hints on the right, always shown, under a thin separator. Its background drags the window.
    private func makeFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(separator)

        let hints = NSTextField(labelWithString: "⌘↩ Save · ⌘S Save as…")
        hints.font = .systemFont(ofSize: 11)
        hints.textColor = .tertiaryLabelColor
        hints.lineBreakMode = .byTruncatingHead
        hints.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hints.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(hints)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: Self.inset),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -Self.inset),

            hints.leadingAnchor.constraint(greaterThanOrEqualTo: footer.leadingAnchor, constant: Self.inset),
            hints.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -Self.inset),
            hints.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 0.5),
        ])
        return footer
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
