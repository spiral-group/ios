//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftUI

struct RoomHeaderView: View {
    @Environment(\.isChatBackgroundDrawn) private var isChatBackgroundDrawn // AGENT-PLATFORM (Brief 0083, question 359)
    
    struct DMRecipientDetails {
        var statusEmoji: Character?
        var verification: UserIdentityVerificationState?
        // AGENT-PLATFORM (Brief 0072, ADR-0083): the other person's presence,
        // nil when unknown or not a DM. Draws the dot and the subtitle.
        var presence: UserPresence?
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): who's typing, which takes the status line's place.
    struct Typing: Equatable {
        var members: [String] = []
        var isDM = false
        
        /// What the status line says, nil when nobody is typing.
        var text: String? {
            line.map { $0.names + $0.ending }
        }
        
        /// The names truncate and the ending doesn't, so a long name still reads as someone typing.
        fileprivate var line: (names: String, ending: String)? {
            switch members.count {
            case 0:
                nil
            case 1 where isDM:
                ("", UntranslatedL10n.screenRoomTypingDmIos)
            case 1:
                (members[0], L10n.screenRoomTypingNotificationSingularIos)
            case 2:
                (L10n.screenRoomTypingTwoMembers(members[0], members[1]), L10n.screenRoomTypingNotificationPluralIos)
            default:
                (L10n.tr("Localizable", "screen_room_typing_many_members_first_component_ios", members[0], members[1])
                    + L10n.commonManyMembers(members.count - 2),
                    L10n.screenRoomTypingNotificationPluralIos)
            }
        }
        
        /// The narrowest the header may be, at rest too, so that a short room name leaves the line room and the capsule
        /// doesn't change width when somebody starts typing.
        fileprivate var narrowestLine: String {
            Self(members: ["Alexander"], isDM: isDM).text ?? ""
        }
    }
    
    let roomName: String
    var roomSubtitle: String?
    let roomAvatar: RoomAvatar
    var dmRecipientDetails = DMRecipientDetails()
    var roomHistorySharingState: RoomHistorySharingState?
    var typing: Typing? // AGENT-PLATFORM (Brief 0083, question 359): nil where a screen shows no typing.
    // AGENT-PLATFORM (Brief 0083, decision 344): the room screen's header, a capsule with the avatar inside. It's centred
    // on iOS 26+, between the back and call buttons. The screens not yet reworked keep the leading header.
    var isCapsule = false
    
    let mediaProvider: MediaProviderProtocol?
    
    let action: () -> Void
    
