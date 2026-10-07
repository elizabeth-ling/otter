import AppKit
import OtterCore
import os
import Sparkle

/// Sparkle 2 updates (T13): Otter's only network access (ADR-009). While "Automatically check for
/// updates" is on (Settings › Advanced, on by default), Sparkle asks the appcast on GitHub once a
/// day whether there's a newer version; "Check for Updates…" in the menu bar asks now. Sparkle sends
/// no system profile, only its User-Agent with Otter's version.
///
/// Otter is an agent app, so a scheduled check never brings an update window forward over the
/// user's work (Sparkle's "gentle reminders"): the menu bar item becomes "Update Available…", and the
/// window opens when the user picks it.
@MainActor
final class UpdateController: NSObject {
    private var controller: SPUStandardUpdaterController?

    /// A scheduled check found an update the user hasn't seen yet.
    private(set) var hasUnseenUpdate = false

    override init() {
        super.init()
        #if DEBUG
        // A Debug build (build number 1) would be offered every release, and would reach the network
        // while developing. Test updates with `scripts/release.sh --local` builds instead.
        Logger.app.info("Updates are off in Debug builds")
        #else
        // Started here rather than by the controller, so a failure (e.g. a missing public key in a
        // local build) is logged and turns updates off instead of showing Sparkle's alert.
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        do {
            try controller.updater.start()
            self.controller = controller
        } catch {
            Logger.app.error("Updates are off: \(error.loggableCode, privacy: .public)")
        }
        #endif
    }

    /// False while a check or an install is in progress, and when the updater couldn't start.
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    var isAvailable: Bool {
        controller != nil
    }

    /// Kept by Sparkle in Otter's defaults (`SUEnableAutomaticChecks`); Info.plist makes it on by
    /// default, without Sparkle's "check automatically?" prompt.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Shows Sparkle's window: the update found, "You're up to date", or the error.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// After "Reset All Settings" removed Sparkle's keys: schedule from the restored defaults.
    func settingsDidReset() {
        controller?.updater.resetUpdateCycleAfterShortDelay()
    }
}

// Sparkle calls these on the main thread.
extension UpdateController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    /// Sparkle shows the update itself only when Otter is already in front, e.g. just opened from
    /// Finder; otherwise the menu bar item waits for the user.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate, !state.userInitiated else {
            return
        }
        MainActor.assumeIsolated {
            hasUnseenUpdate = true
            Logger.app.info("An update is available; the menu bar shows it")
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            hasUnseenUpdate = false
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            hasUnseenUpdate = false
        }
    }
}
