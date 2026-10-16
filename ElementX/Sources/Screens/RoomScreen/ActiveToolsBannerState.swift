//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0044, ADR-0058): state model for the
// all-participant tools banner. A sibling of `PinnedEventsBannerState`
// — same rotation / count / "X of N" mechanics — but the unit of
// rotation is a SINGLE active tool (not an agent). Every active tool in
// the room, across every participant's agent, is one banner item, so a
// tap cycles through each tool in turn (e.g. your agent's "Translating
// to English" → your agent's "Summarise" → Bohdan's agent's tool). The
// items are fed from `com.spiral.tools` timeline events, not a
// dedicated SDK-focused timeline. The compact line shows only the
// tool's name; full attribution ("whose agent, what exactly") lives in
// the Manage panel.

import Compound
import OrderedCollections
import SwiftUI

/// One active tool as shown in the banner. The unit of rotation.
struct BannerToolItem: Equatable, Identifiable {
    /// Stable id, unique even when an agent has two tools of the same
    /// kind — `"<agentMXID>#<toolID-or-ordinal>"`. Used to preserve the
    /// selected item across timeline refreshes.
    let id: String
    /// Compact display line — the tool's name only (e.g. "Translating
    /// to English", "Summarise").
    let title: String
    /// The Compound icon for this tool's kind, resolved via its capability
    /// (`AgentCapability.icon(forToolKind:)`) so the banner icon matches the
    /// one shown in the capabilities sheet. Defaults to the translate icon.
    var icon: KeyPath<CompoundIcons, Image> = \.translate
    // periphery:ignore - used via the synthesized Hashable conformance
    /// The agent whose tool this is (attribution lives in Manage).
    let agentMatrixUserID: String
}

@MainActor
enum ActiveToolsBannerState: Equatable {
    case loading
    case loaded(state: ActiveToolsState)

    var isEmpty: Bool {
        switch self {
        case .loaded(let state): state.items.isEmpty
        case .loading: true
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Number of active tools in the room (across all agents).
    var count: Int {
        switch self {
        case .loaded(let state): state.items.count
        case .loading: 0
        }
    }

    var selectedIndex: Int {
        switch self {
        case .loaded(let state): state.selectedIndex
        case .loading: 0
        }
    }

    /// The current tool's compact line, e.g. "Translating to English".
    var displayedMessage: String {
        switch self {
        case .loading: ""
        case .loaded(let state): state.selectedTitle
        }
    }

    /// The current tool's icon, matching its kind (translate / voice call /
    /// summary / recording). Falls back to the translate icon while loading.
    var selectedIcon: KeyPath<CompoundIcons, Image> {
        switch self {
        case .loading: \.translate
        case .loaded(let state): state.selectedIcon
        }
    }

    /// "1 of N" indicator, shown only when count > 1.
    var bannerIndicatorDescription: AttributedString {
        let index = selectedIndex + 1
        let boldPlaceholder = "{bold}"
        var finalString = AttributedString(UntranslatedL10n.screenRoomToolsBannerIndicatorToolsDescription(boldPlaceholder))
        var boldString = AttributedString(UntranslatedL10n.screenRoomToolsBannerIndicator(index, count))
        boldString.bold()
        finalString.replace(boldPlaceholder, with: boldString)
        return finalString
    }

    /// Rotate to the next tool (wraps at last → 0), like pins.
    mutating func rotate() {
        if case .loaded(var state) = self {
            state.rotate()
            self = .loaded(state: state)
        }
    }

    /// Replace the flat tool list (from a fresh timeline read),
    /// preserving the selected tool by id when it still exists.
    mutating func setItems(_ items: [BannerToolItem]) {
        switch self {
        case .loading:
            self = items.isEmpty ? .loading
                : .loaded(state: .init(items: items, selectedID: items.first?.id))
        case .loaded(var state):
            state.items = items
            self = items.isEmpty ? .loading : .loaded(state: state)
        }
    }
}

@MainActor
struct ActiveToolsState: Equatable {
    /// Every active tool, flat. Order = reader order (newest-armed agent
    /// first) with each agent's tools kept together, in tool order.
    var items: [BannerToolItem] = [] {
        didSet {
            if let selectedID, !items.contains(where: { $0.id == selectedID }) {
                self.selectedID = items.first?.id
            } else if selectedID == nil, !items.isEmpty {
                selectedID = items.first?.id
            } else if items.isEmpty {
                selectedID = nil
            }
        }
    }

    var selectedID: String?

    var selectedIndex: Int {
        guard let selectedID else { return 0 }
        return items.firstIndex(where: { $0.id == selectedID }) ?? 0
    }

    var selectedTitle: String {
        guard let selectedID, let item = items.first(where: { $0.id == selectedID }) else { return " " }
        return item.title
    }

    var selectedIcon: KeyPath<CompoundIcons, Image> {
        guard let selectedID, let item = items.first(where: { $0.id == selectedID }) else { return \.translate }
        return item.icon
    }

    mutating func rotate() {
        guard !items.isEmpty else { return }
        let next = selectedIndex + 1
        selectedID = items[next % items.count].id
    }
}
