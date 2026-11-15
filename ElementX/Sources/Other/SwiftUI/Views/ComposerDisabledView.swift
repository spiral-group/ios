//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct ComposerDisabledView: View {
    var body: some View {
        // AGENT-PLATFORM (Brief 0083): a caption in the field's place, as Messages says a conversation can't be
        // replied to; it was body text at the field's insets.
        Text(L10n.screenRoomTimelineNoPermissionToPost)
            .font(.compound.bodyMD)
            .foregroundStyle(.compound.textSecondary) // AGENT-PLATFORM (Brief 0083): textDisabled read 2.21:1 in light
            .multilineTextAlignment(.center)
            .chatBackgroundChip() // AGENT-PLATFORM (Brief 0083, question 357): 3.9:1 on the gradient without it
            // AGENT-PLATFORM (Brief 0083, end stage): one element, the caption on its chip: in the composer's bar the
            // chip's shadow picture was an unlabelled image of its own to accessibility, and the caption's frame took
            // in the paddings over the picture.
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.top, CompoundDesignTokens.space2X)
            .padding(.bottom, CompoundDesignTokens.space4X)
            .onChatBackground() // AGENT-PLATFORM (Brief 0083, question 357)
    }
}
