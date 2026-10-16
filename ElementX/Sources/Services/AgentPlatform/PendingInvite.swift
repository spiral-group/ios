//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import Foundation

/// The invitation a person opened the app with, remembered in
/// `AppSettings.pendingInvite` until the first session uses it.
nonisolated struct PendingInvite: Codable, Hashable {
    let token: String
    /// Known when the public landing endpoint answered before the
    /// person reached the start screen; a campaign token has none.
    var inviterDisplayName: String?
    var inviterUserID: String?
    
    var link: SpiralInviteLink? {
        SpiralInviteLink(token: token)
    }
}
