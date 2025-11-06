import MullvadTypes
import SwiftUI

struct SelectLocationView<ViewModel>: View where ViewModel: SelectLocationViewModel {
    @ObservedObject var viewModel: ViewModel

    @State private var progress: CGFloat = 1
    var showSearchField: Bool {
        guard showSearchFieldState else { return false }
        return !viewModel.showDAITAInfo || viewModel.multihopContext == .exit
    }

    @State var showSearchFieldState: Bool = true
    var body: some View {
        VStack(spacing: 16) {
            MultihopSelectionView(
                hops: (viewModel.isMultihopEnabled ? MultihopContext.allCases : [MultihopContext.exit])
                    .map {
                        HopContext(
                            multihopContext: $0,
                            selectedLocation: $0 == .entry
                                ? viewModel.entryContext.selectedLocation : viewModel.exitContext.selectedLocation,
                            noMatchFound: nil
                        )
                    },
                selectedMultihopContext: $viewModel.multihopContext,
                deviceLocationName: nil,
                isExpanded: progress
            )
            .padding(.horizontal, 16)
            if showSearchField {
                MullvadSecondaryTextField(
                    placeholder: "Search for locations or servers...",
                    text: $viewModel.searchText
                )
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            switch viewModel.multihopContext {
            case .exit:
                ExitLocationView(
                    viewModel: viewModel,
                    context: $viewModel.exitContext
                )
                .transition(
                    .move(edge: .trailing).combined(with: .opacity)
                )
                .geometryGroup()
                .simultaneousGesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged {
                            let delta = min($0.velocity.height / 5000, 0.1)
                            print(delta)
                            progress = max(min(progress + delta, 1), 0)
                        }
                        .onEnded { value in
                            withAnimation {
                                let delta = value.velocity.height / 5000
                                progress = max(min(progress + delta, 1), 0).rounded()
                            }
                        }
                )
            case .entry:
                EntryLocationView(
                    viewModel: viewModel
                )
                .transition(
                    .move(edge: .leading).combined(with: .opacity)
                )
                .geometryGroup()
            }
        }
        .coordinateSpace(name: "scroll")
        .animation(.default, value: showSearchField)
        .animation(.default, value: viewModel.multihopContext)
        .background(Color.mullvadBackground)
        .navigationTitle("Select location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing,
                content: {
                    Button("Done") {
                        viewModel.didFinish()
                    }
                    .foregroundStyle(Color.mullvadTextPrimary)
                    .accessibilityIdentifier(.closeSelectLocationButton)
                }
            )
            ToolbarItem(
                placement: .topBarLeading,
                content: {
                    Menu {
                        Button {
                            viewModel.showFilterView()
                        } label: {
                            HStack {
                                Image(systemName: "line.3.horizontal.decrease")
                                Text("Filters")
                            }
                            .foregroundStyle(Color.mullvadTextPrimary)
                        }
                        .accessibilityIdentifier(.selectLocationFilterButton)
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .foregroundStyle(Color.mullvadTextPrimary)
                            .accessibilityIdentifier(.selectLocationToolbarMenu)
                    }
                }
            )
        }
    }
}

#Preview {
    Text("")
        .sheet(isPresented: .constant(true)) {
            NavigationView {
                SelectLocationView(
                    viewModel: MockSelectLocationViewModel()
                )
            }
        }
}
