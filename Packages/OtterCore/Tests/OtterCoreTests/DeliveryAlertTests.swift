import Foundation
import Testing
@testable import OtterCore

@Test(.timeLimit(.minutes(1)))
func destinationAlertsFromItsFifthFailureInARowUntilDelivered() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = TestClock()
    let destination = FakeDestination(failTimes: 5, clock: clock)
    let outbox = Outbox(directory: root)
    let service = DeliveryService(outbox: outbox, destinations: { _ in destination }, clock: clock)

    try await outbox.enqueue(makeCapture("one", destination: destination.id))
    try await outbox.enqueue(makeCapture("two", destination: destination.id))
    await service.kick()
    await service.waitUntilIdle()

    for failures in 1...5 {
        let deadline = await clock.nextSleepDeadline()
        let status = await service.status
        #expect(await outbox.pending().first?.attempts == failures)
        #expect(status.failingDestinations == [destination.id])
        // Both captures wait, but only the first has been tried.
        let expected = failures >= DeliveryAlert.failureThreshold ? [destination.id: 2] : [:]
        #expect(status.alertingDestinations == expected, "after \(failures) failure(s)")
        clock.advance(to: deadline)
    }

    await destination.waitForDeliveries(2)
    await service.waitUntilIdle()
    #expect(await service.status == .idle)
}

@Test func alertingIsNotifiedOncePerBurst() {
    let inbox = DestinationID()
    let vault = DestinationID()
    let idle = DeliveryStatus.idle
    var failing = idle
    failing.alertingDestinations = [inbox: 1]
    var stillFailing = failing
    stillFailing.alertingDestinations = [inbox: 3, vault: 1]

    #expect(DeliveryAlert.newlyAlerting(from: idle, to: failing) == [inbox: 1])
    #expect(DeliveryAlert.newlyAlerting(from: failing, to: failing).isEmpty)
    // More notes waiting for the same destination isn't a new burst; another destination is.
    #expect(DeliveryAlert.newlyAlerting(from: failing, to: stillFailing) == [vault: 1])
    #expect(DeliveryAlert.recovered(from: stillFailing, to: failing) == [vault])
    #expect(DeliveryAlert.recovered(from: failing, to: idle) == [inbox])
    #expect(DeliveryAlert.recovered(from: idle, to: failing).isEmpty)
    // A fresh burst after recovering is notified again.
    #expect(DeliveryAlert.newlyAlerting(from: idle, to: failing) == [inbox: 1])

    #expect(!DeliveryAlert.isAlerting(failures: 4))
    #expect(DeliveryAlert.isAlerting(failures: 5))
}

@Test func alertTextNamesTheDestinationAndCountOnly() {
    #expect(DeliveryAlert.notificationText(count: 1, destinationName: "Inbox") == "1 note couldn't be delivered to Inbox")
    #expect(DeliveryAlert.notificationText(count: 3, destinationName: "Work Vault") == "3 notes couldn't be delivered to Work Vault")
    #expect(DeliveryAlert.waitingRow(count: 1) == "1 note waiting to deliver… Retry")
    #expect(DeliveryAlert.waitingRow(count: 2) == "2 notes waiting to deliver… Retry")
}

@Test func recentMenuTitleIsFirstLineDestinationAndTime() {
    let now = referenceDate
    let english = Locale(identifier: "en_US")
    func recent(_ firstLine: String, deliveredAt: Date) -> RecentCapture {
        RecentCapture(
            id: UUID(),
            firstLine: firstLine,
            destinationName: "Inbox",
            location: .file(URL(fileURLWithPath: "/Notes/Inbox/Note.md")),
            deliveredAt: deliveredAt
        )
    }

    #expect(RecentMenu.title(for: recent("Call the dentist", deliveredAt: now - 300), now: now, locale: english) == "Call the dentist · Inbox · 5 min. ago")
    // The clock moved back since the delivery.
    #expect(RecentMenu.title(for: recent("Call the dentist", deliveredAt: now + 60), now: now, locale: english) == "Call the dentist · Inbox · now")
    #expect(RecentMenu.title(for: recent("", deliveredAt: now), now: now, locale: english).hasPrefix("Untitled note · Inbox · "))

    let long = String(repeating: "word ", count: 20)
    let cut = RecentMenu.firstLine(long)
    #expect(cut.count <= RecentMenu.maxFirstLineLength)
    #expect(cut.hasSuffix("…"))
    #expect(!cut.hasSuffix(" …"))
    let exactly40 = String(repeating: "a", count: 40)
    #expect(RecentMenu.firstLine(exactly40) == exactly40)
}
