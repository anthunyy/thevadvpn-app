import SwiftUI

struct HopContext {
    let multihopContext: MultihopContext
    let selectedLocation: LocationNode?
    let noMatchFound: NoMatchFoundReason?

    enum NoMatchFoundReason {
        case noFilterMatch
        case selectionNotAvailable

        var description: LocalizedStringKey {
            switch self {
            case .noFilterMatch:
                return "Selection does not match filter"
            case .selectionNotAvailable:
                return "Selection is not available"
            }
        }
    }
}

struct MultihopSelectionView: View {
    let hops: [HopContext]
    @Binding var selectedMultihopContext: MultihopContext
    let deviceLocationName: String?
    let isExpanded: CGFloat

    @State private var animationId: UUID = .init()
    @State private var animationId2: UUID = .init()
    @Namespace private var animation
    @State private var outerViewSizes: [MultihopContext: CGSize] = [:]
    @State private var innerViewSizes: [MultihopContext: CGSize] = [:]
    @State private var pressedMultihopContext: MultihopContext?

    @State private var iconPositions: [AnyHashable: CGRect] = [:]
    private let lineWidth: CGFloat = 1
    private let iconPadding: CGFloat = 2
    private let spacing: CGFloat = 8
    private let outerHorizontalPadding: CGFloat = 4
    private let outerVerticalPadding: CGFloat = 6
    private let iconSize = CGSize(width: 18, height: 18)
    private var leadingPadding: CGFloat {
        ((iconSize.width / 2) + 8) - lineWidth / 2
    }

    enum Position {
        case first
        case last
        case middle
        case only
    }

    struct MultihopLabel: View {
        let label: LocalizedStringKey
        let image: Image
        let onIconPositionChange: (CGRect) -> Void
        let isExpanded: CGFloat
        let isTop: Bool
        @State private var size: CGSize = .init()
        private var offset: CGFloat {
            size.height * (1 - isExpanded)
        }
        var body: some View {
            HStack {
                image
                    .capturePosition(in: .named("test")) {
                        onIconPositionChange($0)
                    }
                Text(label)
            }
            .foregroundStyle(Color.mullvadTextPrimary.opacity(0.6))
            .font(.mullvadMiniSemiBold)
            .opacity(isExpanded)
            .sizeOfView { size in
                self.size = size
            }
        }
    }

    @State private var viewHeight: CGFloat = 0
    @State private var topHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                MultihopLabel(
                    label: "Internet",
                    image: Image.mullvadIconInternet,
                    onIconPositionChange: { position in
                        iconPositions["internet"] = position
                    },
                    isExpanded: isExpanded,
                    isTop: true
                )
                .sizeOfView { size in
                    topHeight = size.height
                }
                Spacer()
                    .frame(
                        height:
                            min(
                                max(
                                    viewHeight + 4 - (1 - isExpanded) * (topHeight + bottomHeight),
                                    0
                                ),
                                .greatestFiniteMagnitude
                            )
                    )
                var label: LocalizedStringKey {
                    if let deviceLocationName {
                        "Your device (\(deviceLocationName))"
                    } else {
                        "Your device"
                    }
                }
                MultihopLabel(
                    label: label,
                    image: Image.mullvadSmartphone,
                    onIconPositionChange: { position in
                        iconPositions["device"] = position
                    },
                    isExpanded: isExpanded,
                    isTop: false
                )
                .sizeOfView { size in
                    bottomHeight = size.height
                }
            }
            .padding(.horizontal, outerHorizontalPadding + 8 + 2)
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(
                    Array(hops.reversed().enumerated()),
                    id: \.element.multihopContext
                ) {
                    index,
                    hop in
                    let isSelected = hop.multihopContext == selectedMultihopContext
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading) {
                            PressedExposingButton {
                                withAnimation {
                                    selectedMultihopContext = hop.multihopContext
                                }
                            } label: {
                                MultihopHopView(
                                    hop: hop,
                                    isSelected: selectedMultihopContext == hop.multihopContext,
                                    onFilterTapped: {
                                    },
                                    onIconPositionChange: { position in
                                        iconPositions[hop.multihopContext] = position
                                    }
                                )
                                .background {
                                    ZStack {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.MullvadList.Item.child3)
                                                .matchedGeometryEffect(id: animationId, in: animation)
                                        }
                                        if hop.noMatchFound != nil {
                                            RoundedRectangle(cornerRadius: 12)
                                                .inset(by: 1)
                                                .stroke(Color.mullvadDangerColor)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())

                            } onPressedChange: {
                                pressedMultihopContext = $0 ? hop.multihopContext : nil
                            }
                            .accessibilityLabel(hop.multihopContext.description)

                            .sizeOfView {
                                innerViewSizes[hop.multihopContext] = $0
                            }
                            if let noMatchFound = hop.noMatchFound {
                                Text(noMatchFound.description)
                                    .padding(.leading, 36)
                                    .foregroundStyle(Color.mullvadDangerColor)
                                    .font(.mullvadMini)
                            }
                        }
                        .sizeOfView {
                            outerViewSizes[hop.multihopContext] = $0
                        }
                    }
                }
            }
            .padding(.horizontal, outerHorizontalPadding)
            .padding(.vertical, outerHorizontalPadding + 2)
            .background(
                Color.mullvadDarkBackground
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.vertical, 2)
            )
            .offset(y: topHeight * isExpanded + 2)
            .sizeOfView {
                viewHeight = $0.height
            }
        }
        .overlay {
            lineOverlay()
        }
        .coordinateSpace(name: "test")
        //        .animation(.default, value: isExpanded)
        .onChange(of: selectedMultihopContext) {
            announce()
        }
    }

    func announce() {
        var announcement = AttributedString(
            NSLocalizedString(
                "Multihop selection changed to \(NSLocalizedString(selectedMultihopContext.description, comment: ""))",
                comment: ""
            ))
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }

    @ViewBuilder func lineOverlay() -> some View {
        Path { path in
            path.move(to: .zero)
            var sortedIconPositions: [Dictionary<AnyHashable, CGRect>.Element] {
                iconPositions.sorted(by: { first, second in
                    first.value.origin.y < second.value.origin.y
                })
                .filter {
                    if $0.key == "internet" as AnyHashable || $0.key == "device" as AnyHashable {
                        return isExpanded > 0.5
                    }
                    return true
                }
            }
            sortedIconPositions.forEach { key, value in

                let top = value.topCenter.applying(.init(translationX: 0, y: -4))
                let bottom = value.bottomCenter.applying(.init(translationX: 0, y: 4))
                if key != sortedIconPositions.first?.key {
                    path.addLine(to: top)
                }
                path.move(to: bottom)
            }
        }
        .stroke(Color.mullvadTextPrimary.opacity(0.6))
    }
}

