#if OTTER_TEST_HOOKS
import AppKit
import OtterCore

/// Launch arguments for the soak test and the benchmarks (T14). Compiled into Debug builds, and into
/// the Release build `scripts/perf.sh` makes with `OTTER_TEST_HOOKS`; never into a shipped build.
///
/// - `--otter-dir DIR` (required): everything goes under `DIR`: the outbox and draft, the
///   destinations' folders, and the results. The preferences go to their own suite, wiped when `DIR`
///   is new. The user's own notes and settings are never touched.
/// - `--otter-soak N [--otter-soak-interval MS]`: no UI. Submits synthetic captures until `N` are in
///   the outbox, waits for delivery, then quits. Run it again after a kill and it carries on
///   (`SoakRunner`, `scripts/soak.sh`).
/// - `--otter-bench launch`: quits once the hotkey is registered, after saving how long that took.
/// - `--otter-bench full`: launches as usual, then drives the panel and the pipeline and saves the
///   memory and wakeups it measures (`BenchRunner`, `scripts/perf.sh`).
struct TestHooks {
    enum Mode: Equatable {
        case soak(count: Int, interval: Duration)
        case benchLaunch
        case bench
    }

    static let suiteName = "io.github.elizabeth-ling.otter.test-hooks"

    let mode: Mode
    let directory: URL
    let defaults: UserDefaults

    /// Stands in for `~/Documents`, so the default inbox lands in `DIR` too.
    var documents: URL { directory.appendingPathComponent("Documents", isDirectory: true) }
    /// Where the runners write what they found.
    var results: URL { directory.appendingPathComponent("results", isDirectory: true) }

    /// `nil` without a test-hook argument. Also points `StorageLocations` at `DIR`, so call it before
    /// any store is created. Exits on a malformed command line rather than touching the user's files.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> TestHooks? {
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }

        let mode: Mode
        if let count = value(after: "--otter-soak") {
            guard let count = Int(count), count > 0 else {
                exitWithUsage("--otter-soak needs a positive count")
            }
            let interval = value(after: "--otter-soak-interval").flatMap(Int.init) ?? 20
            mode = .soak(count: count, interval: .milliseconds(interval))
        } else if let kind = value(after: "--otter-bench") {
            switch kind {
            case "launch": mode = .benchLaunch
            case "full": mode = .bench
            default: exitWithUsage("--otter-bench is launch or full")
            }
        } else {
            return nil
        }
        guard let path = value(after: "--otter-dir") else {
            exitWithUsage("--otter-dir is required")
        }

        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            exitWithUsage("couldn't open the \(suiteName) preferences")
        }
        let marker = directory.appendingPathComponent(".otter-test-hooks")
        if !FileManager.default.fileExists(atPath: marker.path) {
            // A new run: no destinations, shortcuts or panel frame from the last one.
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        }
        AppSettings(defaults: defaults).hasOnboarded = true
        StorageLocations.rootOverride = directory.appendingPathComponent("Application Support", isDirectory: true)
        return TestHooks(mode: mode, directory: directory, defaults: defaults)
    }

    /// Four folder destinations under `DIR/destinations`, added on the first launch: a plain folder
    /// and an Obsidian vault, each with one file per note and with appends to one file. Returns them
    /// by name, with the default inbox in `DIR/Documents` as "Otter Inbox".
    @discardableResult
    func addTestDestinations(to registry: DestinationRegistry) throws -> [String: DestinationID] {
        let root = directory.appendingPathComponent("destinations", isDirectory: true)
        let vault = root.appendingPathComponent("Vault", isDirectory: true)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian", isDirectory: true), withIntermediateDirectories: true)
        try Data(#"{"attachmentFolderPath":"attachments"}"#.utf8).write(to: vault.appendingPathComponent(".obsidian/app.json"))

        let destinations: [(String, URL, FolderOptions.Mode)] = [
            ("Folder", folder, .newFilePerNote),
            ("Folder append", folder, .appendToFile(name: "Inbox.md")),
            ("Vault", vault, .newFilePerNote),
            ("Vault append", vault.appendingPathComponent("Daily", isDirectory: true), .appendToFile(name: "Soak.md")),
        ]
        // By name, so a kill part-way through adds only the ones still missing.
        let existing = Set(registry.configs.map(\.name))
        for (name, url, mode) in destinations where !existing.contains(name) {
            let options = FolderOptions(bookmark: Data(), displayPath: url.path, fallbackPath: url.path, mode: mode)
            registry.add(DestinationConfig(name: name, options: .folder(options)))
        }
        return Dictionary(registry.configs.map { ($0.name, $0.id) }) { first, _ in first }
    }

    /// Writes `value` as `results/<name>.json`.
    func save(_ value: some Encodable, as name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
            try encoder.encode(value).write(to: results.appendingPathComponent("\(name).json"), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Couldn't save \(name).json: \(error)\n".utf8))
        }
    }

    private static func exitWithUsage(_ problem: String) -> Never {
        FileHandle.standardError.write(Data("Otter test hooks: \(problem)\n".utf8))
        exit(64) // EX_USAGE
    }
}

/// Memory and wakeups for this process, as Activity Monitor shows them.
enum ProcessUsage {
    /// Activity Monitor's Memory column.
    static func footprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// Activity Monitor's Idle Wake Ups counts package idle exits; interrupt wakeups are the total.
    static func wakeups() -> (idle: UInt64, interrupt: UInt64)? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? (usage.ri_pkg_idle_wkups, usage.ri_interrupt_wkups) : nil
    }
}
#endif
