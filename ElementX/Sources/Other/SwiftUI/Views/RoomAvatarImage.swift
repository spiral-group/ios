//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// Information about a room avatar such as it's URL or the heroes to use as a fallback.
enum RoomAvatar: Equatable {
    /// An avatar generated from a Room's details.
    case room(id: String, name: String?, avatarURL: URL?)
    // AGENT-PLATFORM (Brief 0083, decision 357): a DM that isn't drawn from its hero, such as a bridge's with a room
    // avatar, is still one person, so it stays round.
    /// An avatar generated from a DM's own details.
    case direct(id: String, name: String?, avatarURL: URL?)
    /// An avatar generated from a collection of room heroes.
    case heroes([UserProfile])
    /// An avatar generated from a Space's details.
    case space(id: String, name: String?, avatarURL: URL?)
    /// A static avatar for a tombstoned room.
    case tombstoned
    
    // AGENT-PLATFORM (Brief 0083, decision 357): the one rule for what a room's avatar is. A direct room with two or
    // more heroes has more than one other person in it, so it is a group.
    nonisolated static func make(id: String, name: String?, avatarURL: URL?, isDirect: Bool, isSpace: Bool, heroes: [UserProfile]) -> RoomAvatar {
        if isSpace {
            .space(id: id, name: name, avatarURL: avatarURL)
        } else if isDirect, avatarURL == nil, heroes.count == 1 {
            .heroes(heroes)
        } else if isDirect, heroes.count <= 1 {
            .direct(id: id, name: name, avatarURL: avatarURL)
        } else {
            .room(id: id, name: name, avatarURL: avatarURL)
        }
    }
    
    var removingAvatar: RoomAvatar {
        switch self {
        case let .room(id, name, _):
            .room(id: id, name: name, avatarURL: nil)
        case let .direct(id, name, _):
            .direct(id: id, name: name, avatarURL: nil)
        case let .heroes(users):
            .heroes(users.map { .init(userID: $0.id, displayName: $0.displayName, avatarURL: nil) })
        case .space(let id, let name, _):
            .space(id: id, name: name, avatarURL: nil)
        case .tombstoned:
            .tombstoned
        }
    }
    
    var hasURL: Bool {
        url != nil
    }
    
