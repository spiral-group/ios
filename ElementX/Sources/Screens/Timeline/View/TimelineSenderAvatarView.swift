//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import Foundation
import SwiftUI

struct TimelineSenderAvatarView: View {
    @Environment(\.timelineContext) private var context
    
    let sender: TimelineItemSender
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083): beside the bubble, not over it, so it has no ring of the canvas's colour.
        LoadableAvatarImage(url: sender.avatarURL,
                            name: sender.displayName,
                            contentID: sender.id,
                            avatarSize: .user(on: .timeline),
                            mediaProvider: context?.mediaProvider)
            .agentBadge(userID: sender.id, avatarURL: sender.avatarURL, avatarSize: Avatars.Size.user(on: .timeline).value) // AGENT-PLATFORM (Brief 0083, decision 357)
    }
}
