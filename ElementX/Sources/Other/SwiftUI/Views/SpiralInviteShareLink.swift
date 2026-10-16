//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import SwiftUI

/// Shares the caller's personal invite link — the one thing a person
/// needs to register once the gate is `invite_only`.
struct SpiralInviteShareLink<Label: View>: View {
    let invite: MyInvite
    private let label: Label
    
    init(invite: MyInvite, @ViewBuilder label: () -> Label) {
        self.invite = invite
        self.label = label()
    }
    
    var body: some View {
        ShareLink(item: UntranslatedL10n.screenInvitePeopleShareMessage(invite.link.webURL.absoluteString)) {
            label
        }
    }
}

struct SpiralInviteShareLink_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        SpiralInviteShareLink(invite: MyInvite(link: SpiralInviteLink(token: "Qz8Hf72Kd91")!, maxUses: 10, used: 2, expiresAt: nil)) {
            Label("Share", icon: \.shareIos)
        }
    }
}
