import OtterCore
import ServiceManagement
import os

/// "Launch at login" (T12): Otter itself as a login item, through `SMAppService.mainApp`. macOS
/// keeps the real state, and the user can change it in System Settings › General › Login Items, so
/// Settings shows `status` rather than the stored preference. Registered only when the user chooses
/// (Settings › General, onboarding's last step), never at launch, so Otter doesn't undo a removal
/// made in System Settings.
@MainActor
enum LoginItem {
    /// An XPC call to macOS; read it when it's shown, not on the launch path.
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// On, including while macOS waits for the user to approve it.
    static func isOn(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    /// Adds or removes the login item. A failure is logged; the status returned shows what macOS did.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> SMAppService.Status {
        let service = SMAppService.mainApp
        let current = service.status
        do {
            if enabled, !isOn(current) {
                try service.register()
                Logger.app.info("Added the login item")
            } else if !enabled, isOn(current) {
                try service.unregister()
                Logger.app.info("Removed the login item")
            }
        } catch {
            Logger.app.error("Couldn't \(enabled ? "add" : "remove", privacy: .public) the login item: \(error.loggableCode, privacy: .public)")
        }
        let status = service.status
        if status == .requiresApproval {
            Logger.app.notice("The login item waits for approval in System Settings")
        }
        return status
    }

    /// System Settings › General › Login Items, to approve Otter.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
