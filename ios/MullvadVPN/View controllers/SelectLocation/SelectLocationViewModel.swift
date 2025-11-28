import Combine
import MullvadREST
import MullvadSettings
import MullvadTypes

@MainActor
protocol SelectLocationViewModel: ObservableObject {
    var exitContext: LocationContext { get set }
    var entryContext: LocationContext { get set }
    var multihopContext: MultihopContext { get set }
    var searchText: String { get set }
    var showDAITAInfo: Bool { get }
    var isMultihopEnabled: Bool { get }
    var isRecentsEnabled: Bool { get }
    func onFilterTapped(_ filter: SelectLocationFilter)
    func onFilterRemoved(_ filter: SelectLocationFilter)
    func customListsChanged()
    func addLocationToCustomList(location: LocationNode, customListName: String)
    func removeLocationFromCustomList(location: LocationNode, customListName: String)
    func deleteCustomList(name: String)
    func showEditCustomList(name: String)
    func didFinish()
    func showDaitaSettings()
    func showEditCustomListView(locations: [LocationNode])
    func showAddCustomListView(locations: [LocationNode])
    func showFilterView()
    func toggleRecents()
}

struct SelectLocationDelegate {
    let showDaitaSettings: () -> Void
    let showObfuscationSettings: () -> Void
    let showFilterView: () -> Void
    let showEditCustomListView: ([LocationNode], CustomList?) -> Void
    let showAddCustomListView: ([LocationNode]) -> Void
    let didSelectExitRelayLocations: (UserSelectedRelays) -> Void
    let didSelectEntryRelayLocations: (UserSelectedRelays) -> Void
    let didFinish: () -> Void
}

@MainActor
class SelectLocationViewModelImpl: SelectLocationViewModel {
    @Published var isMultihopEnabled: Bool
    @Published var isRecentsEnabled: Bool = true
    @Published var multihopContext: MultihopContext = .exit
    @Published var exitContext = LocationContext()
    @Published var entryContext = LocationContext()
    @Published var searchText: String = ""
    @Published var showDAITAInfo: Bool

    private let userSelectedLocationFinder = UserSelectedLocationFinding()
    private let exitLocationsDataSource = AllLocationDataSource()
    private let entryLocationsDataSource = AllLocationDataSource()
    private let entryCustomListsDataSource: CustomListsDataSource
    private let exitCustomListsDataSource: CustomListsDataSource
    private let entryRecentsDataSource: RecentListDataSource
    private let exitRecentsDataSource: RecentListDataSource

    private let relaySelectorWrapper: RelaySelectorWrapper
    private let tunnelManager: TunnelManager
    private let customListInteractor: CustomListInteractorProtocol
    private let recentsInteractor: RecentsInteractorProtocol
    private var relaysCandidates: RelayCandidates?

    private var tunnelObserver: TunnelBlockObserver?

    private let delegate: SelectLocationDelegate

    private var cancellables = Set<Combine.AnyCancellable>()

    private var allLocations: [LocationNode] {
        exitContext.locations + exitContext.customLists + entryContext.locations + entryContext.customLists
    }

