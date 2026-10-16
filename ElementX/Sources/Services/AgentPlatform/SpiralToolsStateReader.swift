//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0044, ADR-0058): timeline-native reader for
// `com.spiral.tools` room state events. This is the SINGLE source for
// the all-participant tools banner — no REST. It reads the raw event
// JSON the SDK exposes on each timeline item
// (`EventTimelineItemProxy.debugInfo.originalJSON`), so it works for a
// CUSTOM state type the SDK doesn't model as a typed content case, and
// it carries the full payload (content + state_key) our backend emits.
//
// Privacy (Brief 0044 hybrid): the event carries only what is safe to
// show EVERY participant — tool_id / kind / trigger / enabled /
// target_language. Private free-text params are never on the wire.

import Foundation

/// One agent's active tools in a room, aggregated from its
/// `com.spiral.tools` state event (state_key = agent MXID).
nonisolated struct ToolsBannerEntry: Equatable, Identifiable {
    /// Agent MXID — the state_key of the event. Stable id per agent.
    let agentMatrixUserID: String
    /// Owner MXID that armed the tools (event `by`), for attribution.
    let ownerUserID: String
    /// Wall-clock the event was emitted (event `at`).
    let updatedAt: Date
    /// The agent's active tools (public fields only).
    let tools: [Tool]

    var id: String { agentMatrixUserID }

    /// A human name from the agent MXID localpart, e.g.
    /// `@assistant-bohdan:host` → "Assistant-bohdan". Attribution only;
    /// the banner never needs a fetched profile.
    var agentDisplayName: String {
        let localpart = agentMatrixUserID.hasPrefix("@") ? String(agentMatrixUserID.dropFirst()) : agentMatrixUserID
        let name = localpart.split(separator: ":").first.map(String.init) ?? localpart
        return name.isEmpty ? agentMatrixUserID : name.localizedCapitalized
    }

    struct Tool: Equatable {
        let toolID: String?
        let kind: String
        let trigger: String
        let targetLanguage: String?
    }
}

