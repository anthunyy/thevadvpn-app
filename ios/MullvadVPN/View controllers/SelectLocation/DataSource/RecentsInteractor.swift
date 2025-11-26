//
//  RecentsInteractor.swift
//  MullvadVPN
//
//  Created by Mojgan on 2025-11-25.
//  Copyright © 2025 Mullvad VPN AB. All rights reserved.
//

import Combine
import MullvadLogging
import MullvadSettings
import MullvadTypes

protocol RecentsInteractorProtocol {
    var isEnabled: Bool { get }
    func toggle()
    func save(userSelectedRelays: UserSelectedRelays, for context: MultihopContext)
    func fetch(context: MultihopContext) -> [UserSelectedRelays]
}

class RecentsInteractor: RecentsInteractorProtocol {
    private let tunnelManager: SettingsUpdating
    private let repository: RecentConnectionsRepositoryProtocol
    private let logger = Logger(label: "RecentsInteractor")
    private var recentConnection: RecentConnections?
    private var cancellables = Set<Combine.AnyCancellable>()

    init(
        tunnelManager: SettingsUpdating,
        repository: RecentConnectionsRepositoryProtocol
    ) {
        self.tunnelManager = tunnelManager
        self.repository = repository
        self.subscribeToRecentConnections()
        self.repository.all()
    }

    private func subscribeToRecentConnections() {
        repository
            .recentConnectionsPublisher
            .sink { [weak self] completion in
                switch completion {
                case .failure(let error):
                    self?.logger.error("Failed to subscribe to recent connections: \(error)")
                default:
                    break
                }

            } receiveValue: { [weak self] recentConnections in
                self?.recentConnection = recentConnections
            }.store(in: &cancellables)
    }

    var isEnabled: Bool {
        recentConnection?.isEnabled ?? true
    }

    func toggle() {
        repository.setRecentsEnabled(!isEnabled)
    }

    func fetch(context: MultihopContext) -> [UserSelectedRelays] {
        switch context {
        case .entry:
            recentConnection?.entryLocations ?? []
        case .exit:
            recentConnection?.exitLocations ?? []
        }
    }

    func save(userSelectedRelays: UserSelectedRelays, for context: MultihopContext) {
        switch context {
        case .entry:
            repository.add(userSelectedRelays, as: .entry)
        case .exit:
            repository.add(userSelectedRelays, as: .exit)
        }
    }
}
