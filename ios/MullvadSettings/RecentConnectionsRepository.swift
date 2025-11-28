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

    public func disable() {
        do {
            // Clear all recents whenever the recents feature status changes.
            let value = RecentConnections(isEnabled: false, entryLocations: [], exitLocations: [])
            try write(value)
            recentConnectionsSubject.send(value)
        } catch {
            recentConnectionsSubject.send(completion: .failure(error))
        }
    }
    public func enable(_ selectedEntryRelays: UserSelectedRelays?, selectedExitRelays: UserSelectedRelays) {
        do {
            // Enable recents with the last selected locations for entry and exit.
            let value = RecentConnections(
                entryLocations: (selectedEntryRelays != nil) ? [selectedEntryRelays!] : [],
                exitLocations: [selectedExitRelays])
            try write(value)
            recentConnectionsSubject.send(value)
        } catch {
            recentConnectionsSubject.send(completion: .failure(error))
        }
    }

    public func add(_ selectedEntryRelays: UserSelectedRelays?, selectedExitRelays: UserSelectedRelays) {
        do {
            let current = try read()
            guard current.isEnabled else { throw RecentConnectionsRepositoryError.recentsDisabled }

            let insertAtZero: ([UserSelectedRelays], UserSelectedRelays?) -> [UserSelectedRelays] = {
                (locations, location) in
                guard let location = location else { return locations }
                var currentLocations = locations
                currentLocations.removeAll(where: { $0 == location })
                currentLocations.insert(location, at: 0)
                return Array(currentLocations.prefix(Int(self.maxLimit)))
            }

            let new = RecentConnections(
                entryLocations: insertAtZero(current.entryLocations, selectedEntryRelays),
                exitLocations: insertAtZero(current.exitLocations, selectedExitRelays))
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
    private func read() throws -> RecentConnections {
        let data = try store.read(key: .recentConnections)
        return try settingsParser.parseUnversionedPayload(as: RecentConnections.self, from: data)
    }

    private func write(_ value: RecentConnections) throws {
        let data = try settingsParser.produceUnversionedPayload(value)
        try store.write(data, for: .recentConnections)
    }
}
