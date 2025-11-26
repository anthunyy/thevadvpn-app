import Combine
//
//  UserSelectedLocationFinding.swift
//  MullvadVPN
//
//  Created by Mojgan on 2025-11-20.
//  Copyright © 2025 Mullvad VPN AB. All rights reserved.
//
import MullvadTypes

struct LocationNodes {
    let allLocationsNodes: [LocationNode]
    let customListsNodes: [LocationNode]
}

protocol UserSelectedLocationFinder {
    func node(in source: LocationNodes, for selectedRelays: UserSelectedRelays) -> LocationNode?
}

struct UserSelectedLocationFinding: UserSelectedLocationFinder {

    func node(in source: LocationNodes, for selectedRelays: UserSelectedRelays) -> LocationNode? {
        customListNode(rootNode: RootLocationNode(children: source.customListsNodes), selectedRelays: selectedRelays)
            ?? relayNode(rootNode: RootLocationNode(children: source.allLocationsNodes), selectedRelays: selectedRelays)
    }

    private func customListNode(rootNode: RootLocationNode, selectedRelays: UserSelectedRelays)
        -> LocationNode?
    {
        // Look for a matching custom list node.
        if let customListSelection = selectedRelays.customListSelection {
            return rootNode.children.first { node in
                node.asCustomListNode?.customList.id == customListSelection.listId
            }
        }
        return nil
    }

    private func relayNode(rootNode: LocationNode, selectedRelays: UserSelectedRelays) -> LocationNode? {
        // Look for a matching node.
        if let location = selectedRelays.locations.first {
            let descendantNodeFor: ([String]) -> LocationNode? = { codes in
                switch location {
                case let .country(countryCode):
                    rootNode.descendantNodeFor(codes: codes + [countryCode])
                case let .city(countryCode, cityCode):
                    rootNode.descendantNodeFor(codes: codes + [countryCode, cityCode])
                case let .hostname(_, _, hostCode):
                    rootNode.descendantNodeFor(codes: codes + [hostCode])
                }
            }

            return descendantNodeFor([])
        }
        return nil
    }
}
