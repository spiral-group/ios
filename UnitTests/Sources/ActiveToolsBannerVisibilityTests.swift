//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0044, ADR-0058): the all-participant tools banner
// mirrors the pinned-events banner's scroll behaviour — it hides once the user
// scrolls to the top of the timeline so it never obscures the messages the user
// just scrolled up to read.

import Foundation
@testable import Spiral
import Testing

@MainActor
struct ActiveToolsBannerVisibilityTests {
    private func makeState(tools: [BannerToolItem],
                           scroll: ScrollDirection?) -> RoomScreenViewState {
        var state = RoomScreenViewState(roomAvatar: .room(id: "!r:host", name: "Room", avatarURL: nil),
                                        hasOngoingCall: false,
                                        isDM: false,
                                        hasSuccessor: false)
        state.activeToolsBannerState.setItems(tools)
        state.lastScrollDirection = scroll
        return state
    }

    private func item(_ id: String) -> BannerToolItem {
        BannerToolItem(id: id, title: "Translating to English", agentMatrixUserID: "@a:host")
    }

    @Test
    func showsWhenToolsPresentAndNotScrolledToTop() {
        #expect(makeState(tools: [item("i0")], scroll: nil).shouldShowActiveToolsBanner)
        #expect(makeState(tools: [item("i0")], scroll: .bottom).shouldShowActiveToolsBanner)
    }

    @Test
    func hidesWhenScrolledToTop() {
        // Scrolled to the top → the banner steps out of the way, exactly like
        // the pinned-events banner.
        #expect(!makeState(tools: [item("i0")], scroll: .top).shouldShowActiveToolsBanner)
    }

    @Test
    func hidesWhenNoTools() {
        #expect(!makeState(tools: [], scroll: .bottom).shouldShowActiveToolsBanner)
        #expect(!makeState(tools: [], scroll: .top).shouldShowActiveToolsBanner)
    }
}
