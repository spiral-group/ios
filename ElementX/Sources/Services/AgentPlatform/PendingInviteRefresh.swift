//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008; Brief 0086).
//

import Foundation

/// Asks the public landing endpoint about the remembered invitation and updates `pendingInvite` with its answer:
/// the inviter for a live one, nothing for a dead one. A tapped link and the App Clip's hand-off both end here,
/// so the inviter the start screen and the first session's welcome use is always the server's.
enum PendingInviteRefresh {
    static func refresh(_ link: SpiralInviteLink, resolver: InviteLinkResolverProtocol, appSettings: AppSettings) async {
        let resolution = await resolver.resolve(link)
        guard appSettings.pendingInvite?.token == link.token else { return } // Replaced meanwhile.
        
        switch resolution {
        case .success(.valid(let inviter)):
            appSettings.pendingInvite = PendingInvite(token: link.token,
                                                      inviterDisplayName: inviter?.displayName,
                                                      inviterUserID: inviter?.mxid)
        case .success:
            // Dead link: no banner, no token on the OAuth URL.
            appSettings.pendingInvite = nil
        case .failure:
            break // Could not check; keep it, identity-login decides.
        }
    }
}
