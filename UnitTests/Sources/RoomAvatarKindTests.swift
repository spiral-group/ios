//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import Testing

/// Decision 357 item 9: people are round, groups a rounded square. The sparkle's rule is in `AgentAvatarTests`.
@MainActor
struct RoomAvatarKindTests {
    private let person = UserProfile(userID: "@erin:example.com")
    private let otherPerson = UserProfile(userID: "@dan:example.com")
    private let agent = UserProfile(userID: "@assistant-alice:example.com")
    
    @Test
    func aDMWithoutARoomAvatarIsItsHeroAndRound() {
        let avatar = make(isDirect: true, heroes: [person])
        
        #expect(avatar == RoomAvatar.heroes([person]))
        #expect(avatar.shape == .circle)
    }
    
    @Test
    func aDMWithARoomAvatarStaysRound() {
        let avatar = make(isDirect: true, avatarURL: .mockMXCAvatar, heroes: [person])
        
        #expect(avatar == RoomAvatar.direct(id: "!room", name: "Room", avatarURL: .mockMXCAvatar))
        #expect(avatar.shape == .circle)
    }
    
    @Test
    func aDMWhoseOtherPersonLeftStaysRound() {
        #expect(make(isDirect: true, heroes: []).shape == .circle)
    }
    
    @Test
    func aDirectRoomWithTwoOtherPeopleIsAGroup() {
        #expect(make(isDirect: true, heroes: [person, otherPerson]).shape == .roundedSquare)
    }
    
    @Test
    func aGroupIsARoundedSquare() {
        #expect(make(heroes: [person]).shape == .roundedSquare)
        #expect(make(avatarURL: .mockMXCAvatar, heroes: [person, otherPerson]).shape == .roundedSquare)
    }
    
    @Test
    func aSpaceKeepsItsShape() {
        #expect(make(isSpace: true, heroes: []).shape == .roundedRect)
    }
    
    @Test
    func removingADMsAvatarKeepsItRound() {
        let avatar = make(isDirect: true, avatarURL: .mockMXCAvatar, heroes: [person]).removingAvatar
        
        #expect(avatar == RoomAvatar.direct(id: "!room", name: "Room", avatarURL: nil))
    }
    
    @Test
    func onlyADMWithOneHeroNamesThePerson() {
        #expect(make(isDirect: true, heroes: [agent]).heroUserID == agent.id)
        #expect(make(isDirect: true, avatarURL: .mockMXCAvatar, heroes: [agent]).heroUserID == nil)
        #expect(make(heroes: [agent]).heroUserID == nil)
    }
    
    private func make(isDirect: Bool = false, isSpace: Bool = false, avatarURL: URL? = nil, heroes: [UserProfile]) -> RoomAvatar {
        .make(id: "!room", name: "Room", avatarURL: avatarURL, isDirect: isDirect, isSpace: isSpace, heroes: heroes)
    }
}