    var body: some View {
        if isCapsule {
            capsule // AGENT-PLATFORM (Brief 0083, decision 344)
        } else if #available(iOS 26.0, *) {
            // On iOS 26+ we use the toolbarRole(.editor) to leading align.
            content
                // Not using a Button here so that we get our custom padding around the avatar. This also
                // helps fix a bug where the top pixel was being clipped during the push/pop animation as
                // the Button styling results in a view that is slightly taller than a bar item should be.
                .padding(6)
                .padding(.trailing, 6)
                .glassEffect(.regular.interactive())
                .roomHeaderAction(action)
        } else {
            // On iOS 18 and lower, the editor role causes an animation glitch with the back button whenever
            // you push a screen whilst the large title is visible on the room screen.
            content
                // So take up as much space as possible, with a leading alignment for use in the default principal toolbar position
                .frame(idealWidth: .greatestFiniteMagnitude, maxWidth: .infinity, alignment: .leading)
                .roomHeaderAction(action)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): on iOS 26+ a glass capsule; before iOS 26 the standard bar's title.
    @ViewBuilder
    private var capsule: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(.vertical, 6)
                .padding(.leading, 6)
                .padding(.trailing, 16)
                .glassEffect(.regular.interactive())
                .roomHeaderAction(action)
        } else {
            content
                .roomHeaderAction(action)
        }
    }
    
    private var content: some View {
        HStack(spacing: 8) {
            avatarImage
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 0) {
                roomDetails
                statusLine // AGENT-PLATFORM (Brief 0083)
                widthFloor
            }
            // AGENT-PLATFORM (Brief 0083, question 359): an overlay, so what's typed gets the header's width and adds none.
            .overlay(alignment: .bottomLeading) { typingLine }
            .animation(.elementDefault.disabledDuringTests(), value: typingText)
        }
    }
    
    private var typingText: String? {
        typing?.text
    }
    
    /// The subtitle keeps its place under the typing line, and a header with no subtitle makes one.
    private var statusLine: some View {
        ZStack(alignment: .leading) {
            if typingText != nil {
                subtitleText(" ")
                    .hidden()
            }
            
            subtitle
                .opacity(typingText == nil ? 1 : 0)
                .accessibilityHidden(typingText != nil)
        }
    }
    
    @ViewBuilder
    private var widthFloor: some View {
        if let typing {
            subtitleText(typing.narrowestLine)
                .hidden()
                .frame(height: 0)
        }
    }
    
    @ViewBuilder
    private var typingLine: some View {
        if let line = typing?.line {
            HStack(spacing: 0) {
                if !line.names.isEmpty {
                    subtitleText(line.names)
                }
                subtitleText(line.ending)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        }
    }
    
    @ViewBuilder
    private var subtitle: some View {
        if let roomSubtitle {
            subtitleText(roomSubtitle)
        } else if let presence = dmRecipientDetails.presence {
            // AGENT-PLATFORM (Brief 0072, ADR-0083): «online» / «last
            // seen 5 minutes ago» — the minutes move without a new answer.
            SwiftUI.TimelineView(.everyMinute) { context in
                if let status = presence.statusText(now: context.date) {
                    subtitleText(status)
                }
            }
        }
    }
    
    private var roomDetails: some View {
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(roomName)
                    .lineLimit(1)
                    .font(.compound.bodyMDSemibold) // AGENT-PLATFORM (Brief 0083)
                    .foregroundStyle(.compound.textPrimary)
                    .accessibilityIdentifier(A11yIdentifiers.roomScreen.name)
                    // AGENT-PLATFORM (Brief 0083, decision 357; question 389): an agent, in words, badge or Peek.
                    .accessibilityValue(roomAvatar.heroUserID.map(SpiralAppPostSession.isAgent) ?? false
                        ? UntranslatedL10n.screenNativeCallAgentCenterForeignDetailTitle : "")
                
                if let statusEmoji = dmRecipientDetails.statusEmoji {
                    Text(String(statusEmoji))
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textPrimary)
                }
            }
            if let verificationState = dmRecipientDetails.verification {
                VerificationBadge(verificationState: verificationState, size: .xSmall, relativeTo: .compound.bodyMDSemibold)
            }
            
            if let historySharingIcon {
                CompoundIcon(historySharingIcon, size: .xSmall, relativeTo: .compound.bodyMDSemibold)
                    .foregroundStyle(.compound.iconInfoPrimary)
            }
        }
    }
    
    private var avatarImage: some View {
        RoomAvatarImage(avatar: roomAvatar,
                        avatarSize: .room(on: .timeline),
                        mediaProvider: mediaProvider)
            // AGENT-PLATFORM (Brief 0072, ADR-0083)
            // AGENT-PLATFORM (Brief 0083, decision 344): no dot in the capsule, where the status says it in words.
            // AGENT-PLATFORM (Brief 0083, decision 357): an agent's badge stays there.
            .avatarBadges(userID: roomAvatar.heroUserID,
                          avatarURL: roomAvatar.url,
                          isOnline: !isCapsule && dmRecipientDetails.presence?.isOnline ?? false,
                          avatarSize: Avatars.Size.room(on: .timeline).value)
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.avatar)
    }
    
    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .font(.compound.bodyXS)
            .foregroundStyle(subtitleColor)
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): the glass takes the blue of the picture, where grey reads 2.6:1 in dark.
    private var subtitleColor: Color {
        Compound.supportsGlass && isChatBackgroundDrawn ? .compound.textPrimary : .compound.textSecondary
    }
    
    private var historySharingIcon: KeyPath<CompoundIcons, Image>? {
        switch roomHistorySharingState {
        case .none, .hidden: nil
        case .shared: isCapsule ? nil : \.history // AGENT-PLATFORM (Brief 0083, decision 344): Security says it
        case .worldReadable: \.userProfileSolid
        }
    }
}

extension RoomHeaderView {
    static var toolbarRole: ToolbarRole {
        if #available(iOS 26.0, *) {
            .editor
        } else {
            .automatic
        }
    }
}

private extension View {
    func roomHeaderAction(_ action: @escaping () -> Void) -> some View {
        // Using a button stops it from getting truncated in the navigation bar
        contentShape(.rect)
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

struct RoomHeaderView_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083): Spiral's gates
    static var previews: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                makeHeader(avatarURL: nil)
                makeHeader(avatarURL: .mockMXCAvatar)
                
                makeHeader(avatarURL: .mockMXCAvatar, historySharingState: .shared)
                makeHeader(avatarURL: .mockMXCAvatar, historySharingState: .worldReadable)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                makeHeader(avatarURL: .mockMXCUserAvatar, verificationState: .verified)
                makeHeader(avatarURL: .mockMXCUserAvatar, verificationState: .verificationViolation)
                
                makeHeader(avatarURL: .mockMXCUserAvatar,
                           userStatus: .mockHoliday,
                           verificationState: .notVerified)
                makeHeader(avatarURL: .mockMXCUserAvatar,
                           userStatus: .mockCall,
                           verificationState: .verificationViolation)
                makeHeader(avatarURL: .mockMXCUserAvatar,
                           roomSubtitle: "Subtitle",
                           userStatus: .mockFocussing,
                           verificationState: .verified)
                
