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

/// Drives `PublicProfileScreen`: the target user's public profile,
/// persona previews and per-agent "Contact agent" actions, with friendly
/// copy for 404 / self-lookup / failure states.
///
/// ### Self-lookup short-circuit
///
/// When the caller navigates to their own MXID we render an explicit
/// "this is you" terminal state instead of duplicating the owner
/// dashboard; nothing is read.
///
/// AGENT-PLATFORM: platform sync (decision 289). The profile is the
/// session store's; `profile.public` (any public agent's profile moved; it
/// names the agent, not the person) reads an open profile again.
class PublicProfileScreenViewModel: PublicProfileScreenViewModelType, PublicProfileScreenViewModelProtocol {
    private let targetMXID: String
    private let currentUserMXID: String
    private let store: AgentsStore

    private let actionsSubject: PassthroughSubject<PublicProfileScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<PublicProfileScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    private var resource: AgentsResource {
        .publicProfile(userID: targetMXID)
    }

    private var isSelfLookup: Bool {
        Self.isSameUser(lhs: targetMXID, rhs: currentUserMXID)
    }

    init(targetMXID: String,
         currentUserMXID: String,
         store: AgentsStore) {
        self.targetMXID = targetMXID
        self.currentUserMXID = currentUserMXID
        self.store = store
        super.init(initialViewState: PublicProfileScreenViewState(targetMXID: targetMXID, bindings: PublicProfileScreenViewStateBindings()))

        // Don't fire the wire for oneself: the owner already sees their dashboard.
        guard !isSelfLookup else {
            state.detailState = .selfLookup
            return
        }
        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        store.show(resource, by: self)
    }

    isolated deinit {
        store.stopShowing(resource, by: self)
    }

    // MARK: - Public

    override func process(viewAction: PublicProfileScreenViewAction) {
        MXLog.info("PublicProfileScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .retry:
            guard !isSelfLookup else { return }
            Task { await store.reread(resource) }
        case .contactAgent(let mxid):
            actionsSubject.send(.contactAgent(matrixUserID: mxid))
        case .dismiss:
            actionsSubject.send(.dismissed)
        }
    }

    // MARK: - Private

    private func render() {
        let detailState: PublicProfileState = switch store.readState(resource, \.publicProfile) {
        case .loading: .loading
        case .loaded(let profile): .loaded(profile)
        case .failed(.notFound): .notFound
        case .failed(let error): .failed(reason: error.description)
        }
        if state.detailState != detailState {
            state.detailState = detailState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
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
