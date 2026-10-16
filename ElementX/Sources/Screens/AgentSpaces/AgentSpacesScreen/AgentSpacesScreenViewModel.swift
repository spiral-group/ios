//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AgentSpacesScreenViewModelType = StateStoreViewModelV2<AgentSpacesScreenViewState, AgentSpacesScreenViewAction>

class AgentSpacesScreenViewModel: AgentSpacesScreenViewModelType, AgentSpacesScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol

    /// While the reconcile worker is provisioning the Personal space
    /// the directory answers `provisioningStatus: .inProgress` — poll
    /// until it settles so the owner isn't stuck on the hint screen.
    private static let provisioningPollInterval: Duration = .seconds(2)
    private var provisioningPollTask: Task<Void, Never>?
    /// Reads overlap (appear, pull, a change elsewhere); only the newest one's answer is shown.
    private var reloadGeneration: UInt64 = 0

    private let actionsSubject: PassthroughSubject<AgentSpacesScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentSpacesScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    private let approvalsStreamService: ApprovalsStreamServiceProtocol?

    init(userSession: UserSessionProtocol,
         agentPlatformService: AgentPlatformServiceProtocol) {
        self.agentPlatformService = agentPlatformService
        approvalsStreamService = userSession.approvalsStreamService

        super.init(initialViewState: AgentSpacesScreenViewState(userID: userSession.clientProxy.userID),
                   mediaProvider: userSession.mediaProvider)

        // Bell badge: self-rearming observation of the approvals stream's
        // pending count — the same @Observable pattern the tab badge uses
        // in UserSessionFlowCoordinator.
        if approvalsStreamService != nil {
            state.pendingApprovalsCount = approvalsStreamService?.pendingCount ?? 0
            rearmApprovalsBadgeObservation()
        }

        userSession.clientProxy.userProfilePublisher
            .receive(on: DispatchQueue.main)
            .map(\.avatarURL)
            .weakAssign(to: \.state.userAvatarURL, on: self)
            .store(in: &cancellables)

        userSession.clientProxy.userProfilePublisher
            .receive(on: DispatchQueue.main)
            .map(\.displayName)
            .weakAssign(to: \.state.userDisplayName, on: self)
            .store(in: &cancellables)
    }

    isolated deinit {
        provisioningPollTask?.cancel()
    }

    // MARK: - Public

    override func process(viewAction: AgentSpacesScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .selectAgent(let agentID):
            for section in state.sections {
                if let card = section.agents.first(where: { $0.agentID == agentID }) {
                    actionsSubject.send(.selectAgent(.init(card: card,
                                                           companyName: section.summary.kind == .company ? section.summary.displayName : nil)))
                    return
                }
            }
        case .showSettings:
            actionsSubject.send(.showSettings)
        case .createCompany:
            actionsSubject.send(.showCreateCompany)
        case .createAgent(let orgID):
            guard let company = state.companies.first(where: { $0.orgID == orgID }) else { return }
            actionsSubject.send(.showCreateAgent(company))
        case .editCompany(let orgID):
            guard let detail = state.sections.first(where: { $0.id == orgID })?.detail, detail.kind == .company else { return }
            actionsSubject.send(.showEditCompany(detail))
        case .showNotifications:
            actionsSubject.send(.showNotifications)
        case .retry:
            state.listState = .loading
            Task { await reload() }
        case .refresh:
            Task { await reload() }
        case .appeared:
            // A company or agent made elsewhere shows once the list is back
            // on screen; rows already shown stay until the answer replaces them.
            Task { await reload() }
        }
    }

    func reload() async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        let result = await agentPlatformService.listMyAgentSpaces()
        guard generation == reloadGeneration else { return }

        switch result {
        case .success(let directory):
            if directory.spaces.isEmpty, directory.provisioningStatus == .inProgress {
                state.listState = .provisioning
                scheduleProvisioningPoll()
                return
            }
            let sections = await loadSections(directory.spaces)
            guard generation == reloadGeneration else { return }
            state.listState = .loaded(sections)
        case .failure(let error):
            MXLog.error("Failed to load agent spaces: \(error)")
            // Keep showing stale content if we have it; only surface
            // the failure state when there is nothing to show.
            if case .loaded = state.listState {} else {
                state.listState = .failure
            }
        }
    }

    // MARK: - Private

    /// Each space's agents, in the directory's order (Personal first).
    /// Sequential: Swift 6.2 strict checking forbids `async let` child tasks
    /// capturing the non-Sendable service existential, and a person has a
    /// handful of spaces at most.
    private func loadSections(_ spaces: [AgentSpaceSummary]) async -> [AgentSpaceSection] {
        var sections: [AgentSpaceSection] = []
        for space in spaces {
            switch await agentPlatformService.fetchAgentSpace(orgID: space.orgID) {
            case .success(let detail):
                sections.append(.init(summary: space, content: .loaded(detail)))
            case .failure(let error):
                MXLog.error("Failed to load agent space \(space.orgID): \(error)")
                // A refresh that fails keeps what was shown for this space.
                if let shown = state.sections.first(where: { $0.id == space.orgID }), shown.detail != nil {
                    sections.append(shown)
                } else {
                    sections.append(.init(summary: space, content: .failed))
                }
            }
        }
        return sections
    }

    private func rearmApprovalsBadgeObservation() {
        guard let approvalsStreamService else { return }
        withObservationTracking {
            _ = approvalsStreamService.pendingCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let approvalsStreamService = self.approvalsStreamService else { return }
                state.pendingApprovalsCount = approvalsStreamService.pendingCount
                rearmApprovalsBadgeObservation()
            }
        }
    }

    private func scheduleProvisioningPoll() {
        provisioningPollTask?.cancel()
        provisioningPollTask = Task { [weak self] in
            try? await Task.sleep(for: Self.provisioningPollInterval)
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }
}
