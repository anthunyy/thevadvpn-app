import Combine
//
//  RecentConnectionsRepository.swift
//  MullvadVPN
//
//  Created by Mojgan on 2025-10-15.
//  Copyright © 2025 Mullvad VPN AB. All rights reserved.
//
import MullvadTypes

public enum RecentConnectionsRepositoryError: LocalizedError, Hashable {
    case recentsDisabled

    public var errorDescription: String? {
        switch self {
        case .recentsDisabled:
            "To add the location to the recents, first enable it in the settings."
        }
    }
}

final public class RecentConnectionsRepository: RecentConnectionsRepositoryProtocol {
    private let store: SettingsStore
    private let maxLimit: UInt
    private let recentConnectionsSubject: PassthroughSubject<RecentConnections, Error> = .init()

    private let settingsParser: SettingsParser = {
        SettingsParser(decoder: JSONDecoder(), encoder: JSONEncoder())
    }()

    public var recentConnectionsPublisher: AnyPublisher<RecentConnections, Error> {
        recentConnectionsSubject.eraseToAnyPublisher()
    }

    public init(store: SettingsStore, maxLimit: UInt = 50) {
        self.store = store
        self.maxLimit = maxLimit
    }

    public func setRecentsEnabled(_ isEnabled: Bool) {
        do {
            // Clear all recents whenever the recents feature status changes.
            let value = RecentConnections(isEnabled: isEnabled, entryLocations: [], exitLocations: [])
            try write(value)
            recentConnectionsSubject.send(value)
        } catch {
            recentConnectionsSubject.send(completion: .failure(error))
        }
    }

    public func add(_ location: UserSelectedRelays, as type: RecentLocationType) {

        do {
            let current = try read()
            guard current.isEnabled else { throw RecentConnectionsRepositoryError.recentsDisabled }
            var currentList = current[keyPath: keyPath(for: type)]
            if let idx = currentList.firstIndex(of: location) { currentList.remove(at: idx) }
            currentList.insert(location, at: 0)
            currentList = Array(currentList.prefix(Int(maxLimit)))

            let new =
                (type == .entry)
                ? RecentConnections(
                    isEnabled: current.isEnabled, entryLocations: currentList, exitLocations: current.exitLocations)
                : RecentConnections(
                    isEnabled: current.isEnabled, entryLocations: current.entryLocations, exitLocations: currentList)

            try write(new)
            recentConnectionsSubject.send(new)
        } catch {
            recentConnectionsSubject.send(completion: .failure(error))
        }

    }

    public func initiate() {
        do {
            let value = try read()
            recentConnectionsSubject.send(value)
        } catch {
            recentConnectionsSubject.send(completion: .failure(error))
        }
    }
}

private extension RecentConnectionsRepository {
    private func keyPath(for type: RecentLocationType) -> KeyPath<RecentConnections, [UserSelectedRelays]> {
        switch type {
        case .entry: return \.entryLocations
        case .exit: return \.exitLocations
        }
    }

    private func read() throws -> RecentConnections {
        let data = try store.read(key: .recentConnections)
        return try settingsParser.parseUnversionedPayload(as: RecentConnections.self, from: data)
    }

    private func write(_ value: RecentConnections) throws {
        let data = try settingsParser.produceUnversionedPayload(value)
        try store.write(data, for: .recentConnections)
    }
}
