//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct RoomListFiltersEmptyStateView: View {
    let state: RoomListFiltersState
    
    private var emptyStateTitle: String {
        if state.activeFilters.count == 1 {
            switch state.activeFilters[0] {
            case .unreads:
                return L10n.screenRoomlistFilterUnreadsEmptyStateTitle
            case .mentions:
                return L10n.screenRoomlistFilterMentionEmptyStateTitle
            case .people:
                return L10n.screenRoomlistFilterPeopleEmptyStateTitle
            case .rooms:
                return L10n.screenRoomlistFilterRoomsEmptyStateTitle
            case .favourites:
                return L10n.screenRoomlistFilterFavouritesEmptyStateTitle
            case .invites:
                return L10n.screenRoomlistFilterInvitesEmptyStateTitle
            case .lowPriority:
                return L10n.screenRoomlistFilterLowPriorityEmptyStateTitle
            }
        }
        return L10n.screenRoomlistFilterMixedEmptyStateTitle
    }
    
    private var emptyStateSubtitle: String {
        if state.activeFilters.first == .favourites {
            return L10n.screenRoomlistFilterFavouritesEmptyStateSubtitle
        }
        return L10n.screenRoomlistFilterMixedEmptyStateSubtitle
    }
    
    // AGENT-PLATFORM (Brief 0083): Spiral's empty state.
    var body: some View {
        SpiralEmptyState(symbol: .line3HorizontalDecrease, title: emptyStateTitle, message: emptyStateSubtitle)
    }
}

struct RoomListFiltersEmptyStateView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 24) {
            ForEach(RoomListFilter.allCases) { filter in
                RoomListFiltersEmptyStateView(state: .init(activeFilters: [filter],
                                                           userSettings: .mock()))
            }
            RoomListFiltersEmptyStateView(state: .init(activeFilters: [.people, .favourites],
                                                       userSettings: .mock()))
        }
        .padding(.bottom)
        .previewLayout(.sizeThatFits)
    }
}
