//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403): what the call's translation is for this person — the languages they can
// listen to (free when someone else's assistant produces them, "2 of 3" when it covers only some speakers), what their
// own assistant would add, and whether the 文A button shows at all. One pure derive from the lanes, the participants'
// languages and the person's choice, so the button, its menu, the capsule's events and the tiles' badges agree.

import Foundation

/// One lane as the call shows it: `speaker`'s voice in `language`, produced by the assistant `producer`, owned by
/// `owner` (ADR-0094 A.6).
nonisolated struct NativeCallTranslationLane: Hashable {
    let speaker: String
    let input: VoiceTranslationInput
    /// A catalog code in its exact form.
    let language: String
    /// The producing assistant's MXID.
    let producer: String
    /// The producing assistant's owner, as its document names them.
    let owner: String?

    /// The call's Live lanes (ADR-0094 D5): every live agent document's lanes, one producer each. The pocket
    /// interpreter's consecutive clips are no lane to pick (scenario 8).
    static func lanes(documents: [String: SpiralAgentStateReader.AgentClaim]) -> [NativeCallTranslationLane] {
        var lanes: [NativeCallTranslationLane] = []
        for (agent, claim) in documents.sorted(by: { $0.key < $1.key })
            where claim.lifecycle == .live && claim.translation.isActive && claim.translation.style != .consecutive {
            for lane in claim.translation.lanes
                where !lanes.contains(where: { $0.speaker == lane.speaker && $0.input == lane.input && $0.language == lane.language }) {
                lanes.append(NativeCallTranslationLane(speaker: lane.speaker,
                                                       input: lane.input,
                                                       language: lane.language,
                                                       producer: agent,
                                                       owner: claim.translation.owner))
            }
        }
        return lanes
    }
}

/// A translation that stopped in this call (ADR-0094 D6): its listeners fall back to the original and may continue
/// it with their own assistant.
nonisolated struct NativeCallTranslationStop: Equatable, Identifiable {
    enum Reason: Equatable {
        case stoppedByOwner
        /// "Владелец вышел из звонка · Продолжить": the owner was gone for a minute.
        case ownerLeft
        /// The AI limit, the Call translation cap or the per-call cap.
        case limitReached
        /// Anything else, or a reason this build doesn't know: never "the owner stopped".
        case ended

        init(_ reason: VoiceTranslationStopReason) {
            switch reason {
            case .ownerStopped: self = .stoppedByOwner
            case .ownerLeft: self = .ownerLeft
            case .aiLimit, .translationPaused, .callCap: self = .limitReached
            case .ended: self = .ended
            }
        }
    }

    /// Unique per stop: the same assistant may stop, continue and stop again.
    let id: Int
    let language: String
    let producer: String
    let owner: String?
    /// The speakers its lanes carried when it was last seen.
    let speakers: [String]
    let reason: Reason
}

/// The stops, read from the documents as they change (ADR-0094 D6): a translation function that stops while its agent
/// stays, an agent that leaves with a reason, or one that vanishes without (`ended`). The last document of every agent
/// that produced lanes is kept, so a stop still knows its language and speakers once the agent is gone.
struct NativeCallTranslationStopHistory: Equatable {
    private(set) var stops: [NativeCallTranslationStop] = []
    private var producing: [String: SpiralAgentStateReader.AgentClaim] = [:]
    private var serial = 0

    mutating func update(documents: [String: SpiralAgentStateReader.AgentClaim]) {
        for (agent, last) in producing.sorted(by: { $0.key < $1.key }) {
            let next = documents[agent]
            let reason: VoiceTranslationStopReason?
            if let next {
                if next.lifecycle == .leaving {
                    reason = next.leavingReason ?? next.translation.stoppedReason ?? .ended
                } else if let stopped = next.translation.stoppedReason {
                    reason = stopped
                } else {
                    // Still producing, standing by, or its lanes moved on: no stop.
                    reason = nil
                }
            } else {
                reason = .ended
            }
            if let reason {
                record(last, of: agent, reason: reason)
                producing[agent] = nil
            } else if next?.translation.isActive != true || next?.translation.lanes.isEmpty == true {
                producing[agent] = nil
            }
        }
        for (agent, claim) in documents
            where claim.lifecycle == .live && claim.translation.isActive && !claim.translation.lanes.isEmpty && claim.translation.style != .consecutive {
            producing[agent] = claim
        }
    }

