import AppKit
import OtterCore
import UserNotifications
import os

/// Tells the user when notes can't be delivered (ARCHITECTURE §4 rule 5, §7): one notification per
/// destination per failure burst, "1 note couldn't be delivered to Inbox", never the note's text.
/// Permission is asked for at the first failed delivery, not at launch; if it's denied, the menu
/// bar badge is all that shows. Clicking the notification opens Settings › Advanced.
@MainActor
final class DeliveryNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let destinationName: @MainActor (DestinationID) -> String
    private let showDetails: @MainActor () -> Void
    /// Asked once per run; macOS keeps the answer and prompts only the first time.
    private var authorization: Task<Bool, Never>?

    init(
        destinationName: @escaping @MainActor (DestinationID) -> String,
        showDetails: @escaping @MainActor () -> Void
    ) {
        self.destinationName = destinationName
        self.showDetails = showDetails
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func statusDidChange(from old: DeliveryStatus, to new: DeliveryStatus) {
        if !new.failingDestinations.isEmpty {
            _ = authorize()
        }
        for (id, count) in DeliveryAlert.newlyAlerting(from: old, to: new) {
            post(DeliveryAlert.notificationText(count: count, destinationName: destinationName(id)), for: id)
        }
        let recovered = DeliveryAlert.recovered(from: old, to: new)
        if !recovered.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: recovered.map(Self.identifier))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shown even while Otter is active, e.g. with Settings open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await openDetails()
    }

    // MARK: - Private

    private func openDetails() {
        showDetails()
    }

    private func authorize() -> Task<Bool, Never> {
        if let authorization {
            return authorization
        }
        let task = Task {
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            } catch {
                Logger.app.error("Couldn't ask to show notifications: \(error.loggableCode, privacy: .public)")
                return false
            }
        }
        authorization = task
        return task
    }

    /// Replaces an earlier notification for the same destination.
    private func post(_ text: String, for id: DestinationID) {
        Logger.app.info("Deliveries to \(id, privacy: .public) keep failing; notifying")
        let authorization = authorize()
        Task {
            guard await authorization.value else {
                Logger.app.info("Notifications aren't allowed; only the menu bar badge shows")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = text
            let request = UNNotificationRequest(identifier: Self.identifier(id), content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Logger.app.error("Couldn't show the delivery notification: \(error.loggableCode, privacy: .public)")
            }
        }
    }

    private static func identifier(_ id: DestinationID) -> String {
        "deliveryFailed.\(id)"
    }
}
