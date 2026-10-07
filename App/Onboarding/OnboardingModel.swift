import AppKit
import KeyboardShortcuts
import Observation
import OtterCore
import os

/// First-run onboarding's state (T10, UX_SPEC §6): the hotkey, where notes go, then a first note.
/// Shown once, in the Settings window, until `hasOnboarded` is set.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case hotkey
        case destination
        case tryIt
    }

    enum DestinationChoice: Hashable {
        case vault(URL)
        /// The default `~/Documents/Otter Inbox/`.
        case inbox
        /// A folder picked with "A folder…".
        case folder
    }

    @ObservationIgnored let hotkeys: HotkeyService
    /// For the folder picker's sheet.
    @ObservationIgnored weak var window: NSWindow?
    /// Done: close the window.
    @ObservationIgnored var onFinish: (@MainActor () -> Void)?

    @ObservationIgnored private let settings = AppSettings()
    @ObservationIgnored private let folderChooser: FolderChooser
    @ObservationIgnored private let delivery: DeliveryService
    @ObservationIgnored private var deliveryTask: Task<Void, Never>?

    private(set) var step = Step.hotkey

    // MARK: Step 1

    /// The registered shortcut when a press last reached Otter during this step.
    private(set) var lastPress: HotkeyCombo?
    var isRecordingOtherShortcut = false
    var shortcutNote: String?

    var hotkeyStatus: OnboardingHotkeyStatus {
        OnboardingHotkeyStatus(effective: hotkeys.effectiveToggle, lastPress: lastPress)
    }

    // MARK: Step 2

    private(set) var vaults: [DiscoveredVault] = []
    var choice = DestinationChoice.inbox
    private(set) var chosenFolder: URL?

    // MARK: Step 3

    /// The first note delivered since step 3 opened.
    private(set) var firstDelivery: Delivery?
    var launchAtLogin = true

    init(hotkeys: HotkeyService, folderChooser: FolderChooser, delivery: DeliveryService) {
        self.hotkeys = hotkeys
        self.folderChooser = folderChooser
        self.delivery = delivery
    }

    /// From the first step. Pre-selects the vault opened most recently, if there is one.
    func start() {
        step = .hotkey
        lastPress = nil
        firstDelivery = nil
        launchAtLogin = settings.launchAtLogin
        hotkeys.refreshSpotlightState()
        Task {
            let vaults = await Task.detached(priority: .userInitiated) { VaultDiscovery.vaults() }.value
            self.vaults = vaults
            if choice == .inbox, let newest = vaults.first {
                choice = .vault(newest.path)
            }
        }
    }

    /// The toggle hotkey fired while onboarding is on screen. In step 1 the press confirms the
    /// shortcut rather than opening the panel; from step 3 it opens the panel to try it.
    /// - Returns: Whether the press was used here.
    func handleTogglePress() -> Bool {
        guard step == .hotkey else {
            return false
        }
        lastPress = hotkeys.effectiveToggle.combo
        Logger.hotkey.info("Onboarding: the toggle shortcut reached Otter")
        return true
    }

    func useCommandSpace() {
        isRecordingOtherShortcut = false
        shortcutNote = ShortcutText.note(for: hotkeys.useCommandSpace(), otherAction: "Save clipboard")
    }

    func recordedShortcut() {
        shortcutNote = ShortcutText.note(for: hotkeys.shortcutDidChange(for: .togglePanel), otherAction: "Save clipboard")
    }

    func next() {
        switch step {
        case .hotkey:
            step = .destination
        case .destination:
            applyDestination()
            step = .tryIt
            listenForFirstDelivery()
        case .tryIt:
            finish()
        }
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else {
            return
        }
        if step == .tryIt {
            deliveryTask?.cancel()
            deliveryTask = nil
        }
        step = previous
    }

    /// "A folder…": the picker, as a sheet. Cancel goes back to the previous choice.
    func chooseFolder(otherwise previous: DestinationChoice) async {
        let presentation: FolderChooser.Presentation = window.map { .sheet(on: $0) } ?? .window(above: nil)
        if let folder = await folderChooser.pickFolder(startingAt: chosenFolder, presentation: presentation) {
            chosenFolder = folder
            choice = .folder
        } else if chosenFolder == nil {
            choice = previous
        }
    }

    /// "Open" in step 3: the note in Obsidian, or in Finder.
    func openFirstNote() {
        guard case let .file(url)? = firstDelivery?.receipt.location else {
            return
        }
        ObsidianLink.open(url)
    }

    func finish() {
        settings.launchAtLogin = launchAtLogin
        settings.hasOnboarded = true
        deliveryTask?.cancel()
        deliveryTask = nil
        Logger.panel.info("Onboarding finished")
        onFinish?()
    }

    /// Closing the window counts as done: onboarding is shown once.
    func windowWillClose() {
        settings.hasOnboarded = true
        deliveryTask?.cancel()
        deliveryTask = nil
    }

    // MARK: - Private

    /// The choice becomes the default destination, in place of the inbox (ADR-013: one file per note).
    private func applyDestination() {
        switch choice {
        case let .vault(root):
            folderChooser.use(root, for: nil)
        case .folder:
            if let chosenFolder {
                folderChooser.use(chosenFolder, for: nil)
            }
        case .inbox:
            break
        }
    }

    private func listenForFirstDelivery() {
        deliveryTask?.cancel()
        firstDelivery = nil
        deliveryTask = Task { [weak self, delivery] in
            for await delivered in await delivery.deliveries() {
                self?.firstDelivery = delivered
                return
            }
        }
    }
}
