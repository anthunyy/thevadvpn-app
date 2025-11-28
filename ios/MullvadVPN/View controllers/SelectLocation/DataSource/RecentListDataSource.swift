//
//  RecentListDataSource.swift
//  MullvadVPN
//
//  Created by Mojgan on 2025-11-18.
//  Copyright © 2025 Mullvad VPN AB. All rights reserved.
//

import Foundation
import MullvadLogging
import MullvadSettings
import MullvadTypes

class RecentListDataSource: LocationDataSourceProtocol {
    private(set) var nodes = [LocationNode]()
    private let finder: UserSelectedLocationFinder

    init(nodes: [LocationNode] = [LocationNode](), finder: UserSelectedLocationFinder) {
        self.nodes = nodes
        self.finder = finder
    }

    func reload(
        allLocationNodes: [LocationNode], customListNodes: [LocationNode], recents: [UserSelectedRelays]
    ) {
        self.nodes = Array(
            recents.map({
                let node =
                    (finder.node(in: customListNodes, for: $0) ?? finder.node(in: allLocationNodes, for: $0))?.copy()
                node?.showsChildren = false
                return node
            })
            .compactMap({ $0 })
            .prefix(3))
    }
}
