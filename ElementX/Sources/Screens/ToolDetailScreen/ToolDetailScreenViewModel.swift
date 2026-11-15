//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

typealias ToolDetailScreenViewModelType = StateStoreViewModelV2<ToolDetailScreenViewState, ToolDetailScreenViewAction>

class ToolDetailScreenViewModel: ToolDetailScreenViewModelType {
    init(detail: ToolDetail, mediaProvider: MediaProviderProtocol?) {
        super.init(initialViewState: ToolDetailScreenViewState(detail: detail), mediaProvider: mediaProvider)
    }
}
