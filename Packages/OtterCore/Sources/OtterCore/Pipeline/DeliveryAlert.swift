import Foundation

/// When failed deliveries need the user's attention, and what to tell them (ARCHITECTURE §4 rule 5).
/// Nothing here includes note text: only counts and destination names.
public enum DeliveryAlert {
    /// Failures in a row for one destination before the menu bar badge and the notification.
    public static let failureThreshold = 5

    /// Whether a destination whose oldest waiting capture has failed `failures` times needs the user.
    /// That capture holds back the rest of its lane, so its attempts are the destination's
    /// consecutive failures.
    public static func isAlerting(failures: Int) -> Bool {
        failures >= failureThreshold
    }

    /// Destinations that started needing attention between two statuses, with how many captures
    /// wait for each. Each gets one notification: it stays alerting through later failures and
    /// Retry, until its captures are delivered or moved, so a burst is notified once.
    public static func newlyAlerting(from old: DeliveryStatus, to new: DeliveryStatus) -> [DestinationID: Int] {
        new.alertingDestinations.filter { old.alertingDestinations[$0.key] == nil }
    }

    /// Destinations that no longer need attention: their notification can go.
    public static func recovered(from old: DeliveryStatus, to new: DeliveryStatus) -> Set<DestinationID> {
        Set(old.alertingDestinations.keys).subtracting(new.alertingDestinations.keys)
    }

    /// The notification: "1 note couldn't be delivered to Inbox".
    public static func notificationText(count: Int, destinationName: String) -> String {
        "\(notes(count)) couldn't be delivered to \(destinationName)"
    }

    /// The menu bar row (UX_SPEC §4): "2 notes waiting to deliver… Retry".
    public static func waitingRow(count: Int) -> String {
        "\(notes(count)) waiting to deliver… Retry"
    }

    private static func notes(_ count: Int) -> String {
        count == 1 ? "1 note" : "\(count) notes"
    }
}
