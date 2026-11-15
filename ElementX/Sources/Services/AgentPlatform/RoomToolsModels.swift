//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: view models + wire bridges for the unified Tool +
// Trigger control API (Brief 0036 / ADR-0048). These are the
// lifecycle-stable mirrors the agent-tools UI consumes, keeping the
// swift-openapi-generator module (`AgentPlatformClient`) out of the
// screens.
//
// Every rule is a Tool (the WHAT — typed `ToolParams`) composed with a
// Trigger (the WHEN — typed `TriggerKind`). Arming / disabling is a
// second transport into the same three-layer gate the LLM-through-chat
// path uses (`tool.arm` / `tool.disable`); the client never writes a
// repository row — it POSTs the typed params + trigger and the backend
// routes them through the gate (ADR-0047 Principle 1). This replaces the
// Brief 0034 `/controls/*` surface (deleted server-side). An edit is one
// arm carrying `replaces_tool_id`: the backend turns the old tool off in
// the same transaction (ADR-0088), so there is no arm-then-disable window.
//

import AgentPlatformClient
import Foundation
import OpenAPIRuntime

// MARK: - Read model (`GET /rooms/{room_id}/tools`)

/// Room-wide read: every agent joined to the room with its active Tools.
/// Own Tools carry full params/trigger/id; other owners' Tools are a
/// safe slice (Brief 0035 visibility model — private details elided).
nonisolated struct RoomToolsView: Equatable {
    // periphery:ignore - documents the schema, parsed but not consumed yet
    let roomID: String
    let agents: [RoomToolAgentEntry]
}

/// One agent joined to the room, with its active Tools. The read lists joined
/// agents only, so the entry keeps no membership.
nonisolated struct RoomToolAgentEntry: Equatable, Identifiable {
    var id: String {
        agentID
    }

    let agentID: String
    let matrixUserID: String
    let displayName: String
    let ownerUserID: String?
    /// True when this agent is owned by the caller (full Tool detail).
    let isMine: Bool
    let tools: [RoomToolView]
}

/// One active Tool as the API surfaces it on read. `id` + `params` +
/// `trigger` are populated only for the caller's own agents (the safe
/// slice returns `nil` for other owners).
nonisolated struct RoomToolView: Equatable, Identifiable {
    /// Tool id — `Some` only for own agents (needed for `DELETE`). A
    /// synthesised UUID for the safe slice so SwiftUI `Identifiable`
    /// still works in a list.
    var id: String {
        toolID ?? "\(toolKind).\(triggerKind).\(safeSliceSalt)"
    }

    /// Tool id for the owner's own tools; `nil` in the safe slice.
    let toolID: String?
    /// Tool kind discriminant (`translate` / `live_translate` / …).
    let toolKind: String
    /// Trigger discriminant (`on_message` / `on_voice_call`).
    let triggerKind: String
    /// Translate/live-translate target language — public for EVERY agent
    /// (Brief 0044), so the banner can render "Translating to X" even for
    /// another participant's agent from the REST snapshot. `nil` for
    /// non-translate tools.
    let targetLanguage: String?
    /// Full typed params — `nil` in the safe slice.
    let params: ToolParams?
    /// Full typed trigger — `nil` in the safe slice.
    let trigger: TriggerKind?
    /// Stable per-row salt so two same-kind safe-slice rows keep distinct ids.
    let safeSliceSalt: String
    /// Whether this Tool touches the reader's own messages, on every Tool, own and others'.
    let appliesToViewer: ToolAppliesToViewer
}

/// `applies_to_viewer`: the server's answer for this reader only. The owner's chosen audience stays private.
nonisolated enum ToolAppliesToViewer: Equatable {
    case yes
    case no
    /// A call tool: it has no sender.
    case notApplicable
    /// A read failed on the server, which is never a `no`.
    case unknown

    /// A value newer than this build says nothing, so it reads as `unknown` (decision 96).
    init(wire: String) {
        switch wire {
        case "yes": self = .yes
        case "no": self = .no
        case "not_applicable": self = .notApplicable
        default: self = .unknown
        }
    }
}

