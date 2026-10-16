//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0054): app-level models for in-call agent
// session controls (`/api/v1/voice-sessions/{id}/controls*`).
//
// The JSON keys deliberately mirror the Element Call widget's
// `SpiralBridgeApi` contract (element-call `src/spiral/bridge.ts`) —
// the CallScreen bridge encodes these types verbatim and hands the
// string to the webview, so the two sides share one wire vocabulary.
//

import Foundation

/// One controllable agent session in the current call
/// (`SpiralSessionCtx` on the widget side).
nonisolated struct VoiceSessionControlContext: Codable, Equatable {
    let sessionID: String
    /// Matrix user ID of the agent — the widget matches this against
    /// the participant's `userId`.
    let agentMxid: String
    let canControl: Bool
    /// The backend's own lifecycle tag. Carried so a session that is
    /// TEARING DOWN can say so: without it an `ending` session rendered
    /// exactly like a live one — "Ready", with an armed Remove button —
    /// and the owner pressed it again because nothing had visibly changed.
    let state: String

    /// `true` while the backend is tearing this session down. Self-clearing
    /// by construction: the row either disappears or comes back `active`,
    /// so no client-side bookkeeping can go stale.
    var isEnding: Bool {
        state == "ending"
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agentMxid = "agent_mxid"
        case canControl = "can_control"
        case state
    }
}

/// One translation booth: WHO is translated → into WHICH languages
/// (Brief 0062 / backend ADR-0075 `BoothView`; the widget's
/// `SpiralBooth`). The read AND write shape — the panel edits exactly
/// what the engine runs.
nonisolated struct VoiceTranslationBooth: Codable, Equatable {
    /// `anyone` | `non_self_non_owner` | `owner_only` |
    /// `specific_senders` | `everyone_except`.
    let speakerScope: String
    /// Concrete MXIDs for the member scopes; empty otherwise.
    let speakerMembers: [String]
    let targetLanguages: [String]

    enum CodingKeys: String, CodingKey {
        case speakerScope = "speaker_scope"
        case speakerMembers = "speaker_members"
        case targetLanguages = "target_languages"
    }
}

/// Effective per-control resolution (`SpiralEffectiveTranslation`).
///
/// Brief 0062 — the FULL booth list, never a flattened projection.
/// The old flat shape (`audience` + a languages union) dropped
/// `specific_senders` members and could not represent two booths, so
/// a multi-booth session silently read back as single-booth.
nonisolated struct VoiceControlsEffective: Codable, Equatable {
    /// `override` | `room_tool` | `off`.
    let source: String
    /// `simultaneous` | `consecutive`; nil when off.
    let style: String?
    /// The booths the engine actually runs; empty when off.
    let booths: [VoiceTranslationBooth]

    enum CodingKeys: String, CodingKey {
        case source, style, booths
    }
}

/// The translation override row (`SpiralTranslationOverride`).
nonisolated struct VoiceControlsOverride: Codable, Equatable {
    /// `inherit` | `enabled` | `disabled`.
    let state: String
    /// CAS token for the next write.
    let revision: Int32

    enum CodingKeys: String, CodingKey {
        case state, revision
    }
}

/// One call artifact's live state + the CAS token for a disable
/// (`SpiralArtifactState`).
nonisolated struct VoiceArtifactState: Codable, Equatable {
    let enabled: Bool
    /// Revision of the matching override row; 0 when none exists yet.
    let revision: Int32
    /// Brief 0056 — `pending` | `delivered` | `failed`; nil when the
    /// artifact is not armed for this session.
    let delivery: String?
    /// Brief 0057 — WHERE a delivered artifact landed: `room` or
    /// `owner_dm`.
    let deliveryTarget: String?
    /// Recording only: the capture was stopped mid-call (dictaphone
    /// semantics — what was captured is published right away).
    let stopped: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, revision, delivery, stopped
        case deliveryTarget = "delivery_target"
    }
}

/// A session control that is only ever ON or OFF: the backend flips it with a
/// bare `state` and no params, under its own CAS revision. Raw values are the
/// backend's control names (`PUT …/controls/{control}`).
nonisolated enum VoiceSessionSwitch: String, Equatable {
    case recording
    case summary
    /// Brief 0080 — enabled: the agent talks; disabled: it stays silent.
    case conversation
}

/// The per-session artifact pair (`SpiralControlsState.artifacts`).
nonisolated struct VoiceControlsArtifacts: Codable, Equatable {
    let recording: VoiceArtifactState
    let summary: VoiceArtifactState

    enum CodingKeys: String, CodingKey {
        case recording, summary
    }
}

/// Brief 0080 — the owner's Conversation / Silent switch (`ConversationView`).
nonisolated struct VoiceConversationState: Codable, Equatable {
    /// The agent talks now — the session's live mode, so a spoken "just
    /// listen" reads here too.
    let active: Bool
    /// False while the call runs the interpreter: the switch is hidden then.
    let available: Bool
    /// CAS token of the `conversation` override row; 0 when none exists yet.
    let revision: Int32

    enum CodingKeys: String, CodingKey {
        case active, available, revision
    }
}

