import AppKit
import KeyboardShortcuts
import OtterCore
import os

/// Owns the menu bar item (UX_SPEC §4). AppKit `NSStatusItem` rather than SwiftUI `MenuBarExtra`,
/// for the badge and a menu built fresh each time it opens.
///
/// Nothing polls: the menu is rebuilt in `menuNeedsUpdate(_:)`, the badge and the notifications
/// follow `DeliveryService.statusUpdates()`, and the recent captures are re-read after each delivery
/// and each time the menu opens.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// What the menu's items do.
    struct Actions {
        var newNote: @MainActor () -> Void
        var saveClipboard: @MainActor () -> Void
        /// "Finish setting up ⌘Space…": onboarding's hotkey step.
        var finishHotkeySetup: @MainActor () -> Void
        var openSettings: @MainActor () -> Void
    }

    private let statusItem: NSStatusItem
    private let badge = BadgeDot()
    private let menu = NSMenu()
    /// Kept across rebuilds: a submenu can belong to one item only.
    private let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
    private let recentMenu = NSMenu()
    private let hotkeys: HotkeyService
    private let recents: RecentStore
    private let delivery: DeliveryService
    private let notifier: DeliveryNotifier
    private let updates: UpdateController
    private let actions: Actions

    private var status = DeliveryStatus.idle
    /// Newest first, as `RecentStore` last returned them.
    private var recentCaptures: [RecentCapture] = []
    private var statusTask: Task<Void, Never>?
    private var deliveriesTask: Task<Void, Never>?

    init(hotkeys: HotkeyService, recents: RecentStore, delivery: DeliveryService, notifier: DeliveryNotifier, updates: UpdateController, actions: Actions) {
        self.hotkeys = hotkeys
        self.recents = recents
        self.delivery = delivery
        self.notifier = notifier
        self.updates = updates
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            // A template image follows the menu bar's appearance and tint; the badge is a view on top.
            // The app icon's glyph, a vector in the asset catalog, sized to the menu bar's 16pt cap height.
            let image = NSImage(named: "MenuBarIcon")
            image?.size = NSSize(width: 16 * 591 / 700, height: 16)
            image?.isTemplate = true
            image?.accessibilityDescription = "Otter"
            button.image = image
            badge.install(in: button)
        }
        recentItem.submenu = recentMenu
        menu.delegate = self
        statusItem.menu = menu

        statusTask = Task { [weak self, delivery] in
            for await status in await delivery.statusUpdates() {
                self?.statusDidChange(status)
            }
        }
        deliveriesTask = Task { [weak self, delivery] in
            for await _ in await delivery.deliveries() {
                self?.reloadRecents()
            }
        }
        // The actor reads `recent.json` off the main thread.
        reloadRecents()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        hotkeys.refreshSpotlightState()
        reloadRecents()
        menu.removeAllItems()

        let newNote = addItem("New Note", #selector(newNote(_:)), to: menu)
        newNote.setShortcut(hotkeys.effectiveToggle.combo.map(KeyboardShortcuts.Shortcut.init))
        if hotkeys.needsSpotlightHandoff {
            addItem("Finish setting up ⌘Space…", #selector(finishHotkeySetup(_:)), to: menu)
        }
        let saveClipboard = addItem("Save Clipboard", #selector(saveClipboard(_:)), to: menu)
        saveClipboard.setShortcut(KeyboardShortcuts.getShortcut(for: .saveClipboard))
        menu.addItem(.separator())

        rebuildRecentMenu()
        menu.addItem(recentItem)
        menu.addItem(.separator())

        if status.pendingCount > 0 {
            addItem(DeliveryAlert.waitingRow(count: status.pendingCount), #selector(retry(_:)), to: menu)
            menu.addItem(.separator())
        }

        addItem("Settings…", #selector(openSettings(_:)), key: ",", to: menu)
        let checkForUpdates = addItem(updates.hasUnseenUpdate ? "Update Available…" : "Check for Updates…", #selector(checkForUpdates(_:)), to: menu)
        if !updates.canCheckForUpdates {
            // No action, so the menu disables it: a check is already running, or updates are off.
            checkForUpdates.action = nil
        }
        menu.addItem(withTitle: "Quit Otter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: - Actions

    @objc private func newNote(_ sender: Any?) {
        actions.newNote()
    }

    @objc private func finishHotkeySetup(_ sender: Any?) {
        actions.finishHotkeySetup()
    }

    /// The same path as the save-clipboard hotkey (T11).
    @objc private func saveClipboard(_ sender: Any?) {
        actions.saveClipboard()
    }

    @objc private func retry(_ sender: Any?) {
        Task { [delivery] in
            await delivery.retryNow()
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        actions.openSettings()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updates.checkForUpdates()
    }

    /// Opens the note where it lives: in Obsidian if it's in a vault, otherwise in Finder.
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let location = sender.representedObject as? DeliveryReceipt.Location else {
            return
        }
        switch location {
        case let .file(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                Logger.app.info("A recent note has been moved or deleted since it was saved")
                NSSound.beep()
                return
            }
            ObsidianLink.open(url)
        case .appleNote:
            // Nothing delivers to Apple Notes until T08, which opens these in Notes.
            NSSound.beep()
        }
    }

    // MARK: - Private

    private func statusDidChange(_ new: DeliveryStatus) {
        let old = status
        status = new
        let isAlerting = !new.alertingDestinations.isEmpty
        badge.isHidden = !isAlerting
        statusItem.button?.setAccessibilityLabel(isAlerting ? "Otter, notes waiting to deliver" : "Otter")
        notifier.statusDidChange(from: old, to: new)
    }

    private func reloadRecents() {
        Task { [recents] in
            let latest = await recents.recent()
            guard latest != recentCaptures else {
                return
            }
            recentCaptures = latest
            rebuildRecentMenu()
        }
    }

    /// Also called while the menu is open, when the recent captures arrive.
    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()
        let shown = recentCaptures.prefix(RecentMenu.count)
        guard !shown.isEmpty else {
            // No action, so the menu disables it.
            recentMenu.addItem(withTitle: "No Recent Notes", action: nil, keyEquivalent: "")
            return
        }
        let now = Date()
        for capture in shown {
            let item = addItem(RecentMenu.title(for: capture, now: now), #selector(openRecent(_:)), to: recentMenu)
            item.representedObject = capture.location
        }
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}

/// The amber dot on the menu bar icon while deliveries keep failing (UX_SPEC §4, ARCHITECTURE §4
/// rule 5). A view of its own, so the icon stays a template image.
private final class BadgeDot: NSView {
    static let diameter: CGFloat = 6

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    /// Runs with the view's appearance current, so the colour follows Light and Dark.
    override func updateLayer() {
        layer?.cornerRadius = Self.diameter / 2
        layer?.backgroundColor = NSColor.systemOrange.cgColor
    }

    /// Clicks go to the button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// Top-right of the button, clear of the glyph's full stop.
    func install(in button: NSView) {
        button.addSubview(self)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
            topAnchor.constraint(equalTo: button.topAnchor, constant: 1),
        ])
    }
}