    init(
        tunnelManager: TunnelManager,
        relaySelectorWrapper: RelaySelectorWrapper,
        customListRepository: CustomListRepositoryProtocol,
        recentConnectionsRepository: RecentConnectionsRepositoryProtocol,
        delegate: SelectLocationDelegate
    ) {
        self.tunnelManager = tunnelManager
        self.relaySelectorWrapper = relaySelectorWrapper
        self.customListInteractor = CustomListInteractor(
            tunnelManager: tunnelManager,
            repository: customListRepository
        )
        self.recentsInteractor = RecentsInteractor(
            tunnelManager: tunnelManager,
            repository: recentConnectionsRepository)

        self.delegate = delegate
        self.entryCustomListsDataSource = CustomListsDataSource(
            repository: customListRepository
        )
        self.exitCustomListsDataSource = CustomListsDataSource(
            repository: customListRepository
        )

        self.entryRecentsDataSource = RecentListDataSource(finder: userSelectedLocationFinder)
        self.exitRecentsDataSource = RecentListDataSource(finder: userSelectedLocationFinder)

        showDAITAInfo = tunnelManager.settings.daita.isAutomaticRouting

        // If multihop is enabled, we should check if there's a DAITA related error when opening the location
        // view. If there is, help the user by showing the entry instead of the exit view.
        isMultihopEnabled = tunnelManager.settings.tunnelMultihopState.isEnabled

        // Sync the UI with the current Recents enabled state.
        isRecentsEnabled = recentsInteractor.isEnabled

        if isMultihopEnabled {
            self.multihopContext =
                if case .noRelaysSatisfyingDaitaConstraints = tunnelManager.tunnelStatus.observedState
                    .blockedState?.reason
                { .entry } else { .exit }
        }

        self.entryContext = LocationContext(
            filter: SelectLocationFilter.getActiveFilters(tunnelManager.settings).0,
            selectLocation: { [weak self] location in
                delegate
                    .didSelectEntryRelayLocations(location.userSelectedRelays)
                self?.multihopContext = .exit
            }
        )
        self.exitContext = LocationContext(
            filter: SelectLocationFilter.getActiveFilters(tunnelManager.settings).1,
            selectLocation: { location in
                delegate
                    .didSelectExitRelayLocations(location.userSelectedRelays)
            }
        )
        let tunnelObserver =
            TunnelBlockObserver(
                didUpdateTunnelStatus: { [weak self] _, status in
                    self?.updateConnectedLocations(status)
                },
                didUpdateTunnelSettings: { [weak self] _, settings in
                    guard let self else { return }
                    fetchLocations()
                    refreshCustomLists()
                    refreshRecents()
                    updateSelections()
                    updateConnectedLocations(tunnelManager.tunnelStatus)
                    if !searchText.isEmpty {
                        search(searchText: searchText)
                    }

                    showDAITAInfo = tunnelManager.settings.daita.isAutomaticRouting

                    let (activeEntryFilter, activeExitFilter) = SelectLocationFilter.getActiveFilters(
                        settings
                    )
                    entryContext.filter = activeEntryFilter
                    exitContext.filter = activeExitFilter

                }
            )

        $searchText
            .removeDuplicates()
            .withPreviousValue()
            .sink { [weak self] prevValue, newValue in
                if prevValue == newValue { return }
                if prevValue == nil && newValue == "" { return }
                self?.search(searchText: newValue)
                if newValue == "" {
                    self?.expandSelectedLocation()
                }
            }.store(in: &cancellables)

        tunnelManager.addObserver(tunnelObserver)
        self.tunnelObserver = tunnelObserver

        fetchLocations()
        refreshCustomLists()
        refreshRecents()
        updateSelections()
        updateConnectedLocations(tunnelManager.tunnelStatus)
        expandSelectedLocation()
    }

    deinit {
        guard let tunnelObserver else { return }
        tunnelManager.removeObserver(tunnelObserver)
    }

    func onFilterTapped(_ filter: SelectLocationFilter) {
        switch filter {
        case .owned, .rented, .provider:
            delegate.showFilterView()
        case .daita:
            delegate.showDaitaSettings()
        case .obfuscation:
            delegate.showObfuscationSettings()
        }
    }

    func onFilterRemoved(_ filter: SelectLocationFilter) {
        switch filter {
        case .owned, .rented:
            var relayConstraints = tunnelManager.settings.relayConstraints
            guard var filter = relayConstraints.filter.value else { return }
            filter.ownership = .any
            relayConstraints.filter = .only(filter)
            tunnelManager.updateSettings([.relayConstraints(relayConstraints)])
        case .provider:
            var relayConstraints = tunnelManager.settings.relayConstraints
            guard var filter = relayConstraints.filter.value else { return }
            filter.providers = .any
            relayConstraints.filter = .only(filter)
            tunnelManager.updateSettings([.relayConstraints(relayConstraints)])
        default:
            break
        }
    }