    // AGENT-PLATFORM (question 389's DEBT): the picture the avatar loads, which decides the agent badge on it.
    var url: URL? {
        switch self {
        case let .room(_, _, url),
             let .direct(_, _, url),
             let .space(_, _, url):
            url
        case let .heroes(heroes):
            heroes.first?.avatarURL
        case .tombstoned:
            nil
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 357): people are round, groups a rounded square, spaces keep theirs.
    var shape: LoadableAvatarImage.Shape {
        switch self {
        case .room, .tombstoned: .roundedSquare
        case .direct, .heroes: .circle
        case .space: .roundedRect
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 357): the person a DM's avatar shows, for the badges on it.
    var heroUserID: String? {
        guard case let .heroes(heroes) = self, heroes.count == 1 else { return nil }
        return heroes[0].id
    }
}

/// A view that shows the avatar for a room, or a cluster of heroes if provided.
///
/// This should be preferred over `LoadableAvatarImage` when displaying a
/// room avatar so that DMs have a consistent appearance throughout the app.
struct RoomAvatarImage: View {
    let avatar: RoomAvatar
    
    let avatarSize: Avatars.Size
    let mediaProvider: MediaProviderProtocol?
    
    private(set) var onAvatarTap: ((URL) -> Void)?
    
    var body: some View {
        switch avatar {
        case .room(let id, let name, let avatarURL),
             .direct(let id, let name, let avatarURL),
             .space(let id, let name, let avatarURL):
            LoadableAvatarImage(url: avatarURL,
                                name: name,
                                contentID: id,
                                shape: avatar.shape,
                                avatarSize: avatarSize,
                                mediaProvider: mediaProvider,
                                onTap: onAvatarTap)
        case .heroes(let users):
            // We will expand upon this with more stack sizes in the future.
            if users.isEmpty {
                let _ = assertionFailure("We should never pass empty heroes here.")
                PlaceholderAvatarImage(name: nil, contentID: "")
            } else if users.count == 2 {
                let clusterSize = avatarSize.value * 1.6
                ZStack {
                    LoadableAvatarImage(url: users[0].avatarURL,
                                        name: users[0].displayName,
                                        contentID: users[0].id,
                                        avatarSize: avatarSize,
                                        mediaProvider: mediaProvider,
                                        onTap: onAvatarTap)
                        .scaledFrame(size: clusterSize, alignment: .topTrailing)
                    
                    LoadableAvatarImage(url: users[1].avatarURL,
                                        name: users[1].displayName,
                                        contentID: users[1].id,
                                        avatarSize: avatarSize,
                                        mediaProvider: mediaProvider,
                                        onTap: onAvatarTap)
                        .inverseMask {
                            Circle()
                                .inset(by: -4)
                                .scaledOffset(x: clusterSize - avatarSize.value,
                                              y: -clusterSize + avatarSize.value)
                        }
                        .scaledFrame(size: clusterSize, alignment: .bottomLeading)
                }
                .scaledFrame(size: clusterSize)
            } else {
                LoadableAvatarImage(url: users[0].avatarURL,
                                    name: users[0].displayName,
                                    contentID: users[0].id,
                                    avatarSize: avatarSize,
                                    mediaProvider: mediaProvider,
                                    onTap: onAvatarTap)
            }
        case .tombstoned:
            TombstonedAvatarImage(avatarSize: avatarSize)
        }
    }
}

struct RoomAvatarImage_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                RoomAvatarImage(avatar: .room(id: "!1:server.com",
                                              name: "Room",
                                              avatarURL: nil),
                                avatarSize: .room(on: .chats),
                                mediaProvider: MediaProviderMock(.init()))
                
                RoomAvatarImage(avatar: .room(id: "!2:server.com",
                                              name: "Room",
                                              avatarURL: .mockMXCAvatar),
                                avatarSize: .room(on: .chats),
                                mediaProvider: MediaProviderMock(.init()))
                
                RoomAvatarImage(avatar: .space(id: "!space:server.com",
                                               name: "Room",
                                               avatarURL: nil),
                                avatarSize: .room(on: .chats),
                                mediaProvider: MediaProviderMock(.init()))
                
                RoomAvatarImage(avatar: .space(id: "!otherspace:server.com",
                                               name: "Room",
                                               avatarURL: .mockMXCAvatar),
                                avatarSize: .room(on: .chats),
                                mediaProvider: MediaProviderMock(.init()))
                
                RoomAvatarImage(avatar: .tombstoned, avatarSize: .room(on: .chats), mediaProvider: MediaProviderMock(.init()))
            }
            
            HStack(spacing: 12) {
                RoomAvatarImage(avatar: .heroes([.init(userID: "@user:server.com",
                                                       displayName: "User",
                                                       avatarURL: nil)]),
                avatarSize: .room(on: .chats),
                mediaProvider: MediaProviderMock(.init()))
                
                RoomAvatarImage(avatar: .heroes([.init(userID: "@user:server.com",
                                                       displayName: "User",
                                                       avatarURL: .mockMXCAvatar)]),
                avatarSize: .room(on: .chats),
                mediaProvider: MediaProviderMock(.init()))
                
                RoomAvatarImage(avatar: .heroes([.init(userID: "@alice:server.com", displayName: "Alice", avatarURL: nil),
                                                 .init(userID: "@bob:server.net", displayName: "Bob", avatarURL: nil)]),
                                avatarSize: .room(on: .chats),
                                mediaProvider: MediaProviderMock(.init()))
            }
        }
    }
}
