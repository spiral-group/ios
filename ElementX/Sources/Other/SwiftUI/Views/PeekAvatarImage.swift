//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 389, operator 2026-11-09): an agent with no picture of its own shows the Peek, never its
// letter, everywhere the app draws it. `LoadableAvatarImage` decides; the agent badge stays on agents' own pictures.
// Question 390: each agent's Peek has a colour of its own (`AgentAvatarPalette`).
//

import Compound
import SpiralTokens
import SwiftUI

/// What an avatar draws for its owner, and whether the agent badge goes on it.
enum AgentAvatar {
    enum Fallback: Equatable {
        /// A person's or a room's initial.
        case letter
        /// An agent's Peek.
        case peek
    }

    /// What `contentID`'s avatar draws while it has no picture to show: no URL, still loading, or failed to load.
    nonisolated static func fallback(contentID: String) -> Fallback {
        SpiralAppPostSession.isAgent(contentID) ? .peek : .letter
    }

    /// Whether the badge goes on `userID`'s avatar: an agent with a picture of its own, never the Peek, which already
    /// says it is an agent; and only at a size where the badge's glyph reads. Decided by the URL, not by the load, so
    /// the badge is there from the first frame and doesn't pop in on a cold scroll (389's DEBT). A picture that fails
    /// to load keeps it, on the Peek.
    nonisolated static func showsBadge(userID: String?, avatarURL: URL?, avatarSize: CGFloat) -> Bool {
        guard let userID, avatarURL != nil, avatarSize >= AgentBadge.smallestAvatarSize else { return false }
        return SpiralAppPostSession.isAgent(userID)
    }
}

/// An agent's avatar without a picture: the Peek in white on the agent's own colour (question 390).
struct PeekAvatarImage: View {
    /// The agent's Matrix ID, which picks its colour.
    let agentID: String

    @Environment(\.redactionReasons) private var redactionReasons

    /// The glyph's share of the avatar's side: the letter's cap height, so a Peek sits beside a letter at its weight.
    private static let glyphScale = 0.56

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if redactionReasons.contains(.placeholder) {
                    Color(.systemGray4) // As the letters' monogram, and the default text redaction.
                } else {
                    LinearGradient(colors: AgentAvatarPalette.gradient(for: agentID).colors, startPoint: .top, endPoint: .bottom)

                    // `.fill` is the single-layer Peek; the call dock's `.layers` loses its second layer at 16–20 pt.
                    Image(asset: Asset.spiralPeekFill)
                        .resizable()
                        .symbolRenderingMode(.monochrome)
                        .scaledToFit()
                        .foregroundStyle(.compound.textOnSolidPrimary)
                        .frame(width: geometry.size.width * Self.glyphScale, height: geometry.size.width * Self.glyphScale)
                        .accessibilityHidden(true)
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
    }
}

struct PeekAvatarImage_Previews: PreviewProvider, TestablePreview {
    private static let agent = "@assistant-alex:example.com"
    private static let person = "@mira:example.com"

    static var previews: some View {
        avatars
            .previewDisplayName("Scale")

        avatars
            .environment(\.layoutDirection, .rightToLeft)
            .previewDisplayName("Right to left")
    }

    /// Each step of the scale with an agent's Peek beside a person's letter, then an agent's own picture and its badge.
    private static var avatars: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach([SpiralAvatarSize.xxSmall, SpiralAvatarSize.xSmall, SpiralAvatarSize.small, SpiralAvatarSize.medium], id: \.self) { size in
                HStack(spacing: 12) {
                    avatar(agent, name: "Alex Sample", size: size, url: nil)
                    avatar(person, name: "Mira Testova", size: size, url: nil)
                }
            }
            HStack(spacing: 12) {
                avatar(agent, name: "Alex Sample", size: SpiralAvatarSize.large, url: nil)
                avatar(agent, name: "Alex Sample", size: SpiralAvatarSize.large, url: .mockMXCUserAvatar)
            }
        }
        .padding()
    }

    private static func avatar(_ userID: String, name: String, size: CGFloat, url: URL?) -> some View {
        LoadableAvatarImage(url: url,
                            name: name,
                            contentID: userID,
                            avatarSize: .custom(size),
                            mediaProvider: MediaProviderMock(.init()))
            .agentBadge(userID: userID, avatarURL: url, avatarSize: size)
    }
}
