//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct TombstonedAvatarImage: View {
    @ScaledMetric private var frameSize: CGFloat
    
    init(avatarSize: Avatars.Size) {
        _frameSize = ScaledMetric(wrappedValue: avatarSize.value)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                // AGENT-PLATFORM: Spiral's bgSubtlePrimary is the canvas white and bgSubtleSecondary the grouped
                // background. gray.600 (#CACACE / #48484A, the secondary border's step) shows on white, the grouped
                // gray, black and a dark row, and carries the "!" in iconSecondary at 3.2:1.
                Color.compound.borderInteractiveSecondary
                
                Text(verbatim: "!")
                    .foregroundColor(.compound.iconSecondary) // AGENT-PLATFORM
                    .font(.system(size: geometry.size.width * 0.5625, weight: .semibold))
                    .minimumScaleFactor(0.001)
                    .frame(alignment: .center)
                    .accessibilityLabel(L10n.a11yTombstonedRoom)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(width: frameSize, height: frameSize)
        .background(Color.compound.bgCanvasDefault)
        .avatarShape(.roundedSquare, scaledSize: _frameSize) // AGENT-PLATFORM (Brief 0083, decision 357): a room's, as a live one.
    }
}

struct TombstonedAvatarImage_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        TombstonedAvatarImage(avatarSize: .room(on: .chats))
            .previewLayout(.sizeThatFits)
    }
}
