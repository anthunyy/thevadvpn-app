//
//  RecentConnectionsRepositoryProtocol.swift
//  MullvadVPN
//
//  Created by Mojgan on 2025-10-15.
//  Copyright © 2025 Mullvad VPN AB. All rights reserved.
//

import Combine
import MullvadTypes

public protocol RecentConnectionsRepositoryProtocol {
    var recentConnectionsPublisher: AnyPublisher<RecentConnections, Error> { get }
    func disable()
    func enable(_ selectedEntryRelays: UserSelectedRelays?, selectedExitRelays: UserSelectedRelays)
    func add(_ selectedEntryRelays: UserSelectedRelays?, selectedExitRelays: UserSelectedRelays)
    func initiate()
}
