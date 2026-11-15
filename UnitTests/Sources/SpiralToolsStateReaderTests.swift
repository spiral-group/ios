//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0044): pins the com.spiral.tools raw-JSON
// contract against backend `reply_dispatch_executor::emit_spiral_tools_state`.

import Foundation
@testable import Spiral
import Testing

struct SpiralToolsStateReaderTests {
    static func event(stateKey: String, by: String, at: Double, tools: String) -> String {
        """
        {"type":"com.spiral.tools","state_key":"\(stateKey)","sender":"\(stateKey)",
         "content":{"version":1,"by":"\(by)","at":\(at),"tools":\(tools)}}
        """
    }

    @Test
    func parsesTranslateToolWithLanguage() {
        let json = Self.event(stateKey: "@assistant-alice:host", by: "@alice:host", at: 1_783_000_000_000,
                              tools: #"[{"tool_id":"t1","tool":"translate","trigger":"on_message","enabled":true,"target_language":"English"}]"#)
        let entry = SpiralToolsStateReader.parse(rawEventJSON: json)
        #expect(entry?.agentMatrixUserID == "@assistant-alice:host")
        #expect(entry?.ownerUserID == "@alice:host")
        #expect(entry?.tools.count == 1)
        #expect(entry?.tools.first?.kind == "translate")
        #expect(entry?.tools.first?.toolID == "t1")
        #expect(entry?.tools.first?.targetLanguage == "English")
    }

    @Test
    func ignoresNonSpiralAndClearedEvents() {
        #expect(SpiralToolsStateReader.parse(rawEventJSON: #"{"type":"m.room.topic","content":{}}"#) == nil)
        // All tools cleared (enabled=false) → no entry.
        let cleared = Self.event(stateKey: "@a:host", by: "@o:host", at: 1,
                                 tools: #"[{"tool":"translate","enabled":false}]"#)
        #expect(SpiralToolsStateReader.parse(rawEventJSON: cleared) == nil)
        // Empty tools → no entry.
        let empty = Self.event(stateKey: "@a:host", by: "@o:host", at: 1, tools: "[]")
        #expect(SpiralToolsStateReader.parse(rawEventJSON: empty) == nil)
    }

    @Test
    func disableClearsAgentFromBanner() {
        // Agent armed a tool, then disabled it — the LATEST (empty)
        // event must win and the agent drop out of the banner. Both
        // events stay in the timeline, so the reader must not skip the
        // empty one (the lingering-tool bug).
        let armed = Self.event(stateKey: "@a-alice:host", by: "@alice:host", at: 1_000,
                               tools: #"[{"tool":"translate","enabled":true,"target_language":"English"}]"#)
        let cleared = Self.event(stateKey: "@a-alice:host", by: "@alice:host", at: 2_000, tools: "[]")
        let bob = Self.event(stateKey: "@a-bob:host", by: "@bob:host", at: 1_500,
                             tools: #"[{"tool":"summarize","enabled":true}]"#)

        // Alice cleared → only Bob remains.
        let entries = SpiralToolsStateReader.aggregate(rawEventJSONs: [armed, bob, cleared])
        #expect(entries.count == 1)
        #expect(entries.first?.agentMatrixUserID == "@a-bob:host")

        // All agents cleared → empty banner.
        let bobCleared = Self.event(stateKey: "@a-bob:host", by: "@bob:host", at: 3_000, tools: "[]")
        #expect(SpiralToolsStateReader.aggregate(rawEventJSONs: [armed, bob, cleared, bobCleared]).isEmpty)
    }

    @Test
    func aggregatesPerAgentLatestWins() {
        // Alice's agent, two events — the newer (English) must win.
        let old = Self.event(stateKey: "@a-alice:host", by: "@alice:host", at: 1_000,
                             tools: #"[{"tool":"translate","enabled":true,"target_language":"French"}]"#)
        let new = Self.event(stateKey: "@a-alice:host", by: "@alice:host", at: 2_000,
                             tools: #"[{"tool":"translate","enabled":true,"target_language":"English"}]"#)
        // Bob's agent, one event.
        let bob = Self.event(stateKey: "@a-bob:host", by: "@bob:host", at: 1_500,
                             tools: #"[{"tool":"summarize","enabled":true}]"#)

        let entries = SpiralToolsStateReader.aggregate(rawEventJSONs: [old, bob, new])
        #expect(entries.count == 2, "two distinct agents")
        // Newest-armed first: Alice (2000) before Bob (1500).
        #expect(entries[0].agentMatrixUserID == "@a-alice:host")
        #expect(entries[0].tools.first?.targetLanguage == "English", "latest event per agent wins")
        #expect(entries[1].agentMatrixUserID == "@a-bob:host")
    }

    private static func member(stateKey: String, membership: String, ts: Double) -> String {
        """
        {"type":"m.room.member","state_key":"\(stateKey)","sender":"\(stateKey)",
         "origin_server_ts":\(ts),"content":{"membership":"\(membership)"}}
        """
    }

    @Test
    func departedMemberIDsTakesLatestMembership() {
        // Bob's agent joined then left → departed. Alice's agent joined → not.
        let events = [
            Self.member(stateKey: "@a-alice:host", membership: "join", ts: 1_000),
            Self.member(stateKey: "@a-bob:host", membership: "join", ts: 1_000),
            Self.member(stateKey: "@a-bob:host", membership: "leave", ts: 2_000)
        ]
        let departed = SpiralToolsStateReader.departedMemberIDs(rawEventJSONs: events)
        #expect(departed == ["@a-bob:host"])

        // Bob's agent rejoins (newer join) → no longer departed.
        let rejoined = events + [Self.member(stateKey: "@a-bob:host", membership: "join", ts: 3_000)]
        #expect(SpiralToolsStateReader.departedMemberIDs(rawEventJSONs: rejoined).isEmpty)

        // Ban counts as departed too.
        let banned = [Self.member(stateKey: "@a-x:host", membership: "ban", ts: 1_000)]
        #expect(SpiralToolsStateReader.departedMemberIDs(rawEventJSONs: banned) == ["@a-x:host"])
    }

    @Test
    func filterDepartedDropsOnlyExplicitlyDepartedAgents() {
        let alice = Self.event(stateKey: "@a-alice:host", by: "@alice:host", at: 1_000,
                               tools: #"[{"tool":"translate","enabled":true,"target_language":"English"}]"#)
        let bob = Self.event(stateKey: "@a-bob:host", by: "@bob:host", at: 1_500,
                             tools: #"[{"tool":"summarize","enabled":true}]"#)
        let entries = SpiralToolsStateReader.aggregate(rawEventJSONs: [alice, bob])
        #expect(entries.count == 2)

        // Bob's agent departed → dropped; Alice (no membership event) stays.
        let live = SpiralToolsStateReader.filterDeparted(entries: entries, departedMemberIDs: ["@a-bob:host"])
        #expect(live.map(\.agentMatrixUserID) == ["@a-alice:host"])

        // Empty departed set → everything passes (Variant 1: never blank a
        // banner just because membership wasn't observed).
        #expect(SpiralToolsStateReader.filterDeparted(entries: entries, departedMemberIDs: []).count == 2)
    }

    // MARK: - Hybrid seed (Brief 0044)

    private static func roomTools(_ agents: [RoomToolAgentEntry]) -> RoomToolsView {
        RoomToolsView(roomID: "!r:host", agents: agents)
    }

    private static func agentEntry(_ mxid: String, owner: String, isMine: Bool,
                                   tools: [RoomToolView]) -> RoomToolAgentEntry {
        RoomToolAgentEntry(agentID: mxid, matrixUserID: mxid, displayName: mxid,
                           ownerUserID: owner, isMine: isMine, tools: tools)
    }

    private static func restTool(_ kind: String, language: String?) -> RoomToolView {
        RoomToolView(toolID: nil, toolKind: kind, triggerKind: "on_message",
                     targetLanguage: language, params: nil, trigger: nil, safeSliceSalt: kind, appliesToViewer: .yes)
    }

    @Test
    func seedEventsCarryTargetLanguageForEveryAgent() {
        // The REST snapshot's public target_language must survive into the
        // seed so the banner shows "Translating to X" for another
        // participant's agent (safe slice), not a bare kind.
        let snapshot = Self.roomTools([
            Self.agentEntry("@a-me:host", owner: "@me:host", isMine: true,
                            tools: [Self.restTool("translate", language: "English")]),
            Self.agentEntry("@a-bob:host", owner: "@bob:host", isMine: false,
                            tools: [Self.restTool("translate", language: "uk")])
        ])
        let seed = SpiralToolsStateReader.seedEvents(fromRoomTools: snapshot, seedTime: Date(timeIntervalSince1970: 5_000))
        #expect(seed.count == 2)
        let bob = seed.first { $0.agentMatrixUserID == "@a-bob:host" }
        #expect(bob?.tools.first?.kind == "translate")
        #expect(bob?.tools.first?.targetLanguage == "uk", "other agent's language survives the seed")
    }

    @Test
    func hybridAggregateSeedCoversOutOfWindowAndTimelineOverrides() {
        // Seed says: alice=translate, bob=summarize. Their arm events are old
        // and NOT in the timeline window (empty rawEventJSONs) — the seed must
        // still surface both.
        let snapshot = Self.roomTools([
            Self.agentEntry("@a-alice:host", owner: "@alice:host", isMine: false,
                            tools: [Self.restTool("translate", language: "English")]),
            Self.agentEntry("@a-bob:host", owner: "@bob:host", isMine: false,
                            tools: [Self.restTool("summarize", language: nil)])
        ])
        let seed = SpiralToolsStateReader.seedEvents(fromRoomTools: snapshot, seedTime: Date())

        // No timeline events in the window → the seed surfaces BOTH agents
        // (their arm events scrolled out).
        let fromSeedOnly = SpiralToolsStateReader.aggregate(rawEventJSONs: [], seed: seed)
        #expect(Set(fromSeedOnly.map(\.agentMatrixUserID)) == ["@a-alice:host", "@a-bob:host"])

        // The timeline is authoritative for any agent it mentions: alice's
        // disable event in the window drops her (masking the stale seed);
        // bob, absent from the timeline, is still covered by the seed.
        let aliceDisabled = Self.event(stateKey: "@a-alice:host", by: "@alice:host", at: 2_000, tools: "[]")
        let merged = SpiralToolsStateReader.aggregate(rawEventJSONs: [aliceDisabled], seed: seed)
        #expect(merged.map(\.agentMatrixUserID) == ["@a-bob:host"], "timeline disable overrides the seed")

        // A timeline arm for bob overrides bob's seed summarize.
        let bobTranslate = Self.event(stateKey: "@a-bob:host", by: "@bob:host", at: 3_000,
                                      tools: #"[{"tool":"translate","enabled":true,"target_language":"French"}]"#)
        let merged2 = SpiralToolsStateReader.aggregate(rawEventJSONs: [bobTranslate], seed: seed)
        let bobEntry = merged2.first { $0.agentMatrixUserID == "@a-bob:host" }
        #expect(bobEntry?.tools.first?.kind == "translate", "timeline event is authoritative over the seed")
        #expect(bobEntry?.tools.first?.targetLanguage == "French")
    }

    // MARK: - AGENT-PLATFORM (Brief 0066 § 5.89): the fallback

    /// What the platform sends when the room refuses the agent's state row.
    static func fallback(sender: String, by: String, at: Double, tools: String) -> String {
        """
        {"type":"com.spiral.tools.changed","sender":"\(sender)",
         "content":{"version":1,"by":"\(by)","at":\(at),"tools":\(tools),"fallback":true}}
        """
    }

    static let owner = "@emm2:spiral.md"
    static let agent = "@assistant-emm2:spiral.md"
    static let czech = #"[{"tool_id":"t1","tool":"translate","trigger":"on_message","enabled":true,"target_language":"cs"}]"#

    @Test
    func readsTheFallbackFromAnAgentOfThisServer() {
        let json = Self.fallback(sender: Self.agent, by: Self.owner, at: 2000, tools: Self.czech)
        let event = SpiralToolsStateReader.parseEvent(rawEventJSON: json, ownUserID: Self.owner)
        #expect(event?.agentMatrixUserID == Self.agent, "the sender is the agent: a fallback has no state_key")
        #expect(event?.ownerUserID == Self.owner)
        #expect(event?.tools.first?.targetLanguage == "cs")
        #expect(SpiralToolsStateReader.parseFallbackEvent(rawEventJSON: json, ownUserID: Self.owner)?.agentMatrixUserID == Self.agent)
    }

    @Test
    func ignoresTheFallbackWithoutOwnUserID() {
        let json = Self.fallback(sender: Self.agent, by: Self.owner, at: 2000, tools: Self.czech)
        #expect(SpiralToolsStateReader.parseEvent(rawEventJSON: json) == nil)
        #expect(SpiralToolsStateReader.aggregate(rawEventJSONs: [json]).isEmpty)
    }

    /// Anyone in the room may send a message of this type; only the agent may
    /// say what it runs.
    @Test
    func ignoresAFallbackFromAPersonOrAnotherServersAgent() {
        for sender in ["@bob:spiral.md", "@assistant-emm2:elsewhere.org"] {
            let json = Self.fallback(sender: sender, by: Self.owner, at: 2000, tools: Self.czech)
            #expect(SpiralToolsStateReader.parseEvent(rawEventJSON: json, ownUserID: Self.owner) == nil, "\(sender)")
        }
    }

    @Test
    func theFallbackRowParserTakesOnlyTheFallback() {
        let state = Self.event(stateKey: Self.agent, by: Self.owner, at: 1000, tools: Self.czech)
        #expect(SpiralToolsStateReader.parseFallbackEvent(rawEventJSON: state, ownUserID: Self.owner) == nil)
    }

    /// A room can hold both: a state row from before a grant was lost, or a
    /// fallback from before one was made. The newest `at` speaks.
    @Test
    func theNewestOfStateRowAndFallbackWins() {
        let armed = Self.event(stateKey: Self.agent, by: Self.owner, at: 1000, tools: Self.czech)
        let cleared = Self.fallback(sender: Self.agent, by: Self.owner, at: 2000, tools: "[]")
        let rearmed = Self.event(stateKey: Self.agent, by: Self.owner, at: 3000, tools: Self.czech)

        #expect(SpiralToolsStateReader.aggregate(rawEventJSONs: [armed, cleared], seed: [], ownUserID: Self.owner).isEmpty,
                "a later fallback clears the state row")
        #expect(SpiralToolsStateReader.aggregate(rawEventJSONs: [cleared, armed, rearmed], seed: [], ownUserID: Self.owner).count == 1,
                "a later state row re-arms over the fallback")
    }

    // MARK: - What an event changed (question 357)

    private static func event(changes: String) -> String {
        """
        {"type":"com.spiral.tools","state_key":"@a:host","sender":"@a:host",
         "content":{"version":1,"by":"@o:host","at":2,"tools":[],"changes":\(changes)}}
        """
    }

    private static func tool(_ kind: String, language: String? = nil, trigger: String = "on_message") -> ToolsBannerEntry.Tool {
        ToolsBannerEntry.Tool(toolID: nil, kind: kind, trigger: trigger, targetLanguage: language)
    }

    private func changes(_ json: String) -> [SpiralToolChange]? {
        SpiralToolsStateReader.parseEvent(rawEventJSON: Self.event(changes: json))?.changes
    }

    @Test
    func readsEachActionInOrder() {
        let json = """
        [{"action":"armed","tool":"call_recording","trigger":"on_voice_call","actor":"owner"},
         {"action":"disabled","tool":"translate","trigger":"on_message","target_language":"uk","actor":"system"}]
        """
        #expect(changes(json) == [SpiralToolChange(action: .turnedOn, tool: Self.tool("call_recording", trigger: "on_voice_call"), actor: .owner),
                                  SpiralToolChange(action: .turnedOff, tool: Self.tool("translate", language: "uk"), actor: .system)])
    }

    @Test
    func anEditCarriesWhatTheToolWas() {
        let json = """
        [{"action":"edited","tool":"translate","trigger":"on_message","target_language":"en","actor":"owner",
          "previous":{"tool":"translate","trigger":"on_message","target_language":"uk"}}]
        """
        #expect(changes(json) == [SpiralToolChange(action: .changed(from: Self.tool("translate", language: "uk")),
                                                   tool: Self.tool("translate", language: "en"),
                                                   actor: .owner)])
    }

    @Test
    func anEmptyListIsNotAMissingOne() {
        #expect(changes("[]") == [])
        let withoutList = SpiralToolsStateReader.parseEvent(rawEventJSON: Self.event(stateKey: "@a:host", by: "@o:host", at: 1, tools: "[]"))
        #expect(withoutList != nil)
        #expect(withoutList?.changes == nil)
    }

    /// One entry this build can't read leaves the whole list unread, never a part of it, and never an empty list.
    @Test
    func aListThisBuildCantReadIsNoList() {
        let armed = #"{"action":"armed","tool":"summarize","actor":"owner"}"#
        let unreadable = ["[\(armed),{\"action\":\"paused\",\"tool\":\"summarize\",\"actor\":\"owner\"}]",
                          "[\(armed),{\"action\":\"armed\",\"tool\":\"summarize\",\"actor\":\"schedule\"}]",
                          #"[{"action":"armed","tool":"summarize"}]"#,
                          #"[{"action":"armed","actor":"owner"}]"#,
                          #"[{"action":"edited","tool":"summarize","actor":"owner"}]"#,
                          #""armed""#,
                          "null"]
        for json in unreadable {
            #expect(changes(json) == nil, "\(json)")
        }
    }

    /// The comparison with the previous state is gone: the server's `prev_content` says nothing to the row.
    @Test
    func thePreviousStateIsNotRead() throws {
        let json = """
        {"type":"com.spiral.tools","state_key":"@a:host","sender":"@a:host",
         "content":{"by":"@o:host","at":2,"tools":[]},
         "unsigned":{"replaces_state":"$old",
                     "prev_content":{"by":"@o:host","at":1,"tools":[{"tool_id":"t1","tool":"summarize","enabled":true}]}}}
        """
        let event = try #require(SpiralToolsStateReader.parseEvent(rawEventJSON: json))
        #expect(event.changes == nil)
    }

    @Test
    func theFallbackCarriesTheSameChanges() throws {
        let json = """
        {"type":"com.spiral.tools.changed","sender":"\(Self.agent)",
         "content":{"by":"\(Self.owner)","at":1000,"tools":\(Self.czech),"fallback":true,
                    "changes":[{"action":"armed","tool":"translate","target_language":"cs","actor":"owner"}]}}
        """
        let event = try #require(SpiralToolsStateReader.parseFallbackEvent(rawEventJSON: json, ownUserID: Self.owner))
        #expect(event.changes == [SpiralToolChange(action: .turnedOn, tool: Self.tool("translate", language: "cs"), actor: .owner)])
    }
}
