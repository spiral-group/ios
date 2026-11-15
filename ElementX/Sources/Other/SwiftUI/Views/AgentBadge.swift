//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, decision 357): the badge that tells an agent from a person, wherever the two can be
// confused. Every agent's page shows it: in a chat, in a profile and on the Agents tab (359). Only on an agent's own
// picture: an agent without one shows the Peek, which says it already (question 389). The picture's URL decides, so the
// badge never waits for the load. Not in the chat list, where the row's name says it and the badge would crowd the
// online dot (question 391). Question 393: it is drawn as the online dot is, a filled circle with the surface's ring
// cut round it, and carries our white Peek, not the generic sparkle (as 386 did for the assistant). Its fill is the
// agent's own colour, so it reads as a tiny copy of the agent's Peek avatar.
//

import Compound
import SpiralTokens
import SwiftUI

struct AgentBadge: View {
    /// The avatar's side, in points; the badge scales with it.
    let avatarSize: CGFloat
    /// The colour behind the avatar: the badge's own, as though the surface showed through a cut in the picture.
    var surfaceColor: Color = .compound.bgCanvasDefault
    /// The most the badge grows to; an agent's page lets it follow its big avatar.
    var largestSide: CGFloat = 24
    /// The agent's Matrix ID, which picks its colour.
    let agentID: String
    
    /// Under this size the glyph can't be read.
    nonisolated static let smallestAvatarSize = SpiralAvatarSize.xSmall
    /// The Peek's share of the plate's side.
    private static let glyphScale = 0.66
    
    private var side: CGFloat {
        min(largestSide, max(13, (avatarSize * 0.34).rounded()))
    }
    
    /// How far in from the frame's corner the badge sits, so that its centre lies where the round avatar crosses the
    /// diagonal. Negative when the badge is bigger than that gap: it then hangs just over the frame.
    var cornerInset: CGFloat {
        avatarSize * (1 - 1 / 2.squareRoot()) / 2 - side / 2
    }
    
    var body: some View {
        Image(asset: Asset.spiralPeekFill)
            .resizable()
            .symbolRenderingMode(.monochrome)
            .scaledToFit()
            // A share of the plate, not Dynamic Type: the avatar's size already carries the scaling.
            .frame(width: (side * Self.glyphScale).rounded(), height: (side * Self.glyphScale).rounded())
            .foregroundStyle(.compound.iconOnSolidPrimary)
            .frame(width: side, height: side)
            .background(AgentAvatarPalette.gradient(for: agentID).solid, in: Circle())
            // The online dot's ring: the surface cut round the mark, outside its layout box as the dot's.
            .background(Circle().fill(surfaceColor).padding(-PresenceBadge.ringWidth(around: side)))
    }
}

extension AgentBadge {
    /// Where an avatar is drawn, which can rule the badge out whatever the avatar shows.
    nonisolated enum Context {
        /// The room header, timeline senders, members, calls and profiles: the badge wherever the avatar allows it.
        case standard
        /// A chat-list row, whose name already says what the agent is: no badge, so it never crowds the online dot.
        case chatList
        
        /// Whether an avatar drawn here may carry the badge; the avatar itself still decides whether it does.
        var allowsBadge: Bool {
            switch self {
            case .standard: true
            case .chatList: false
            }
        }
    }
}

extension EnvironmentValues {
    /// Where the avatars below are drawn, for the agent badge; a chat list sets `.chatList`.
    @Entry var agentBadgeContext = AgentBadge.Context.standard
}

extension View {
    /// Overlays the badge on `userID`'s avatar when they are an agent with a picture of its own (`avatarURL`, the
    /// one the avatar loads), on the bottom trailing corner; never on the Peek (question 389). VoiceOver skips it: an
    /// avatar is hidden from it, and the row says what this is.
    func agentBadge(userID: String?, avatarURL: URL?, avatarSize: CGFloat, surfaceColor: Color = .compound.bgCanvasDefault, largestSide: CGFloat = 24) -> some View {
        modifier(AvatarBadgesModifier(userID: userID,
                                      showsAgentBadge: AgentAvatar.showsBadge(userID: userID, avatarURL: avatarURL, avatarSize: avatarSize),
                                      isOnline: false,
                                      announced: false,
                                      avatarSize: avatarSize,
                                      surfaceColor: surfaceColor,
                                      largestSide: largestSide))
    }
    
