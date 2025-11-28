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
                var node: LocationNode?
                // Resolve each recent selection to the appropriate node:
                // - If it's a custom list selection:
                //     a. use the custom list root when the list itself is selected
                //     b. otherwise resolve the specific item inside the list
                // - If not a custom list selection, resolve from the full location set.
                if let customListSelection = $0.customListSelection {
                    if customListSelection.isList == true {
                        node = finder.node(in: customListNodes, for: $0)
                    } else {
                        node = finder.node(in: allLocationNodes, for: UserSelectedRelays(locations: $0.locations))
                    }
                } else {
                    node = finder.node(in: allLocationNodes, for: $0)
                }
                return node?.copy()
            })
            .compactMap({ $0 })
            .prefix(3))
    }
}
