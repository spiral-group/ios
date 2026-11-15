//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0063): the profile avatar at call scales.

import Compound
import SwiftUI

/// The design's letter avatar with the real picture when the profile has
/// one — sized for the stage and the cards from Spiral's avatar scale.
struct NativeCallLetterAvatar: View {
    let userID: String?
    let profile: NativeCallMemberProfile?
    let fallbackName: String?
    let size: CGFloat
    let mediaProvider: MediaProviderProtocol?
    /// For someone who is not a room member yet — an agent in the picker has
    /// no member profile to read, so its avatar arrives on its own. The
    /// member profile still wins when there is one: that is the picture the
    /// rest of the room sees.
    var avatarURL: URL?

    var body: some View {
        LoadableAvatarImage(url: profile?.avatarURL ?? avatarURL,
                            name: profile?.displayName ?? fallbackName,
                            contentID: userID ?? fallbackName ?? "",
                            avatarSize: .custom(size),
                            mediaProvider: mediaProvider)
            .accessibilityHidden(true)
    }
}
