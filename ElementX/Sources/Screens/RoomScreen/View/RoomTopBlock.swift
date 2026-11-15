//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, decision 345): the block under the room's header, one capsule that never grows, floating
// over the timeline: the pinned message, or the active tool, or the pinned message with the tools as a chip.
//

import Compound
import OrderedCollections
import SwiftUI

struct RoomTopBlock: View {
    /// Nil when there's nothing to show of that kind.
    let pinned: PinnedEventsBannerState?
    let tools: ActiveToolsBannerState?
    
    let onPinnedTap: () -> Void
    let onViewAllTap: () -> Void
    let onToolTap: () -> Void
    let onManageTap: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            if let pinned {
                pinnedText(pinned)
                if let tools {
                    toolChip(tools)
                }
                viewAllButton(pinned)
            } else if let tools {
                toolText(tools)
                manageButton(tools)
            }
        }
        .roomBlockCapsule()
        // The text would leave nothing of a pinned message beside the chip and the list at AX3.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.top, CompoundDesignTokens.space1X)
    }
    
    private func pinnedText(_ state: PinnedEventsBannerState) -> some View {
        Button(action: onPinnedTap) {
            HStack(spacing: CompoundDesignTokens.space2X) {
                if state.count > 1 {
                    PinnedItemsIndicatorView(pinIndex: state.selectedPinnedIndex, pinsCount: state.count)
                        .dynamicTypeSize(.large) // It stays inside the capsule's curve.
                        .accessibilityHidden(true)
                }
                CompoundIcon(\.pinSolid, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconSecondary)
                    .accessibilityHidden(true)
                Text(state.displayedMessage)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, CompoundDesignTokens.space4X)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .disabled(state.isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.displayedMessage))
        .accessibilityValue(String(state.bannerIndicatorDescription.characters), isEnabled: state.count > 1)
    }
    
    private func viewAllButton(_ state: PinnedEventsBannerState) -> some View {
        Button(action: onViewAllTap) {
            blockIcon(\.listBulleted)
        }
        .disabled(state.isLoading)
        .accessibilityLabel(L10n.screenRoomPinnedBannerViewAllButtonTitle)
    }
    
    private func toolText(_ state: ActiveToolsBannerState) -> some View {
        Button(action: onToolTap) {
            HStack(spacing: CompoundDesignTokens.space2X) {
                if state.count > 1 {
                    PinnedItemsIndicatorView(pinIndex: state.selectedIndex, pinsCount: state.count)
                        .dynamicTypeSize(.large) // It stays inside the capsule's curve.
                        .accessibilityHidden(true)
                }
                CompoundIcon(state.selectedIcon, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconAccentPrimary)
                    .accessibilityHidden(true)
                Text(state.displayedMessage)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, CompoundDesignTokens.space4X)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .disabled(state.isLoading || state.count <= 1)
        .accessibilityElement(children: .contain)
    }
    
    private func manageButton(_ state: ActiveToolsBannerState) -> some View {
        Button(action: onManageTap) {
            blockIcon(\.settings)
        }
        .disabled(state.isLoading)
        .accessibilityLabel(UntranslatedL10n.actionManage)
    }
    
    /// What's running beside a pinned message, opening Manage. Its name isn't on screen, so VoiceOver says it: a tool is a
    /// disclosure. Several show their count.
    private func toolChip(_ state: ActiveToolsBannerState) -> some View {
        Button(action: onManageTap) {
            HStack(spacing: CompoundDesignTokens.space1X) {
                CompoundIcon(state.selectedIcon, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconAccentPrimary)
                if state.count > 1 {
                    Text(state.count, format: .number)
                        .font(.compound.bodySMSemibold)
                        .foregroundStyle(.compound.textPrimary)
                }
            }
            .padding(.horizontal, CompoundDesignTokens.space3X)
            .padding(.vertical, CompoundDesignTokens.space1_5X)
            .background(.compound.iconAccentPrimary.opacity(0.14), in: Capsule())
            .frame(minWidth: CompoundDesignTokens.space11X, minHeight: CompoundDesignTokens.space11X)
            .contentShape(.rect)
        }
        .disabled(state.isLoading)
        .accessibilityLabel(toolNames(state))
        .accessibilityHint(UntranslatedL10n.actionManage)
    }
    
    private func toolNames(_ state: ActiveToolsBannerState) -> String {
        switch state {
        case .loading: ""
        case .loaded(let state): state.items.map(\.title).formatted(.list(type: .and))
        }
    }
    
    private func blockIcon(_ icon: KeyPath<CompoundIcons, Image>) -> some View {
        CompoundIcon(icon, size: .small, relativeTo: .compound.bodyMD)
            .foregroundStyle(.compound.iconPrimary)
            .frame(width: CompoundDesignTokens.space11X, height: CompoundDesignTokens.space11X)
            .contentShape(.rect)
    }
}

private extension View {
    /// The header's glass with Liquid Glass (decisions 346 and 347), and the thick material before it.
    func roomBlockCapsule() -> some View {
        modifier(RoomBlockCapsule())
    }
}

private struct RoomBlockCapsule: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        let capsule = content.frame(minHeight: CompoundDesignTokens.space11X)
        if #available(iOS 26, *) {
            capsule.glassEffect(glass, in: Capsule())
        } else {
            capsule.background(.thickMaterial, in: Capsule())
        }
    }
    
    // The one exception to decision 346 (347): over a blue bubble in dark, plain glass leaves white text at 3:1.
    // 0.2 is the least that holds 4.5:1 over the whole capsule.
    @available(iOS 26, *)
    private var glass: Glass {
        colorScheme == .dark ? .regular.tint(.compound.bgCanvasDefault.opacity(0.2)).interactive() : .regular.interactive()
    }
}

// MARK: - Previews

struct RoomTopBlock_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    private static let tools: [BannerToolItem] = [.init(id: "@a:host#0", title: "Translating to English", icon: \.translate, agentMatrixUserID: "@a:host"),
                                                  .init(id: "@a:host#1", title: "Summarising this chat", icon: \.listBulleted, agentMatrixUserID: "@a:host")]
    
    static var previews: some View {
        VStack(spacing: 20) {
            block(pins: ["1": "Content"], tools: 0)
            block(pins: ["1": "Very very very very long content here", "2": "2", "3": "3"], tools: 0)
            block(pins: [:], tools: 1)
            block(pins: [:], tools: 2)
            block(pins: ["1": "Content"], tools: 1)
            block(pins: ["1": "Very very very very long content here", "2": "2"], tools: 2)
            RoomTopBlock(pinned: .loading(numbersOfEvents: 5), tools: nil,
                         onPinnedTap: { }, onViewAllTap: { }, onToolTap: { }, onManageTap: { })
        }
        .padding(.vertical)
        .background(Color.compound.bgCanvasDefault)
        .previewLayout(.sizeThatFits)
    }
    
    private static func block(pins: OrderedDictionary<String, AttributedString>, tools count: Int) -> some View {
        RoomTopBlock(pinned: pins.isEmpty ? nil : .loaded(state: .init(pinnedEventContents: pins, selectedPinnedEventID: "1")),
                     tools: count == 0 ? nil : .loaded(state: .init(items: Array(tools.prefix(count)), selectedID: tools[0].id)),
                     onPinnedTap: { }, onViewAllTap: { }, onToolTap: { }, onManageTap: { })
    }
}
