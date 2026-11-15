//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

struct ToolDetailScreenCoordinatorParameters {
    let detail: ToolDetail
    let mediaProvider: MediaProviderProtocol?
}

final class ToolDetailScreenCoordinator: CoordinatorProtocol {
    private let viewModel: ToolDetailScreenViewModel
    
    init(parameters: ToolDetailScreenCoordinatorParameters) {
        viewModel = ToolDetailScreenViewModel(detail: parameters.detail, mediaProvider: parameters.mediaProvider)
    }
    
    func toPresentable() -> AnyView {
        AnyView(ToolDetailScreen(context: viewModel.context))
    }
}
