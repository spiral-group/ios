//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063, backend ADR-0071 D8, ADR-0094 A.6 document v6): the agent publishes a
// versioned state document in its LiveKit participant attributes under
// `spiral.agent.state`, refreshed by the runtime on session start and after
// every applied reconfigure. LiveKit pushes attribute changes to EVERY
// participant instantly, which makes this document the canonical live
// source of the agent's in-call state on all devices alike — no polling,
// no owner-gated REST asymmetry, gone the moment the agent leaves.
// This is the same contract the Element Call fork reads
// (`element-call/src/spiral/agentState.ts`); parsing is fail-soft for the
// same reason: a malformed document renders the participant as an
// ordinary user, never a broken screen.

import Foundation

nonisolated enum SpiralAgentStateReader {
    static let attributeKey = "spiral.agent.state"

    /// The agent's translation function (document v6, ADR-0094 A.6): the intent, the lanes its mode airs, and why it
    /// stopped. Every language is a catalog code in its exact form.
    struct TranslationClaim: Equatable {
        /// The function airs its lanes; false while it stands by or after a stop.
        let isActive: Bool
        /// `consecutive` | `simultaneous` as the document declares it.
        let style: TranslationStyle?
        /// Who turned it on: the owner in this call, or their personal Tool. Nil when unknown.
        let source: Source?
        /// The intent language; nil for the pocket interpreter.
        let forLanguage: String?
        /// The pocket interpreter's two languages.
        let pocket: [String]?
        /// The agent's owner's MXID: "Bohdan · assistant" for everyone.
        let owner: String?
        /// What the running mode airs, voice lanes only: a lane with an input this build doesn't know is left out
        /// (D12). It may name a speaker who already left the call (their grace).
        let lanes: [VoiceTranslationLane]
        /// Why it stopped while the agent stays; nil while it produces or stands by.
        let stoppedReason: VoiceTranslationStopReason?

        static let none = TranslationClaim(isActive: false, style: nil, source: nil, forLanguage: nil, pocket: nil, owner: nil,
                                           lanes: [], stoppedReason: nil)

        /// Producing `language` for `speakers` in the Live style, for previews and tests.
        static func producing(_ language: String, speakers: [String], owner: String? = nil) -> TranslationClaim {
            TranslationClaim(isActive: true, style: .simultaneous, source: .override, forLanguage: language, pocket: nil, owner: owner,
                             lanes: speakers.map { VoiceTranslationLane(speaker: $0, language: language) }, stoppedReason: nil)
        }

        /// The languages the intent asks for while it is on — producing or standing by; empty once stopped or off.
        var languages: [String] {
            guard stoppedReason == nil else { return [] }
            if let forLanguage { return [forLanguage] }
            if let pocket { return pocket }
            return Array(Set(lanes.map(\.language))).sorted()
        }

        /// The languages its lanes air now.
        var producedLanguages: [String] {
            isActive ? Array(Set(lanes.map(\.language))).sorted() : []
        }

        /// On, holding no lane: it takes one over when its producer stops ("if nobody translates, my assistant does").
        var isStandby: Bool {
            !isActive && stoppedReason == nil && lanes.isEmpty && forLanguage != nil
        }

        /// Stopped by a limit: the AI limit, the Call translation cap, or the per-call cap.
        var isStoppedByLimit: Bool {
            switch stoppedReason {
            case .aiLimit, .translationPaused, .callCap: true
            case .ownerStopped, .ownerLeft, .ended, nil: false
            }
        }
    }

    /// `source` (A.6): who turned the translation on.
    enum Source: String, Equatable {
        case override
        case roomTool = "room_tool"
    }

    enum TranslationStyle: String, Equatable {
        case consecutive
        case simultaneous
    }

    /// Where the agent is in its life, as the document (v3) declares it.
    /// `leaving` is published on teardown START, before the participant
    /// disconnects — every device sees it, no REST involved.
    enum Lifecycle: String, Equatable {
        case live
        case leaving
    }

    /// The runtime's call gate (doc v5, decision 182): `waiting` while the
    /// call is not live — ringing, or fewer people than it needs — so the
    /// agent captures and processes nothing. nil when the document does not
    /// say, or says something this build does not know: no claim either way.
    enum CallGate: String, Equatable {
        case live
        case waiting
    }

    /// EVERY live fact the document carries about one agent, read once.
    /// The presentation derive consumes this and nothing else from the
    /// attribute — one parse, one shape, no per-fact readers to drift.
    struct AgentClaim: Equatable {
        let lifecycle: Lifecycle
        /// Why the agent's part of the call ends, beside `lifecycle: leaving` (D6); nil otherwise or unsaid.
        var leavingReason: VoiceTranslationStopReason?
        let isRecording: Bool
        /// Question 404: a recording function, active or only armed — this agent holds the call's one recording.
        var holdsRecording = false
        let isSummaryArmed: Bool
        /// v4 (Brief 0080): the agent TALKS in this call — only its owner's
        /// audio reaches the model and everyone hears the answers. Absent
        /// from the document while it is silent.
        let isConversationActive: Bool
        let translation: TranslationClaim
        let callGate: CallGate?
        /// The mode epoch the runtime runs: diagnostics only.
        var modeEpoch: Int?

        /// A claim from its parts, for previews and tests — production
        /// claims come from the document only.
        static func make(translation: TranslationClaim = .none,
                         recording: Bool = false,
                         summaryArmed: Bool = false,
                         conversation: Bool = false,
                         lifecycle: Lifecycle = .live,
                         leavingReason: VoiceTranslationStopReason? = nil,
                         callGate: CallGate? = nil,
                         holdsRecording: Bool? = nil) -> AgentClaim {
            AgentClaim(lifecycle: lifecycle,
                       leavingReason: leavingReason,
                       isRecording: recording,
                       holdsRecording: holdsRecording ?? recording,
                       isSummaryArmed: summaryArmed,
                       isConversationActive: conversation,
                       translation: translation,
                       callGate: callGate)
        }
    }

    /// nil when the participant publishes no valid agent document.
    static func agentClaim(attributes: [String: String]) -> AgentClaim? {
        guard let doc = document(attributes: attributes)?.parsed else { return nil }
        let functions = (doc["functions"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        // A lifecycle this build does not know (a newer runtime's) reads as live.
        let lifecycle = (doc["lifecycle"] as? String).flatMap(Lifecycle.init(rawValue:)) ?? .live
        return AgentClaim(lifecycle: lifecycle,
                          leavingReason: (doc["leaving_reason"] as? String).map(VoiceTranslationStopReason.init(wire:)),
                          isRecording: functions.contains { $0["kind"] as? String == "recording" && $0["active"] as? Bool == true },
                          holdsRecording: functions.contains { $0["kind"] as? String == "recording" },
                          isSummaryArmed: functions.contains { $0["kind"] as? String == "summary" && $0["armed"] as? Bool == true },
                          isConversationActive: functions.contains { $0["kind"] as? String == "conversation" && $0["active"] as? Bool == true },
                          translation: translationClaim(functions: functions),
                          callGate: (doc["call"] as? String).flatMap(CallGate.init(rawValue:)),
                          modeEpoch: (doc["mode_epoch"] as? NSNumber)?.intValue)
    }

    /// The first translation function, read entry by entry like EC's parser: one malformed lane must not erase the
    /// valid ones next to it. No function is `.none`.
    private static func translationClaim(functions: [[String: Any]]) -> TranslationClaim {
        guard let function = functions.first(where: { $0["kind"] as? String == "translation" }) else { return .none }
        let lanes = (function["lanes"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap { lane -> VoiceTranslationLane? in
                guard let speaker = lane["speaker"] as? String, let language = lane["language"] as? String,
                      let input = lane["input"] as? String else { return nil }
                return VoiceTranslationLane(speaker: speaker, input: input, language: language)
            }
        let pocket = (function["pocket"] as? [Any])?.compactMap { $0 as? String }
        let stopped = (function["stopped"] as? [String: Any]).map { stopped in
            VoiceTranslationStopReason(wire: stopped["reason"] as? String ?? "")
        }
        return TranslationClaim(isActive: function["active"] as? Bool == true,
                                style: (function["style"] as? String).flatMap(TranslationStyle.init(rawValue:)),
                                source: (function["source"] as? String).flatMap(Source.init(rawValue:)),
                                forLanguage: function["for_language"] as? String,
                                pocket: pocket?.count == 2 ? pocket : nil,
                                owner: function["owner"] as? String,
                                lanes: lanes,
                                stoppedReason: stopped)
    }

    /// The languages the agent's lanes air now, from its state document. nil when the participant publishes no valid
    /// agent document; empty when the document is valid but nothing airs.
    static func translationLanguages(attributes: [String: String]) -> [String]? {
        agentClaim(attributes: attributes)?.translation.producedLanguages
    }

    /// Whether the agent's document claims a LIVE recording
    /// (`{"kind": "recording", "active": true}`). This is the only
    /// recording truth every participant shares: the REST session list is
    /// owner-scoped (`listForOwner`), so a foreign agent's capture is
    /// invisible there — but the document reaches every device.
    static func isRecordingActive(attributes: [String: String]) -> Bool {
        agentClaim(attributes: attributes)?.isRecording ?? false
    }

    /// The document exactly as published, or nil when this participant is not
    /// an agent. Callers use it as a CHANGE TOKEN: the runtime rewrites the
    /// document on session start and after every applied reconfigure, so a
    /// different string means the agent's in-call state moved — including the
    /// functions this reader does not otherwise interpret.
    static func agentDocument(attributes: [String: String]) -> String? {
        document(attributes: attributes)?.raw
    }

    /// One parse site for the document, so every reader agrees on what counts
    /// as an agent.
    private static func document(attributes: [String: String]) -> (raw: String, parsed: [String: Any])? {
        guard let raw = attributes[attributeKey], !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              parsed["agent"] as? Bool == true,
              parsed["v"] is NSNumber,
              // Every document names its lifecycle (decision 97): one that
              // does not is malformed, not live.
              parsed["lifecycle"] is String else {
            return nil
        }
        return (raw, parsed)
    }
}
