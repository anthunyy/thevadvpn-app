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
    func fetch(context: MultihopContext) -> [UserSelectedRelays]
}

class RecentsInteractor: RecentsInteractorProtocol {
    private let repository: RecentConnectionsRepositoryProtocol
    private var selectedEntryRelays: UserSelectedRelays?
    private var selectedExitRelays: UserSelectedRelays
    private let logger = Logger(label: "RecentsInteractor")
    private var recentConnection: RecentConnections?
    private var cancellables = Set<Combine.AnyCancellable>()
    private var tunnelObserver: TunnelObserver!
    private let tunnelManager: TunnelManager

    init(
        tunnelManager: TunnelManager,
        repository: RecentConnectionsRepositoryProtocol
    ) {
        self.tunnelManager = tunnelManager
        self.repository = repository
        self.selectedEntryRelays = tunnelManager.settings.relayConstraints.entryLocations.value
        self.selectedExitRelays = tunnelManager.settings.relayConstraints.exitLocations.value ?? .default
        self.updateTunnelObserver()
        self.subscribeToRecentConnections()
        self.repository.initiate()
    }

    private func updateTunnelObserver() {
        tunnelObserver = TunnelBlockObserver(didUpdateTunnelSettings: { [weak self] _, newSettings in
            guard let self else { return }
            selectedEntryRelays = newSettings.relayConstraints.entryLocations.value
            selectedExitRelays = newSettings.relayConstraints.exitLocations.value ?? .default
            guard isEnabled else { return }
            repository.add(selectedEntryRelays, selectedExitRelays: selectedExitRelays)
        })
        tunnelManager.addObserver(tunnelObserver)
    }

    private func subscribeToRecentConnections() {
        repository
            .recentConnectionsPublisher
            .sink { [weak self] completion in
                guard let self else { return }
                if case .failure(let error) = completion {
                    // Key not found: this occurs only on first use.
                    // Initialize Recents using the user's most recent entry/exit selections by default.
                    if (error as? KeychainError) == .itemNotFound {
                        repository.enable(selectedEntryRelays, selectedExitRelays: selectedExitRelays)
                    } else {
                        logger.error("Failed to subscribe to recent connections: \(error)")
                    }
                }
            } receiveValue: { [weak self] recentConnections in
                self?.recentConnection = recentConnections
            }.store(in: &cancellables)
    }

    private func save(_ selectedEntryRelays: UserSelectedRelays?, selectedExitRelays: UserSelectedRelays) {
        self.selectedEntryRelays = selectedEntryRelays
        self.selectedExitRelays = selectedExitRelays
        repository.enable(selectedEntryRelays, selectedExitRelays: selectedExitRelays)
    }

    var isEnabled: Bool {
        recentConnection?.isEnabled ?? false
    }

    func fetch(context: MultihopContext) -> [UserSelectedRelays] {
        switch context {
        case .entry:
            recentConnection?.entryLocations ?? []
        case .exit:
            recentConnection?.exitLocations ?? []
        }
    }

    func toggle() {
        if isEnabled {
            repository.disable()
        } else {
            repository.enable(selectedEntryRelays, selectedExitRelays: selectedExitRelays)
        }
    }
}
