//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083 phase 4, lane room-profile, decision 344): what the header's pills said, in words near
// the foot of the page: encryption, a public room, what new members see.

import Compound
import SwiftUI

/// One thing the page says about a room's security.
struct SpiralProfileSecurityFact: Identifiable {
    let icon: KeyPath<CompoundIcons, Image>
    let title: String
    var description: String?

    var id: String {
        title
    }

    static func facts(of room: RoomDetails) -> [SpiralProfileSecurityFact] {
        var facts = [room.isEncrypted
            ? SpiralProfileSecurityFact(icon: \.lock,
                                        title: L10n.screenRoomDetailsEncryptionEnabledTitle,
                                        description: L10n.screenRoomDetailsEncryptionEnabledSubtitle)
            : SpiralProfileSecurityFact(icon: \.lockOff, title: L10n.screenRoomDetailsBadgeNotEncrypted)]

        if room.isPublic {
            facts.append(.init(icon: \.public, title: L10n.screenRoomDetailsBadgePublic))
        }

        // A DM has no new members.
        switch room.isDirect ? nil : room.historySharingState {
        case .hidden:
            facts.append(.init(icon: \.visibilityOff, title: L10n.cryptoHistorySharingRoomInfoHiddenBadgeContent))
        case .shared:
            facts.append(.init(icon: \.history, title: L10n.cryptoHistorySharingRoomInfoSharedBadgeContent))
        case .worldReadable:
            facts.append(.init(icon: \.userProfileSolid, title: L10n.cryptoHistorySharingRoomInfoWorldReadableBadgeContent))
        case .none:
            break
        }

        return facts
    }
}