// MARK: - Tool params (the WHAT)

/// The typed tool parameters — one case per backend `ToolKind`. The UI
/// builds these from the catalog form; `wireObject` produces the tagged
/// `{ "kind": …, … }` shape the `tool.arm` capability accepts (mirrors
/// the backend `ToolParams` externally-tagged `oneOf`).
nonisolated enum ToolParams: Equatable {
    case translate(targetLanguage: String)
    case simplify
    case correct
    case rephrase(instruction: String)
    case summarize
    case custom(instruction: String)
    /// The personal per-chat call translation (ADR-0094 D9, A.5): "in calls here I listen in `language`; if nobody
    /// translates, my assistant does". One catalog code.
    case liveTranslate(language: String)
    case callSummary
    case callRecording
    /// Forward-compat: an unknown kind decodes here so a newer backend
    /// kind never crashes the read (it renders as a generic tool).
    case unknown(kind: String)

    /// The backend `kind` discriminant tag.
    var kind: String {
        switch self {
        case .translate: return "translate"
        case .simplify: return "simplify"
        case .correct: return "correct"
        case .rephrase: return "rephrase"
        case .summarize: return "summarize"
        case .custom: return "custom"
        case .liveTranslate: return "live_translate"
        case .callSummary: return "call_summary"
        case .callRecording: return "call_recording"
        case .unknown(let kind): return kind
        }
    }

    /// Produce the tagged wire object the `tool.arm` capability accepts.
    var wireObject: OpenAPIRuntime.OpenAPIObjectContainer {
        var payload: [String: (any Sendable)?] = ["kind": kind]
        switch self {
        case .translate(let lang):
            payload["target_language"] = lang
        case .rephrase(let instruction), .custom(let instruction):
            payload["instruction"] = instruction
        case .liveTranslate(let language):
            payload["language"] = language
        case .simplify, .correct, .summarize, .callSummary, .callRecording, .unknown:
            break
        }
        return (try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: payload))
            ?? OpenAPIRuntime.OpenAPIObjectContainer()
    }

    /// Parse the read-model wire object (own-tools slice) back into the enum.
    init(wire: [String: Any]) {
        let kind = wire["kind"] as? String ?? "unknown"
        switch kind {
        case "translate":
            self = .translate(targetLanguage: wire["target_language"] as? String ?? "")
        case "simplify": self = .simplify
        case "correct": self = .correct
        case "rephrase": self = .rephrase(instruction: wire["instruction"] as? String ?? "")
        case "summarize": self = .summarize
        case "custom": self = .custom(instruction: wire["instruction"] as? String ?? "")
        case "live_translate":
            self = .liveTranslate(language: wire["language"] as? String ?? "")
        case "call_summary": self = .callSummary
        case "call_recording": self = .callRecording
        default:
            self = .unknown(kind: kind)
        }
    }
}

// MARK: - Trigger (the WHEN)

/// The typed trigger — when a Tool fires. `on_message` arms a standing
/// text rule; `on_voice_call` arms the voice interpreter. Every Tool is a
/// standing rule: the one-shot `manual` trigger is gone (ADR-0088) and now
/// decodes as `unknown` like any kind this build does not know.
nonisolated enum TriggerKind: Equatable {
    case onMessage(senderScope: AudienceScope)
    case onVoiceCall(speakerScope: AudienceScope)
    case unknown(kind: String)

    var kind: String {
        switch self {
        case .onMessage: return "on_message"
        case .onVoiceCall: return "on_voice_call"
        case .unknown(let kind): return kind
        }
    }

    /// Produce the tagged wire object.
    var wireObject: OpenAPIRuntime.OpenAPIObjectContainer {
        var payload: [String: (any Sendable)?] = ["kind": kind]
        switch self {
        case .onMessage(let scope):
            payload["sender_scope"] = scope.scopeWireValue
        case .onVoiceCall(let scope):
            payload["speaker_scope"] = scope.scopeWireValue
        case .unknown:
            break
        }
        return (try? OpenAPIRuntime.OpenAPIObjectContainer(unvalidatedValue: payload))
            ?? OpenAPIRuntime.OpenAPIObjectContainer()
    }

    /// Parse the read-model wire object back into the enum.
    init(wire: [String: Any]) {
        let kind = wire["kind"] as? String ?? "unknown"
        switch kind {
        case "on_message":
            self = .onMessage(senderScope: AudienceScope(scopeWire: wire["sender_scope"]))
        case "on_voice_call":
            self = .onVoiceCall(speakerScope: AudienceScope(scopeWire: wire["speaker_scope"]))
        default: self = .unknown(kind: kind)
        }
    }
}

