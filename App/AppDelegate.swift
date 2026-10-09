import AppKit
import OtterCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var capturePipeline: CapturePipeline?

    #if OTTER_TEST_HOOKS
    /// The soak test or a benchmark (T14). Read first, since it moves Otter's files.
    private let testHooks = TestHooks.fromLaunchArguments()
    #endif

    /// `.standard`, or the test hooks' own suite.
    private var defaults: UserDefaults {
        #if OTTER_TEST_HOOKS
        testHooks?.defaults ?? .standard
        #else
        .standard
        #endif
    }

    /// Builds the capture pipeline before `applicationDidFinishLaunching`, so it already exists when
    /// the panel (T03) and the clipboard hotkey (T11) are wired to it there. It's cheap: no disk work,
    /// and the first outbox drain waits 1 s.
    func applicationWillFinishLaunching(_ notification: Notification) {
        #if OTTER_TEST_HOOKS
        let pipeline = testHooks.map { CapturePipeline(defaults: $0.defaults, documents: $0.documents) } ?? CapturePipeline()
        #else
        let pipeline = CapturePipeline()
        #endif
        // The panel keeps the note open; showing `message` in its footer is still to come.
        pipeline.captureService.onCaptureFailed = { message in
            Logger.pipeline.error("Capture not saved; the panel will show this in the footer: \(message, privacy: .public)")
        }
        pipeline.start()
        capturePipeline = pipeline
    }

    private var statusItemController: StatusItemController?
    private var hotkeyService: HotkeyService?
    private var panelController: PanelController?
    private var settingsWindowController: SettingsWindowController?
    private var updateController: UpdateController?
    /// How long after the process started the toggle hotkey was registered.
    private var hotkeyReadyAfter: Duration?

    // Keep this minimal: it sits on the cold-launch path (ARCHITECTURE §9).
    // Later tasks register services here; anything slow must be deferred.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let pipeline = capturePipeline else {
            return
        }
        #if OTTER_TEST_HOOKS
        if let testHooks, case let .soak(count, interval) = testHooks.mode {
            // No UI: just the pipeline, as fast as it goes.
            SoakRunner(hooks: testHooks, pipeline: pipeline, count: count, interval: interval).start()
            return
        }
        #endif
        // Built once here and only ordered in and out (ARCHITECTURE §6).
        let destinations = pipeline.destinations
        let captureService = pipeline.captureService
        let folderChooser = FolderChooser(destinations: destinations, delivery: pipeline.delivery)
        // Set below; the panel's `⌘,` and the menu bar open it.
        var settingsWindow: SettingsWindowController?
        // One stager for `drafts/files/`, shared with the clipboard hotkey, so the panel's launch sweep
        // never removes a file the hotkey staged this session.
        let attachmentStager = AttachmentStager(directory: StorageLocations.draftFiles)
        let panel = PanelController(
            defaults: defaults,
            draftStore: DraftStore(fileURL: StorageLocations.draft),
            attachmentStager: attachmentStager
        ) { id in
            // A destination deleted in Settings since it was picked falls back to the default.
            guard let config = id.flatMap(destinations.config(for:)) ?? destinations.defaultID.flatMap(destinations.config(for:)) else {
                return PanelDestination(name: "No destination")
            }
            return PanelDestination(config)
        } destinationChoices: {
            destinations.configs.map(PanelDestination.init)
        } refreshDestination: { id in
            // A folder destination re-bookmarks a renamed folder here, which updates its name.
            guard let destination = (id ?? destinations.defaultID).flatMap(destinations.destination(for:)) else {
                return
            }
            _ = await destination.healthCheck()
        } submit: { text, file, attachments, id in
            await captureService.submit(text: text, saveAs: file, attachments: attachments, destinationID: id)
        } chooseFolder: { window, id in
            await folderChooser.chooseFolder(for: id, presentation: .window(above: window))
        } chooseSaveFile: { window, defaultName, id in
            await SaveAsPrompt.chooseFile(above: window, in: folderChooser.currentFolder(for: id), defaultName: defaultName)
        } openSettings: {
            settingsWindow?.showSettings()
        }
        panelController = panel

        // The HUD's panel is built on its first message, not here.
        let clipboardCapture = ClipboardCapture(captureService: captureService, destinations: destinations, stager: attachmentStager, hud: HUDController())

        let hotkeys = HotkeyService()
        hotkeys.onTogglePanel = {
            // Onboarding's first step asks for a press to check the shortcut reaches Otter.
            if settingsWindow?.handleTogglePress() == true {
                return
            }
            panel.toggle()
        }
        hotkeys.onSaveClipboard = {
            clipboardCapture.save()
        }
        hotkeys.start()
        hotkeyService = hotkeys
        hotkeyReadyAfter = logHotkeyReady()

        // Cheap: Sparkle reads its defaults and schedules the next check; nothing goes over the
        // network here.
        let updates = UpdateController()
        updateController = updates

        // The window itself is built on first show.
        let settings = SettingsWindowController(
            model: SettingsModel(pipeline: pipeline, hotkeys: hotkeys, folderChooser: folderChooser, panel: panel, updates: updates),
            onboarding: OnboardingModel(hotkeys: hotkeys, folderChooser: folderChooser, delivery: pipeline.delivery)
        )
        settingsWindow = settings
        settingsWindowController = settings

        let notifier = DeliveryNotifier { id in
            destinations.config(for: id)?.name ?? "its destination"
        } showDetails: {
            settings.showSettings(tab: .advanced)
        }
        statusItemController = StatusItemController(
            hotkeys: hotkeys,
            recents: pipeline.recents,
            delivery: pipeline.delivery,
            notifier: notifier,
            updates: updates,
            actions: StatusItemController.Actions(
                newNote: { panel.show() },
                saveClipboard: { clipboardCapture.save() },
                finishHotkeySetup: { settings.showHotkeySetup() },
                openSettings: { settings.showSettings() }
            )
        )

        if !AppSettings(defaults: defaults).hasOnboarded {
            // After launch finishes, off the cold-launch path.
            DispatchQueue.main.async {
                settings.showOnboarding()
            }
        }

        #if OTTER_TEST_HOOKS
        switch testHooks?.mode {
        case .benchLaunch:
            testHooks?.save(["hotkeyReadyMs": hotkeyReadyAfter.map { $0 / .milliseconds(1) }], as: "launch-\(getpid())")
            exit(0)
        case .bench:
            if let testHooks {
                BenchRunner(hooks: testHooks, pipeline: pipeline, panel: panel, hotkeyReady: hotkeyReadyAfter) {
                    hotkeys.onTogglePanel?()
                }.start()
            }
        case .soak, nil:
            break
        }
        #endif
    }

    /// Cold launch → hotkey registered (ARCHITECTURE §9): an event in Points of Interest, and a log
    /// line, since Instruments isn't always running.
    private func logHotkeyReady() -> Duration? {
        guard let elapsed = ProcessLaunch.elapsed() else {
            return nil
        }
        let milliseconds = Int((elapsed / .milliseconds(1)).rounded())
        os_signpost(.event, log: Signpost.log, name: Signpost.hotkeyReady, "%d ms after the process started", milliseconds)
        Logger.app.info("Hotkey registered \(milliseconds, privacy: .public) ms after the process started")
        return elapsed
    }

    /// Otter.app opened again while it's running (Finder, Spotlight, Launchpad). An agent app has no
    /// window to bring back, so Settings opens.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowController?.showSettings()
        return false
    }

    /// Synchronous, so the draft is on disk before the process exits.
    func applicationWillTerminate(_ notification: Notification) {
        panelController?.flushDraft()
    }
}
