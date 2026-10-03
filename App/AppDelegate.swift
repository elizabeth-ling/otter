import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    // Keep this minimal: it sits on the cold-launch path (ARCHITECTURE §9).
    // Later tasks register services here; anything slow must be deferred.
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()
    }
}
