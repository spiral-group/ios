//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

enum Avatars {
    enum Size {
        case user(on: UserAvatarSizeOnScreen)
        case room(on: RoomAvatarSizeOnScreen)
        // AGENT-PLATFORM (Brief 0083, decision 300b): custom sizes are on the scale too.
        /// A step of `SpiralAvatarSize`, for a place without a case of its own.
        case custom(CGFloat)
        
        /// Value in UIKit points
        var value: CGFloat {
            switch self {
            case .user(let screen):
                return screen.value
            case .room(let screen):
                return screen.value
            case .custom(let val):
                return val
            }
        }
        
        /// Value in pixels by using the scale of the main screen
        @MainActor var scaledValue: CGFloat {
            value * UIScreen.main.scale
        }
        
        @MainActor var scaledSize: CGSize {
            CGSize(width: scaledValue, height: scaledValue)
        }
    }
    
    @MainActor
    static func generatePlaceholderAvatarImageData(name: String, id: String, size: CGSize) -> Data? {
        let image = PlaceholderAvatarImage(name: name, contentID: id)
            .clipShape(Circle())
            .frame(width: size.width, height: size.height)
        
        let renderer = ImageRenderer(content: image)
        
        // Specify the scale so the image is rendered correctly. We don't have access to the screen
        // here so a hardcoded 3.0 will have to do
        renderer.scale = 3.0
        
        guard let image = renderer.uiImage else {
            MXLog.info("Generating notification icon placeholder failed")
            return nil
        }
        
        return image.pngData()
    }
}

enum UserAvatarSizeOnScreen {
    case chats
    case chatsCompact
    case spaces
    case spacesCompact
    case timeline
    case settings
    case roomDetails
    case roomMembersList
    case roomChangeRoles
    case startChat
    case memberDetails
    case inviteUsers
    case readReceipt
    case readReceiptSheet
    case editUserDetails
    case spaceHeader
    case completionSuggestions
    case blockedUsers
    case knockingUsersBannerStack
    case knockingUserBanner
    case knockingUserList
    case mediaPreviewDetails
    case sendInviteConfirmation
    case sessionVerification
    case threadList
    case threadSummary
    case map
    // AGENT-PLATFORM (Brief 0083 L1b): no classicAppAccount size.
    case search
    /// The native call's large avatar: a one-to-one call, the spotlight and the ringing screen.
    case call
    
    // AGENT-PLATFORM (Brief 0083, decision 300b): every place takes the step of Spiral's avatar scale nearest
    // to Element's size for it, a tie rounding up; Element's size is noted where it differs.
    var value: CGFloat {
        switch self {
        case .readReceipt:
            SpiralAvatarSize.xxSmall
        case .spaceHeader:
            SpiralAvatarSize.xSmall // 20
        case .threadSummary:
            SpiralAvatarSize.xSmall
        case .knockingUsersBannerStack:
            SpiralAvatarSize.small // 28
        case .chatsCompact, .spacesCompact, .map,
             .timeline, .readReceiptSheet, .completionSuggestions,
             .blockedUsers, .roomMembersList, .knockingUserBanner:
            SpiralAvatarSize.small
        case .startChat:
            SpiralAvatarSize.small // 36
        case .chats, .spaces:
            SpiralAvatarSize.small // 40
        case .roomDetails:
            SpiralAvatarSize.medium // 44
        case .inviteUsers, .knockingUserList, .sessionVerification,
             .threadList, .mediaPreviewDetails, .search:
            SpiralAvatarSize.medium
        case .roomChangeRoles:
            SpiralAvatarSize.medium // 56
        case .sendInviteConfirmation:
            SpiralAvatarSize.medium // 64
        case .memberDetails, .editUserDetails: // AGENT-PLATFORM (Brief 0083 L1b): no .classicAppAccount
            SpiralAvatarSize.large
        case .settings: // AGENT-PLATFORM (Brief 0083, lane settings): the root's profile card; was medium (52).
            SpiralAvatarSize.large
        case .call:
            SpiralAvatarSize.xLarge // 140
        }
    }
}

enum RoomAvatarSizeOnScreen {
    case chats
    case spaces
    case spaceSettings
    case spaceFilters
    case authorizedSpaces
    case timeline
    case leaveSpace
    case messageForwarding
    case search
    case searchHistory
    case roomSelection
    case details
    case editRoomDetails
    case notificationSettings
    case roomDirectorySearch
    case joinRoom
    case spaceHeader
    case editSpaceDetails
    case spaceAddRooms
    case spaceAddRoomsSelected
    case completionSuggestions
    case createRoomSelectSpace
    
    // AGENT-PLATFORM (Brief 0083, decision 300b): as `UserAvatarSizeOnScreen.value`, the nearest step of the scale.
    var value: CGFloat {
        switch self {
        case .timeline, .leaveSpace, .notificationSettings, .roomDirectorySearch,
             .completionSuggestions, .authorizedSpaces, .createRoomSelectSpace,
             .spaceFilters, .searchHistory:
            SpiralAvatarSize.small
        case .messageForwarding, .roomSelection,
             .spaceAddRooms:
            SpiralAvatarSize.small // 36
        case .chats, .spaces, .spaceSettings,
             .spaceAddRoomsSelected, .search:
            SpiralAvatarSize.medium
        case .joinRoom, .spaceHeader, .editSpaceDetails:
            SpiralAvatarSize.medium // 64
        case .details, .editRoomDetails:
            SpiralAvatarSize.large
        }
    }
}
