//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0054, Brief 0085): app-level models for in-call agent
// session controls (`/api/v1/voice-sessions/{id}/controls*`), as backend
// ADR-0094 Appendix A shapes them for call translation.
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

/// A lane's source (ADR-0094 D12): the speaker's microphone in this release. A later one adds the owner's device audio.
nonisolated enum VoiceTranslationInput: String, Equatable {
    case voice
}

/// One lane (ADR-0094 D2): `speaker`'s `input` in `language`, at most one producer each. `language` is a catalog code
/// in its exact form (`zh-Hans`, `pt-BR`).
nonisolated struct VoiceTranslationLane: Hashable {
    let speaker: String
    let input: VoiceTranslationInput
    let language: String

    init(speaker: String, input: VoiceTranslationInput = .voice, language: String) {
        self.speaker = speaker
        self.input = input
        self.language = language
    }

    /// Nil for an input this build doesn't know: the lane is left out (forward tolerance, decision 96).
    init?(speaker: String, input: String, language: String) {
        guard let input = VoiceTranslationInput(rawValue: input) else { return nil }
        self.init(speaker: speaker, input: input, language: language)
    }
}

/// Why a session's translation stopped (ADR-0094 D6), as the document's `stopped.reason` / `leaving_reason` and the
/// owner's `stopped_reason` say it.
nonisolated enum VoiceTranslationStopReason: Equatable {
    case ownerStopped
    /// The owner had no live membership in the call for a minute.
    case ownerLeft
    case aiLimit
    /// The Call translation category cap paused it.
    case translationPaused
    /// The per-call cap ran out: final for the call.
    case callCap
    /// Anything else, a reason newer than this build included: unknown, never "the owner stopped".
    case ended

    init(wire: String) {
        switch wire {
        case "owner_stopped": self = .ownerStopped
        case "owner_left": self = .ownerLeft
        case "ai_limit": self = .aiLimit
        case "translation_paused": self = .translationPaused
        case "call_cap": self = .callCap
        default: self = .ended
        }
    }
}

/// What the session's translation is for the owner (ADR-0094 A.3): the intent, the lanes it holds, and whether it
/// stands by, stopped, or waits for the runtime.
nonisolated struct VoiceControlsEffective: Equatable {
    /// `override` | `room_tool` | `off`.
    let source: String
    /// `simultaneous` | `consecutive`, derived by the server; nil when off or stopped.
    let style: String?
    var forLanguage: String?
    /// The pocket interpreter's two languages.
    var pocket: [String]?
    var lanes: [VoiceTranslationLane] = []
    /// An enabled intent that holds no lane: it takes one over when its producer stops.
    var isStandby = false
    var stoppedReason: VoiceTranslationStopReason?
    /// The runtime hasn't acknowledged the newest mode: the lanes are starting.
    var isSyncing = false
    /// Call translation is paused by its cap (question 395) while the assistant stays for its other jobs.
    var pause: AgentUsage.Pause?

    /// The intent is on: producing, standing by or syncing, not stopped.
    var isEnabled: Bool {
        stoppedReason == nil && (forLanguage != nil || pocket != nil)
    }

    static let off = VoiceControlsEffective(source: "off", style: nil)
}

