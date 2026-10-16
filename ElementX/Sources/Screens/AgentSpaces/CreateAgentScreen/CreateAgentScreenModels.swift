//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// AGENT-PLATFORM: Brief 0037, artboard 0037-F — provision a role agent
// inside a company space.

enum CreateAgentScreenViewModelAction {
    /// Created — the flow dismisses the sheet and reloads the space.
    case created
    case cancel
}

/// The three provisionable company roles (backend `CompanyRole`).
enum CreateAgentRole: String, CaseIterable, Equatable {
    case sales, outreach, support
    
    var title: String {
        switch self {
        case .sales: UntranslatedL10n.screenCreateAgentRoleSales
        case .outreach: UntranslatedL10n.screenCreateAgentRoleOutreach
        case .support: UntranslatedL10n.screenCreateAgentRoleSupport
        }
    }
}

struct CreateAgentScreenViewState: BindableState {
    let companyName: String
    
    var isCreating = false
    var bindings = CreateAgentScreenViewStateBindings()
    
    var canCreate: Bool { !isCreating && bindings.roleBrief.count <= 500 }
    
    /// The name an agent gets when the owner types none, in the app's
    /// language («Продажи · Кофейня Зерно»). Sent by the app: the server's
    /// own default would be English.
    var defaultDisplayName: String {
        "\(bindings.role.title) · \(companyName)"
    }
}

struct CreateAgentScreenViewStateBindings {
    var role: CreateAgentRole = .sales
    var displayName = ""
    /// What this agent is for, in the owner's words (artboard 0037-F;
    /// published bound 1..500 — submitted in the same create request).
    var roleBrief = ""
    var alertInfo: AlertInfo<CreateAgentScreenAlertType>?
}

enum CreateAgentScreenAlertType: Hashable {
    case createFailed
}

enum CreateAgentScreenViewAction {
    case selectRole(CreateAgentRole)
    case create
    case cancel
}
