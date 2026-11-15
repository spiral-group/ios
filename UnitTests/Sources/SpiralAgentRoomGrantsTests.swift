//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066 § 5.88).
//

@testable import Spiral
import Testing

struct SpiralAgentRoomGrantsTests {
    private let me = "@emm2:spiral.md"

    @Test
    func thisServersAgentsAreGranted() {
        #expect(SpiralAgentRoomGrants.isLocalAgent("@assistant-emm2:spiral.md", ownUserID: me))
        #expect(SpiralAgentRoomGrants.isLocalAgent("@agent-legal-0a1b2c3d:spiral.md", ownUserID: me))
    }

    /// A person, another server's «agent», or something that is not an MXID
    /// gets no grant — inviting them changes nothing in the room's levels.
    @Test
    func nobodyElseIsGranted() {
        #expect(!SpiralAgentRoomGrants.isLocalAgent("@emmm:spiral.md", ownUserID: me))
        #expect(!SpiralAgentRoomGrants.isLocalAgent("@assistant-emm2:elsewhere.org", ownUserID: me))
        #expect(!SpiralAgentRoomGrants.isLocalAgent("assistant-emm2", ownUserID: me))
        #expect(!SpiralAgentRoomGrants.isLocalAgent("@assistant-emm2:", ownUserID: me))
    }

    /// The two types the backend writes as the agent — renaming either on
    /// one side only would silently undo the grant.
    @Test
    func theGrantedTypesAreTheOnesTheAgentWrites() {
        #expect(SpiralAgentRoomGrants.stateTypes == ["com.spiral.tools", "io.element.functional_members"])
    }
}
