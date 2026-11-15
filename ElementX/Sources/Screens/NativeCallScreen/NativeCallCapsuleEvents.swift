//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403, critique item 7): an event briefly expands the agent capsule, Dynamic
// Island-like, with its one action, then it collapses back into what the assistant does. Events wait their turn; the
// same action always stays in the 文A menu, so one missed is never lost. Question 409: to a person who never picked
// their language, the capsule also says when someone's assistant starts translating them, from which language, with
// «Змінити».

import Foundation

enum NativeCallCapsuleEvent: Equatable {
    /// Someone else's assistant started producing your language (scenario 3.1): "Listen".
    case translationAvailable(language: String, producer: String, owner: String?)
    /// The lane you listened to stopped (scenario 4.1): "Continue" with your own assistant.
    case translationStopped(language: String, producer: String, owner: String?, reason: NativeCallTranslationStop.Reason)
    /// This chat's tool switched translation on at the call's start (scenario 5.2): "Undo" — it undoes an action (L3).
    case toolSwitchedOn(language: String)
    /// Your own assistant started translating (scenario 1.3).
    case ownTranslating(language: String, speakers: [String])
    /// Question 409: someone's assistant translates you from `language`, your language: "Change". After a change, the
    /// same words with the new language and no action (`isConfirmation`).
    case translatingYou(language: String, producer: String, owner: String?, isConfirmation: Bool)

    enum Action: Equatable {
        case listen(language: String)
        case continueTranslation(language: String)
        case cancelTool
        /// The language list, the one «Моя мова» is picked in.
        case changeSpokenLanguage
    }

    var action: Action? {
        switch self {
        case .translationAvailable(let language, _, _): .listen(language: language)
        case .translationStopped(let language, _, _, _): .continueTranslation(language: language)
        case .toolSwitchedOn: .cancelTool
        case .ownTranslating: nil
        case .translatingYou(_, _, _, let isConfirmation): isConfirmation ? nil : .changeSpokenLanguage
        }
    }

    /// The assistant the capsule shows while the event lasts.
    func agent(ownAgent: String?) -> String? {
        switch self {
        case .translationAvailable(_, let producer, _), .translationStopped(_, let producer, _, _), .translatingYou(_, let producer, _, _): producer
        case .toolSwitchedOn, .ownTranslating: ownAgent
        }
    }

    /// Question 409: the first lane for your voice says who translates you and from which language — once per call,
    /// when `announced` (the language the capsule last named) is nil, and only while your language is still the
    /// default (`isLanguageChosen` false): a language you picked is yours. Again, without an action, once your language
    /// is no longer the one it named. Nothing while nobody translates you.
    static func spokenLanguageEvent(_ translation: NativeCallTranslationState,
                                    announced: String?,
                                    isLanguageChosen: Bool) -> NativeCallCapsuleEvent? {
        guard let translator = translation.yourTranslator, announced != translation.myLanguage,
              announced != nil || !isLanguageChosen else { return nil }
        return .translatingYou(language: translation.myLanguage, producer: translator.agent, owner: translator.owner, isConfirmation: announced != nil)
    }

    /// An event about your voice no longer holds once nobody translates you, or once your language changed.
    func isStale(in translation: NativeCallTranslationState) -> Bool {
        guard case .translatingYou(let language, _, _, _) = self else { return false }
        return translation.yourTranslator == nil || language != translation.myLanguage
    }

    /// What changed between two looks at the call's translation, as events (model points 5, 7). `heardLanguage` is
    /// the language listened to before: its lanes may be gone already when their stop arrives.
    static func events(from previous: NativeCallTranslationState,
                       to next: NativeCallTranslationState,
                       newStops: [NativeCallTranslationStop],
                       heardLanguage: String?,
                       ownAgents: Set<String>) -> [NativeCallCapsuleEvent] {
        var events: [NativeCallCapsuleEvent] = []
        let mine = next.myLanguage
        let wasOffered = previous.options.first { $0.language == mine }.map { !$0.producers.isEmpty } ?? false
        if !wasOffered, let option = next.options.first(where: { $0.language == mine && !$0.producers.isEmpty }),
           next.listeningLanguage != mine, let producer = option.producers.first {
            events.append(.translationAvailable(language: mine, producer: producer, owner: option.producerOwners.first))
        }
        for stop in newStops where stop.language == heardLanguage && !ownAgents.contains(stop.producer) {
            events.append(.translationStopped(language: stop.language, producer: stop.producer, owner: stop.owner, reason: stop.reason))
        }
        if previous.ownLanguage == nil, let language = next.ownLanguage {
            events.append(.ownTranslating(language: language, speakers: next.ownSpeakers))
        }
        return events
    }
}