// MARK: - AudienceScope (WHO — sender / speaker selector)

/// The `sender_scope` / `speaker_scope` selector. In the unified model
/// the scope is the SAME shape everywhere (unlike Brief 0034's GET/SET
/// mismatch): member-less scopes are a bare tag string; member-carrying
/// scopes are a single-key object `{ tag: { members: [...] } }`.
nonisolated enum AudienceScope: Equatable {
    /// Everyone in the room.
    case anyone
    /// Only the owner's own messages/speech.
    case ownerOnly
    /// Every remote human except the owner (and never the agent itself).
    case nonSelfNonOwner
    /// Only the listed members.
    case specificSenders(members: [String])
    /// Everyone except the listed members.
    case everyoneExcept(members: [String])
    /// Forward-compat for an unknown tag from a newer backend.
    case unknown(tag: String, members: [String])

    /// The wire tag (matches the backend `AudienceScope` variant names).
    var tag: String {
        switch self {
        case .anyone: return "anyone"
        case .ownerOnly: return "owner_only"
        case .nonSelfNonOwner: return "non_self_non_owner"
        case .specificSenders: return "specific_senders"
        case .everyoneExcept: return "everyone_except"
        case .unknown(let tag, _): return tag
        }
    }

    var members: [String] {
        switch self {
        case .anyone, .ownerOnly, .nonSelfNonOwner: return []
        case .specificSenders(let m), .everyoneExcept(let m), .unknown(_, let m): return m
        }
    }

    /// Whether this scope requires a non-empty member list.
    var requiresMembers: Bool {
        switch self {
        case .specificSenders, .everyoneExcept: return true
        default: return false
        }
    }

    /// The value placed inline under `sender_scope` / `speaker_scope`:
    /// a bare tag string for member-less scopes, or a single-key object
    /// `{ tag: { members: [...] } }` for member-carrying scopes.
    var scopeWireValue: any Sendable {
        if members.isEmpty {
            return tag
        }
        return [tag: ["members": members]]
    }

    /// Parse the scope value from a read-model wire node — either a bare
    /// tag string or a single-key object with `members`.
    init(scopeWire: Any?) {
        if let tag = scopeWire as? String {
            self = AudienceScope(tag: tag, members: [])
        } else if let obj = scopeWire as? [String: Any], let (tag, inner) = obj.first {
            let members = (inner as? [String: Any])?["members"] as? [String] ?? []
            self = AudienceScope(tag: tag, members: members)
        } else {
            self = .anyone
        }
    }

    /// Build from a flat tag + members pair.
    init(tag: String, members: [String]) {
        switch tag {
        case "anyone": self = .anyone
        case "owner_only": self = .ownerOnly
        case "non_self_non_owner": self = .nonSelfNonOwner
        case "specific_senders": self = .specificSenders(members: members)
        case "everyone_except": self = .everyoneExcept(members: members)
        default: self = .unknown(tag: tag, members: members)
        }
    }
}

// MARK: - Catalog (`GET /tools/catalog`)