    func deleteCustomList(name: String) {
        guard let customList = customListInteractor.fetchAll().first(where: { $0.name == name }) else {
            return
        }
        customListInteractor.delete(customList: customList)
        customListsChanged()
    }

    func showEditCustomList(name: String) {
        guard let customList = customListInteractor.fetchAll().first(where: { $0.name == name }) else {
            return
        }
        switch multihopContext {
        case .entry:
            delegate
                .showEditCustomListView(entryContext.locations, customList)
        case .exit:
            delegate
                .showEditCustomListView(exitContext.locations, customList)
        }
    }

    func addLocationToCustomList(location: LocationNode, customListName: String) {
        try? customListInteractor
            .addLocationToCustomList(
                relayLocations: location.locations,
                customListName: customListName
            )
        customListsChanged()
    }

    func removeLocationFromCustomList(
        location: LocationNode,
        customListName: String
    ) {
        try? customListInteractor
            .removeLocationFromCustomList(
                relayLocations: location.locations,
                customListName: customListName
            )
        customListsChanged()
    }

    func customListsChanged() {
        refreshCustomLists()
        updateSelections()
        updateConnectedLocations(tunnelManager.tunnelStatus)
    }

    private func refreshRecents() {
        isRecentsEnabled = recentsInteractor.isEnabled
        entryRecentsDataSource.reload(
            allLocationNodes: entryContext.locations, customListNodes: entryContext.customLists,
            recents: recentsInteractor.fetch(context: .entry))
        exitRecentsDataSource.reload(
            allLocationNodes: exitContext.locations, customListNodes: exitContext.customLists,
            recents: recentsInteractor.fetch(context: .exit))

        exitContext.recents = exitRecentsDataSource.nodes
        entryContext.recents = entryRecentsDataSource.nodes
    }

    private func refreshCustomLists() {
        exitCustomListsDataSource.reload(allLocationNodes: exitContext.locations)
        entryCustomListsDataSource.reload(allLocationNodes: entryContext.locations)

        exitContext.customLists = exitCustomListsDataSource.nodes
        entryContext.customLists = entryCustomListsDataSource.nodes
    }

    private func fetchLocations() {
        relaysCandidates = try? relaySelectorWrapper.findCandidates(
            tunnelSettings: tunnelManager.settings
        )
        if let relaysCandidates {
            exitLocationsDataSource
                .reload(relaysCandidates.exitRelays.toLocationRelays())
            exitContext.locations = exitLocationsDataSource.nodes

            if let entryRelays = relaysCandidates.entryRelays {
                entryLocationsDataSource
                    .reload(entryRelays.toLocationRelays())
                entryContext.locations =
                    entryLocationsDataSource.nodes
            }
        } else {
            entryContext.locations = []
            exitContext.locations = []
        }
    }

    private func updateConnectedLocations(_ status: TunnelStatus) {
        exitRecentsDataSource
            .setConnectedRelay(hostname: status.state.relays?.exit.hostname)
        exitLocationsDataSource
            .setConnectedRelay(hostname: status.state.relays?.exit.hostname)
        exitCustomListsDataSource
            .setConnectedRelay(hostname: status.state.relays?.exit.hostname)

        entryRecentsDataSource
            .setConnectedRelay(hostname: status.state.relays?.entry?.hostname)
        entryLocationsDataSource
            .setConnectedRelay(hostname: status.state.relays?.entry?.hostname)
        entryCustomListsDataSource
            .setConnectedRelay(hostname: status.state.relays?.entry?.hostname)
    }

    private func search(searchText: String) {
        exitLocationsDataSource
            .search(by: searchText)
        exitCustomListsDataSource
            .search(by: searchText)
        entryLocationsDataSource
            .search(by: searchText)
        entryCustomListsDataSource
            .search(by: searchText)
    }

