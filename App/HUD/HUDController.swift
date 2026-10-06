import AppKit
import OtterCore

/// The save-clipboard HUD (T11, UX_SPEC §3): a pill near the bottom centre of the screen with the
/// pointer that says what the clipboard hotkey did, then fades away. It never takes focus or clicks:
/// a borderless, non-activating panel that ignores the mouse, above full-screen apps on every Space.
///
/// Built on first use, so it stays off the cold-launch path (ARCHITECTURE §9). Nothing runs while
/// it's hidden.
@MainActor
final class HUDController {
    static let fadeInDuration: TimeInterval = 0.15
    static let fadeOutDuration: TimeInterval = 0.3
    /// Fully shown for this long, between the fades.
    static let visibleDuration: TimeInterval = 1.2

    private var panel: HUDPanel?
    private lazy var content = HUDContentView()
    /// Bumped on every show, so an earlier message's timer or fade-out never hides a later one.
    private var generation = 0
    private var hideTask: Task<Void, Never>?

    /// Shows `message` after a ✓ (`success`) or a ✕, and announces it to VoiceOver. A HUD that's
    /// already up takes the new message in place, moves to the pointer's screen and stays for the
    /// full time again; one that's fading out comes back.
    func show(_ message: String, success: Bool) {
        let panel = panel ?? makePanel()
        guard let screen = screenUnderPointer() else {
            return
        }
        generation += 1
        let generation = generation
        hideTask?.cancel()

        content.set(message: message, success: success)
        content.setReduceTransparency(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        panel.setFrame(HUDPlacement.frame(contentWidth: content.fittingWidth, in: screen.visibleFrame), display: true)
        panel.invalidateShadow()

        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible {
            panel.alphaValue = animate ? 0 : 1
        }
        // Not `makeKeyAndOrderFront`: the HUD is never key, and Otter stays inactive.
        panel.orderFrontRegardless()
        fade(panel, to: 1, duration: Self.fadeInDuration, animate: animate, completion: nil)
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])

        let delay = (animate ? Self.fadeInDuration : 0) + Self.visibleDuration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }
            self?.hide(generation)
        }
    }

    // MARK: - Private

    private func hide(_ generation: Int) {
        guard let panel, generation == self.generation else {
            return
        }
        hideTask = nil
        fade(panel, to: 0, duration: Self.fadeOutDuration, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { [weak self] in
            guard let self, generation == self.generation else {
                return
            }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> HUDPanel {
        let panel = HUDPanel()
        panel.contentView = content
        self.panel = panel
        return panel
    }

    /// Same rule as the capture panel (T03): the screen containing the pointer.
    private func screenUnderPointer() -> NSScreen? {
        let screens = NSScreen.screens
        if let index = PanelPlacement.screenIndex(containing: NSEvent.mouseLocation, screenFrames: screens.map(\.frame)) {
            return screens[index]
        }
        return NSScreen.main ?? screens.first
    }

    private func fade(_ panel: NSPanel, to alpha: CGFloat, duration: TimeInterval, animate: Bool, completion: (@MainActor () -> Void)?) {
        guard animate else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated {
                completion?()
            }
        }
    }
}

/// Borderless, non-activating and click-through, so the app the user is in keeps focus and every
/// click (T11 scope 3).
private final class HUDPanel: NSPanel {
    init() {
        // `.nonactivatingPanel` must be in the mask at init: toggling it later has known quirks.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: HUDPlacement.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .statusBar
        // The current Space, over full-screen apps, never in ⌘` cycling.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // The content view draws the pill; the shadow follows its alpha.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // `HUDController` fades it instead.
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The pill: a ✓ or ✕ symbol and one line of text on `.hudWindow` vibrancy, or a solid background
/// with Reduce Transparency (UX_SPEC §7).
private final class HUDContentView: NSVisualEffectView {
    private static let leadingInset: CGFloat = 14
    private static let trailingInset: CGFloat = 18
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

    private let solidBackground = NSView()
    private let symbol = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stack: NSStackView

    init() {
        stack = NSStackView(views: [symbol, label])
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: HUDPlacement.height))
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = HUDPlacement.height / 2
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        solidBackground.wantsLayer = true
        solidBackground.isHidden = true
        solidBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(solidBackground)

        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        // A message wider than the screen allows truncates rather than pushing the pill wider.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The message is announced and read without the symbol.
        symbol.setAccessibilityElement(false)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            solidBackground.topAnchor.constraint(equalTo: topAnchor),
            solidBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            solidBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingInset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The width the symbol and the whole message need, padding included.
    var fittingWidth: CGFloat {
        Self.leadingInset + stack.fittingSize.width + Self.trailingInset
    }

    func set(message: String, success: Bool) {
        label.stringValue = message
        let name = success ? "checkmark.circle.fill" : "xmark.circle.fill"
        symbol.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(Self.symbolConfiguration)
        symbol.contentTintColor = success ? .systemGreen : .secondaryLabelColor
    }

    /// Reduce Transparency swaps the vibrancy for a solid `windowBackgroundColor`, as in the panel.
    func setReduceTransparency(_ reduce: Bool) {
        solidBackground.isHidden = !reduce
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    /// Layer colors are `CGColor`s, which don't follow Light/Dark on their own.
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            solidBackground.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}
