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

enum PublicProfileScreenViewModelAction {
    /// User tapped "Contact agent" on a row. Coordinator opens
    /// a DM (or pushes a room timeline) with that agent's MXID.
    /// The view model is intentionally unopinionated about how
    /// the DM is created — that's a flow-coordinator concern.
    case contactAgent(matrixUserID: String)
    /// User tapped Done / swiped to dismiss the screen.
    case dismissed
}

// MARK: - View ↔ ViewModel state

/// Modal state for the profile lookup. Mirrors the shape of
/// the verification + activity screens (loading → loaded |
/// failed) but adds an explicit "self" terminal so the screen
/// can short-circuit when an owner navigates to their own
/// profile (the dashboard already shows that surface — there's
/// no point re-rendering it as a stranger view).
enum PublicProfileState: Equatable {
    /// Initial fetch in flight.
    case loading
    /// Wire returned 200. Target user exists; agent list may
    /// be empty (every agent is private OR the user hasn't
    /// been provisioned yet — indistinguishable on the wire,
    /// rendered as the same empty state).
    case loaded(UserProfileView)
    /// Wire returned 404. The MXID is syntactically valid but
    /// the backend has no row for it. Distinct from
    /// `.failed` so the UI renders a friendlier "not on the
    /// platform" copy rather than a generic error.
    case notFound
    /// Caller looked up their own MXID. The dashboard is the
    /// canonical owner-side surface; we redirect rather than
    /// duplicate. Coordinator listens for this and pops the
    /// screen (or never pushes it from the dashboard entry
    /// point in the first place — guarded both sides).
    case selfLookup
    /// Wire returned 4xx (not 404) or 5xx, or transport blew
    /// up. The view renders an inline error + retry button.
    case failed(reason: String)
}

struct PublicProfileScreenViewState: BindableState {
    /// MXID handed to the view model at construction time.
    /// Surfaced in the header even while the fetch is in
    /// flight so the user knows what they're waiting on.
    var targetMXID: String
    var detailState: PublicProfileState = .loading
    /// The sync's state at the top while the stream is not live (decision 289).
    var syncStatus: PlatformSyncStatus?
    var bindings: PublicProfileScreenViewStateBindings
}

struct PublicProfileScreenViewStateBindings {
    var alertInfo: AlertInfo<PublicProfileScreenAlertType>?
}

enum PublicProfileScreenAlertType: Hashable {
    case fetchFailed
}

// MARK: - View → ViewModel actions

enum PublicProfileScreenViewAction {
    /// The inline retry button on `.failed`.
    case retry
    /// User tapped the "Contact agent" button on a row.
    case contactAgent(matrixUserID: String)
    /// User tapped Done / Close.
    case dismiss
}
