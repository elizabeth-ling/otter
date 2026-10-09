#if OTTER_TEST_HOOKS
import AppKit
import OtterCore
import os

/// `--otter-bench full` (T14): after a normal launch, drives the panel and the pipeline the way a
/// user would, then measures what signposts can't: memory and idle wakeups. `scripts/perf.sh`
/// records the signposts at the same time and turns both into the numbers in PERF.md.
///
/// The toggle goes through the same closure the hotkey calls, and `⌘↩` is a key event sent to the
/// panel, so the editor's own key handling submits. The panel shows and takes keyboard focus about
/// 130 times, so nothing else should be typed into while it runs.
@MainActor
final class BenchRunner {
    struct Results: Codable {
        var hotkeyReadyMs: Int?
        /// Toggle press to panel key, measured here as well as by the signpost. The first show is
        /// apart: it reads the draft and lays the editor out for the first time.
        var firstShowToKeyMs: Double?
        var showToKeyMs: [Double] = []
        /// `⌘↩` to the panel starting to hide, and to it no longer being key (after the fade).
        var submitToHideMs: [Double] = []
        var submitToResignKeyMs: [Double] = []
        /// From just before `enqueue` (so including the outbox write) to the delivery, one at a time.
        var submitToDeliveredMs: [String: [Double]] = [:]
        var captures = 0
        var footprintAfterCapturesMB: Double?
        var idleSeconds = 0
        var idleWakeupsPerSecond: Double?
        var interruptWakeupsPerSecond: Double?
    }

    static let toggles = 30
    static let panelCaptures = 100
    static let directCaptures = 50
    static let idleSeconds = 60

    private let hooks: TestHooks
    private let pipeline: CapturePipeline
    private let panel: PanelController
    private let toggle: @MainActor () -> Void
    private var results = Results()
    private let clock = ContinuousClock()

    init(hooks: TestHooks, pipeline: CapturePipeline, panel: PanelController, hotkeyReady: Duration?, toggle: @escaping @MainActor () -> Void) {
        self.hooks = hooks
        self.pipeline = pipeline
        self.panel = panel
        self.toggle = toggle
        results.hotkeyReadyMs = hotkeyReady.map { Int(Self.milliseconds($0).rounded()) }
    }

    func start() {
        Task {
            await run()
            hooks.save(results, as: "bench")
            exit(0)
        }
    }

    private func run() async {
        // Past the deferred launch drain (1 s), like a user's first press.
        try? await Task.sleep(for: .seconds(2))

        for index in 0..<Self.toggles {
            let start = clock.now
            toggle()
            await waitUntil { self.panel.testWindow.isKeyWindow }
            let elapsed = Self.milliseconds(clock.now - start)
            if index == 0 {
                results.firstShowToKeyMs = elapsed
            } else {
                results.showToKeyMs.append(elapsed)
            }
            try? await Task.sleep(for: .milliseconds(200))
            toggle()
            await waitUntil { !self.panel.testWindow.isVisible }
            try? await Task.sleep(for: .milliseconds(200))
        }

        for index in 0..<Self.panelCaptures {
            toggle()
            await waitUntil { self.panel.testWindow.isKeyWindow }
            panel.testSetText(Self.noteText(index: index))
            try? await Task.sleep(for: .milliseconds(100))

            var hiddenAt: ContinuousClock.Instant?
            panel.testOnHide = { hiddenAt = self.clock.now }
            let start = clock.now
            sendCommandReturn()
            await waitUntil { hiddenAt != nil }
            await waitUntil { !self.panel.testWindow.isKeyWindow }
            let resigned = clock.now
            panel.testOnHide = nil
            if let hiddenAt {
                results.submitToHideMs.append(Self.milliseconds(hiddenAt - start))
            }
            results.submitToResignKeyMs.append(Self.milliseconds(resigned - start))
            results.captures += 1
            try? await Task.sleep(for: .milliseconds(200))
        }
        await waitUntilDelivered()

        await measureDelivery()
        await waitUntilDelivered()

        // Idle, as after a day's use: nothing shown, nothing pending.
        try? await Task.sleep(for: .seconds(5))
        results.footprintAfterCapturesMB = ProcessUsage.footprintBytes().map { Double($0) / 1_048_576 }
        if let before = ProcessUsage.wakeups() {
            try? await Task.sleep(for: .seconds(Self.idleSeconds))
            if let after = ProcessUsage.wakeups() {
                results.idleSeconds = Self.idleSeconds
                results.idleWakeupsPerSecond = Double(after.idle - before.idle) / Double(Self.idleSeconds)
                results.interruptWakeupsPerSecond = Double(after.interrupt - before.interrupt) / Double(Self.idleSeconds)
            }
        }
    }

    /// Captures straight into the pipeline for a plain folder and an Obsidian vault, one at a time.
    private func measureDelivery() async {
        guard let ids = try? hooks.addTestDestinations(to: pipeline.destinations) else {
            return
        }
        // The signposts carry destination IDs; `perf_report.py` shows names.
        hooks.save(Dictionary(uniqueKeysWithValues: ids.map { ($1.description, $0) }), as: "destinations")
        var deliveries = await pipeline.delivery.deliveries().makeAsyncIterator()
        for name in ["Folder", "Vault"] {
            guard let id = ids[name] else {
                continue
            }
            for index in 0..<Self.directCaptures {
                let start = clock.now
                let result = await pipeline.captureService.enqueue(text: Self.noteText(index: index), destinationID: id, source: .panel)
                guard case .success = result, let delivery = await deliveries.next(), delivery.destinationID == id else {
                    continue
                }
                results.submitToDeliveredMs[name, default: []].append(Self.milliseconds(clock.now - start))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func waitUntilDelivered() async {
        await pipeline.delivery.kick()
        for await status in await pipeline.delivery.statusUpdates() where status.pendingCount == 0 {
            break
        }
    }

    /// `⌘↩`, as if typed into the panel.
    private func sendCommandReturn() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.testWindow.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) else {
            return
        }
        NSApp.sendEvent(event)
    }

    /// Checks every millisecond, for up to 2 s. The signposts have the exact times.
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        let deadline = clock.now + .seconds(2)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// A few lines, sometimes a few kilobytes, like real notes.
    private static func noteText(index: Int) -> String {
        let line = "Bench note \(index): call the plumber about the kitchen tap, then buy oat milk."
        return Array(repeating: line, count: index % 10 == 0 ? 60 : 1 + index % 4).joined(separator: "\n")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        duration / .milliseconds(1)
    }
}
#endif
