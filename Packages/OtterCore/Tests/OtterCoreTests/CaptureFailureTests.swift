import Foundation
import Testing
@testable import OtterCore

@Test func diskFullIsRecognisedHoweverItIsReported() {
    let cocoa = CocoaError(.fileWriteOutOfSpace)
    let posix = POSIXError(.ENOSPC)
    let quota = POSIXError(.EDQUOT)
    let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue, userInfo: [NSUnderlyingErrorKey: posix])

    for error in [cocoa, posix, quota, wrapped] as [any Error] {
        #expect(CaptureFailure.isOutOfSpace(error))
        #expect(CaptureFailure.message(for: error).contains("disk is full"))
    }
}

@Test func otherErrorsGetTheGenericMessage() {
    let error = CocoaError(.fileWriteNoPermission)
    #expect(!CaptureFailure.isOutOfSpace(error))
    #expect(CaptureFailure.message(for: error) == "Not saved: Otter couldn't write to its outbox. Press ⌘↩ to try again.")
}

@Test func loggableCodeHasNoDescription() {
    let error = CocoaError(.fileWriteOutOfSpace, userInfo: [NSFilePathErrorKey: "/Users/me/Notes/Secret plans.md"])
    #expect(error.loggableCode == "NSCocoaErrorDomain 640")
}
