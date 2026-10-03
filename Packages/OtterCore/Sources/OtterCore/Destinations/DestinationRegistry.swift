import Foundation
import os

/// Builds a concrete `Destination` from its config, one builder per kind. T06 registers `.folder`;
/// T07 and T08 register their own kinds.
public struct DestinationFactory: Sendable {
    public typealias Builder = @Sendable (DestinationConfig) -> (any Destination)?

    private var builders: [DestinationKind: Builder] = [:]

    public init() {}

    public mutating func register(_ kind: DestinationKind, builder: @escaping Builder) {
        builders[kind] = builder
    }

    /// `nil` when no builder is registered for the config's kind, or the builder can't make one.
    public func make(_ config: DestinationConfig) -> (any Destination)? {
        builders[config.kind]?(config)
    }
}

/// The configured destinations, which one is the default, and their order (`⌘1…⌘9`).
/// The configs are persisted to `UserDefaults` as JSON. Safe to use from any thread.
public final class DestinationRegistry: Sendable {
    public static let configsKey = "destinations"
    public static let defaultIDKey = "defaultDestinationID"

    private struct State: Sendable {
        var configs: [DestinationConfig]
        var defaultID: DestinationID?
        /// Destinations built so far, dropped when their config changes.
        var built: [DestinationID: any Destination] = [:]
    }

    /// `UserDefaults` is documented as thread-safe but isn't marked `Sendable`. After `init` it is
    /// only used under `state`'s lock.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let factory: DestinationFactory
    private let state: OSAllocatedUnfairLock<State>

    public init(defaults: UserDefaults = .standard, factory: DestinationFactory) {
        self.defaults = defaults
        self.factory = factory

        var configs: [DestinationConfig] = []
        if let data = defaults.data(forKey: Self.configsKey) {
            do {
                configs = try JSONDecoder().decode([DestinationConfig].self, from: data)
            } catch {
                Logger.pipeline.error("Couldn't read the saved destinations: \(error.loggableCode, privacy: .public)")
            }
        }
        let defaultID = defaults.string(forKey: Self.defaultIDKey).flatMap(UUID.init(uuidString:)).map(DestinationID.init)
        state = OSAllocatedUnfairLock(initialState: State(configs: configs, defaultID: defaultID))
    }

    /// In the user's order: the first is `⌘1`.
    public var configs: [DestinationConfig] {
        state.withLock { $0.configs }
    }

    /// The default destination: the chosen one, or the first if none is chosen or it's gone.
    public var defaultID: DestinationID? {
        state.withLock { state in
            if let id = state.defaultID, state.configs.contains(where: { $0.id == id }) {
                return id
            }
            return state.configs.first?.id
        }
    }

    public func config(for id: DestinationID) -> DestinationConfig? {
        state.withLock { $0.configs.first { $0.id == id } }
    }

    /// The destination for `⌘number`, where `number` is 1…9.
    public func config(forShortcut number: Int) -> DestinationConfig? {
        guard (1...9).contains(number) else {
            return nil
        }
        return state.withLock { state in
            state.configs.indices.contains(number - 1) ? state.configs[number - 1] : nil
        }
    }

    /// Adds a destination at the end. The first one becomes the default.
    public func add(_ config: DestinationConfig) {
        mutate { state in
            state.configs.removeAll { $0.id == config.id }
            state.configs.append(config)
            if state.defaultID == nil {
                state.defaultID = config.id
            }
        }
    }

    /// Replaces the config with the same ID. The next lookup rebuilds the destination.
    public func update(_ config: DestinationConfig) {
        mutate { state in
            guard let index = state.configs.firstIndex(where: { $0.id == config.id }) else {
                return
            }
            state.configs[index] = config
            state.built[config.id] = nil
        }
    }

    /// Removes a destination. If it was the default, the first remaining one takes over.
    public func remove(_ id: DestinationID) {
        mutate { state in
            state.configs.removeAll { $0.id == id }
            state.built[id] = nil
            if state.defaultID == id {
                state.defaultID = state.configs.first?.id
            }
        }
    }

    /// Moves a destination to `index` in the `⌘1…⌘9` order.
    public func move(_ id: DestinationID, to index: Int) {
        mutate { state in
            guard let from = state.configs.firstIndex(where: { $0.id == id }) else {
                return
            }
            let config = state.configs.remove(at: from)
            state.configs.insert(config, at: min(max(index, 0), state.configs.count))
        }
    }

    public func setDefault(_ id: DestinationID) {
        mutate { state in
            guard state.configs.contains(where: { $0.id == id }) else {
                return
            }
            state.defaultID = id
        }
    }

    /// The concrete destination for `id`, built on first use. `nil` if it isn't configured or its
    /// kind has no builder yet. Items for it then stay in the outbox.
    public func destination(for id: DestinationID) -> (any Destination)? {
        let lookup = state.withLock { state -> (built: (any Destination)?, config: DestinationConfig?) in
            (state.built[id], state.configs.first { $0.id == id })
        }
        if let built = lookup.built {
            return built
        }
        guard let config = lookup.config, let destination = factory.make(config) else {
            return nil
        }
        // Built outside the lock: a builder may touch the disk (resolving a bookmark).
        return state.withLock { state -> (any Destination)? in
            guard state.configs.contains(config) else {
                return nil // Changed or removed while building.
            }
            if let raced = state.built[id] {
                return raced
            }
            state.built[id] = destination
            return destination
        }
    }

    // MARK: - Private

    /// Applies `change` and saves, under the lock so two changes can't be saved out of order.
    private func mutate(_ change: @Sendable (inout State) -> Void) {
        state.withLock { state in
            change(&state)
            do {
                defaults.set(try JSONEncoder().encode(state.configs), forKey: Self.configsKey)
            } catch {
                Logger.pipeline.error("Couldn't save the destinations: \(error.loggableCode, privacy: .public)")
            }
            defaults.set(state.defaultID?.description, forKey: Self.defaultIDKey)
        }
    }
}
