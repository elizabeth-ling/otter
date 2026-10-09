import Foundation
import os

/// `os_signpost` intervals from ARCHITECTURE §9. They are logged to Points of Interest so they
/// show up in Instruments without extra setup. Most intervals use the `.exclusive` signpost ID
/// (only one runs at a time), so the code that ends it doesn't need an ID from the code that began it.
/// `enqueueToDelivered` overlaps, so it's keyed by capture (`id(for:)`).
public enum Signpost {
    public static let log = OSLog(subsystem: Logger.subsystem, category: .pointsOfInterest)

    /// An event, once the toggle hotkey is registered at launch. Its message is the time since the
    /// process started (`ProcessLaunch.elapsed`). Budget: < 300 ms.
    public static let hotkeyReady: StaticString = "hotkey ready"

    /// Begun by `PanelController` when a toggle press shows the panel; ended once the panel is key.
    public static let hotkeyToVisible: StaticString = "hotkey→visible"

    /// Begun by `PanelController` on `⌘↩`; ended when the panel stops taking keys and starts to fade
    /// out, which is when focus is back with the app the user came from. Budget: < 50 ms.
    public static let submitToHidden: StaticString = "submit→hidden"

    /// Begun once the outbox has a capture, ended once a destination has it, keyed by capture ID
    /// with the destination ID as the message. Budget: p95 < 50 ms for a folder.
    public static let enqueueToDelivered: StaticString = "enqueue→delivered"

    /// One inline-styling pass in the panel's editor (ADR-016): parse the note, re-attribute the
    /// lines whose styling changed. Budget: < 1 ms for a 10 KB note.
    public static let restyle: StaticString = "restyle"

    /// A signpost ID for one capture, so its `enqueueToDelivered` begin and end match up.
    public static func id(for captureID: UUID) -> OSSignpostID {
        let bytes = captureID.uuid
        let value = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7]
            .reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        // 0 and ~0 are `.null` and `.invalid`.
        return OSSignpostID(value == 0 || value == .max ? 1 : value)
    }
}

/// How long ago this process started, from the kernel's start time for it, so it covers dyld and
/// everything before `main`.
public enum ProcessLaunch {
    public static func elapsed(now: Date = Date()) -> Duration? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        let start = info.kp_proc.p_starttime
        let started = Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        return .seconds(now.timeIntervalSince(started))
    }
}
