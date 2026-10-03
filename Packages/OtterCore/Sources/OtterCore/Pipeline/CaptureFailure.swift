import Foundation

/// What the panel footer says when a note can't be saved to the outbox. The panel stays open and
/// keeps the text (T05 §6). The wording is short and actionable (ARCHITECTURE §10).
public enum CaptureFailure {
    public static let noDestinationMessage = "Not saved: there's no destination yet. Add one in Settings, then press ⌘↩ again."

    public static func message(for error: any Error) -> String {
        if isOutOfSpace(error) {
            return "Not saved: your disk is full. Free up some space, then press ⌘↩ again."
        }
        return "Not saved: Otter couldn't write to its outbox. Press ⌘↩ to try again."
    }

    static func isOutOfSpace(_ error: any Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain where error.code == CocoaError.fileWriteOutOfSpace.rawValue:
            return true
        case NSPOSIXErrorDomain where error.code == Int(ENOSPC) || error.code == Int(EDQUOT):
            return true
        default:
            guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? any Error else {
                return false
            }
            return isOutOfSpace(underlying)
        }
    }
}
