//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0086 — the Clip reads `GET /join/<token>` as the app's InviteLinkResolver does.
//

import Foundation
@testable import SpiralClip
import Testing

struct ClipInviteResolverTests {
    @Test
    func aValidInvitationWithItsInviter() {
        let body = #"{"state":"valid","inviter":{"display_name":"Alice","avatar_url":null,"mxid":"@alice:spiral.md"}}"#
        #expect(ClipInviteResolver.resolution(from: Data(body.utf8)) == .valid(inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md", inviterAvatarURL: nil))
    }

    @Test
    func aCampaignInvitationHasNoInviter() {
        #expect(ClipInviteResolver.resolution(from: Data(#"{"state":"valid"}"#.utf8)) == .valid(inviterDisplayName: nil, inviterUserID: nil, inviterAvatarURL: nil))
        #expect(ClipInviteResolver.resolution(from: Data(#"{"state":"valid","inviter":null}"#.utf8)) == .valid(inviterDisplayName: nil, inviterUserID: nil, inviterAvatarURL: nil))
    }

    @Test
    func theInvitersPublicPictureComesOnlyFromSpiral() throws {
        let body = #"{"state":"valid","inviter":{"display_name":"Alice","avatar_url":"https://spiral.md/og/u/alice","mxid":"@alice:spiral.md"}}"#
        let avatarURL = try #require(URL(string: "https://spiral.md/og/u/alice"))
        #expect(ClipInviteResolver.resolution(from: Data(body.utf8)) == .valid(inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md", inviterAvatarURL: avatarURL))
        #expect(ClipInviteResolver.avatarURL("https://tracker.example/og/u/alice") == nil)
        #expect(ClipInviteResolver.avatarURL("http://spiral.md/og/u/alice") == nil)
        #expect(ClipInviteResolver.avatarURL("mxc://spiral.md/abc") == nil)
    }

    @Test
    func expiredUsedUpAndUnknownInvitationsAreUnavailable() {
        for state in ["expired", "exhausted", "invalid"] {
            #expect(ClipInviteResolver.resolution(from: Data(#"{"state":"\#(state)"}"#.utf8)) == .unavailable, "\(state)")
        }
    }

    @Test
    func anAnswerItCannotReadIsNotADeadInvitation() {
        #expect(ClipInviteResolver.resolution(from: Data(#"{"state":"paused"}"#.utf8)) == .unreadable, "a newer server's state")
        #expect(ClipInviteResolver.resolution(from: Data("<html>502</html>".utf8)) == .unreadable)
        #expect(ClipInviteResolver.resolution(from: Data()) == .unreadable)
    }
}