/// The typed `ToolParams` + `TriggerKind` JSON Schemas the client
/// renders arm forms from (schemars 2020-12, ADR-0039). Kept as raw
/// dictionaries — a schema-driven form renderer walks the `oneOf`.
// swiftformat:disable:next redundantSendable
nonisolated struct ToolsCatalogView: Equatable, Sendable {
    // periphery:ignore - documents the schema, parsed but not consumed yet
    let agentID: String
    // periphery:ignore - documents the schema, parsed but not consumed yet
    let roomID: String
    // periphery:ignore - documents the schema, parsed but not consumed yet
    /// The `ToolParams` `oneOf` schema (tagged by `kind`).
    let paramsSchema: [String: AnyHashableJSON]
    // periphery:ignore - documents the schema, parsed but not consumed yet
    /// The `TriggerKind` `oneOf` schema.
    let triggerSchema: [String: AnyHashableJSON]
    /// Languages the `translate` (text) Tool may target — the backend's
    /// curated text-provider set (Brief 0047 / ADR-0062). The Translate
    /// language picker renders from this, NOT from a device-local ISO list.
    let textTranslationLanguages: [AgentLanguage]
    /// Languages the `live_translate` (voice) Tool may target — the voice
    /// provider's allow-list. Off-list codes crash the runtime session with
    /// `1007 Unsupported language code`, so the LiveTranslate picker MUST
    /// render only from this.
    let voiceTranslationLanguages: [AgentLanguage]
    /// The tool kinds that can fire in this room as the owner sees it, in
    /// catalog order (ADR-0088). A client offers only these: the backend
    /// refuses the rest with `/errors/tool-does-not-fire-here`.
    let availableToolKinds: [String]
}

nonisolated extension AgentLanguage {
    /// Keep the backend's exact provider code. Its English display name is a
    /// fallback only; `AgentLanguage.displayName` localises the code through
    /// Foundation for the current app language.
    init(catalog language: Components.Schemas.CatalogLanguage) {
        self.init(code: language.code, displayName: language.displayName)
    }
}

/// A minimal `Equatable`/`Hashable` JSON value so the catalog schemas can
/// live in an `Equatable` view type (SwiftUI state) without importing the
/// runtime container into the screens.
// swiftformat:disable:next redundantSendable
nonisolated enum AnyHashableJSON: Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([AnyHashableJSON])
    case object([String: AnyHashableJSON])
    case null

    init(_ value: Any?) {
        switch value {
        case let s as String: self = .string(s)
        case let b as Bool: self = .bool(b)
        case let i as Int: self = .number(Double(i))
        case let d as Double: self = .number(d)
        case let arr as [Any]: self = .array(arr.map(AnyHashableJSON.init))
        case let obj as [String: Any]:
            self = .object(obj.mapValues(AnyHashableJSON.init))
        default: self = .null
        }
    }
}

// MARK: - SET result (`ControlSetResponse`)

/// Result of an arm / disable that applied (or escalated) through the gate.
nonisolated struct ControlSetResultView: Equatable {
    let status: Status
    /// The `agent_action_log` row id for this change.
    let actionLogID: String

    enum Status: Equatable {
        /// The gate executed the action (owner-bypass direct path).
        case applied
        /// PolicyEngine escalated to owner consent (reserved for a future
        /// non-owner transport; owner-driven arms apply directly).
        case awaitingConsent
        /// Forward-compat for an unknown status string.
        case unknown(String)

        init(wire: String) {
            switch wire {
            case "applied": self = .applied
            case "awaiting_consent": self = .awaitingConsent
            default: self = .unknown(wire)
            }
        }
    }
}

nonisolated extension ControlSetResultView {
    /// Build from the generated `ControlSetResponse` body.
    init(_ body: Components.Schemas.ControlSetResponse) {
        self.init(status: Status(wire: body.status), actionLogID: body.actionLogId)
    }
}

// MARK: - Refusals (ADR-0088)

