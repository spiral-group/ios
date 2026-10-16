//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine

protocol RoomScreenViewModelProtocol {
    var actions: AnyPublisher<RoomScreenViewModelAction, Never> { get }
    var context: RoomScreenViewModel.Context { get }
    
    func stop()
    
    func timelineHasScrolled(direction: ScrollDirection)
    func setSelectedPinnedEventID(_ eventID: String)
    /// AGENT-PLATFORM: re-pull the room's active tools so the in-chat banner
    /// reflects an arm / edit / disable done from the agent-tools sheet (Brief 0036 F2).
    func refreshAgentToolsBanner()
    func displayMediaPreview(_ mediaPreviewViewModel: TimelineMediaPreviewViewModel)
}
