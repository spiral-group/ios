//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import Combine

@MainActor
protocol InvitePeopleScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<InvitePeopleScreenViewModelAction, Never> { get }
    var context: InvitePeopleScreenViewModelType.Context { get }
}
