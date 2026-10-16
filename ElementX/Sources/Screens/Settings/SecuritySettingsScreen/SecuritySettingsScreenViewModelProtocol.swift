//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (decision 187): the Security hub.
// The Spiral feature is built on Element's `SettingsScreenViewModelProtocol.swift`.
//

import Combine

protocol SecuritySettingsScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<SecuritySettingsScreenViewModelAction, Never> { get }
    var context: SecuritySettingsScreenViewModelType.Context { get }
}
