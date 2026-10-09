#if OTTER_TEST_HOOKS
import Foundation
import OtterCore
import os

/// `--otter-soak N` (T14): submits synthetic captures through the real `CaptureService` while
/// `scripts/soak.sh` `kill -9`s and relaunches the app, then checks nothing was lost.
///
/// Each capture's text starts with a line holding a soak ID (`otter-soak:<UUID>`), and is padded
/// with filler to a random size up to 100 KB; one in ten has an attachment. The ID and the number
/// of attachments are appended to `soak/acknowledged.txt` only once `enqueue` has returned, which is
/// the promise "never lose a note" makes. Every acknowledged ID must then turn up in a destination's
/// files at least once.
///
/// A relaunch carries on from the count in `acknowledged.txt`. Once there are `N`, it waits for
/// the outbox to empty, writes `soak/done`, and quits.
@MainActor
final class SoakRunner {
    static let idPrefix = "otter-soak:"
    static let maxTextBytes = 100_000

    private let hooks: TestHooks
    private let pipeline: CapturePipeline
    private let count: Int
    private let interval: Duration
    private let stager: AttachmentStager
    private let soakDirectory: URL
    private var generator = SystemRandomNumberGenerator()

    init(hooks: TestHooks, pipeline: CapturePipeline, count: Int, interval: Duration) {
        self.hooks = hooks
        self.pipeline = pipeline
        self.count = count
        self.interval = interval
        stager = AttachmentStager(directory: StorageLocations.draftFiles)
        soakDirectory = hooks.directory.appendingPathComponent("soak", isDirectory: true)
    }

    private var acknowledgedFile: URL { soakDirectory.appendingPathComponent("acknowledged.txt") }

    func start() {
        Task {
            do {
                try await run()
            } catch {
                Logger.app.error("Soak test stopped: \(error.localizedDescription, privacy: .public)")
                exit(1)
            }
        }
    }

    private func run() async throws {
        try FileManager.default.createDirectory(at: soakDirectory, withIntermediateDirectories: true)
        let destinations = Array(try hooks.addTestDestinations(to: pipeline.destinations).values)
        let log = try FileHandle(forWritingTo: acknowledged())
        try log.seekToEnd()

        var submitted = acknowledgedCount()
        Logger.app.info("Soak: \(submitted, privacy: .public) of \(self.count, privacy: .public) acknowledged so far")
        while submitted < count {
            let soakID = UUID()
            let attachments = try await attachmentsForNextCapture()
            let result = await pipeline.captureService.enqueue(
                text: makeText(soakID: soakID),
                attachments: attachments,
                destinationID: destinations.randomElement(using: &generator),
                source: .panel
            )
            switch result {
            case .success:
                // One `write(2)`: a kill can't leave half a line.
                try log.write(contentsOf: Data("\(soakID.uuidString) \(attachments.count)\n".utf8))
                submitted += 1
            case let .failure(error):
                Logger.app.error("Soak: a capture wasn't accepted: \(String(describing: error), privacy: .public)")
            }
            try await Task.sleep(for: interval)
        }

        // Everything is in the outbox; now it has to drain. The kick makes sure the status read
        // below is the outbox's, not the idle one a relaunch starts with.
        await pipeline.delivery.kick()
        for await status in await pipeline.delivery.statusUpdates() where status.pendingCount == 0 {
            break
        }
        FileManager.default.createFile(atPath: soakDirectory.appendingPathComponent("done").path, contents: nil)
        Logger.app.info("Soak: all \(self.count, privacy: .public) captures acknowledged and delivered")
        exit(0)
    }

    private func acknowledged() throws -> URL {
        if !FileManager.default.fileExists(atPath: acknowledgedFile.path) {
            FileManager.default.createFile(atPath: acknowledgedFile.path, contents: nil)
        }
        return acknowledgedFile
    }

    private func acknowledgedCount() -> Int {
        let text = (try? String(contentsOf: acknowledgedFile, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").filter { UUID(uuidString: String($0.prefix(36))) != nil }.count
    }

    /// The soak ID's line, then lines of filler, to a random total size of up to 100 KB. Mostly
    /// short, like real notes, with a long tail.
    private func makeText(soakID: UUID) -> String {
        let header = "\(Self.idPrefix)\(soakID.uuidString)\n"
        let roll = Double.random(in: 0..<1, using: &generator)
        let size = roll < 0.8 ? Int.random(in: 0...2_000, using: &generator) : Int.random(in: 0...(Self.maxTextBytes - header.utf8.count), using: &generator)
        let words = ["otter", "river", "kelp", "note", "pebble", "swim", "tide", "float", "shell", "whisker"]
        var text = header
        var line = ""
        while text.utf8.count + line.utf8.count < size {
            line += words.randomElement(using: &generator)! + " "
            if line.utf8.count > 70 {
                text += line + "\n"
                line = ""
            }
        }
        return text + line
    }

    /// One capture in ten gets a 1–64 KB attachment, staged the way a paste stages one.
    private func attachmentsForNextCapture() async throws -> [StagedAttachment] {
        guard Int.random(in: 0..<10, using: &generator) == 0 else {
            return []
        }
        var bytes = [UInt8](repeating: 0, count: Int.random(in: 1_024...65_536, using: &generator))
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
        }
        return [try await stager.stageImage(Data(bytes), uti: "public.png")]
    }
}
#endif
