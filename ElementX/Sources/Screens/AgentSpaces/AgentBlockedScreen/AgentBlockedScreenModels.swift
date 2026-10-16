//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 194): «Контроль» › «Заблокированные» — the people
// this agent blocks (`GET /agents/{id}/blocks`), page by page, each with
// «Разблокировать». The owner's own messenger blocks are not listed here.
//

import Foundation

struct AgentBlockedScreenViewState: BindableState {
    let agent: AgentSpaceAgentCard

    var listState: AgentBlockedListState = .loading
    /// The person whose unblock is on its way (row spinner).
    var unblockingMXID: String?
    var bindings = AgentBlockedScreenViewStateBindings()

    var blocks: [AgentBlockedContact] {
        if case .loaded(let blocks, _) = listState { return blocks }
        return []
    }

    /// The bottom sentinel; `nil` when there is nothing more to read.
    var sentinel: LoadMoreState? {
        guard case .loaded(let blocks, let loadMore) = listState, !blocks.isEmpty else { return nil }
        if case .exhausted = loadMore { return nil }
        return loadMore
    }
}

enum AgentBlockedListState: Equatable {
    case loading
    case loaded([AgentBlockedContact], loadMore: LoadMoreState)
    /// The first page could not be read: never shown as «nobody».
    case failed
}

struct AgentBlockedScreenViewStateBindings {
    var alertInfo: AlertInfo<AgentBlockedScreenAlertType>?
}

enum AgentBlockedScreenAlertType: Hashable {
    case confirmUnblock
}

enum AgentBlockedScreenViewAction {
    case retry
    case loadMore
    /// «Разблокировать» on a row — asks first.
    case unblock(contactMXID: String)
}

/// How many people an agent blocks, as far as the first page says. `nil`
/// on the agent screen when it could not be read, never `0`.
enum AgentBlockedCount: Equatable {
    case exactly(Int)
    /// The first page was full: at least this many.
    case atLeast(Int)

    init(page: AgentBlockedContactsPage) {
        self = page.nextCursor == nil ? .exactly(page.blocks.count) : .atLeast(page.blocks.count)
    }

    /// «0», «3», «50+».
    var text: String {
        switch self {
        case .exactly(let count): String(count)
        case .atLeast(let count): "\(count)+"
        }
    }
}
