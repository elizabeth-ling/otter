import AppKit

/// The header's destination (UX_SPEC §1): the colored dot and the destination's name. For a folder
/// destination it's a button that opens the folder picker (T17). It takes every mouse-down in its
/// bounds, so the label never swallows one: a press that turns into a drag moves the window, which
/// keeps the header a drag handle.
final class DestinationPill: NSView {
    /// A click or VoiceOver's press. Only called while the destination is a folder.
    var onChooseFolder: (() -> Void)? {
        didSet { update() }
    }

    /// Between the highlight's edge and the dot, so the header can keep the dot on its inset.
    static let leadingPadding: CGFloat = 6
    private static let dragThreshold: CGFloat = 3

    private let label = NSTextField(labelWithString: "")
    private var folderPath: String?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    private var isPressed = false {
        didSet { needsDisplay = true }
    }

    private var isClickable: Bool { folderPath != nil && onChooseFolder != nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The pill speaks for it.
        label.setAccessibilityElement(false)

        let row = NSStackView(views: [DestinationDot(diameter: 8), label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingPadding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        setAccessibilityElement(true)
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `folderPath` is the full path for the tooltip, or `nil` when the destination isn't a folder.
    func set(name: String, folderPath: String?) {
        label.stringValue = name
        self.folderPath = folderPath
        update()
    }

    // MARK: - Drawing

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let fill: NSColor? = switch (isClickable, isPressed, isHovered) {
        case (false, _, _): nil
        case (true, true, _): .secondarySystemFill
        case (true, false, true): .tertiarySystemFill
        case (true, false, false): nil
        }
        layer?.backgroundColor = fill?.cgColor
    }

    // MARK: - Mouse

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinates.
        frame.contains(point) ? self : nil
    }

    /// The window is moved by `mouseDown` instead, once a press turns into a drag.
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // `.activeAlways`: Otter is usually not the active app while the panel is up.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    /// A click opens the folder picker on mouse-up inside; a drag moves the window and opens nothing.
    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }
        guard isClickable else {
            window.performDrag(with: event)
            return
        }
        isPressed = true
        defer { isPressed = false }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let location = next.locationInWindow
            if next.type == .leftMouseUp {
                if bounds.contains(convert(location, from: nil)) {
                    onChooseFolder?()
                }
                return
            }
            if hypot(location.x - start.x, location.y - start.y) > Self.dragThreshold {
                isPressed = false
                window.performDrag(with: event)
                return
            }
        }
    }

    // MARK: - Accessibility

    override func accessibilityPerformPress() -> Bool {
        guard isClickable else {
            return false
        }
        onChooseFolder?()
        return true
    }

    // MARK: - Private

    private func update() {
        toolTip = isClickable ? folderPath : nil
        if isClickable {
            setAccessibilityRole(.button)
            setAccessibilityLabel("Save location: \(label.stringValue)")
            setAccessibilityHelp("Change folder")
        } else {
            setAccessibilityRole(.staticText)
            setAccessibilityLabel("Destination: \(label.stringValue)")
            setAccessibilityHelp(nil)
        }
        needsDisplay = true
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
