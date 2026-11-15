//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083 phase 4, lane room-profile, decision 344): who this is and what can be done: the avatar,
// the name, the status and the action row on the page's field, then the first card. Element's pills are gone.

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

/// The first row of a `SpiralProfilePage`.
struct SpiralProfileHero<Actions: View, Footer: View>: View {
    private let picture: SpiralProfilePicture
    private let title: String
    private let isVerified: Bool
    private let agent: SpiralAgentProfile?
    private let presence: UserPresence?
    private let subtitle: String?
    private let userStatus: UserStatus?
    private let agentStatus: SpiralAgentStatus?
    private let showsActions: Bool
    private let mediaProvider: MediaProviderProtocol?
    private let avatarAccessibilityIdentifier: String?
    private let onAvatarTap: ((URL) -> Void)?
    private let actions: () -> Actions
    private let footer: () -> Footer

    /// - Parameters:
    ///   - agent: When this is an agent's page: the badge on the avatar and the role under the name (359).
    ///   - presence: The person's presence: «online / last seen …» under the name.
    ///   - subtitle: What stands under the name when no presence does: a group's size.
    ///   - agentStatus: An agent's own status, with its dot, under the role (the Agents tab's screen).
    ///   - footer: What needs saying right under the actions: an identity that changed.
    init(picture: SpiralProfilePicture,
         title: String,
         isVerified: Bool = false,
         agent: SpiralAgentProfile? = nil,
         presence: UserPresence? = nil,
         subtitle: String? = nil,
         userStatus: UserStatus? = nil,
         agentStatus: SpiralAgentStatus? = nil,
         mediaProvider: MediaProviderProtocol? = nil,
         avatarAccessibilityIdentifier: String? = nil,
         onAvatarTap: ((URL) -> Void)? = nil,
         @ViewBuilder actions: @escaping () -> Actions,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.init(picture: picture, title: title, isVerified: isVerified, agent: agent, presence: presence, subtitle: subtitle,
                  userStatus: userStatus, agentStatus: agentStatus, showsActions: true, mediaProvider: mediaProvider,
                  avatarAccessibilityIdentifier: avatarAccessibilityIdentifier, onAvatarTap: onAvatarTap,
                  actions: actions, footer: footer)
    }

    private init(picture: SpiralProfilePicture,
                 title: String,
                 isVerified: Bool,
                 agent: SpiralAgentProfile?,
                 presence: UserPresence?,
                 subtitle: String?,
                 userStatus: UserStatus?,
                 agentStatus: SpiralAgentStatus?,
                 showsActions: Bool,
                 mediaProvider: MediaProviderProtocol?,
                 avatarAccessibilityIdentifier: String?,
                 onAvatarTap: ((URL) -> Void)?,
                 actions: @escaping () -> Actions,
                 footer: @escaping () -> Footer) {
        self.picture = picture
        self.title = title
        self.isVerified = isVerified
        self.agent = agent
        self.presence = presence
        self.subtitle = subtitle
        self.userStatus = userStatus
        self.agentStatus = agentStatus
        self.showsActions = showsActions
        self.mediaProvider = mediaProvider
        self.avatarAccessibilityIdentifier = avatarAccessibilityIdentifier
        self.onAvatarTap = onAvatarTap
        self.actions = actions
        self.footer = footer
    }

    var body: some View {
        Section {
            hero
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }
    }

    private var hero: some View {
        VStack(spacing: CompoundDesignTokens.space4X) {
            avatar
                .agentBadge(userID: agent?.userID, avatarURL: picture.url, avatarSize: SpiralAvatarSize.xLarge, largestSide: 34)
                .dynamicTypeSize(.large) // The words below carry the scaling.
                .padding(.top, CompoundDesignTokens.space4X)

            VStack(spacing: CompoundDesignTokens.space1X) {
                name
                    .font(.compound.headingLGBold)
                statusLines
            }
            .multilineTextAlignment(.center)

            if showsActions {
                SpiralProfileActionRow(content: actions)
                    .padding(.top, CompoundDesignTokens.space2X)
            }

            footer()
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, CompoundDesignTokens.space3X)
        .spiralProfileFieldEdge()
    }

    private var avatar: some View {
        Group {
            switch picture {
            case .room(let roomAvatar):
                RoomAvatarImage(avatar: roomAvatar,
                                avatarSize: .custom(SpiralAvatarSize.xLarge),
                                mediaProvider: mediaProvider,
                                onAvatarTap: onAvatarTap)
            case .user(let profile):
                LoadableAvatarImage(url: profile.avatarURL,
                                    name: profile.displayName,
                                    contentID: profile.id,
                                    avatarSize: .custom(SpiralAvatarSize.xLarge),
                                    mediaProvider: mediaProvider,
                                    onTap: onAvatarTap)
            }
        }
        .accessibilityLabel(onAvatarTap != nil && picture.url != nil ? L10n.a11yViewAvatar : L10n.a11yAvatar)
        .accessibilityIdentifier(avatarAccessibilityIdentifier ?? "", isEnabled: avatarAccessibilityIdentifier != nil)
    }

    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1_5X) {
            // A wrapped name never starts its second line with the separator ("Anna Kovalchuk · assistant"), as the role line.
            Text(title.keepingSeparators)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

            if isVerified {
                CompoundIcon(\.verified, size: .small, relativeTo: .compound.headingLGBold)
                    .accessibilityLabel(L10n.commonVerified)
            }
        }
    }

    /// Only the ink stands on the field (340).
    @ViewBuilder
    private var statusLines: some View {
        // An agent's handle, which a person's page keeps in its first card, comes right under the name.
        if presence == nil, let subtitle {
            Text(subtitle)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
                .textSelection(.enabled)
        }
        
        if let roleLine = agent?.roleLine {
            Text(roleLine.keepingSeparators)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
        }
        
        if let agentStatus {
            HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1X) {
                SpiralAgentStatusMark(status: agentStatus)
                Text(agentStatus.title.keepingSeparators)
            }
            .font(.compound.bodyMD)
            .foregroundStyle(.compound.textPrimary)
        }
        
        // The minutes move without a new answer.
        if let presence {
            SwiftUI.TimelineView(.everyMinute) { context in
                if let status = presence.statusText(now: context.date) {
                    Text(status)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textPrimary)
                }
            }
        }

        if let displayedStatus = userStatus?.displayed {
            HStack(spacing: CompoundDesignTokens.space1_5X) {
                Text(String(displayedStatus.emoji))
                Text(displayedStatus.text)
            }
            .font(.compound.bodyMD)
            .foregroundStyle(.compound.textPrimary)
        }
    }
}