    private mutating func record(_ claim: SpiralAgentStateReader.AgentClaim, of agent: String, reason: VoiceTranslationStopReason) {
        let byLanguage = Dictionary(grouping: claim.translation.lanes, by: \.language)
        for language in byLanguage.keys.sorted() {
            serial += 1
            stops.append(NativeCallTranslationStop(id: serial,
                                                   language: language,
                                                   producer: agent,
                                                   owner: claim.translation.owner,
                                                   speakers: byLanguage[language, default: []].map(\.speaker),
                                                   reason: .init(reason)))
        }
    }
}

/// Why your own assistant can't produce a translation now: the menu greys its item with it, the sheet marks Перевод.
enum NativeCallTranslationBlock: Equatable {
    case noAssistant
    case aiConsentOwner
    case aiConsentRoom
    case paused
    case limit
    /// The `call_translation` cap paused translation while the call goes on (question 395).
    case translationPaused
    /// The assistant talks with you: talking and translating exclude each other (ADR-0071 G1).
    case talking

    /// Scenario 9: a join check or a failed add, as far as translation is concerned. Nil lets the add say why.
    init?(_ failure: NativeAgentCenterJoinFailure) {
        switch failure {
        case .paused: self = .paused
        case .aiConsentOwner: self = .aiConsentOwner
        case .aiConsentRoom: self = .aiConsentRoom
        case .budgetReached: self = .limit
        case .categoryPaused(let category, _): self = category == .callTranslation ? .translationPaused : .limit
        case .askToJoin, .cannotJoinCalls, .failed, .needsUpdate: return nil
        }
    }
}

struct NativeCallTranslationState: Equatable {
    /// One language the person can listen to.
    struct Option: Equatable, Identifiable {
        var id: String {
            language
        }

        let language: String
        /// Speakers it covers, of those who don't speak it.
        let covered: Int
        let needed: Int
        /// The other assistants producing it, and their owners where known, by MXID.
        let producers: [String]
        let producerOwners: [String]
        /// Your own assistant produces (part of) it.
        let isYours: Bool
        /// It appeared since the person last opened the menu: the button's dot.
        let isNew: Bool

        var isPartial: Bool {
            covered < needed
        }
    }

    /// What your own assistant would add.
    enum Production: Equatable {
        /// Nobody translates into your language yet: "Translate into Ukrainian".
        case myLanguage(String)
        /// Someone does, for some speakers: "Translate the others", naming them.
        case others(language: String, speakers: [String])

        var language: String {
            switch self {
            case .myLanguage(let language), .others(let language, _): language
            }
        }
    }

    struct Inputs: Equatable {
        var ownUserID: String?
        var myLanguage: String
        /// The other people in the call, in roster order.
        var speakers: [String] = []
        /// Published languages by MXID, catalog codes (ADR-0094 A.1).
        var languages: [String: String] = [:]
        var lanes: [NativeCallTranslationLane] = []
        var ownAgents: Set<String> = []
        var choice = NativeCallListeningChoice.original
        /// D10: the language you heard from your own assistant, whose lanes just went while a standby may take them over.
        /// It stays the one you hear, so the button keeps its code through the takeover.
        var heldLanguage: String?
        /// The languages whose lane you listened to stopped and can be continued with your own assistant (D6).
        var stoppedLanguages: [String] = []
        var seenLanguages: Set<String> = []
        var block: NativeCallTranslationBlock?
        /// The private call with one's own assistant: the pocket interpreter, never a lane to pick (scenario 8).
        var isPrivateCall = false
        /// My language is a catalog code (ADR-0094 D1): nothing is asked for in any other.
        var canProduceMyLanguage = true
        /// The person picked «Моя мова» rather than living with the default (question 409).
        var isLanguageChosen = true
        /// Your own assistant translates, or is asked to: the menu's last action opens it rather than adding one.
        var isOwnTranslating = false
    }

    /// Question 409: someone else's assistant translating your voice, and its owner where its document names them.
    struct VoiceTranslator: Equatable {
        let agent: String
        let owner: String?
    }

