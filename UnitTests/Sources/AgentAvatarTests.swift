//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import SwiftUI
import Testing

/// Question 389: an agent without a picture shows the Peek and no badge, an agent's own picture keeps the badge, and
/// a person keeps their letter. The badge comes from the picture's URL, not from its load (389's DEBT).
struct AgentAvatarTests {
    private let assistant = "@assistant-alex:example.com"
    private let companyAgent = "@agent-support-2:example.com"
    private let person = "@mira:example.com"
    private let picture = URL(string: "mxc://example.com/picture")
    
    @Test
    func anAgentWithoutAPictureShowsThePeekWithNoBadge() {
        #expect(AgentAvatar.fallback(contentID: assistant) == .peek)
        #expect(AgentAvatar.fallback(contentID: companyAgent) == .peek)
        #expect(!AgentAvatar.showsBadge(userID: assistant, avatarURL: nil, avatarSize: 52))
    }
    
    @Test
    func anAgentsOwnPictureKeepsTheBadgeDownTo24Points() {
        #expect(AgentAvatar.showsBadge(userID: assistant, avatarURL: picture, avatarSize: 24))
        #expect(AgentAvatar.showsBadge(userID: companyAgent, avatarURL: picture, avatarSize: 52))
        #expect(!AgentAvatar.showsBadge(userID: assistant, avatarURL: picture, avatarSize: 23))
    }
    
    /// Before the picture loads, and after it fails, the avatar draws the Peek; the badge is already there and stays,
    /// so a cold scroll neither pops it in nor moves the online dot.
    @Test
    func theBadgeIsDecidedByTheURLNotByTheLoad() {
        #expect(AgentAvatar.fallback(contentID: assistant) == .peek)
        #expect(AgentAvatar.showsBadge(userID: assistant, avatarURL: picture, avatarSize: 52))
    }
    
    @Test
    func aPersonKeepsTheLetterAndNoBadge() {
        #expect(AgentAvatar.fallback(contentID: person) == .letter)
        #expect(!AgentAvatar.showsBadge(userID: person, avatarURL: picture, avatarSize: 52))
        #expect(!AgentAvatar.showsBadge(userID: person, avatarURL: nil, avatarSize: 52))
        #expect(!AgentAvatar.showsBadge(userID: nil, avatarURL: picture, avatarSize: 52))
    }
    
    @Test
    func aRoomKeepsTheLetter() {
        #expect(AgentAvatar.fallback(contentID: "!assistant-alex:example.com") == .letter)
        #expect(AgentAvatar.fallback(contentID: "") == .letter)
    }
}

/// Question 391: the chat list carries no badge, even on an agent's own picture; everywhere else keeps it.
struct AgentBadgeContextTests {
    @Test
    func theChatListRulesTheBadgeOut() {
        #expect(!AgentBadge.Context.chatList.allowsBadge)
    }
    
    @Test
    func everywhereElseLeavesItToTheAvatar() {
        #expect(AgentBadge.Context.standard.allowsBadge)
        #expect(EnvironmentValues().agentBadgeContext == .standard)
    }
}

/// Question 400: a profile header's field without a photo follows the avatar in front of it. An agent's is its Peek's
/// colour, washed as a photo is; a person's, a group's and every photo's wash stay as they were.
struct AgentHeaderFieldTests {
    private let assistant = "@assistant-alex:example.com"
    private let otherAssistant = "@assistant-mira:spiral.example"
    private let person = "@mira:example.com"
    private let picture = URL(string: "mxc://example.com/picture")

    @Test
    func anAgentWithoutAPhotoIsWashedInItsOwnColourAsAPhotoIs() {
        let fill = NativeCallBackdrop.Fill(contentID: assistant)
        #expect(fill == .agent(id: assistant))
        #expect(fill.colors == AgentAvatarPalette.gradient(for: assistant).colors)
        #expect(NativeCallBackdrop.Fill(contentID: otherAssistant).colors == AgentAvatarPalette.gradient(for: otherAssistant).colors)
        #expect(scrim(fill: fill, hasPhoto: false, isDark: false) == scrim(fill: .monogram, hasPhoto: true, isDark: false))
        #expect(scrim(fill: fill, hasPhoto: false, isDark: true) == scrim(fill: .monogram, hasPhoto: true, isDark: true))
    }

    /// The colour stays under the photo, so a slow or failed load shows what the Peek shows, at the photo's alpha.
    @Test
    func anAgentWithAPhotoKeepsThePhotosWash() {
        let fill = NativeCallBackdrop.Fill(contentID: assistant)
        #expect(scrim(fill: fill, hasPhoto: true, isDark: false) == 0.72)
        #expect(scrim(fill: fill, hasPhoto: true, isDark: true) == 0.55)
    }

    @Test
    func aPersonAndAGroupAreUnchanged() {
        #expect(NativeCallBackdrop.Fill(contentID: person) == .monogram)
        #expect(NativeCallBackdrop.Fill(contentID: nil) == .monogram)
        #expect(NativeCallBackdrop.Fill(contentID: "!assistant-alex:example.com") == .monogram)
        #expect(scrim(fill: .monogram, hasPhoto: false, isDark: false) == 0.4)
        #expect(scrim(fill: .monogram, hasPhoto: false, isDark: true) == 0.3)
        #expect(scrim(fill: .monogram, hasPhoto: true, isDark: false) == 0.72)
        #expect(scrim(fill: .monogram, hasPhoto: true, isDark: true) == 0.55)
    }

    /// A DM's page washes in its one hero's colour; a group's and a room with its own picture keep the monogram.
    @Test
    func aDMsPageTakesItsAgentsColour() {
        let agentDM = SpiralProfilePicture.room(.heroes([UserProfile(userID: assistant, displayName: "Alex Sample", avatarURL: nil)]))
        let group = SpiralProfilePicture.room(.heroes([UserProfile(userID: assistant), UserProfile(userID: person)]))
        let room = SpiralProfilePicture.room(.room(id: "!room:example.com", name: "Sample room", avatarURL: picture))
        #expect(agentDM.contentID == assistant)
        #expect(group.contentID == nil)
        #expect(room.contentID == nil)
        #expect(SpiralProfilePicture.user(UserProfile(userID: assistant, avatarURL: picture)).contentID == assistant)
    }

    private func scrim(fill: NativeCallBackdrop.Fill, hasPhoto: Bool, isDark: Bool) -> Double {
        NativeCallBackdrop.scrimOpacity(tone: .wash, isDark: isDark, hasPhoto: hasPhoto, fill: fill)
    }
}
