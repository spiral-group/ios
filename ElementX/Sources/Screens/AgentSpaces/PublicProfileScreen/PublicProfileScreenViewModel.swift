//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.

import Combine
import SwiftUI

typealias PublicProfileScreenViewModelType = StateStoreViewModelV2<PublicProfileScreenViewState, PublicProfileScreenViewAction>

/// Drives `PublicProfileScreen`. Fetches the target user's
/// public profile on `.appeared`, surfaces persona previews +
/// per-agent "Contact agent" actions, falls back to friendly
/// copy for 404 / self-lookup / failure states.
///
/// ### Self-lookup short-circuit
///
/// When the caller navigates to their own MXID we render an
/// explicit "this is you — open the dashboard" terminal state
/// instead of duplicating the owner dashboard. The
/// `currentUserMXID` parameter is injected at construction
/// (resolved from `UserSession.clientProxy.userID` by the
/// coordinator) so this check happens entirely in the view
/// model — easy to unit-test, never re-tries on refresh.
///
/// ### `.appeared` skip on terminal state
///
/// Mirrors `VerificationDetailScreenViewModel`'s pattern: once
/// the screen has landed on `notFound` / `selfLookup` /
/// `failed`, refetching on re-appearance is wasted (the user
/// is just looking before dismissing). Explicit `.refresh`
/// pulls a fresh request through.
class PublicProfileScreenViewModel: PublicProfileScreenViewModelType, PublicProfileScreenViewModelProtocol {
    private let targetMXID: String
    private let currentUserMXID: String
    private let agentPlatformService: any AgentPlatformServiceProtocol

    private let actionsSubject: PassthroughSubject<PublicProfileScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<PublicProfileScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(targetMXID: String,
         currentUserMXID: String,
         agentPlatformService: any AgentPlatformServiceProtocol,
         initialState: PublicProfileState = .loading) {
        self.targetMXID = targetMXID
        self.currentUserMXID = currentUserMXID
        self.agentPlatformService = agentPlatformService
        let bindings = PublicProfileScreenViewStateBindings()
        var initial = PublicProfileScreenViewState(targetMXID: targetMXID, bindings: bindings)
        initial.detailState = initialState
        super.init(initialViewState: initial)
    }

    // MARK: - Public

    override func process(viewAction: PublicProfileScreenViewAction) {
        MXLog.info("PublicProfileScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            if state.detailState.isTerminalForFetch {
                return
            }
            Task { await loadProfile() }
        case .refresh:
            Task { await loadProfile() }
        case .contactAgent(let mxid):
            actionsSubject.send(.contactAgent(matrixUserID: mxid))
        case .dismiss:
            actionsSubject.send(.dismissed)
        }
    }

    // MARK: - Private

    private func loadProfile() async {
        // Self-lookup short-circuit. Don't fire the wire — the
        // backend would happily return the profile but the UX
        // is wrong (owner already sees their dashboard).
        if Self.isSameUser(lhs: targetMXID, rhs: currentUserMXID) {
            state.detailState = .selfLookup
            return
        }

        state.detailState = .loading

        switch await agentPlatformService.fetchUserProfile(mxid: targetMXID) {
        case .success(let profile):
            state.detailState = .loaded(profile)
        case .failure(let error):
            if case .notFound = error {
                state.detailState = .notFound
                return
            }
            MXLog.error("PublicProfileScreenViewModel: fetch failed: \(error)")
            state.detailState = .failed(reason: error.description)
            state.bindings.alertInfo = AlertInfo(id: .fetchFailed,
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                     Task { await self?.loadProfile() }
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        }
    }

    /// Compare two MXIDs case-insensitively (Matrix spec MSC1597
    /// — localparts are case-sensitive in spec but in practice
    /// homeservers store canonical lowercase; mixed-case input
    /// to the search field shouldn't bypass the self-lookup
    /// guard). Trims surrounding whitespace too.
    ///
    /// Public-on-static so unit tests can pin the comparator
    /// without instantiating the view model.
    static func isSameUser(lhs: String, rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension PublicProfileState {
    /// True iff refetching on `.appeared` is wasted because the
    /// state can't transition out via a no-op refetch. The user
    /// can still pull-to-refresh which fires the explicit
    /// `.refresh` action.
    var isTerminalForFetch: Bool {
        switch self {
        case .notFound, .selfLookup, .failed:
            return true
        case .loaded, .loading:
            return false
        }
    }
}