    /// The badge and the online dot together, for a place that can show both: beside the badge, the dot moves to
    /// the opposite bottom corner.
    func avatarBadges(userID: String?, avatarURL: URL?, isOnline: Bool, avatarSize: CGFloat, surfaceColor: Color = .compound.bgCanvasDefault, announced: Bool = true) -> some View {
        modifier(AvatarBadgesModifier(userID: userID,
                                      showsAgentBadge: AgentAvatar.showsBadge(userID: userID, avatarURL: avatarURL, avatarSize: avatarSize),
                                      isOnline: isOnline,
                                      announced: announced,
                                      avatarSize: avatarSize,
                                      surfaceColor: surfaceColor,
                                      largestSide: 24))
    }
}

private struct AvatarBadgesModifier: ViewModifier {
    let userID: String?
    let showsAgentBadge: Bool
    let isOnline: Bool
    let announced: Bool
    let avatarSize: CGFloat
    let surfaceColor: Color
    let largestSide: CGFloat
    @ScaledMetric private var scaledAvatarSize: CGFloat // As `LoadableAvatarImage`'s frame.
    @Environment(\.agentBadgeContext) private var context
    
    init(userID: String?, showsAgentBadge: Bool, isOnline: Bool, announced: Bool, avatarSize: CGFloat, surfaceColor: Color, largestSide: CGFloat) {
        self.userID = userID
        self.showsAgentBadge = showsAgentBadge
        self.isOnline = isOnline
        self.announced = announced
        self.avatarSize = avatarSize
        self.surfaceColor = surfaceColor
        self.largestSide = largestSide
        _scaledAvatarSize = ScaledMetric(wrappedValue: avatarSize)
    }
    
    func body(content: Content) -> some View {
        let showsBadge = context.allowsBadge && showsAgentBadge
        return content
            .overlay(alignment: .bottomTrailing) {
                if showsBadge, let userID {
                    let badge = AgentBadge(avatarSize: scaledAvatarSize, surfaceColor: surfaceColor, largestSide: largestSide, agentID: userID)
                    badge
                        .padding(.trailing, badge.cornerInset)
                        .padding(.bottom, badge.cornerInset)
                        .accessibilityHidden(true)
                }
            }
            .presenceBadge(isOnline: isOnline,
                           avatarSize: avatarSize,
                           ringColor: surfaceColor,
                           announced: announced,
                           corner: showsBadge ? .bottomLeading : .bottomTrailing)
    }
}

struct AgentBadge_Previews: PreviewProvider, TestablePreview {
    private static let agent = "@assistant-alice:example.com"
    private static let person = "@alice:example.com"
    
    static var previews: some View {
        badges
            .previewDisplayName("Sizes")
        
        badges
            .environment(\.layoutDirection, .rightToLeft)
            .previewDisplayName("Right to left")
    }
    
    private static var badges: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                ForEach([SpiralAvatarSize.xxSmall, SpiralAvatarSize.xSmall, SpiralAvatarSize.small, SpiralAvatarSize.medium], id: \.self) { size in
                    avatar(agent, size: size, url: nil)
                }
            }
            
            HStack(spacing: 24) {
                avatar(agent, size: SpiralAvatarSize.medium, url: .mockMXCUserAvatar)
                avatar(agent, size: SpiralAvatarSize.medium, url: nil, isOnline: true)
                avatar(person, size: SpiralAvatarSize.medium, url: nil, isOnline: true)
            }
            
            HStack(spacing: 24) {
                avatar(agent, size: SpiralAvatarSize.large, url: nil, isOnline: true)
                avatar(agent, size: SpiralAvatarSize.xLarge, url: .mockMXCUserAvatar)
            }
        }
        .padding()
    }
    
    private static func avatar(_ userID: String, size: CGFloat, url: URL?, isOnline: Bool = false) -> some View {
        LoadableAvatarImage(url: url,
                            name: "Alice",
                            contentID: userID,
                            avatarSize: .custom(size),
                            mediaProvider: MediaProviderMock(.init()))
            .avatarBadges(userID: userID, avatarURL: url, isOnline: isOnline, avatarSize: size)
    }
}
