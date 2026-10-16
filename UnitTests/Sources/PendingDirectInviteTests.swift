//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import ElementX
import Testing

// AGENT-PLATFORM (Brief 0073): both people tapped «Message» within a minute
// and got two DMs — the pending invite from the other one must count.
struct PendingDirectInviteTests {
    private func inviter(_ userID: String) -> RoomMemberProxyMock {
        RoomMemberProxyMock(with: .init(userID: userID, membership: .join))
    }
    
    @Test
    func aPendingDirectInviteFromThatPersonIsTheDM() {
        let rooms: [RoomSummary] = [
            .mock(id: "!group", name: "Group", joinRequestType: .invite(inviter: inviter("@olena:spiral.md")), isDirect: false),
            .mock(id: "!other", name: "Bob", joinRequestType: .invite(inviter: inviter("@bob:spiral.md")), isDirect: true),
            .mock(id: "!dm", name: "Olena", joinRequestType: .invite(inviter: inviter("@olena:spiral.md")), isDirect: true)
        ]
        #expect(ClientProxy.pendingDirectInvite(from: "@olena:spiral.md", in: rooms) == "!dm")
    }
    
    @Test
    func noInviteNoRoom() {
        let rooms: [RoomSummary] = [
            .mock(id: "!joined", name: "Olena", isDirect: true),
            .mock(id: "!knock", name: "Olena", joinRequestType: .knock, isDirect: true)
        ]
        #expect(ClientProxy.pendingDirectInvite(from: "@olena:spiral.md", in: rooms) == nil)
    }
}
