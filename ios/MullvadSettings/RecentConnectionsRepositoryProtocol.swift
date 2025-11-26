//
//  RecentConnectionsRepositoryProtocol.swift
//  MullvadVPN
//
//  Created by Mojgan on 2025-10-15.
//  Copyright © 2025 Mullvad VPN AB. All rights reserved.
//

import Combine
import MullvadTypes

public enum RecentLocationType: CaseIterable {
    case entry, exit
}
public protocol RecentConnectionsRepositoryProtocol {
    var recentConnectionsPublisher: AnyPublisher<RecentConnections, Error> { get }
    func setRecentsEnabled(_ isEnabled: Bool)
    func add(_ location: UserSelectedRelays, as: RecentLocationType)
    func initiate()
}