    private func updateSelections() {
        var selectedEntryNode: LocationNode?
        var selectedExitNode: LocationNode?

        let selectedEntryRelays = tunnelManager.settings.relayConstraints.entryLocations.value ?? .default
        let selectedExitRelays = tunnelManager.settings.relayConstraints.exitLocations.value ?? .default

        if isRecentsEnabled {
            selectedEntryNode = userSelectedLocationFinder.node(
                in: entryRecentsDataSource.nodes, for: selectedEntryRelays)
            selectedExitNode = userSelectedLocationFinder.node(in: exitRecentsDataSource.nodes, for: selectedExitRelays)

        } else {
            selectedEntryNode =
                userSelectedLocationFinder.node(in: entryCustomListsDataSource.nodes, for: selectedEntryRelays)
                ?? userSelectedLocationFinder.node(in: entryLocationsDataSource.nodes, for: selectedEntryRelays)
            selectedExitNode =
                userSelectedLocationFinder.node(in: exitCustomListsDataSource.nodes, for: selectedExitRelays)
                ?? userSelectedLocationFinder.node(in: exitLocationsDataSource.nodes, for: selectedExitRelays)
        }
        resetSelections()
        selectedExitNode?.isSelected = true
        selectedEntryNode?.isSelected = true
        applySelectionExclusionRules(selectedEntryRelays, selectedExitRelays: selectedExitRelays)
    }

    private func resetSelections() {
        //reset selection before applying the selecetd
        entryRecentsDataSource.resetSelection()
        entryLocationsDataSource.resetSelection()
        entryCustomListsDataSource.resetSelection()

        exitLocationsDataSource.resetSelection()
        exitRecentsDataSource.resetSelection()
        exitCustomListsDataSource.resetSelection()

    }

    private func applySelectionExclusionRules(
        _ selectedEntryRelays: UserSelectedRelays?, selectedExitRelays: UserSelectedRelays?
    ) {
        guard let selectedEntryRelays, let selectedExitRelays else { return }
        // exclude selected entry relays in exit lists
        exitRecentsDataSource.setExcludedNode(excludedSelection: selectedEntryRelays)
        exitLocationsDataSource
            .setExcludedNode(excludedSelection: selectedEntryRelays)
        exitCustomListsDataSource
            .setExcludedNode(excludedSelection: selectedEntryRelays)

        // exclude selected exit relays in entry lists
        entryRecentsDataSource.setExcludedNode(excludedSelection: selectedExitRelays)
        entryLocationsDataSource
            .setExcludedNode(excludedSelection: selectedExitRelays)
        entryCustomListsDataSource
            .setExcludedNode(excludedSelection: selectedExitRelays)
    }

    private func findNode(
        nodes: [LocationNode],
        for userSelectedRelays: UserSelectedRelays
    ) -> LocationNode? {
        userSelectedLocationFinder.node(in: nodes, for: userSelectedRelays)
    }

    private func expandSelectedLocation() {
        // Only expand the selection when Recents is disabled.
        // Per spec, Recents mode does not allow expansion.
        guard !isRecentsEnabled else { return }
        exitLocationsDataSource
            .expandSelection()
        exitCustomListsDataSource
            .expandSelection()
        entryLocationsDataSource
            .expandSelection()
        entryCustomListsDataSource
            .expandSelection()
    }

    func didFinish() {
        delegate.didFinish()
    }

    func showDaitaSettings() {
        delegate.showDaitaSettings()
    }

    func showEditCustomListView(locations: [LocationNode]) {
        delegate.showEditCustomListView(locations, nil)
    }

    func showAddCustomListView(locations: [LocationNode]) {
        delegate.showAddCustomListView(locations)
    }

    func showFilterView() {
        delegate.showFilterView()
    }

    func toggleRecents() {
        recentsInteractor.toggle()
        refreshRecents()
        updateSelections()
    }
}
