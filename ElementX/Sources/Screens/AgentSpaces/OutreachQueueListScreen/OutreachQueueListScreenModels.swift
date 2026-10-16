//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.

import Foundation

// MARK: - ViewModel → Coordinator actions

enum OutreachQueueListScreenViewModelAction {
    /// User tapped the "Add targets" toolbar button. Coordinator
    /// pushes `OutreachQueueAddScreen` keyed on the same agent.
    case openAddTargets
    /// User tapped Done / back. Coordinator pops.
    case dismissed
}

// MARK: - View ↔ ViewModel state

enum OutreachQueueListState: Equatable {
    case loading
    case loaded([OutreachQueueEntry])
    /// 409 — the agent isn't an outreach-kind variant. Terminal:
    /// the dashboard shouldn't have routed here in the first
    /// place, but defend so the screen doesn't crash on a stale
    /// row id. Distinct from `.failed` so the user gets the right
    /// mental model.
    case unavailable(reason: String)
    /// Wire returned 4xx/5xx other than the expected codes. Show
    /// the inline retry CTA.
    case failed(reason: String)
}

extension OutreachQueueListState {
    var items: [OutreachQueueEntry] {
        if case .loaded(let items) = self { return items }
        return []
    }
}

struct OutreachQueueListScreenViewState: BindableState {
    let agentID: String
    var listState: OutreachQueueListState = .loading
    /// `nil` = "All" filter; otherwise filters the list to the
    /// chosen status.
    var statusFilter: OutreachTargetStatus?
    var bindings: OutreachQueueListScreenViewStateBindings

    /// Helper for the empty-state copy: "All caught up" vs
    /// "No rows for this filter".
    var isFiltering: Bool {
        statusFilter != nil
    }
}

struct OutreachQueueListScreenViewStateBindings {
    var alertInfo: AlertInfo<OutreachQueueListScreenAlertType>?
}

enum OutreachQueueListScreenAlertType: Hashable {
    case fetchFailed
}

// MARK: - View → ViewModel actions

enum OutreachQueueListScreenViewAction {
    case appeared
    case refresh
    case selectFilter(OutreachTargetStatus?)
    case openAddTargets
    case dismiss
}
