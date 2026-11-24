//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias CreateAgentScreenViewModelType = StateStoreViewModelV2<CreateAgentScreenViewState, CreateAgentScreenViewAction>

class CreateAgentScreenViewModel: CreateAgentScreenViewModelType, CreateAgentScreenViewModelProtocol {
    private let companyID: String
    private let agentPlatformService: AgentPlatformServiceProtocol
    
    private let actionsSubject: PassthroughSubject<CreateAgentScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CreateAgentScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(companyID: String,
         companyName: String,
         agentPlatformService: AgentPlatformServiceProtocol) {
        self.companyID = companyID
        self.agentPlatformService = agentPlatformService
        
        super.init(initialViewState: CreateAgentScreenViewState(companyName: companyName))
    }
    
    override func process(viewAction: CreateAgentScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .selectRole(let role):
            state.bindings.role = role
        case .create:
            Task { await create() }
        case .cancel:
            actionsSubject.send(.cancel)
        }
    }
    
    // MARK: - Private
    
    private func create() async {
        state.isCreating = true
        defer { state.isCreating = false }
        
        let displayName = state.bindings.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let roleBrief = state.bindings.roleBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch await agentPlatformService.createCompanyAgent(companyID: companyID,
                                                             role: state.bindings.role.rawValue,
                                                             displayName: displayName.isEmpty ? state.defaultDisplayName : displayName,
                                                             roleBrief: roleBrief.isEmpty ? nil : roleBrief) {
        case .success:
            actionsSubject.send(.created)
        case .failure(let error):
            MXLog.error("Failed to create agent: \(error)")
            state.bindings.alertInfo = AlertInfo(id: .createFailed,
                                                 title: UntranslatedL10n.screenCreateAgentFailure,
                                                 message: error.agentNameRefusal)
        }
    }
}
