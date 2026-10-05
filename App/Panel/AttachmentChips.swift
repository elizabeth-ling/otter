import AppKit
import ImageIO
import OtterCore
import UniformTypeIdentifiers

/// The row of attachments above the footer (UX_SPEC §1, T09): one chip per attachment, with a
/// thumbnail for images or the file type's icon, the name and size, and `✕` to remove it. Scrolls
/// sideways when the chips don't fit. Hidden while there are none.
final class AttachmentChips: NSView {
    static let height: CGFloat = 32

    /// `✕` on a chip.
    var onRemove: ((Attachment) -> Void)?

    private let scrollView = NSScrollView()
    private let row = NSStackView()
    private var chips: [UUID: AttachmentChip] = [:]
    /// Thumbnails are dropped while the panel is hidden (ARCHITECTURE §9).
    private var showsThumbnails = true

    init() {
        super.init(frame: .zero)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: PanelContentView.inset, bottom: 0, right: PanelContentView.inset)
        row.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = row
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: clip.topAnchor),
            row.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            row.widthAnchor.constraint(greaterThanOrEqualTo: clip.widthAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Attachments")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `attachments` in order. Chips already shown keep their thumbnails.
    func set(_ attachments: [StagedAttachment]) {
        let ids = Set(attachments.map(\.attachment.id))
        for (id, chip) in chips where !ids.contains(id) {
            chip.removeFromSuperview()
            chips[id] = nil
        }
        for (index, staged) in attachments.enumerated() {
            let chip = chips[staged.attachment.id] ?? makeChip(for: staged)
            let current = row.arrangedSubviews.firstIndex(of: chip)
            guard current != index else {
                continue
            }
            // `removeArrangedSubview` asserts if the chip isn't in the row yet, which a new chip isn't.
            if current != nil {
                row.removeArrangedSubview(chip)
            }
            row.insertArrangedSubview(chip, at: index)
        }
        if let last = attachments.last, let chip = chips[last.attachment.id] {
            layoutSubtreeIfNeeded()
            chip.scrollToVisible(chip.bounds)
        }
    }

    /// The panel hid: let the thumbnails go. Chips show their file icons until `loadThumbnails`.
    func releaseThumbnails() {
        showsThumbnails = false
        chips.values.forEach { $0.releaseThumbnail() }
    }

    /// The panel is showing again.
    func loadThumbnails() {
        showsThumbnails = true
        chips.values.forEach { $0.loadThumbnail() }
    }

    // MARK: - Private

    private func makeChip(for staged: StagedAttachment) -> AttachmentChip {
        let chip = AttachmentChip(staged: staged)
        chip.onRemove = { [weak self] in self?.onRemove?(staged.attachment) }
        chips[staged.attachment.id] = chip
        if showsThumbnails {
            chip.loadThumbnail()
        }
        return chip
    }
}

/// One attachment: icon or thumbnail, "name · size", and a remove button.
private final class AttachmentChip: NSView {
    private static let iconSize: CGFloat = 18
    private static let maxLabelWidth: CGFloat = 160
    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var onRemove: (() -> Void)?

    private let staged: StagedAttachment
    private let iconView = NSImageView()
    private let isImage: Bool
    /// Bumped on every load and release, so a thumbnail that arrives late doesn't come back.
    private var thumbnailGeneration = 0

    init(staged: StagedAttachment) {
        self.staged = staged
        isImage = UTType(staged.attachment.uti)?.conforms(to: .image) ?? false
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        let name = AttachmentLimits.displayName(of: staged.attachment)
        let size = Self.sizeFormatter.string(fromByteCount: Int64(staged.attachment.byteCount))

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = fileIcon
        iconView.setAccessibilityElement(false)

        let label = NSTextField(labelWithString: "\(name) · \(size)")
        label.font = .systemFont(ofSize: 11)
        label.textColor = AttachmentLimits.isLarge(staged.attachment.byteCount) ? .systemOrange : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setAccessibilityElement(false)

        let remove = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(removeClicked))
        remove.isBordered = false
        remove.contentTintColor = .tertiaryLabelColor
        remove.imageScaling = .scaleProportionallyDown
        remove.setAccessibilityLabel("Remove \(name)")
        // Clicking it mustn't take focus from the editor.
        remove.refusesFirstResponder = true

        let stack = NSStackView(views: [iconView, label, remove])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            remove.widthAnchor.constraint(equalToConstant: 14),
            remove.heightAnchor.constraint(equalToConstant: 14),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxLabelWidth),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Attachment: \(name), \(size)")
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    /// Images get a thumbnail, made off the main thread at the size it's drawn.
    func loadThumbnail() {
        guard isImage else {
            return
        }
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        let file = staged.file
        let pixels = Int(Self.iconSize * (window?.backingScaleFactor ?? 2))
        Task.detached(priority: .utility) {
            let thumbnail = Self.thumbnail(of: file, maxPixels: pixels)
            await MainActor.run { [weak self] in
                guard let self, generation == thumbnailGeneration, let thumbnail else {
                    return
                }
                let scale = Self.iconSize / CGFloat(max(thumbnail.width, thumbnail.height, 1))
                iconView.image = NSImage(cgImage: thumbnail, size: NSSize(width: CGFloat(thumbnail.width) * scale, height: CGFloat(thumbnail.height) * scale))
            }
        }
    }

    func releaseThumbnail() {
        thumbnailGeneration += 1
        iconView.image = fileIcon
    }

    // MARK: - Private

    private var fileIcon: NSImage {
        NSWorkspace.shared.icon(for: UTType(staged.attachment.uti) ?? .data)
    }

    @objc private func removeClicked() {
        onRemove?()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        }
    }

    private nonisolated static func thumbnail(of file: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