                makeHeader(avatarURL: .mockMXCUserAvatar,
                           roomSubtitle: "Subtitle",
                           verificationState: .verified)
                
                makeHeader(avatarURL: .mockMXCUserAvatar,
                           userStatus: .mockHoliday,
                           verificationState: .verified,
                           historySharingState: .shared)
                makeHeader(avatarURL: .mockMXCUserAvatar,
                           verificationState: .verificationViolation,
                           historySharingState: .worldReadable)
            }
        }
        .previewLayout(.sizeThatFits)
        
        // AGENT-PLATFORM (Brief 0072, ADR-0083, ADR-0084): online, last seen
        // exactly, last seen coarsely, and a room subtitle winning over
        // presence. Only texts that do not depend on the clock the snapshot
        // runs at.
        VStack(alignment: .leading, spacing: 16) {
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       verificationState: .verified,
                       presence: .init(userID: "@u:x", state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: .now))
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       userStatus: .mockHoliday,
                       verificationState: .verified,
                       presence: .init(userID: "@u:x", state: .unavailable, lastActiveAgo: 10, currentlyActive: false, receivedAt: .now))
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       verificationState: .verified,
                       presence: .init(userID: "@u:x", state: .offline, lastActiveAgo: nil, currentlyActive: false,
                                       lastSeenBucket: .withinWeek, receivedAt: .now))
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       roomSubtitle: "Thread in Some Room",
                       verificationState: .verified,
                       presence: .init(userID: "@u:x", state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: .now))
        }
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Presence")
        
        // AGENT-PLATFORM (Brief 0083, decision 344): the room screen's capsule.
        VStack(spacing: 16) {
            makeHeader(avatarURL: .mockMXCAvatar, historySharingState: .shared, isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, historySharingState: .worldReadable, isCapsule: true)
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       verificationState: .verified,
                       presence: .init(userID: "@u:x", state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: .now),
                       isCapsule: true)
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Capsule")
        
        // AGENT-PLATFORM (Brief 0083, question 357): an agent has no «last seen»: paused for its owner, otherwise nothing.
        VStack(spacing: 16) {
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       presence: .init(userID: "@assistant-u:x", state: .offline, lastActiveAgo: 780, currentlyActive: false,
                                       receivedAt: .now, isAgentPaused: true),
                       isCapsule: true)
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       presence: .init(userID: "@assistant-u:x", state: .offline, lastActiveAgo: 780, currentlyActive: false, receivedAt: .now),
                       isCapsule: true)
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Agent")
        
        // AGENT-PLATFORM (Brief 0083, question 359): in place of the status, or of a thread's room name, at the same width.
        VStack(spacing: 16) {
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       verificationState: .verified,
                       presence: .init(userID: "@u:x", state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: .now),
                       typing: .init(members: ["Some User Name"], isDM: true),
                       isCapsule: true)
            makeHeader(avatarURL: .mockMXCUserAvatar,
                       verificationState: .verified,
                       presence: .init(userID: "@assistant-u:x", state: .offline, lastActiveAgo: 780, currentlyActive: false, receivedAt: .now),
                       typing: .init(members: ["Some User Name"], isDM: true),
                       isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, typing: .init(members: []), isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, typing: .init(members: ["Alice"]), isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, roomName: "Lunch", typing: .init(members: []), isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, roomName: "Lunch", typing: .init(members: ["Alice"]), isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, typing: .init(members: ["Alice", "Bob"]), isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, typing: .init(members: ["Alice", "Bob", "Charlie", "Dan"]), isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, typing: .init(members: ["Alice with her very long display name"]), isCapsule: true)
            makeHeader(avatarURL: .mockMXCAvatar, roomSubtitle: "Some Room", typing: .init(members: ["Alice"]))
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Typing")
    }
    
    @ViewBuilder
    static func makeHeader(avatarURL: URL?,
                           roomName: String? = nil,
                           roomSubtitle: String? = nil,
                           userStatus: UserStatus? = nil,
                           verificationState: UserIdentityVerificationState? = nil,
                           historySharingState: RoomHistorySharingState? = nil,
                           presence: UserPresence? = nil,
                           typing: RoomHeaderView.Typing? = nil,
                           isCapsule: Bool = false) -> some View {
        let roomName = roomName ?? (verificationState == nil ? "Some Room Name" : "Some User Name")
        RoomHeaderView(roomName: roomName,
                       roomSubtitle: roomSubtitle,
                       roomAvatar: .room(id: "1",
                                         name: roomName,
                                         avatarURL: avatarURL),
                       dmRecipientDetails: .init(statusEmoji: userStatus?.displayed?.emoji,
                                                 verification: verificationState,
                                                 presence: presence),
                       roomHistorySharingState: historySharingState,
                       typing: typing,
                       isCapsule: isCapsule,
                       mediaProvider: MediaProviderMock(.init())) { }
    }
}
