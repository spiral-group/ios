//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModelProtocol.swift`.

import Combine

@MainActor
protocol ApprovalDetailScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<ApprovalDetailScreenViewModelAction, Never> { get }
    var context: ApprovalDetailScreenViewModelType.Context { get }
}
