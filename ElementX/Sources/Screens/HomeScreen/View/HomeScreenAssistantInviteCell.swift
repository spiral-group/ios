//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3 A2, operator's concept A, 2026-11-20): the person's own assistant, pinned on top of Chats
// while its chat waits to be started. A chat row on a soft accent tint: tapping it opens the assistant's chat before
// consent; «Start» accepts the invite, which is the consent (ADR-0017). There is no Decline: the server creates the
// chat once and never invites again.
//

import Compound
import MatrixRustSDKMocks
import SpiralTokens
import SwiftUI

struct HomeScreenAssistantInviteCell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let room: HomeScreenRoom
    let context: HomeScreenViewModel.Context

    var body: some View {
        content
            .padding(.vertical, CompoundDesignTokens.space3X)
            .padding(.leading, CompoundDesignTokens.space4X)
            .padding(.trailing, CompoundDesignTokens.space3X)
            .background(.compound.iconAccentPrimary.opacity(tintOpacity), in: .rect(cornerRadius: SpiralRadius.bubble))
            // The avatar lines up with the rows' avatars below, after their unread marker's column.
            .padding(.horizontal, CompoundDesignTokens.space2X)
            .padding(.vertical, CompoundDesignTokens.space1X)
    }

    // MARK: - Private

    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
                row
                startButton
            }
        } else {
            HStack(spacing: CompoundDesignTokens.space3X) {
                row
                startButton
            }
        }
    }

    private var row: some View {
        Button {
            context.send(viewAction: .selectRoom(roomIdentifier: room.id))
        } label: {
            HStack(spacing: CompoundDesignTokens.space3X) {
                if !dynamicTypeSize.isAccessibilitySize {
                    RoomAvatarImage(avatar: avatar,
                                    avatarSize: .room(on: .chats),
                                    mediaProvider: context.mediaProvider)
                        .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
                    HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1X) {
                        Text(UntranslatedL10n.screenRoomlistAssistantInviteName)
                            .font(.compound.bodyLGSemibold)
                            .foregroundStyle(.compound.textPrimary)

                        CompoundIcon(\.pin, size: .xSmall, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconAccentPrimary)
                            .accessibilityLabel(L10n.commonPinned)
                    }

                    Text(UntranslatedL10n.screenRoomlistAssistantInviteSubtitle)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.homeScreen.roomName(room.name))
    }

    private var startButton: some View {
        Button(UntranslatedL10n.screenRoomlistAssistantInviteStart) {
            context.send(viewAction: .acceptInvite(roomIdentifier: room.id))
        }
        .buttonStyle(.compound(.primary, size: .small))
        .fixedSize()
        .accessibilityLabel(UntranslatedL10n.a11yAssistantInviteStart)
        .accessibilityHint(UntranslatedL10n.a11yAssistantInviteStartHint)
    }

    /// A soft accent tint, lighter in light mode, where the subtitle's secondary text needs 4.5:1 on it.
    private var tintOpacity: Double {
        colorScheme == .dark ? 0.14 : 0.06
    }
    
    /// The assistant's own picture, its Peek without one: the person's own assistant, so never hidden as a stranger's.
    private var avatar: RoomAvatar {
        guard let inviter = room.inviter else { return room.avatar }
        return .heroes([.init(userID: inviter.id, displayName: inviter.displayName, avatarURL: inviter.avatarURL)])
    }
}

// MARK: - Previews

struct HomeScreenAssistantInviteCell_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        VStack(spacing: 0) {
            HomeScreenAssistantInviteCell(room: .assistantInvite, context: HomeScreenInviteCell_Previews.makeViewModel().context)
            HomeScreenRoomCell(room: .init(summary: .mock(id: "!ava", name: "Ava Thompson")),
                               isSelected: false,
                               mediaProvider: MediaProviderMock(.init())) { _ in }
        }
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Pinned on top")
    }
}

extension HomeScreenRoom {
    /// The person's own assistant asking for its chat, as Chats shows it.
    static var assistantInvite: HomeScreenRoom {
        let inviter = RoomMemberProxyMock()
        inviter.displayName = AgentProfileMock.assistant.displayName
        inviter.userID = AgentProfileMock.assistant.matrixUserID

        let summary = RoomSummary(room: RoomSDKMock(),
                                  id: "!assistant-dm:spiral.md",
                                  joinRequestType: .invite(inviter: inviter),
                                  isJoined: false,
                                  name: AgentProfileMock.assistant.displayName,
                                  isDirect: true,
                                  isSpace: false,
                                  avatarURL: nil,
                                  heroes: [.init(userID: AgentProfileMock.assistant.matrixUserID)],
                                  activeMembersCount: 1,
                                  lastMessage: nil,
                                  lastMessageDate: nil,
                                  lastMessageState: nil,
                                  unreadMessagesCount: 0,
                                  unreadMentionsCount: 0,
                                  unreadNotificationsCount: 0,
                                  notificationMode: nil,
                                  canonicalAlias: nil,
                                  alternativeAliases: [],
                                  hasOngoingCall: false,
                                  activeCallIntent: nil,
                                  isMarkedUnread: false,
                                  isFavourite: false,
                                  isTombstoned: false)

        var room = HomeScreenRoom(summary: summary)
        room.assistantInvite = .own
        return room
    }
}
