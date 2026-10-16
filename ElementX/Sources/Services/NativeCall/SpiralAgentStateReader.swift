//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063, backend ADR-0071 D8): the agent publishes a
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

    /// The agent's translation claim, split into what it is actively
    /// producing and what it is merely configured for. Phase 4 reads the
    /// gap: a document that lists a translation function with
    /// `active: false` is an engine that should translate but is not —
    /// the "paused" state, neither an error nor normal.
    struct TranslationClaim: Equatable {
        /// Languages of translation functions with `active == true`.
        let activeLanguages: [String]
        /// Languages of EVERY translation function, active or not.
        let configuredLanguages: [String]
        /// The active booths in full — coverage AND the languages each
        /// produces — so a surface can say "everyone into English · Marta
        /// into German" from the document alone (closeout 2026-09-03: the
        /// sheet read booths from owner-scoped REST because the claim
        /// dropped the per-booth languages).
        let activeBooths: [Booth]
        /// `consecutive` | `simultaneous` as the document declares it.
        let style: TranslationStyle?

        /// Configured but producing nothing — the paused gap.
        var isPaused: Bool {
            activeLanguages.isEmpty && !configuredLanguages.isEmpty
        }
    }

    struct Booth: Equatable {
        let coverage: BoothCoverage
        let targetLanguages: [String]
    }

    /// Who a booth covers, as the runtime RESOLVES it on the wire (Brief
    /// 0066): three shapes a client can phrase without knowing the owner
    /// or the tool vocabulary. `.members` and `.exceptMembers` carry
    /// concrete MXIDs (`owner_only` arrives as `members [owner]`,
    /// `non_self_non_owner` as `everyone_except [owner]`).
    enum BoothCoverage: Equatable {
        case open
        case exceptMembers(Set<String>)
        case members(Set<String>)

        /// Does this booth translate `userID`'s voice?
        func covers(_ userID: String) -> Bool {
            switch self {
            case .open: true
            case .exceptMembers(let excluded): !excluded.contains(userID)
            case .members(let members): members.contains(userID)
            }
        }
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
        let isRecording: Bool
        let isSummaryArmed: Bool
        /// v4 (Brief 0080): the agent TALKS in this call — only its owner's
        /// audio reaches the model and everyone hears the answers. Absent
        /// from the document while it is silent.
        let isConversationActive: Bool
        let translation: TranslationClaim
        let callGate: CallGate?

        /// A claim from its parts, for previews and tests — production
        /// claims come from the document only.
        static func make(languages: [String] = [],
                         paused: Bool = false,
                         recording: Bool = false,
                         summaryArmed: Bool = false,
                         conversation: Bool = false,
                         style: TranslationStyle? = nil,
                         booths: [Booth]? = nil,
                         lifecycle: Lifecycle = .live,
                         callGate: CallGate? = nil) -> AgentClaim {
            let effectiveBooths = booths ?? (languages.isEmpty ? [] : [Booth(coverage: .open, targetLanguages: languages)])
            return AgentClaim(lifecycle: lifecycle,
                              isRecording: recording,
                              isSummaryArmed: summaryArmed,
                              isConversationActive: conversation,
                              translation: TranslationClaim(activeLanguages: paused ? [] : languages,
                                                            configuredLanguages: languages,
                                                            activeBooths: effectiveBooths,
                                                            style: style),
                              callGate: callGate)
        }
    }

    /// nil when the participant publishes no valid agent document.
    static func agentClaim(attributes: [String: String]) -> AgentClaim? {
        guard let doc = document(attributes: attributes)?.parsed,
              let translation = translationClaim(attributes: attributes) else {
            return nil
        }
        let functions = (doc["functions"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        // A lifecycle this build does not know (a newer runtime's) reads as live.
        let lifecycle = (doc["lifecycle"] as? String).flatMap(Lifecycle.init(rawValue:)) ?? .live
        return AgentClaim(lifecycle: lifecycle,
                          isRecording: functions.contains { $0["kind"] as? String == "recording" && $0["active"] as? Bool == true },
                          isSummaryArmed: functions.contains { $0["kind"] as? String == "summary" && $0["armed"] as? Bool == true },
                          isConversationActive: functions.contains { $0["kind"] as? String == "conversation" && $0["active"] as? Bool == true },
                          translation: translation,
                          callGate: (doc["call"] as? String).flatMap(CallGate.init(rawValue:)))
    }

    /// nil when the participant publishes no valid agent document (not an
    /// agent, or an agent whose document did not land — the caller falls
    /// back to the track snapshot).
    static func translationClaim(attributes: [String: String]) -> TranslationClaim? {
        guard let doc = document(attributes: attributes)?.parsed else {
            return nil
        }
        // Per-entry fail-soft, like EC's parser: one malformed function
        // must not erase the valid ones next to it.
        let functions = (doc["functions"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
            .filter { $0["kind"] as? String == "translation" }
        // Canonical BASE tags: the runtime, the catalog and the track names
        // disagree on region and case (`en-US` / `EN` / `en`), and every
        // consumer compares these strings against a track name. Normalising
        // at the boundary keeps those comparisons like-for-like instead of
        // muting a lane over a suffix.
        let languages = { (functions: [[String: Any]]) in
            Array(Set(functions
                    .flatMap { ($0["target_languages"] as? [Any] ?? []).compactMap { $0 as? String } }
                    .map(LanguageTag.base(of:)))).sorted()
        }
        let activeFunctions = functions.filter { $0["active"] as? Bool == true }
        // Coverage arrives resolved (Brief 0066): `anyone`, `members`,
        // `everyone_except`; the runtime publishes every translation function
        // with its booths (decision 97). What a booth covers decides whose
        // original is ducked under the lane (`NativeCallListening`) and who
        // the roster calls covered, so only `anyone` is open. Anything else
        // this build cannot read (a newer runtime's scope, a missing or
        // malformed one) covers nobody: originals stay at full level, as the
        // engine itself reads an unknown scope (it matches nothing). A
        // `members []` is NOT malformed: the runtime publishes it for an
        // owner-only booth whose owner it does not know (a booth naming a
        // phantom), and it covers nobody too. `everyone_except` with no
        // members excludes nobody, and the engine translates everyone.
        let booths: [Booth] = activeFunctions.flatMap { function -> [Booth] in
            (function["booths"] as? [Any] ?? [])
                .compactMap { $0 as? [String: Any] }
                .map { booth in
                    let members = (booth["speaker_members"] as? [Any] ?? []).compactMap { $0 as? String }
                    let coverage: BoothCoverage = switch booth["speaker_scope"] as? String {
                    case "anyone":
                        .open
                    case "members":
                        .members(Set(members))
                    case "everyone_except":
                        members.isEmpty ? .open : .exceptMembers(Set(members))
                    default:
                        .members([])
                    }
                    let targets = (booth["target_languages"] as? [Any] ?? [])
                        .compactMap { $0 as? String }
                        .map(LanguageTag.base(of:))
                    return Booth(coverage: coverage, targetLanguages: targets)
                }
        }
        let style = functions
            .compactMap { $0["style"] as? String }
            .compactMap(TranslationStyle.init(rawValue:))
            .first
        return TranslationClaim(activeLanguages: languages(activeFunctions),
                                configuredLanguages: languages(functions),
                                activeBooths: booths,
                                style: style)
    }

    /// The languages the agent currently translates into, from its state
    /// document. nil when the participant publishes no valid agent
    /// document; empty when the document is valid but translation is off.
    static func translationLanguages(attributes: [String: String]) -> [String]? {
        translationClaim(attributes: attributes)?.activeLanguages
    }

    /// Whether the agent's document claims a LIVE recording
    /// (`{"kind": "recording", "active": true}`). This is the only
    /// recording truth every participant shares: the REST session list is
    /// owner-scoped (`listForOwner`), so a foreign agent's capture is
    /// invisible there — but the document reaches every device.
    static func isRecordingActive(attributes: [String: String]) -> Bool {
        guard let doc = document(attributes: attributes)?.parsed else {
            return false
        }
        return (doc["functions"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
            .contains { $0["kind"] as? String == "recording" && $0["active"] as? Bool == true }
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
