//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine

protocol AIConsentPromptScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AIConsentPromptScreenViewModelAction, Never> { get }
    var context: AIConsentPromptScreenViewModelType.Context { get }
}