/// A room-tool write the backend refused for a reason the owner can act on:
/// arming a Tool, or keeping a call's translation as the room's rule. Told
/// apart by the backend's RFC 7807 `type`, never its prose.
nonisolated enum RoomToolRefusal: Equatable, CustomStringConvertible {
    /// `409` — the agent already has 5 active Tools in this room.
    case capReached
    /// `409` — an identical Tool (same params + trigger) is already on.
    case duplicate
    /// `422` — the Tool would never fire in this kind of room; `reason` is
    /// the backend's detail, for the log.
    case doesNotFireHere(reason: String)

    static let capReachedTypeURI = "/errors/tool-cap-reached"
    static let duplicateTypeURI = "/errors/tool-duplicate"
    static let doesNotFireHereTypeURI = "/errors/tool-does-not-fire-here"

    /// The refusal a problem `type` names, or `nil` for any other problem.
    init?(problemType: String, detail: String) {
        switch problemType {
        case Self.capReachedTypeURI: self = .capReached
        case Self.duplicateTypeURI: self = .duplicate
        case Self.doesNotFireHereTypeURI: self = .doesNotFireHere(reason: detail)
        default: return nil
        }
    }

    /// What the owner reads. On the model so the arm form and the call's
    /// room-default save say the same words.
    var message: String {
        switch self {
        case .capReached: UntranslatedL10n.screenArmToolErrorCapReached
        case .duplicate: UntranslatedL10n.screenArmToolErrorDuplicate
        case .doesNotFireHere: UntranslatedL10n.screenArmToolErrorDoesNotFireHere
        }
    }

    var description: String {
        switch self {
        case .capReached: "tool cap reached"
        case .duplicate: "duplicate tool"
        case .doesNotFireHere(let reason): "tool does not fire here: \(reason)"
        }
    }
}

nonisolated extension AgentPlatformError {
    /// What the owner reads when a room-tool write failed: its own words for
    /// the failures with a known cause, the generic error for the rest.
    var roomToolMessage: String {
        switch self {
        case .forbidden: UntranslatedL10n.screenArmToolErrorForbidden
        case .serverError(let status) where status >= 500: UntranslatedL10n.screenArmToolErrorServer
        default: L10n.errorUnknown
        }
    }
}

/// Why `POST …/tools` did not arm a Tool.
nonisolated enum RoomToolArmError: Error, CustomStringConvertible {
    case refused(RoomToolRefusal)
    /// `409` — the edited tool is no longer on (turned off elsewhere), so the
    /// form holds a stale id; nothing changed.
    case replacedGone
    /// Anything else: auth, a gate denial, transport, 5xx.
    case failed(AgentPlatformError)

    static let replacedGoneTypeURI = "/errors/tool-replaced-gone"

    var description: String {
        switch self {
        case .refused(let refusal): refusal.description
        case .replacedGone: "replaced tool is gone"
        case .failed(let error): error.description
        }
    }
}

// MARK: - SET Output witness

/// Maps a `/tools` SET operation's generated `Output` (`ok` carries a
/// `ControlSetResponse`, the error cases the standard `ProblemDetails`) to
/// a domain result. The arm has its own typed refusals (`RoomToolArmError`)
/// and maps itself in the service.
nonisolated protocol ControlSetOutputConvertible {
    func asControlSetResult() -> Result<ControlSetResultView, AgentPlatformError>
}

nonisolated extension Operations.DeleteTool.Output: ControlSetOutputConvertible {
    func asControlSetResult() -> Result<ControlSetResultView, AgentPlatformError> {
        switch self {
        case .ok(let r): return (try? .success(.init(r.body.json))) ?? .failure(.validation(detail: "tool set body unparseable"))
        case .unauthorized: return .failure(.unauthorized)
        case .forbidden: return .failure(.forbidden)
        case .notFound: return .failure(.notFound)
        case .unprocessableContent: return .failure(.validation(detail: "unprocessable"))
        case .badRequest: return .failure(.validation(detail: "bad request"))
        case .internalServerError: return .failure(.serverError(status: 500))
        case .undocumented(let code, _): return .failure(AudienceScope.mapUndocumented(code))
        }
    }
}

nonisolated extension AudienceScope {
    /// Undocumented-status mapping shared by the SET witnesses. Kept on
    /// `AudienceScope` as a neutral namespace so it does not depend on the
    /// service type.
    static func mapUndocumented(_ status: Int) -> AgentPlatformError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict(detail: "HTTP 409")
        case 422: return .validation(detail: "unprocessable")
        case 500...: return .serverError(status: status)
        default: return .serverError(status: status)
        }
    }
}
