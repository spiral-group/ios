//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AvatarHeaderView<Footer: View>: View {
    // AGENT-PLATFORM (Brief 0083, decision 344): only a person now; a room's details are `SpiralProfilePage`.
    private let user: UserProfile
    private let title: String
    private let status: UserStatus?
    private let subtitle: String?
    private let isVerified: Bool
    
    private let avatarSize: Avatars.Size
    private let mediaProvider: MediaProviderProtocol?
    private var onAvatarTap: ((URL) -> Void)?
    @ViewBuilder private var footer: () -> Footer
    // AGENT-PLATFORM (Brief 0072, ADR-0083): see `presence(_:)`.
    private var presence: UserPresence?
    
    init(member: RoomMemberDetails,
         isVerified: Bool = false,
         avatarSize: Avatars.Size,
         mediaProvider: MediaProviderProtocol? = nil,
         onAvatarTap: ((URL) -> Void)? = nil,
         @ViewBuilder footer: @escaping () -> Footer) {
        let profile = UserProfile(member: member)
        
        self.init(user: profile,
                  isVerified: isVerified,
                  avatarSize: avatarSize,
                  mediaProvider: mediaProvider,
                  onAvatarTap: onAvatarTap,
                  footer: footer)
    }
    
    init(user: UserProfile,
         isVerified: Bool,
         avatarSize: Avatars.Size,
         mediaProvider: MediaProviderProtocol? = nil,
         onAvatarTap: ((URL) -> Void)? = nil,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.user = user
        title = user.displayName ?? user.id
        status = user.status
        subtitle = user.displayName == nil ? nil : user.id
        
        self.avatarSize = avatarSize
        self.mediaProvider = mediaProvider
        self.onAvatarTap = onAvatarTap
        self.footer = footer
        self.isVerified = isVerified
    }
    
    /// Initialises the view by using the sender,
    /// only to be used when a room member has not been loaded yet.
    init(sender: TimelineItemSender,
         avatarSize: Avatars.Size,
         mediaProvider: MediaProviderProtocol? = nil,
         onAvatarTap: ((URL) -> Void)? = nil,
         @ViewBuilder footer: @escaping () -> Footer) {
        let profile = UserProfile(sender: sender)
        
        self.init(user: profile,
                  isVerified: false,
                  avatarSize: avatarSize,
                  mediaProvider: mediaProvider,
                  onAvatarTap: onAvatarTap,
                  footer: footer)
    }
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083): the person's presence — the dot
    // on the avatar and «online / last seen …» under the name.
    func presence(_ presence: UserPresence?) -> Self {
        var view = self
        view.presence = presence
        return view
    }
    
    var body: some View {
        VStack(spacing: 24) {
            avatar
                // AGENT-PLATFORM (Brief 0072, ADR-0083)
                .presenceBadge(isOnline: presence?.isOnline ?? false, avatarSize: avatarSize.value, announced: false)
            
            VStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.compound.textPrimary)
                    .font(.compound.headingMDBold)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                
                // AGENT-PLATFORM (Brief 0072, ADR-0083): the minutes move
                // without a new answer.
                if let presence {
                    SwiftUI.TimelineView(.everyMinute) { context in
                        if let status = presence.statusText(now: context.date) {
                            Text(status)
                                .foregroundStyle(presence.isOnline ? Color.compound.textActionAccent : Color.compound.textSecondary)
                                .font(.compound.bodyMD)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                
                if let displayedStatus = status?.displayed {
                    HStack(spacing: 6) {
                        Text(String(displayedStatus.emoji))
                            .foregroundStyle(.compound.textPrimary)
                        Text(displayedStatus.text)
                            .foregroundStyle(.compound.textSecondary)
                    }
                    .font(.compound.bodyMDSemibold)
                    .multilineTextAlignment(.center)
                }
                
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.compound.textSecondary)
                        .font(.compound.bodyLG)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                
                if isVerified {
                    BadgeLabel(title: L10n.commonVerified,
                               icon: \.verified,
                               style: .accent)
                }
            }
            
            footer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 11,
                                  leading: 0,
                                  bottom: 11,
                                  trailing: 0))
    }
    
    private var avatar: some View {
        LoadableAvatarImage(url: user.avatarURL,
                            name: user.displayName,
                            contentID: user.id,
                            avatarSize: avatarSize,
                            mediaProvider: mediaProvider,
                            onTap: onAvatarTap)
            .accessibilityLabel(onAvatarTap != nil && user.avatarURL != nil ? L10n.a11yViewAvatar : L10n.a11yAvatar)
    }
}

struct AvatarHeaderView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 16) {
            AvatarHeaderView(member: RoomMemberDetails(withProxy: RoomMemberProxyMock.mockAlice),
                             avatarSize: .room(on: .details),
                             mediaProvider: MediaProviderMock(.init())) { Text("") }
                // AGENT-PLATFORM (Brief 0072, ADR-0083, ADR-0084)
                .presence(.init(userID: "@alice:matrix.org", state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: .now))
            
            AvatarHeaderView(member: RoomMemberDetails(withProxy: RoomMemberProxyMock.mockBob),
                             isVerified: true,
                             avatarSize: .room(on: .details),
                             mediaProvider: MediaProviderMock(.init())) { Text("") }
                .presence(.init(userID: "@bob:matrix.org", state: .offline, lastActiveAgo: nil, currentlyActive: false,
                                lastSeenBucket: .withinMonth, receivedAt: .now))
            
            AvatarHeaderView(member: RoomMemberDetails(withProxy: RoomMemberProxyMock.mockErin),
                             isVerified: false,
                             avatarSize: .room(on: .details),
                             mediaProvider: MediaProviderMock(.init())) { Text("") }
            
            AvatarHeaderView(member: RoomMemberDetails(withProxy: RoomMemberProxyMock.mockFrank),
                             isVerified: false,
                             avatarSize: .room(on: .details),
                             mediaProvider: MediaProviderMock(.init())) { Text("") }
            
            AvatarHeaderView(member: RoomMemberDetails(withProxy: RoomMemberProxyMock.mockBanned[3]),
                             avatarSize: .room(on: .details),
                             mediaProvider: MediaProviderMock(.init())) { Text("") }
        }
        .padding()
        .background(Color.compound.bgSubtleSecondaryLevel0)
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Members")
    }
}