/// The translation override row.
nonisolated struct VoiceControlsOverride: Equatable {
    /// `inherit` | `enabled` | `disabled`.
    let state: String
    /// CAS token for the next write.
    let revision: Int32
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

/// Controls snapshot for one session.
nonisolated struct VoiceControlsState: Equatable {
    let sessionID: String
    let effective: VoiceControlsEffective
    let override: VoiceControlsOverride?
    /// Brief 0055 — live recording/summary flags with disable tokens.
    let artifacts: VoiceControlsArtifacts
    let conversation: VoiceConversationState
}

/// One language of the voice-translation catalog (ADR-0094 A.8). `code` is the exact form every other part of the
/// contract uses; `label` is the server's English name, the fallback when the locale can't name the code.
nonisolated struct VoiceControlsCatalogLanguage: Codable, Equatable {
    let code: String
    let label: String
}

/// The translation intent the owner writes (ADR-0094 A.2, D3): exactly one form. The server picks the speakers; the
/// client never sends a speaker list.
nonisolated enum VoiceTranslationParams: Equatable {
    /// "Produce for my language", in a call between people: every speaker whose language isn't `language`.
    case forLanguage(String)
    /// The pocket interpreter in the owner's own chat: the owner's voice into both languages, consecutive.
    case pocket(String, String)

    /// The languages it asks for.
    var languages: [String] {
        switch self {
        case .forLanguage(let language): [language]
        case .pocket(let first, let second): [first, second]
        }
    }
}

/// Why a session-control write or read failed. Everything without its own case is folded into `unavailable`.
nonisolated enum VoiceControlsError: Error, CustomStringConvertible {
    /// 409 — stale CAS revision; reload and retry.
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
    /// 409 `/errors/agent-paused` on attach: the owner paused the agent
    /// (decision 194); it joins no call until resumed.
    case agentPaused
    /// 422 `/errors/translation-paused` on turning translation on (ADR-0094 A.2): the category is paused, the AI
    /// limit is reached, or the per-call cap ended it. Nothing changed.
    case translationPaused(VoiceTranslationRefusal)
    /// 422 `/errors/translation-intent-unavailable`: this form isn't allowed in this kind of room.
    case intentUnavailable(roomKind: String)
    /// 409 `/errors/recording-covered` on starting a recording (question 404): someone else's assistant already records
    /// this call, and there is one recording per call.
    case recordingCovered(VoiceRecordingCover)
    /// 503 `/errors/service-unavailable` on an enabling write: the call's participants couldn't be read; nothing was
    /// written. Retried once after `retryAfter`.
    case serviceUnavailable(retryAfter: Duration)
    /// 401 — the token may have rotated; `controlsCall` retries once on it.
    case unauthorized
    /// Anything else: auth, transport, 5xx, decode.
    case unavailable(String)

    /// The `type` URI the backend stamps on the invite-only refusal.
    static let inviteRequiredTypeURI = "/errors/agent-invite-required"

    /// The `type` URI of the attach 409 that names the session already
    /// running in the room (`existing_session_id`).
    static let voiceSessionActiveTypeURI = "/errors/voice-session-active"

    static let translationPausedTypeURI = "/errors/translation-paused"
    static let intentUnavailableTypeURI = "/errors/translation-intent-unavailable"
    static let recordingCoveredTypeURI = "/errors/recording-covered"

    var description: String {
        switch self {
        case .conflict: "conflict — stale revision"
        case .gone: "gone — session ended"
        case .rejected(let detail): "rejected: \(detail)"
        case .inviteRequired(let detail): "invite required: \(detail)"
        case .agentPaused: "agent paused — it joins no call"
        case .translationPaused(let refusal): "translation paused: \(refusal.reason)"
        case .intentUnavailable(let roomKind): "translation intent unavailable in a \(roomKind) room"
        case .recordingCovered: "recording covered by another assistant"
        case .serviceUnavailable(let retryAfter): "service unavailable, retry after \(retryAfter)"
        case .unauthorized: "unauthorized — token may have rotated"
        case .unavailable(let detail): "unavailable: \(detail)"
        }
    }
}

/// `409 /errors/recording-covered` (question 404): the assistant that records the call (`recording_agent`) and its owner
/// (`recording_owner`); the backend may name neither.
nonisolated struct VoiceRecordingCover: Equatable {
    let agentMxid: String?
    let ownerMxid: String?
}

/// `422 /errors/translation-paused` (ADR-0094 A.2): why translation can't start, and until when.
nonisolated struct VoiceTranslationRefusal: Equatable {
    enum Reason: Equatable {
        case translationPaused
        case aiLimit
        /// The per-call cap: final for this call, no date.
        case callCap

        /// A reason newer than this build reads as the category's pause: still a pause, never a crash.
        init(wire: String?) {
            switch wire {
            case "ai_limit": self = .aiLimit
            case "call_cap": self = .callCap
            default: self = .translationPaused
            }
        }
    }

    let reason: Reason
    /// Nil for `call_cap`, and while a $0 cap holds.
    let pauseUntil: Date?
}

/// `GET /agents/{id}/voice-sessions/join-check` — whether the owner's agent can join a call here, and the one reason
/// the owner can act on when not (question 387, B4). Names no one.
nonisolated enum VoiceJoinCheckReason: Equatable {
    case ok
    case paused
    case aiConsentOwner
    case askToJoin
    case aiConsentRoom
    case budgetReached
    /// Its Calls are paused by their cap (question 395). The check names no date; the agent's usage does.
    case categoryPaused(AgentUsage.Pause?)
    /// A code newer than this build (decision 96): it can't join, and the app may need an update.
    case unknown(String)

    init(wire: String) {
        switch wire {
        case "ok": self = .ok
        case "paused": self = .paused
        case "ai_consent_owner": self = .aiConsentOwner
        case "ask_to_join": self = .askToJoin
        case "ai_consent_room": self = .aiConsentRoom
        case "budget_reached": self = .budgetReached
        case "category_paused": self = .categoryPaused(nil)
        default: self = .unknown(wire)
        }
    }
}

/// Why a voice session ended, from `GET /voice-sessions/{id}` (question 387, B1). The owner reads it after an attach
/// that never reached the call.
nonisolated enum VoiceSessionEndReason: Equatable {
    case callEnded
    case manual
    /// The owner left the call, and their assistant with them.
    case ownerLeft
    /// Translation isn't offered in this call (`translation_not_here`): the assistant left; nothing failed.
    case translationNotHere
    /// Someone without AI consent joined or spoke.
    case optOut
    case aiConsentOwner
    case aiConsentRoom
    case budgetReached
    /// One category's cap is reached (question 395): the calls cap ends the assistant's part of the call, the call
    /// translation cap its translation.
    case categoryPaused(AgentUsage.Category)
    /// The consent gate's own step failed, the runtime crashed or timed out, or any other failure.
    case failed
    /// A reason newer than this build: shown as a plain failure (decision 96).
    case unknown(String)

    /// `category` comes with `category_paused`; a newer or missing one reads as other.
    init(wire: String, category: String? = nil) {
        switch wire {
        case "call_ended": self = .callEnded
        case "manual": self = .manual
        case "owner_left": self = .ownerLeft
        case "translation_not_here": self = .translationNotHere
        case "opt_out": self = .optOut
        case "ai_consent_owner": self = .aiConsentOwner
        case "ai_consent_room": self = .aiConsentRoom
        case "budget_reached": self = .budgetReached
        case "category_paused": self = .categoryPaused(.init(serverValue: category ?? ""))
        case "notice_failed", "error", "crash", "timeout": self = .failed
        default: self = .unknown(wire)
        }
    }
}

/// One voice session's lifecycle as the owner reads it after an attach.
nonisolated enum VoiceSessionProgress: Equatable {
    /// Accepted, not yet in the call (`pending_consent`, `pending_join`, `starting`).
    case joining
    case active
    case ending
    case ended(VoiceSessionEndReason)
}

// MARK: - Brief 0055: the in-call agent center

/// Attach-time function configuration.
nonisolated struct VoiceAttachParams: Equatable {
    /// nil = no translation for this call.
    let translation: VoiceTranslationParams?
    let recording: Bool
    let summary: Bool
    /// Decision 180 — the assistant talks once it has joined. Off is the
    /// call's own rule (`inherit`), so the owner's own chat with the
    /// assistant still talks. Never together with `translation`.
    let conversation: Bool
}