    let myLanguage: String
    let choice: NativeCallListeningChoice
    /// The language held through a takeover (D10).
    let heldLanguage: String?
    /// The menu's stopped tracks: a lane you listened to stopped, nothing carries its language now, and «Продолжить»
    /// brings it back with your own assistant (D6). The capsule's event about it lasts five seconds; this stays.
    let stoppedTracks: [String]
    /// The other people in the call.
    let speakers: [String]
    /// The other people's published languages, by MXID: someone absent hasn't published one.
    let speakerLanguages: [String: String]
    let options: [Option]
    let production: Production?
    let block: NativeCallTranslationBlock?
    let isButtonVisible: Bool
    /// The speakers your own assistant would cover: those who don't speak your language and nobody covers in it.
    let uncoveredSpeakers: [String]
    /// The language your own assistant produces, if any, and whom.
    let ownLanguage: String?
    let ownSpeakers: [String]
    /// The speakers you hear translated, with the language: the badge on their avatars, «文 UA» (L12).
    let badges: [String: String]
    let isLanguageChosen: Bool
    let isOwnTranslating: Bool
    /// Question 409: the first other assistant with a lane for your voice — published, not just airing, so it is said
    /// when translating you starts rather than on every phrase. In a group or a 1:1 with a person; nil in the private
    /// call with your own assistant.
    let yourTranslator: VoiceTranslator?

    /// The language you hear the call in, while a lane carries it, or while a standby takes your own lanes over (D10).
    var listeningLanguage: String? {
        guard let language = choice.language,
              language == heldLanguage || options.contains(where: { $0.language == language }) else { return nil }
        return language
    }

    var hasNewLanguage: Bool {
        options.contains(where: \.isNew)
    }

    init(_ inputs: Inputs) {
        let speakers = inputs.speakers.filter { $0 != inputs.ownUserID }
        // Your own assistant's lanes: by your agents list, or by the owner its document names (A.6) before the list
        // is read.
        let lanes = inputs.lanes.filter { speakers.contains($0.speaker) }
        func isOwn(_ lane: NativeCallTranslationLane) -> Bool {
            inputs.ownAgents.contains(lane.producer) || (lane.owner != nil && lane.owner == inputs.ownUserID)
        }
        func needed(_ language: String) -> [String] {
            // ADR-0094 D3: everyone who doesn't speak it — by base subtag, so a `pt-BR` speaker isn't translated into
            // `pt-PT` — and everyone whose language isn't published.
            speakers.filter { speaker in
                inputs.languages[speaker].map { !NativeCallLanguageCode.isSameSpokenLanguage($0, language) } ?? true
            }
        }
        func covered(_ language: String) -> Set<String> {
            Set(lanes.filter { $0.language == language }.map(\.speaker))
        }

        let languages = Set(lanes.map(\.language)).sorted { lhs, rhs in
            lhs == inputs.myLanguage || (rhs != inputs.myLanguage && lhs < rhs)
        }
        options = languages.map { language in
            let languageLanes = lanes.filter { $0.language == language }
            let others = languageLanes.filter { !isOwn($0) }
            var producers: [String] = []
            var owners: [String] = []
            for lane in others {
                if !producers.contains(lane.producer) { producers.append(lane.producer) }
                if let owner = lane.owner, !owners.contains(owner) { owners.append(owner) }
            }
            let needed = needed(language)
            return Option(language: language,
                          covered: covered(language).intersection(needed).count,
                          needed: needed.count,
                          producers: producers,
                          producerOwners: owners,
                          isYours: languageLanes.count > others.count,
                          // Only someone else's language you don't hear yet is news.
                          isNew: !inputs.seenLanguages.contains(language) && !others.isEmpty && inputs.choice.language != language)
        }

        myLanguage = inputs.myLanguage
        isLanguageChosen = inputs.isLanguageChosen
        isOwnTranslating = inputs.isOwnTranslating
        choice = inputs.choice
        heldLanguage = inputs.heldLanguage
        stoppedTracks = inputs.stoppedLanguages.filter { language in !languages.contains(language) }
        self.speakers = speakers
        speakerLanguages = inputs.languages.filter { speakers.contains($0.key) }
        block = inputs.block
        let coveredMine = covered(inputs.myLanguage)
        uncoveredSpeakers = needed(inputs.myLanguage).filter { !coveredMine.contains($0) }
        if inputs.isPrivateCall || !inputs.canProduceMyLanguage || uncoveredSpeakers.isEmpty {
            production = nil
        } else if coveredMine.isEmpty {
            production = .myLanguage(inputs.myLanguage)
        } else {
            production = .others(language: inputs.myLanguage, speakers: uncoveredSpeakers)
        }

        let ownLanes = lanes.filter(isOwn)
        ownLanguage = ownLanes.first?.language
        ownSpeakers = speakers.filter { speaker in ownLanes.contains { $0.speaker == speaker } }

        yourTranslator = if !inputs.isPrivateCall, let ownUserID = inputs.ownUserID {
            inputs.lanes.first { $0.speaker == ownUserID && !isOwn($0) }.map { VoiceTranslator(agent: $0.producer, owner: $0.owner) }
        } else {
            nil
        }

        let languagesDiffer = speakers.contains { speaker in
            inputs.languages[speaker].map { !NativeCallLanguageCode.isSameSpokenLanguage($0, inputs.myLanguage) } ?? false
        }
        // The menu holds «Я говорю» while someone translates you (question 409).
        isButtonVisible = !inputs.isPrivateCall && (!lanes.isEmpty || languagesDiffer || yourTranslator != nil)

        if let language = inputs.choice.language {
            badges = Dictionary(uniqueKeysWithValues: covered(language).map { ($0, language) })
        } else {
            badges = [:]
        }
    }

