import AppKit
import OtterCore
import os

/// One Otter at a time (#2). Every copy of Otter.app (the DMG's next to /Applications', a Debug build
/// next to the release) shares the preferences and `StorageLocations`, so a second process would drain
/// the same outbox and could save a capture twice.
@MainActor
enum SingleInstance {
    /// Another Otter to defer to, or `nil` if this process should run. Of two copies launched at once,
    /// the one with the higher pid defers, so exactly one keeps running.
    static func runningCopy() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return nil
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { other in
            other.processIdentifier != pid && !other.isTerminated
                && (other.isFinishedLaunching || other.processIdentifier < pid)
        }
    }

    /// Opens `copy` as Finder would, so it shows Settings (`applicationShouldHandleReopen`), then quits.
    static func handOff(to copy: NSRunningApplication) {
        Logger.app.info("Otter is already running (pid \(copy.processIdentifier, privacy: .public)); quitting this copy")
        guard let url = copy.bundleURL else {
            copy.activate()
            NSApp.terminate(nil)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Logger.app.error("Couldn't bring the running Otter to the front: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
