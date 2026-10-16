//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
protocol CreateCompanyScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<CreateCompanyScreenViewModelAction, Never> { get }
    var context: CreateCompanyScreenViewModelType.Context { get }
    
    /// The coordinator hands back the URL picked in one of the three
    /// media pickers (RoomDetailsEdit canon).
    func didSelectMediaUrl(url: URL)
}
