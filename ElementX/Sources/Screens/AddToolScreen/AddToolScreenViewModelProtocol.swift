//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine

@MainActor
protocol AddToolScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AddToolScreenViewModelAction, Never> { get }
    var context: AddToolScreenViewModelType.Context { get }
}