nonisolated enum SpiralToolsStateReader {
    static let eventType = "com.spiral.tools"
    /// AGENT-PLATFORM (Brief 0066 § 5.89): what the platform sends INSTEAD of
    /// the state row when the room refuses it — no grant from the owner's
    /// client (§ 5.88): an older client, or a room the owner does not
    /// administer. Same content plus `fallback: true`, a message-like event in
    /// the clear; the agent is its `sender`, as there is no `state_key`.
    static let fallbackEventType = "com.spiral.tools.changed"

    /// One parsed `com.spiral.tools` event: which agent (state_key),
    /// when, and its CURRENT tools (possibly empty = all tools cleared).
    struct ParsedEvent {
        let agentMatrixUserID: String
        let ownerUserID: String
        let updatedAt: Date
        let tools: [ToolsBannerEntry.Tool]
    }

    /// Parse a `com.spiral.tools` event. Returns nil ONLY when the JSON
    /// isn't our event type. A valid event with empty/cleared tools
    /// still parses (with `tools == []`) — that is the "agent turned
    /// everything off" signal, and dropping it here is exactly the bug
    /// where a disabled tool lingered in the banner (the timeline keeps
    /// both the old armed event and the new empty one, so the empty one
    /// MUST win by timestamp, not be skipped).
    ///
    /// Given `ownUserID`, the fallback (`fallbackEventType`) parses too —
    /// from an agent of that user's server only: anyone in the room may send
    /// a message of that type, and only the agent may say what it runs.
    /// Without `ownUserID` the fallback is not read.
    static func parseEvent(rawEventJSON json: String, ownUserID: String? = nil) -> ParsedEvent? {
        guard let root = jsonObject(json) else { return nil }
        return parseEvent(root: root, ownUserID: ownUserID)
    }

    /// The fallback alone, for the timeline row that stands in for it.
    static func parseFallbackEvent(rawEventJSON json: String, ownUserID: String) -> ParsedEvent? {
        guard let root = jsonObject(json), (root["type"] as? String) == fallbackEventType else { return nil }
        return parseEvent(root: root, ownUserID: ownUserID)
    }

    private static func jsonObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Which agent an event speaks for: the state row names it in
    /// `state_key`; the fallback has none, so it is the `sender`.
    private static func agentMatrixUserID(of root: [String: Any], ownUserID: String?) -> String? {
        switch root["type"] as? String {
        case eventType:
            guard let stateKey = root["state_key"] as? String, !stateKey.isEmpty else { return nil }
            return stateKey
        case fallbackEventType:
            guard let ownUserID,
                  let sender = root["sender"] as? String,
                  SpiralAgentRoomGrants.isLocalAgent(sender, ownUserID: ownUserID) else {
                return nil
            }
            return sender
        default:
            return nil
        }
    }

    private static func parseEvent(root: [String: Any], ownUserID: String?) -> ParsedEvent? {
        guard let agentMatrixUserID = agentMatrixUserID(of: root, ownUserID: ownUserID),
              let content = root["content"] as? [String: Any] else {
            return nil
        }
        let toolsRaw = content["tools"] as? [[String: Any]] ?? []
        let tools: [ToolsBannerEntry.Tool] = toolsRaw.compactMap { entry in
            guard let kind = entry["tool"] as? String else { return nil }
            // `enabled == false` is our per-tool "cleared" marker.
            if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
            return ToolsBannerEntry.Tool(toolID: entry["tool_id"] as? String,
                                         kind: kind,
                                         trigger: (entry["trigger"] as? String) ?? "on_message",
                                         targetLanguage: entry["target_language"] as? String)
        }
        let atMs = (content["at"] as? Double) ?? (content["at"] as? NSNumber)?.doubleValue ?? 0
        return ParsedEvent(agentMatrixUserID: agentMatrixUserID,
                           ownerUserID: (content["by"] as? String) ?? "",
                           updatedAt: Date(timeIntervalSince1970: atMs / 1000),
                           tools: tools)
    }

    /// Convenience: parse into a banner entry, or nil if the event is
    /// not ours OR has no active tools. (Used by the unit tests + the
    /// single-event path.)
    static func parse(rawEventJSON json: String) -> ToolsBannerEntry? {
        guard let event = parseEvent(rawEventJSON: json), !event.tools.isEmpty else {
            return nil
        }
        return ToolsBannerEntry(agentMatrixUserID: event.agentMatrixUserID,
                                ownerUserID: event.ownerUserID,
                                updatedAt: event.updatedAt,
                                tools: event.tools)
    }

    /// Aggregate a room's timeline items into one entry PER AGENT.
    /// State events replace by state_key, so the LATEST event per agent
    /// wins. An agent whose LATEST event has empty tools is dropped
    /// (turned everything off) — fixing the bug where a disabled tool
    /// lingered because the reader skipped the empty event instead of
    /// letting it overwrite the old armed one.
    static func aggregate(rawEventJSONs: [String]) -> [ToolsBannerEntry] {
        aggregate(rawEventJSONs: rawEventJSONs, seed: [])
    }

    /// Hybrid aggregate (Brief 0044): merge a REST SNAPSHOT (`seed`) with
    /// the live timeline events. The live timeline is a sliding window and
    /// can miss an old, unchanged `com.spiral.tools` event in a long chat,
    /// so we seed the banner from the authoritative `GET /rooms/{room}/tools`
    /// snapshot read at room open.
    ///
    /// The timeline is the authority for any agent that HAS an event in the
    /// window — those events are the same source the snapshot was computed
    /// from, and if newer (a live arm/disable), they are strictly fresher.
    /// So the timeline ALWAYS wins per agent; the seed only fills in agents
    /// with NO timeline event in the window (their event scrolled out). An
    /// agent whose latest timeline event cleared all tools is dropped even if
    /// the seed still lists it (a disable delta must not be masked by a
    /// stale snapshot).
    ///
    /// Given `ownUserID`, an agent's fallback events count like its state
    /// rows (`parseEvent(rawEventJSON:ownUserID:)`), and the newest `at`
    /// wins between the two.
    static func aggregate(rawEventJSONs: [String], seed: [ParsedEvent], ownUserID: String? = nil) -> [ToolsBannerEntry] {
        // Resolve the latest timeline event per agent (including empties, so a
        // disable wins). These agents are fully determined by the timeline.
        var timelineLatest: [String: ParsedEvent] = [:]
        for json in rawEventJSONs {
            guard let event = parseEvent(rawEventJSON: json, ownUserID: ownUserID) else { continue }
            if let existing = timelineLatest[event.agentMatrixUserID],
               existing.updatedAt >= event.updatedAt {
                continue
            }
            timelineLatest[event.agentMatrixUserID] = event
        }
        // Start from the timeline, then add seed entries only for agents the
        // timeline said nothing about.
        var latest = timelineLatest
        for event in seed where latest[event.agentMatrixUserID] == nil {
            latest[event.agentMatrixUserID] = event
        }
        // Then keep only agents whose resolved state still has tools.
        return latest.values
            .filter { !$0.tools.isEmpty }
            .map { ToolsBannerEntry(agentMatrixUserID: $0.agentMatrixUserID,
                                    ownerUserID: $0.ownerUserID,
                                    updatedAt: $0.updatedAt,
                                    tools: $0.tools) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Convert a REST `GET /rooms/{room}/tools` snapshot into seed
    /// `ParsedEvent`s for the hybrid aggregate. Each agent's tools become
    /// one seed event stamped `seedTime` (so any later timeline delta wins).
    /// `target_language` is public for every agent (Brief 0044), so a
    /// translate tool renders "Translating to X" even for another
    /// participant's agent. Departed agents aren't in the snapshot at all
    /// (the backend only lists agents currently in the room), so the seed is
    /// self-cleaning.
    static func seedEvents(fromRoomTools roomTools: RoomToolsView, seedTime: Date) -> [ParsedEvent] {
        roomTools.agents.map { agent in
            let tools = agent.tools.map { view in
                ToolsBannerEntry.Tool(toolID: view.toolID,
                                      kind: view.toolKind,
                                      trigger: view.triggerKind,
                                      targetLanguage: view.targetLanguage)
            }
            return ParsedEvent(agentMatrixUserID: agent.matrixUserID,
                               ownerUserID: agent.ownerUserID ?? "",
                               updatedAt: seedTime,
                               tools: tools)
        }
    }

    /// One tool flattened out of its agent entry, ready for the banner:
    /// a stable id (unique even for two same-kind tools on one agent) +
    /// the source entry/tool so the caller can localize a title. The
    /// banner rotates over these — one item per active tool, in agent
    /// order (newest-armed first) with each agent's tools kept together.
    struct FlatTool: Equatable {
        /// `"<agentMXID>#<toolID-or-ordinal>"`.
        let id: String
        let entry: ToolsBannerEntry
        let tool: ToolsBannerEntry.Tool
    }

    /// MXIDs whose LATEST `m.room.member` event in the given raw timeline
    /// JSONs is `leave`/`ban` — i.e. members who have DEPARTED the room.
    ///
    /// We derive membership from the SAME timeline the tools come from
    /// (not `roomProxy.membersPublisher`, which is not reactive to
    /// mid-session membership changes) so a departed agent is spotted the
    /// instant its leave event lands, and — crucially — a rejoining agent
    /// is spotted the instant its join event lands (its state_key drops
    /// out of this set). Latest wins by `origin_server_ts`.
    static func departedMemberIDs(rawEventJSONs: [String]) -> Set<String> {
        // stateKey → (latest membership, its ts)
        var latest: [String: (membership: String, ts: Double)] = [:]
        for json in rawEventJSONs {
            guard let data = json.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (root["type"] as? String) == "m.room.member",
                  let stateKey = root["state_key"] as? String,
                  !stateKey.isEmpty,
                  let content = root["content"] as? [String: Any],
                  let membership = content["membership"] as? String else {
                continue
            }
            let ts = (root["origin_server_ts"] as? Double)
                ?? (root["origin_server_ts"] as? NSNumber)?.doubleValue ?? 0
            if let existing = latest[stateKey], existing.ts >= ts { continue }
            latest[stateKey] = (membership, ts)
        }
        return Set(latest.filter { $0.value.membership == "leave" || $0.value.membership == "ban" }.keys)
    }

    /// Drop entries whose agent has DEPARTED the room (Variant 1): only an
    /// agent whose latest timeline membership is explicitly `leave`/`ban`
    /// is removed. An agent with no membership event in the loaded window
    /// is left alone, so a legitimately-joined agent is never hidden just
    /// because its (old) join event scrolled out of the timeline.
    static func filterDeparted(entries: [ToolsBannerEntry], departedMemberIDs: Set<String>) -> [ToolsBannerEntry] {
        guard !departedMemberIDs.isEmpty else { return entries }
        return entries.filter { !departedMemberIDs.contains($0.agentMatrixUserID) }
    }

    /// Unroll aggregated per-agent entries into a flat, ordered list of
    /// tools. Pure (no L10n / no `ownUserID`) so it is unit-testable; the
    /// display title is applied by the caller.
    static func flatten(entries: [ToolsBannerEntry]) -> [FlatTool] {
        var flat: [FlatTool] = []
        for entry in entries {
            for (ordinal, tool) in entry.tools.enumerated() {
                let toolKey = tool.toolID ?? "\(ordinal)"
                flat.append(FlatTool(id: "\(entry.agentMatrixUserID)#\(toolKey)",
                                     entry: entry,
                                     tool: tool))
            }
        }
        return flat
    }
}
