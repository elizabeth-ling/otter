import AppKit
import OtterCore

/// The panel's content (UX_SPEC §1): a rounded vibrant background holding the header strip
/// (destination dot and name, and the drag handle), the editor, the attachment chips (T09) and the
/// footer hints.
final class PanelContentView: NSVisualEffectView {
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 28
    static let inset: CGFloat = 14
    static let cornerRadius: CGFloat = 12

    static let footerHints = "⌘↩ Save · ⌘S Save as…"

    let editor = EditorView(font: .systemFont(ofSize: 15), inset: PanelContentView.inset, placeholder: "Jot something down…")
    let attachmentChips = AttachmentChips()

    private let solidBackground = NSView()
    private let destinationPill = DestinationPill()
    private let footerLabel = NSTextField(labelWithString: PanelContentView.footerHints)
    /// Zero while there are no attachments, so the editor takes the room.
    private lazy var chipsHeight = attachmentChips.heightAnchor.constraint(equalToConstant: 0)

    /// Clicking the destination in the header: show the destination menu below it (T10).
    var onDestinationClick: ((NSView) -> Void)? {
        get { destinationPill.onClick }
        set { destinationPill.onClick = newValue }
    }

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
        attachmentChips.translatesAutoresizingMaskIntoConstraints = false
        attachmentChips.isHidden = true
        for view in [header, editor, attachmentChips, footer] {
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
            editor.bottomAnchor.constraint(equalTo: attachmentChips.topAnchor),

            attachmentChips.leadingAnchor.constraint(equalTo: leadingAnchor),
            attachmentChips.trailingAnchor.constraint(equalTo: trailingAnchor),
            attachmentChips.bottomAnchor.constraint(equalTo: footer.topAnchor),
            chipsHeight,

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

    /// Call before showing: the default destination may have changed since last time. `folderPath`
    /// is `nil` unless it's a folder destination; it's the pill's tooltip.
    func setDestination(name: String, folderPath: String?) {
        destinationPill.set(name: name, folderPath: folderPath)
    }

    /// Shows the chips row, or hides it and gives the room back to the editor.
    func setAttachments(_ attachments: [StagedAttachment]) {
        attachmentChips.set(attachments)
        attachmentChips.isHidden = attachments.isEmpty
        chipsHeight.constant = attachments.isEmpty ? 0 : AttachmentChips.height
    }

    /// A warning in place of the footer hints (UX_SPEC §1), or `nil` for the hints.
    func setFooterWarning(_ warning: String?) {
        guard footerLabel.stringValue != warning ?? Self.footerHints else {
            return
        }
        footerLabel.stringValue = warning ?? Self.footerHints
        footerLabel.textColor = warning == nil ? .tertiaryLabelColor : .systemOrange
        footerLabel.lineBreakMode = warning == nil ? .byTruncatingHead : .byTruncatingTail
        footerLabel.toolTip = warning
        if let warning {
            NSAccessibility.post(element: footerLabel, notification: .announcementRequested, userInfo: [
                .announcement: warning,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
        }
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
    /// The destination pill moves it too, unless the press is a click on it.
    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        destinationPill.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(destinationPill)

        NSLayoutConstraint.activate([
            destinationPill.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Self.inset - DestinationPill.leadingPadding),
            destinationPill.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -Self.inset),
            destinationPill.centerYAnchor.constraint(equalTo: header.centerYAnchor),
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

        let hints = footerLabel
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