/// One event at a time, each for `duration`, in the order they came; an event already shown or waiting isn't queued
/// twice.
struct NativeCallCapsuleQueue: Equatable {
    static let duration: Duration = .seconds(5)

    private(set) var current: NativeCallCapsuleEvent?
    private(set) var pending: [NativeCallCapsuleEvent] = []

    /// True when `event` shows at once.
    @discardableResult
    mutating func enqueue(_ event: NativeCallCapsuleEvent) -> Bool {
        guard current != event, !pending.contains(event) else { return false }
        if current == nil {
            current = event
            return true
        }
        pending.append(event)
        return false
    }

    /// The current event is done (its time ran out, or its action ran): the next one shows.
    mutating func advance() {
        current = pending.isEmpty ? nil : pending.removeFirst()
    }

    /// Drops the events that no longer hold (the language is already heard, the call ended).
    mutating func drop(where isStale: (NativeCallCapsuleEvent) -> Bool) {
        pending.removeAll(where: isStale)
        if let current, isStale(current) {
            advance()
        }
    }
}

/// An event's words: whose assistant on the small line, what happened, and its action.
struct NativeCallCapsuleEventCopy: Equatable {
    let who: String
    let line: String
    let action: String?
    /// The assistant whose avatar the capsule shows.
    let agentUserID: String?

    /// What VoiceOver reads as the capsule expands.
    var announcement: String {
        "\(who). \(line)"
    }

    init(_ event: NativeCallCapsuleEvent, viewState: NativeCallScreenViewState) {
        func person(_ userID: String) -> String {
            let name = viewState.memberProfiles[userID]?.displayName ?? NativeCallFallbackName.make(mxid: userID)
            return name.split(separator: " ").first.map(String.init) ?? name
        }
        /// "Bohdan · assistant" from its owner; its own name without one (a backend that doesn't say).
        func assistant(_ agent: String, owner: String?) -> String {
            if let owner { return UntranslatedL10n.screenNativeCallAssistantsOwnerAssistant(person(owner)) }
            return viewState.memberProfiles[agent]?.displayName ?? NativeCallFallbackName.make(mxid: agent)
        }
        let ownAgent = viewState.agents.ownAgents.first?.mxid
            ?? viewState.agents.joining.first(where: \.canControl)?.agentMxid
            ?? viewState.agents.panel.candidates.first?.mxid
        agentUserID = event.agent(ownAgent: ownAgent)

        switch event {
        case .translationAvailable(let language, let producer, let owner):
            who = assistant(producer, owner: owner)
            line = UntranslatedL10n.screenNativeCallCapsuleAvailable(NativeCallTranslationCopy.languageName(language))
            action = UntranslatedL10n.screenNativeCallCapsuleListen
        case .translationStopped(_, let producer, let owner, let reason):
            let whose = owner.map(person) ?? assistant(producer, owner: nil)
            // ADR-0094 D6: an unknown reason is "ended", never "the owner turned it off".
            who = switch reason {
            case .limitReached: UntranslatedL10n.screenNativeCallCapsuleStoppedLimit(whose)
            case .stoppedByOwner: UntranslatedL10n.screenNativeCallCapsuleStoppedOwner(whose)
            case .ownerLeft: UntranslatedL10n.screenNativeCallCapsuleStoppedOwnerLeft(whose)
            case .ended: assistant(producer, owner: owner)
            }
            line = UntranslatedL10n.screenNativeCallCapsuleStopped
            action = UntranslatedL10n.screenNativeCallCapsuleContinue
        case .toolSwitchedOn:
            who = UntranslatedL10n.screenNativeCallAgentPillYourAssistant
            line = UntranslatedL10n.screenNativeCallCapsuleTool
            action = UntranslatedL10n.screenNativeCallCapsuleUndo
        case .ownTranslating(let language, let speakers):
            who = UntranslatedL10n.screenNativeCallAgentPillYourAssistant
            line = UntranslatedL10n.screenNativeCallCapsuleOwnTranslating(speakers.map(person).formatted(.list(type: .and)),
                                                                          NativeCallTranslationCopy.languageName(language))
            action = nil
        case .translatingYou(let language, let producer, let owner, let isConfirmation):
            who = assistant(producer, owner: owner)
            line = UntranslatedL10n.screenNativeCallCapsuleTranslatingYou(NativeCallTranslationCopy.languageName(language))
            action = isConfirmation ? nil : UntranslatedL10n.screenNativeCallCapsuleChange
        }
    }
}
