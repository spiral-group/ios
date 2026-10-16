//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0083): the green dot. Drawn on an avatar's
// bottom-trailing corner when the user is online; nothing otherwise — the
// absence of a dot says "we do not know", never "offline".
//

import Compound
import SwiftUI

struct PresenceBadge: View {
    /// The avatar's side, in points; the dot scales with it.
    let avatarSize: CGFloat
    /// The colour behind the avatar, for the ring that separates the dot
    /// from the picture.
    var ringColor: Color = .compound.bgCanvasDefault
    
    private var dotSize: CGFloat {
        min(18, max(8, (avatarSize * 0.28).rounded()))
    }

    private var ringWidth: CGFloat {
        max(1.5, (dotSize * 0.18).rounded(.up) / 2)
    }

    /// How far to move the dot in from the frame's corner so that its centre
    /// sits where the avatar's circle crosses the diagonal — ON the round
    /// avatar at any size, not in the empty corner of its square frame. The
    /// dot's layout box is `ringWidth` smaller than the dot on each side.
    var cornerInset: CGFloat {
        avatarSize * (1 - 1 / 2.squareRoot()) / 2 - (dotSize / 2 - ringWidth)
    }
    
    var body: some View {
        Circle()
            .fill(.compound.iconSuccessPrimary)
            .frame(width: dotSize, height: dotSize)
            .overlay(Circle().strokeBorder(ringColor, lineWidth: ringWidth))
            .padding(-ringWidth)
            .accessibilityLabel(UntranslatedL10n.commonPresenceOnline)
    }
}

extension View {
    /// Overlays the online dot on an avatar when `isOnline`. Not `announced`
    /// where a status line next to it already says «online» to VoiceOver.
    func presenceBadge(isOnline: Bool, avatarSize: CGFloat, ringColor: Color = .compound.bgCanvasDefault, announced: Bool = true) -> some View {
        overlay(alignment: .bottomTrailing) {
            if isOnline {
                let badge = PresenceBadge(avatarSize: avatarSize, ringColor: ringColor)
                badge.offset(x: -max(0, badge.cornerInset), y: -max(0, badge.cornerInset))
                    .accessibilityHidden(!announced)
            }
        }
    }
}

struct PresenceBadge_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 24) {
            HStack(spacing: 24) {
                ForEach([32.0, 52.0, 96.0], id: \.self) { size in
                    avatar(size: size, isOnline: true)
                }
            }
            HStack(spacing: 24) {
                avatar(size: 120, isOnline: true)
                avatar(size: 52, isOnline: false)
            }
        }
        .padding()
    }
    
    private static func avatar(size: CGFloat, isOnline: Bool) -> some View {
        Circle()
            .fill(.compound.bgSubtleSecondary)
            .frame(width: size, height: size)
            .presenceBadge(isOnline: isOnline, avatarSize: size)
    }
}