    /// Everyone else already speaks `language`: an assistant asked for it would only stand by, translating nobody. The
    /// backend's `wanted_lanes` rule (ADR-0094 D3) — the same spoken language by base subtag, and a person who hasn't
    /// published a language still needs one — so with any language unknown there is something to translate. False with
    /// nobody else in the call: that isn't "everyone speaks it".
    func isNothingToTranslate(into language: String) -> Bool {
        Self.isNothingToTranslate(into: language, speakers: speakers, languages: speakerLanguages)
    }

    static func isNothingToTranslate(into language: String, speakers: [String], languages: [String: String]) -> Bool {
        !speakers.isEmpty && speakers.allSatisfy { speaker in
            languages[speaker].map { NativeCallLanguageCode.isSameSpokenLanguage($0, language) } ?? false
        }
    }

    /// What your own assistant is asked for (ADR-0094 D3): "produce for my language". The server picks the speakers it
    /// can still claim, so "Translate the others" is the same write; the speakers above are for display only.
    var productionParams: VoiceTranslationParams? {
        production.map { .forLanguage($0.language) }
    }
}

/// The 文A menu "Listen to the call" (L4, rebuilt for question 409 by the design critic's option A): the call's audio
/// tracks — the original and the translations that exist, as toggles, and the ones you listened to that stopped, as
/// buttons since continuing one starts paid work («Английский · Перевод остановлен · Продолжить», the capsule's event
/// kept) — then "Add your translation…" or "Your translation…" once yours runs, then «Я говорю» with your language: a
/// submenu of the likely languages and «Інша мова…», shown while someone translates you or your language is still the
/// default. The capsule's «Змінити», kept.
enum NativeCallTranslateMenuItem: Equatable {
    case original(isSelected: Bool)
    case track(NativeCallTranslationState.Option, isSelected: Bool)
    /// A lane you listened to stopped: a tap continues it, as the capsule's «Продолжить» does.
    case stopped(language: String)
    /// Opens the Assistants sheet: at creating a translation, or at yours while it runs.
    case own(isRunning: Bool)
    /// The language you speak: the submenu that picks it.
    case spokenLanguage(String)

    static func items(_ state: NativeCallTranslationState) -> [NativeCallTranslateMenuItem] {
        // Wherever the 文A button shows, the menu says what you speak, so it can change at any time (operator,
        // 2026-11-12). The private call has no menu: its «Я говорю» is the pocket interpreter's row in the sheet.
        let isSpokenLanguageAsked = state.isButtonVisible
        return [.original(isSelected: state.listeningLanguage == nil)]
            + state.options.map { .track($0, isSelected: $0.language == state.listeningLanguage) }
            + state.stoppedTracks.map { .stopped(language: $0) }
            + [.own(isRunning: state.isOwnTranslating)]
            + (isSpokenLanguageAsked ? [.spokenLanguage(state.myLanguage)] : [])
    }
}