struct MultihopHopView: View {
    let hop: HopContext
    let isSelected: Bool
    let onFilterTapped: () -> Void
    let onIconPositionChange: (CGRect) -> Void
    var body: some View {
        HStack {
            hop.multihopContext.icon
                .renderingMode(.template)
                .capturePosition(in: .named("test")) { position in
                    onIconPositionChange(position)
                }
            Text(hop.selectedLocation?.name ?? "Select location")
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            // TODO: use individual filter buttons when settings have been migrated
            //            Button {
            //                onFilterTapped()
            //            } label: {
            //                Image(systemName: "line.3.horizontal.decrease")
            //            }
        }
        .font(.mullvadSmallSemiBold)
        .foregroundStyle(
            isSelected
                ? Color.mullvadTextPrimary
                : Color.mullvadTextPrimary
                    .opacity(0.6)
        )
        .padding(8)
    }
}

extension MultihopContext {
    var icon: Image {
        switch self {
        case .entry:
            Image.mullvadServer
        case .exit:
            Image.mullvadLocation
        }
    }
}

#Preview {
    @Previewable @State var selectedContext: MultihopContext = .allCases.first!
    @Previewable @State var isExpanded: CGFloat = 1
    ScrollView {
        Slider(value: $isExpanded, in: 0...1)
        VStack {
            Spacer()
            MultihopSelectionView(
                hops: [.init(multihopContext: .exit, selectedLocation: nil, noMatchFound: nil)],
                selectedMultihopContext: .constant(.exit),
                deviceLocationName: nil,
                isExpanded: isExpanded
            )
            MultihopSelectionView(
                hops: MultihopContext.allCases
                    .map {
                        HopContext(
                            multihopContext: $0,
                            selectedLocation: .init(name: "\($0.description)", code: "se"),
                            noMatchFound: .noFilterMatch
                        )
                    },
                selectedMultihopContext: $selectedContext,
                deviceLocationName: "Sweden",
                isExpanded: isExpanded
            )
            .padding()
            MultihopSelectionView(
                hops: MultihopContext.allCases
                    .map {
                        HopContext(
                            multihopContext: $0,
                            selectedLocation: .init(
                                name: "\($0.description)",
                                code: "se"
                            ),
                            noMatchFound: nil
                        )
                    },
                selectedMultihopContext: $selectedContext,
                deviceLocationName: "Sweden",
                isExpanded: isExpanded
            )
            .padding()
            Spacer()
        }
    }
    .background(Color.mullvadBackground)
}

struct PressedExposingButton<Content: View>: View {
    let action: () -> Void
    let label: () -> Content
    let onPressedChange: ((Bool) -> Void)?
    struct MyButtonStyle: ButtonStyle {
        let action: () -> Void
        let label: () -> Content
        let onPressedChange: ((Bool) -> Void)?

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) {
                    onPressedChange?(configuration.isPressed)
                }
                .opacity(configuration.isPressed ? 0.6 : 1.0)
            //                .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        }
    }

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(
                MyButtonStyle(
                    action: action,
                    label: label,
                    onPressedChange: onPressedChange
                )
            )
    }
}
