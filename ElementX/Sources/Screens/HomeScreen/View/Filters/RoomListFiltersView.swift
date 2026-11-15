//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

// AGENT-PLATFORM (Brief 0083, decision 333): Spiral's filters replace the row of chips, Element's signature on
// Chats: a filter menu in the navigation bar, and while filtering a removable token for each active filter at
// the top of the list. Every filter keeps its behaviour: the same `RoomListFiltersState` calls, which filters
// combine and which hide. Each token's ✕ turns off its filter and keeps the others; each target is 44 pt tall.
struct RoomListFiltersView: View {
    @Binding var state: RoomListFiltersState
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CompoundDesignTokens.space2X) {
                ForEach(state.activeFilters) { filter in
                    token(for: filter)
                }
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, CompoundDesignTokens.space0_5X)
    }
    
    private func token(for filter: RoomListFilter) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2).disabledDuringTests()) {
                state.deactivateFilter(filter)
            }
        } label: {
            HStack(spacing: CompoundDesignTokens.space1_5X) {
                Text(filter.localizedName)
                    .lineLimit(1)
                
                CompoundIcon(\.close, size: .xSmall, relativeTo: .compound.bodyMDSemibold)
            }
            .font(.compound.bodyMDSemibold)
            .foregroundStyle(.compound.textBadgeAccent)
            .padding(.horizontal, CompoundDesignTokens.space3X)
            .padding(.vertical, CompoundDesignTokens.space1_5X)
            .background(.compound.bgBadgeAccent, in: .capsule)
            .frame(minHeight: CompoundDesignTokens.space11X)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.localizedName)
        .accessibilityAddTraits(.isSelected)
    }
}

// AGENT-PLATFORM (Brief 0083): the filter menu's button in Chats' navigation bar. While a filter is on its glyph
// fills its circle, as Mail's filter button does, in the accent; a bar's button style doesn't reach a menu.
struct RoomListFiltersMenuButton: View {
    @Binding var state: RoomListFiltersState
    
    var body: some View {
        Menu {
            RoomListFiltersMenuContent(state: $state)
        } label: {
            CompoundIcon(\.filter)
                .symbolVariant(state.isFiltering ? .circle.fill : .none)
        }
        .tint(state.isFiltering ? .compound.iconAccentPrimary : nil)
        .accessibilityLabel(UntranslatedL10n.screenRoomlistFilterMenuTitle)
        .accessibilityValue(state.activeFiltersDescription)
        .accessibilityAddTraits(state.isFiltering ? .isSelected : [])
    }
}

// AGENT-PLATFORM (Brief 0083): the menu. Each filter the user can turn on now is a
// toggle, in a fixed order, as the chips offered them: one that can't combine with an active filter isn't listed.
// Clear filters closes it while filtering.
struct RoomListFiltersMenuContent: View {
    @Binding var state: RoomListFiltersState
    
    var body: some View {
        Section {
            ForEach(RoomListFilter.allCases.filter { state.isFilterActive($0) || state.availableFilters.contains($0) }) { filter in
                Toggle(filter.localizedName, isOn: binding(for: filter))
            }
        }
        
        if state.isFiltering {
            Section {
                Button(L10n.screenRoomlistClearFilters) {
                    withAnimation(.easeInOut(duration: 0.2).disabledDuringTests()) {
                        state.clearFilters()
                    }
                }
            }
        }
    }
    
    private func binding(for filter: RoomListFilter) -> Binding<Bool> {
        Binding<Bool>(get: {
            state.isFilterActive(filter)
        }, set: { isEnabled, _ in
            withAnimation(.easeInOut(duration: 0.2).disabledDuringTests()) {
                if isEnabled {
                    state.activateFilter(filter)
                } else {
                    state.deactivateFilter(filter)
                }
            }
        })
    }
}

private extension RoomListFiltersState {
    /// The active filters as a localised list, in the order they were turned on: "Unread and People".
    var activeFiltersDescription: String {
        activeFilters.map(\.localizedName).formatted(.list(type: .and))
    }
}

// MARK: - Previews

struct RoomListFiltersView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        // AGENT-PLATFORM (Brief 0083): the tokens show only while filtering.
        RoomListFiltersView(state: .constant(.init(activeFilters: [.unreads], userSettings: .mock())))
        RoomListFiltersView(state: .constant(.init(activeFilters: [.rooms, .favourites],
                                                   userSettings: .mock())))
        RoomListFiltersView(state: .constant(.init(activeFilters: [.lowPriority],
                                                   userSettings: .mock())))
    }
}