/// Controls snapshot for one session (`SpiralControlsState`).
nonisolated struct VoiceControlsState: Codable, Equatable {
    let sessionID: String
    let effective: VoiceControlsEffective
    let override: VoiceControlsOverride?
    /// Brief 0055 — live recording/summary flags with disable tokens.
    let artifacts: VoiceControlsArtifacts
    let conversation: VoiceConversationState
    /// Whether this call's translation can become the room's standing rule.
    /// The server decides it with the room classification the promotion
    /// uses (false in 1:1 rooms, ADR-0088); the client never guesses it.
    let canSaveAsRoomDefault: Bool

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case effective, override, artifacts, conversation
        case canSaveAsRoomDefault = "can_save_as_room_default"
    }
}

/// A selectable translation language (`SpiralCatalogLanguage`).
nonisolated struct VoiceControlsCatalogLanguage: Codable, Equatable {
    let code: String
    let label: String

    enum CodingKeys: String, CodingKey {
        case code, label
    }
}

/// Catalog slice the widget renders (`SpiralCatalog`).
nonisolated struct VoiceControlsCatalog: Codable, Equatable {
    let voiceTranslationLanguages: [VoiceControlsCatalogLanguage]

    enum CodingKeys: String, CodingKey {
        case voiceTranslationLanguages = "voice_translation_languages"
    }
}

/// Translation parameters the owner applies
/// (`SpiralTranslationParams`). Brief 0062: a booth LIST — "translate
/// everyone into X" is the one-booth `anyone` case, not a separate
/// shape.
nonisolated struct VoiceTranslationParams: Codable, Equatable {
    let booths: [VoiceTranslationBooth]
    /// `simultaneous` | `consecutive`.
    let style: String

    enum CodingKeys: String, CodingKey {
        case booths, style
    }
}

/// THE default translation style, shared by every path that starts a
/// translation without an explicit choice (Brief 0066 / ADR-0075 D6
/// amended): Live (`simultaneous`) — what the platform defaults to on
/// every layer (ADR-0044 LT9) and what "live translation" means to the
/// user. Interpreter is the deliberate advanced-tier choice.
nonisolated enum NativeCallTranslationStyleDefault {
    static let wire = "simultaneous"
}

/// Errors the widget's bridge understands (`SpiralBridgeError`
/// codes). Everything else is folded into `unavailable`.
nonisolated enum VoiceControlsError: Error, CustomStringConvertible {
    /// 409 — stale CAS revision; the widget reloads and retries.
    case conflict
    /// 410 — the session already ended.
    case gone
    /// 422 — the write was rejected (validation / policy).
    case rejected(String)
    /// 422 with `type` = `/errors/agent-invite-required` — the room is
    /// invite-only and the agent is not a member yet, so an invite followed by
    /// a retry is the fix.
    ///
    /// This is its own case because it is the one 422 the client ACTS on: it
    /// invites a bot account into a private room. That decision used to be
    /// made by lowercasing the backend's English detail string and checking it
    /// contained both "invite" and "join", so a reworded message — or any
    /// unrelated 422 mentioning both words — silently changed who gets invited
    /// where. The RFC 7807 `type` URI is the backend's stable name for the
    /// case; the prose is free to change.
    case inviteRequired(String)
    /// Keeping the translation as the room's rule was refused the way an arm
    /// is (ADR-0088): no room under the cap, a duplicate, or a 1:1 call.
    case toolRefused(RoomToolRefusal)
    /// 409 `/errors/agent-paused` on attach: the owner paused the agent
    /// (decision 194); it joins no call until resumed.
    case agentPaused
    /// 401 — the token may have rotated; `controlsCall` retries once on it.
    case unauthorized
    /// Anything else: auth, transport, 5xx, decode.
    case unavailable(String)

    /// The `type` URI the backend stamps on the invite-only refusal.
    static let inviteRequiredTypeURI = "/errors/agent-invite-required"

    /// The `type` URI the backend stamps on a booth conflict (audit A8-4).
    ///
    /// Two different 409s used to share `/errors/conflict`, and they carry
    /// OPPOSITE instructions: a CAS revision conflict means "reload and try
    /// again", a booth conflict means "another agent already covers this
    /// speaker, change the configuration". They were told apart by
    /// searching the human `detail` for a marker substring, so a copy edit
    /// on the backend would have silently demoted the second into the first
    /// — and the panel would have gone on reloading against something no
    /// reload can fix.
    static let boothConflictTypeURI = "/errors/booth-conflict"

    /// The `type` URI of the attach 409 that names the session already
    /// running in the room (`existing_session_id`).
    static let voiceSessionActiveTypeURI = "/errors/voice-session-active"

    var description: String {
        switch self {
        case .conflict: "conflict — stale revision"
        case .gone: "gone — session ended"
        case .rejected(let detail): "rejected: \(detail)"
        case .inviteRequired(let detail): "invite required: \(detail)"
        case .toolRefused(let refusal): "room tool refused: \(refusal)"
        case .agentPaused: "agent paused — it joins no call"
        case .unauthorized: "unauthorized — token may have rotated"
        case .unavailable(let detail): "unavailable: \(detail)"
        }
    }
}

// MARK: - Brief 0055: the in-call agent center

/// Attach-time function configuration (`SpiralAttachParams`).
nonisolated struct VoiceAttachParams: Codable, Equatable {
    /// nil = no translation for this call.
    let translation: VoiceTranslationParams?
    let recording: Bool
    let summary: Bool
    /// Decision 180 — the assistant talks once it has joined. Off is the
    /// call's own rule (`inherit`), so the owner's own chat with the
    /// assistant still talks. Never together with `translation`.
    let conversation: Bool

    enum CodingKeys: String, CodingKey {
        case translation, recording, summary, conversation
    }
}
