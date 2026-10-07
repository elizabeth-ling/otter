import Foundation

/// The health dot in Settings › Destinations (T10).
public enum HealthLevel: Sendable, Equatable {
    /// Green.
    case good
    /// Amber: works once the user grants access.
    case warning
    /// Red: notes for it wait in the outbox.
    case failing
}

public extension DestinationHealth {
    var level: HealthLevel {
        switch self {
        case .ok:
            .good
        case .needsPermission:
            .warning
        case .unreachable:
            .failing
        }
    }
}

/// What's wrong with a destination, in words the user can act on, and the button that fixes it
/// (ARCHITECTURE §10). From a health check or a failed Test (T10).
public struct DestinationProblem: Error, Sendable, Equatable {
    public enum Fix: Sendable, Equatable {
        /// The folder is gone: choose it again, or another one.
        case chooseFolder
        /// Otter may not write there: choosing the folder in the picker grants access (ARCHITECTURE §7).
        case grantAccess
    }

    public var message: String
    public var fix: Fix?

    public init(message: String, fix: Fix?) {
        self.message = message
        self.fix = fix
    }

    /// `nil` when the destination is fine.
    public init?(health: DestinationHealth, destinationName name: String) {
        switch health {
        case .ok:
            return nil
        case .needsPermission:
            self = Self.noAccess(name)
        case let .unreachable(reason):
            if reason == FolderDestinationError.folderMissing.localizedDescription {
                self = Self.missing(name)
            } else {
                self.init(message: "Can't write to ‘\(name)’: \(reason).", fix: nil)
            }
        }
    }

    /// A failed delivery or Test.
    public init(error: any Error, destinationName name: String) {
        if let error = error as? FolderDestinationError {
            switch error {
            case .folderMissing:
                self = Self.missing(name)
            case .unsafePath:
                self.init(message: "Can't write to ‘\(name)’: its subfolder or file name points outside the folder. Change it below.", fix: nil)
            }
            return
        }
        if Self.isNoPermission(error) {
            self = Self.noAccess(name)
        } else if Self.isOutOfSpace(error) {
            self.init(message: "Can't write to ‘\(name)’: the disk is full.", fix: nil)
        } else {
            self.init(message: "Can't write to ‘\(name)’: \(error.localizedDescription)", fix: nil)
        }
    }

    private static func missing(_ name: String) -> Self {
        Self(message: "Can't write to ‘\(name)’: the folder is missing. Choose it again.", fix: .chooseFolder)
    }

    private static func noAccess(_ name: String) -> Self {
        Self(message: "Otter isn't allowed to write to ‘\(name)’. Choose the folder to give it access.", fix: .grantAccess)
    }

    private static func isNoPermission(_ error: any Error) -> Bool {
        matches(error, cocoa: [CocoaError.fileWriteNoPermission.rawValue, CocoaError.fileReadNoPermission.rawValue], posix: [EACCES, EPERM])
    }

    private static func isOutOfSpace(_ error: any Error) -> Bool {
        matches(error, cocoa: [CocoaError.fileWriteOutOfSpace.rawValue], posix: [ENOSPC, EDQUOT])
    }

    /// The error itself or the POSIX error underneath it.
    private static func matches(_ error: any Error, cocoa: Set<Int>, posix: Set<Int32>) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, cocoa.contains(error.code) {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, posix.contains(Int32(error.code)) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return matches(underlying, cocoa: cocoa, posix: posix)
        }
        return false
    }
}

public extension DestinationConfig {
    /// The line under the name in Settings › Destinations.
    var modeSummary: String {
        switch options {
        case let .folder(options):
            switch options.mode {
            case .newFilePerNote:
                "New file per note"
            case let .appendToFile(name):
                "Appends to \((name as NSString).pathExtension.isEmpty ? "\(name).md" : name)"
            }
        }
    }
}

/// The Test button (T10): writes a real note to a destination straight away, bypassing the outbox,
/// so the result shows at once.
public enum DestinationTest {
    public static let text = "Otter test — you can delete this"

    /// - Parameter files: An empty directory standing in for the capture's outbox files; a test
    ///   note has no attachments.
    public static func run(_ destination: any Destination, files: URL, now: Date = Date()) async -> Result<DeliveryReceipt, DestinationProblem> {
        let capture = Capture(createdAt: now, text: text, destinationID: destination.id, source: .panel)
        do {
            return .success(try await destination.deliver(capture, files: files))
        } catch {
            return .failure(DestinationProblem(error: error, destinationName: destination.displayName))
        }
    }
}