extension SpiralProfileHero where Footer == EmptyView {
    init(picture: SpiralProfilePicture,
         title: String,
         isVerified: Bool = false,
         agent: SpiralAgentProfile? = nil,
         presence: UserPresence? = nil,
         subtitle: String? = nil,
         userStatus: UserStatus? = nil,
         agentStatus: SpiralAgentStatus? = nil,
         mediaProvider: MediaProviderProtocol? = nil,
         avatarAccessibilityIdentifier: String? = nil,
         onAvatarTap: ((URL) -> Void)? = nil,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.init(picture: picture,
                  title: title,
                  isVerified: isVerified,
                  agent: agent,
                  presence: presence,
                  subtitle: subtitle,
                  userStatus: userStatus,
                  agentStatus: agentStatus,
                  mediaProvider: mediaProvider,
                  avatarAccessibilityIdentifier: avatarAccessibilityIdentifier,
                  onAvatarTap: onAvatarTap,
                  actions: actions,
                  footer: { EmptyView() })
    }
}

extension SpiralProfileHero where Actions == EmptyView {
    /// A hero whose own buttons stand under it, as the footer: no row of round actions.
    init(picture: SpiralProfilePicture,
         title: String,
         agent: SpiralAgentProfile? = nil,
         subtitle: String? = nil,
         agentStatus: SpiralAgentStatus? = nil,
         mediaProvider: MediaProviderProtocol? = nil,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.init(picture: picture, title: title, isVerified: false, agent: agent, presence: nil, subtitle: subtitle,
                  userStatus: nil, agentStatus: agentStatus, showsActions: false, mediaProvider: mediaProvider,
                  avatarAccessibilityIdentifier: nil, onAvatarTap: nil, actions: { EmptyView() }, footer: footer)
    }
}

// MARK: - The action row

/// The page's actions, side by side, up to five. At accessibility sizes they take two columns.
struct SpiralProfileActionRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)],
                      spacing: CompoundDesignTokens.space3X) {
                content()
            }
        } else {
            HStack(alignment: .top, spacing: CompoundDesignTokens.space2X) {
                Group(subviews: content()) { subviews in
                    ForEach(subviews) { subview in
                        subview
                            .frame(maxWidth: CompoundDesignTokens.space24X)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// One action: a button's or a share link's label.
struct SpiralProfileActionLabel: View {
    let title: String
    let icon: KeyPath<CompoundIcons, Image>
    var isBusy = false

    var body: some View {
        VStack(spacing: CompoundDesignTokens.space1_5X) {
            SpiralProfileActionGlyph(icon: icon, isBusy: isBusy)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            SpiralProfileActionTitle(title: title)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// The action row's stand-in until the page knows who it shows: it keeps the row's height.
struct SpiralProfileActionPlaceholder: View {
    var body: some View {
        SpiralProfileActionLabel(title: L10n.commonMessage, icon: \.chat)
            .spiralLoadingSlot(true, label: L10n.commonLoading)
    }
}

/// One action that opens a menu. The menu's label is the glyph alone: with the title in it, iOS 26+ grows the glass
/// to the whole label, over the title.
struct SpiralProfileActionMenu<Content: View>: View {
    let title: String
    let icon: KeyPath<CompoundIcons, Image>
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: CompoundDesignTokens.space1_5X) {
            Menu(content: content) {
                SpiralProfileActionGlyph(icon: icon, isBusy: false)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .buttonStyle(.spiralProfileAction)
            .accessibilityLabel(title)

            SpiralProfileActionTitle(title: title)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SpiralProfileActionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.compound.bodyXS)
            .foregroundStyle(.compound.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }
}

private struct SpiralProfileActionGlyph: View {
    let icon: KeyPath<CompoundIcons, Image>
    let isBusy: Bool

    @ScaledMetric(relativeTo: .caption) private var circleSide = SpiralAvatarSize.medium

    var body: some View {
        Group {
            if isBusy {
                ProgressView()
            } else {
                CompoundIcon(icon)
            }
        }
        .foregroundStyle(.compound.iconPrimary)
        .frame(width: circleSide, height: circleSide)
        .spiralGlass(in: Circle(), isInteractive: true, snapshotBackground: .compound.bgCanvasDefault.opacity(0.72)) // Decision 346
    }
}

struct SpiralProfileActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

extension ButtonStyle where Self == SpiralProfileActionButtonStyle {
    static var spiralProfileAction: SpiralProfileActionButtonStyle {
        SpiralProfileActionButtonStyle()
    }
}

// MARK: - The info card

/// A fact on the page's first card: a caption over its value.
struct SpiralProfileInfoRow<Value: View>: View {
    let caption: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        ListRow(kind: .custom {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
                Text(caption)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)

                value()
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ListRowPadding.insets)
            .accessibilityElement(children: .combine)
        })
    }
}
