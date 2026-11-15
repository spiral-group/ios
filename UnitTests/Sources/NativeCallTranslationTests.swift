//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0085, question 403): the call's translation for one person — when the 文A button shows, what
// its menu offers, coverage and the own assistant's share, the capsule's events and the blocked starts.

struct NativeCallTranslationTests {
    private let me = "@me:example.org"
    private let john = "@john:example.org"
    private let mira = "@mira:example.org"
    private let alex = "@alex:example.org"
    private let bohdan = "@bohdan:example.org"
    private let myAgent = "@assistant-me:example.org"
    private let bohdanAgent = "@assistant-bohdan:example.org"
    private let miraAgent = "@assistant-mira:example.org"
    private let alexAgent = "@assistant-alex:example.org"
    private let johnAgent = "@assistant-john:example.org"

    // MARK: - The 文A button

    @Test
    func theButtonHidesWhileEveryoneSpeaksYourLanguageAndNothingIsTranslated() {
        let state = translation(speakers: [bohdan], languages: [bohdan: "uk"])
        #expect(!state.isButtonVisible)
    }

    @Test
    func theButtonShowsWhenLanguagesDiffer() {
        let state = translation(speakers: [john], languages: [john: "en"])
        #expect(state.isButtonVisible)
        #expect(state.production == .myLanguage("uk"))
    }

    @Test
    func theButtonShowsOnceALaneExistsEvenWithoutLanguages() {
        let state = translation(speakers: [john], lanes: [lane(john, "uk", by: "@assistant-john:example.org")])
        #expect(state.isButtonVisible)
    }

    @Test
    func thePrivateCallHasNoButtonAndNothingToProduce() {
        var inputs = inputs(speakers: [], languages: [:])
        inputs.isPrivateCall = true
        let state = NativeCallTranslationState(inputs)
        #expect(!state.isButtonVisible)
        #expect(state.production == nil)
    }

    @Test
    func theButtonCarriesTheLanguageHeardAndADotForANewOne() {
        var inputs = inputs(speakers: [john], languages: [john: "en"], lanes: [lane(john, "uk", by: "@assistant-john:example.org")])
        #expect(NativeCallTranslationState(inputs).hasNewLanguage)
        #expect(NativeCallTranslationState(inputs).listeningLanguage == nil)

        inputs.seenLanguages = ["uk"]
        inputs.choice = .language("uk")
        let state = NativeCallTranslationState(inputs)
        #expect(!state.hasNewLanguage)
        #expect(state.listeningLanguage == "uk")
        #expect(state.badges == [john: "uk"])
    }

    @Test
    func aLanguageNobodyProducesIsHeardAsTheOriginal() {
        let state = translation(speakers: [john], languages: [john: "en"], choice: .language("uk"))
        #expect(state.listeningLanguage == nil)
        #expect(state.badges.isEmpty)
    }

    // MARK: - Coverage and the menu

    @Test
    func partialCoverageOffersTheOthersOnly() {
        // You speak Ukrainian; Mira English, Alex German, Bohdan Ukrainian. Bohdan's assistant translates Mira.
        let state = translation(speakers: [mira, alex, bohdan],
                                languages: [mira: "en", alex: "de", bohdan: "uk"],
                                lanes: [lane(mira, "uk", by: bohdanAgent, owner: bohdan)])
        let ukrainian = try? #require(state.options.first)
        #expect(ukrainian?.language == "uk")
        #expect(ukrainian?.covered == 1)
        #expect(ukrainian?.needed == 2)
        #expect(ukrainian?.isPartial == true)
        #expect(ukrainian?.producerOwners == [bohdan])
        #expect(state.production == .others(language: "uk", speakers: [alex]))
        // ADR-0094 D3: "Translate the others" is the same write; the server claims only what is missing.
        #expect(state.productionParams == .forLanguage("uk"))
    }

    /// L4: the menu is the call's audio tracks — the original, the translations there are (yours first), then "+".
    @Test
    func theMenuListsTheOriginalTheTracksAndAddOwnInOrder() {
        let state = translation(speakers: [mira, alex],
                                languages: [mira: "en", alex: "de"],
                                lanes: [lane(mira, "uk", by: bohdanAgent, owner: bohdan), lane(alex, "en", by: "@assistant-mira:example.org")],
                                block: .aiConsentOwner)
        let items = NativeCallTranslateMenuItem.items(state)
        #expect(items.count == 5)
        #expect(items.first == .original(isSelected: true))
        guard case .track(let first, false) = items[1], case .track(let second, false) = items[2] else {
            Issue.record("Expected the two tracks after the original")
            return
        }
        // Your language first.
        #expect(first.language == "uk")
        #expect(second.language == "en")
        #expect(items[3] == .own(isRunning: false))
        #expect(items.last == .spokenLanguage("uk"))
    }

    /// L4.5: no tracks yet, the menu is the original, "+" and what you speak.
    @Test
    func withNoTracksTheMenuIsTheOriginalAndAddOwn() {
        let state = translation(speakers: [john], languages: [john: "en"])
        #expect(NativeCallTranslateMenuItem.items(state) == [.original(isSelected: true), .own(isRunning: false), .spokenLanguage("uk")])
    }

    /// D6: a lane you listened to stopped. After the capsule's event, the menu keeps it as a stopped track, «Продолжить»,
    /// after the tracks there are; it goes once a lane carries the language again.
    @Test
    func aStoppedLaneStaysInTheMenuUntilALaneCarriesItsLanguage() {
        var inputs = inputs(speakers: [john, mira], languages: [john: "en", mira: "en"],
                            lanes: [lane(john, "de", by: "@assistant-x:example.org")])
        inputs.stoppedLanguages = ["uk"]
        let stopped = NativeCallTranslationState(inputs)
        #expect(stopped.stoppedTracks == ["uk"])
        let items = NativeCallTranslateMenuItem.items(stopped)
        #expect(items.count == 5)
        #expect(items[2] == .stopped(language: "uk"))
        #expect(items[3] == .own(isRunning: false))
        #expect(items.last == .spokenLanguage("uk"))

        inputs.lanes.append(lane(john, "uk", by: myAgent, owner: me))
        let carried = NativeCallTranslationState(inputs)
        #expect(carried.stoppedTracks.isEmpty)
        #expect(!NativeCallTranslateMenuItem.items(carried).contains(.stopped(language: "uk")))
    }

    @Test
    func yourOwnLaneIsYoursNotFreeAndKeepsItsSpeakersOnTheNextWrite() {
        let state = translation(speakers: [john, mira],
                                languages: [john: "en", mira: "en"],
                                lanes: [lane(john, "uk", by: myAgent, owner: me)])
        #expect(state.options.first?.isYours == true)
        #expect(state.options.first?.producers.isEmpty == true)
        #expect(state.ownLanguage == "uk")
        #expect(state.production == .others(language: "uk", speakers: [mira]))
        #expect(state.productionParams == .forLanguage("uk"))
    }

    /// D3: a speaker whose language is unknown is translated into L.
    @Test
    func withoutLanguagesEveryoneElseNeedsYours() {
        let state = translation(speakers: [john], languages: [:])
        #expect(state.production == .myLanguage("uk"))
        #expect(state.productionParams == .forLanguage("uk"))
    }

    @Test
    func nobodyIsTranslatedIntoTheirOwnLanguage() {
        let state = translation(speakers: [bohdan, john], languages: [bohdan: "uk", john: "en"])
        #expect(state.production == .myLanguage("uk"))
        #expect(state.uncoveredSpeakers == [john])
    }

    // MARK: - Nothing to translate (operator, 2026-11-15)

    /// A 1:1 with someone who speaks your language: the platform would only stand by, so there is nothing to produce.
    @Test
    func aOneToOneInYourLanguageHasNothingToTranslate() {
        let state = translation(speakers: [bohdan], languages: [bohdan: "uk"])
        #expect(state.isNothingToTranslate(into: "uk"))
        #expect(state.production == nil)
    }

    @Test
    func aGroupThatAllSpeaksTheLanguageHasNothingToTranslate() {
        let state = translation(speakers: [bohdan, john, mira], languages: [bohdan: "uk", john: "uk", mira: "uk"])
        #expect(state.isNothingToTranslate(into: "uk"))
        #expect(state.production == nil)
    }

    /// D3: the backend opens a lane for someone who hasn't published a language, so there is something to translate.
    @Test
    func oneUnknownLanguageLeavesSomethingToTranslate() {
        let state = translation(speakers: [bohdan, john], languages: [bohdan: "uk"])
        #expect(!state.isNothingToTranslate(into: "uk"))
        #expect(state.production == .myLanguage("uk"))
    }

    @Test
    func anotherLanguageLeavesSomethingToTranslate() {
        let state = translation(speakers: [bohdan, john], languages: [bohdan: "uk", john: "en"])
        #expect(!state.isNothingToTranslate(into: "uk"))
        #expect(state.isNothingToTranslate(into: "en") == false)
    }

    /// The backend's `same_spoken_language`: the base subtag, case- and separator-blind — `zh-Hans` and `zh-Hant` are
    /// one spoken language, as are `uk_UA` and `uk`.
    @Test
    func theLanguageMatchesByBaseSubtagLikeTheBackend() {
        #expect(NativeCallTranslationState.isNothingToTranslate(into: "zh-Hans", speakers: [john], languages: [john: "zh-Hant"]))
        #expect(NativeCallTranslationState.isNothingToTranslate(into: "uk", speakers: [john], languages: [john: "uk_UA"]))
        #expect(NativeCallTranslationState.isNothingToTranslate(into: "PT-br", speakers: [john], languages: [john: "pt-PT"]))
        #expect(!NativeCallTranslationState.isNothingToTranslate(into: "zh-Hans", speakers: [john], languages: [john: "ja"]))
    }

    /// Alone in the call isn't "everyone speaks it": nobody else is there to say so about.
    @Test
    func nobodyElseInTheCallIsNotNothingToTranslate() {
        #expect(!NativeCallTranslationState.isNothingToTranslate(into: "uk", speakers: [], languages: [:]))
        #expect(!translation(speakers: [me], languages: [me: "uk"]).isNothingToTranslate(into: "uk"))
    }

    /// Row 1, D3: exact codes everywhere, the base subtag only for "the same spoken language" — a `pt-PT` speaker isn't
    /// translated into `pt-BR`, and a `pt-BR` lane isn't a `pt-PT` one.
    @Test
    func theSameSpokenLanguageIsTheBaseSubtagButLanesKeepTheirExactCode() {
        var inputs = inputs(speakers: [john, mira], languages: [john: "pt-PT", mira: "en"], lanes: [lane(mira, "pt-PT", by: "@assistant-x:example.org")])
        inputs.myLanguage = "pt-BR"
        let state = NativeCallTranslationState(inputs)
        #expect(state.uncoveredSpeakers == [mira])
        #expect(state.options.map(\.language) == ["pt-PT"])
        #expect(state.productionParams == .forLanguage("pt-BR"))
    }

    /// Rows 4–5: the lanes come from the live v6 documents only, one producer each, with the owner they name; the pocket
    /// interpreter and a leaving or standing-by agent offer none.
    @Test
    func lanesComeFromLiveDocumentsAndSkipTheInterpreter() {
        let live = SpiralAgentStateReader.AgentClaim.make(translation: .producing("uk", speakers: [john, mira], owner: me))
        let interpreter = SpiralAgentStateReader.AgentClaim.make(translation: .init(isActive: true, style: .consecutive, source: .override, forLanguage: nil,
                                                                                    pocket: ["fr", "uk"], owner: alex,
                                                                                    lanes: [.init(speaker: alex, language: "fr")], stoppedReason: nil))
        let leaving = SpiralAgentStateReader.AgentClaim.make(translation: .producing("de", speakers: [john]), lifecycle: .leaving)
        let lanes = NativeCallTranslationLane.lanes(documents: [myAgent: live, "@assistant-x:example.org": interpreter, bohdanAgent: leaving])
        #expect(lanes.map(\.speaker) == [john, mira])
        #expect(lanes.allSatisfy { $0.language == "uk" && $0.owner == me && $0.producer == myAgent && $0.input == .voice })
    }

    // MARK: - Stops (row 6)

    /// D6: a stop while the agent stays, and the reasons mapped for the capsule.
    @Test(arguments: [(VoiceTranslationStopReason.ownerStopped, NativeCallTranslationStop.Reason.stoppedByOwner),
                      (.ownerLeft, .ownerLeft), (.aiLimit, .limitReached), (.translationPaused, .limitReached),
                      (.callCap, .limitReached), (.ended, .ended)])
    func aStopWhileTheAgentStaysIsRecordedWithItsReason(reason: VoiceTranslationStopReason, expected: NativeCallTranslationStop.Reason) {
        var history = NativeCallTranslationStopHistory()
        history.update(documents: [bohdanAgent: .make(translation: .producing("uk", speakers: [mira], owner: bohdan))])
        #expect(history.stops.isEmpty)

        let stopped = SpiralAgentStateReader.TranslationClaim(isActive: false, style: nil, source: .override, forLanguage: "uk", pocket: nil,
                                                              owner: bohdan, lanes: [], stoppedReason: reason)
        history.update(documents: [bohdanAgent: .make(translation: stopped, recording: true)])
        #expect(history.stops.map(\.reason) == [expected])
        #expect(history.stops.first?.language == "uk")
        #expect(history.stops.first?.owner == bohdan)
        #expect(history.stops.first?.speakers == [mira])
    }

    /// D6: an agent that leaves with a reason, or vanishes without one (`ended`), still names its lanes and owner: its
    /// last document is kept.
    @Test
    func anAgentThatLeavesOrVanishesKeepsItsLastLanes() {
        var history = NativeCallTranslationStopHistory()
        let producing = SpiralAgentStateReader.AgentClaim.make(translation: .producing("uk", speakers: [mira], owner: bohdan))
        history.update(documents: [bohdanAgent: producing])
        history.update(documents: [bohdanAgent: .make(lifecycle: .leaving, leavingReason: .ownerLeft)])
        history.update(documents: [:])
        #expect(history.stops.map(\.reason) == [.ownerLeft])
        #expect(history.stops.first?.speakers == [mira])

        history.update(documents: [bohdanAgent: producing])
        history.update(documents: [:])
        #expect(history.stops.map(\.reason) == [.ownerLeft, .ended])
        #expect(Set(history.stops.map(\.id)).count == 2)
    }

    /// A producer that stands by, or whose lanes moved elsewhere, didn't stop.
    @Test
    func aProducerGoingToStandbyIsNoStop() {
        var history = NativeCallTranslationStopHistory()
        history.update(documents: [bohdanAgent: .make(translation: .producing("uk", speakers: [mira], owner: bohdan))])
        let standby = SpiralAgentStateReader.TranslationClaim(isActive: false, style: .simultaneous, source: .roomTool, forLanguage: "uk", pocket: nil,
                                                              owner: bohdan, lanes: [], stoppedReason: nil)
        history.update(documents: [bohdanAgent: .make(translation: standby)])
        history.update(documents: [:])
        #expect(history.stops.isEmpty)
    }

    // MARK: - Blocked starts

    @Test(arguments: [(NativeAgentCenterJoinFailure.paused, NativeCallTranslationBlock?.some (.paused)),
                      (.aiConsentOwner, .aiConsentOwner),
                      (.aiConsentRoom, .aiConsentRoom),
                      (.budgetReached, .limit),
                      (.categoryPaused(.callTranslation, nil), .translationPaused),
                      (.categoryPaused(.calls, nil), .limit),
                      (.askToJoin, nil),
                      (.failed, nil)])
    func aStartFailureBlocksTranslationWithItsReason(failure: NativeAgentCenterJoinFailure, block: NativeCallTranslationBlock?) {
        #expect(NativeCallTranslationBlock(failure) == block)
    }

    @Test
    func talkingGreysTranslationAndTranslatingGreysTalk() {
        let talking = NativeCallAssistantDockState(.init(isTalking: true, block: .talking))
        #expect(talking.buttons.first { $0.job == .translation }?.isEnabled == false)
        #expect(talking.buttons.first { $0.job == .translation }?.isRefused == false)

        let translating = NativeCallAssistantDockState(.init(isTranslating: true))
        #expect(translating.buttons.first { $0.job == .conversation }?.isEnabled == false)
        #expect(translating.buttons.first { $0.job == .translation }?.isOn == true)

        // D11: a stopped intent not turned off keeps Talk dimmed too.
        let stopped = NativeCallAssistantDockState(.init(isTalkUnavailable: true))
        #expect(stopped.buttons.first { $0.job == .conversation }?.isEnabled == false)
    }

    /// Row 11: while the runtime hasn't taken the new mode, the translation button carries the pending ring, not the fill.
    @Test
    func syncingRingsTheTranslationButton() {
        let syncing = NativeCallAssistantDockState(.init(isTranslating: true, isTranslationSyncing: true))
        #expect(syncing.buttons.first { $0.job == .translation }?.isPending == true)
        #expect(syncing.buttons.first { $0.job == .translation }?.isOn == false)
        let settled = NativeCallAssistantDockState(.init(isTranslating: true))
        #expect(settled.buttons.first { $0.job == .translation }?.isPending == false)
    }

    @Test
    func aBlockMarksTranslationRedAndAReadOnlyPageTapsNothing() {
        let blocked = NativeCallAssistantDockState(.init(block: .aiConsentOwner))
        #expect(blocked.buttons.first { $0.job == .translation }?.isRefused == true)
        #expect(blocked.buttons.filter(\.isRefused).count == 1)

        let theirs = NativeCallAssistantDockState(.init(isTranslating: true, isRecording: true, isReadOnly: true))
        #expect(theirs.buttons.allSatisfy { !$0.isEnabled })
        #expect(theirs.buttons.filter(\.isOn).map(\.job) == [.translation, .recording])
    }

    // MARK: - Capsule events

    @Test
    func someoneElsesLaneIntoYourLanguageBringsListen() {
        let before = translation(speakers: [john], languages: [john: "en"])
        let after = translation(speakers: [john], languages: [john: "en"], lanes: [lane(john, "uk", by: "@assistant-john:example.org", owner: john)])
        let events = NativeCallCapsuleEvent.events(from: before, to: after, newStops: [], heardLanguage: nil, ownAgents: [myAgent])
        #expect(events == [.translationAvailable(language: "uk", producer: "@assistant-john:example.org", owner: john)])
        #expect(events.first?.action == .listen(language: "uk"))
    }

    @Test
    func anotherLanguageOnlyGetsTheDot() {
        let before = translation(speakers: [mira], languages: [mira: "en"])
        let after = translation(speakers: [mira], languages: [mira: "en"], lanes: [lane(mira, "de", by: "@assistant-x:example.org")])
        #expect(NativeCallCapsuleEvent.events(from: before, to: after, newStops: [], heardLanguage: nil, ownAgents: []).isEmpty)
        #expect(after.hasNewLanguage)
    }

    @Test
    func theLaneYouHeardStoppingBringsContinueOnlyForThatLanguage() {
        let before = translation(speakers: [john], languages: [john: "en"], lanes: [lane(john, "uk", by: "@assistant-john:example.org", owner: john)],
                                 choice: .language("uk"))
        let after = translation(speakers: [john], languages: [john: "en"])
        let stop = NativeCallTranslationStop(id: 1, language: "uk", producer: "@assistant-john:example.org", owner: john, speakers: [john], reason: .limitReached)
        let other = NativeCallTranslationStop(id: 2, language: "de", producer: "@assistant-x:example.org", owner: nil, speakers: [john], reason: .stoppedByOwner)
        let events = NativeCallCapsuleEvent.events(from: before, to: after, newStops: [stop, other], heardLanguage: "uk", ownAgents: [myAgent])
        #expect(events == [.translationStopped(language: "uk", producer: "@assistant-john:example.org", owner: john, reason: .limitReached)])
        #expect(events.first?.action == .continueTranslation(language: "uk"))
    }

    @Test
    func yourOwnAssistantStartingSaysWhomItTranslates() {
        let before = translation(speakers: [john], languages: [john: "en"])
        let after = translation(speakers: [john], languages: [john: "en"], lanes: [lane(john, "uk", by: myAgent, owner: me)])
        let events = NativeCallCapsuleEvent.events(from: before, to: after, newStops: [], heardLanguage: nil, ownAgents: [myAgent])
        #expect(events == [.ownTranslating(language: "uk", speakers: [john])])
        #expect(events.first?.action == nil)
    }

    @Test
    func theQueueShowsOneEventAtATimeInOrderWithoutRepeats() {
        var queue = NativeCallCapsuleQueue()
        let tool = NativeCallCapsuleEvent.toolSwitchedOn(language: "uk")
        let listen = NativeCallCapsuleEvent.translationAvailable(language: "uk", producer: "@a:x", owner: nil)
        let shown = [queue.enqueue(tool), queue.enqueue(listen), queue.enqueue(tool), queue.enqueue(listen)]
        #expect(shown == [true, false, false, false])
        #expect(queue.current == tool)
        #expect(queue.pending == [listen])

        queue.advance()
        #expect(queue.current == listen)
        queue.advance()
        #expect(queue.current == nil)
    }

    @Test
    func aStaleEventIsDroppedFromTheQueue() {
        var queue = NativeCallCapsuleQueue()
        let listen = NativeCallCapsuleEvent.translationAvailable(language: "uk", producer: "@a:x", owner: nil)
        queue.enqueue(.toolSwitchedOn(language: "uk"))
        queue.enqueue(listen)
        queue.drop { $0 == listen }
        #expect(queue.pending.isEmpty)
        queue.drop { _ in true }
        #expect(queue.current == nil)
    }

    // MARK: - Someone translates you (question 409)

    @Test
    func aLaneForYourVoiceInAGroupCallSaysWhoTranslatesYouOnce() {
        let state = groupTranslation(lanes: [lane(me, "en", by: miraAgent, owner: mira)])
        #expect(state.yourTranslator == .init(agent: miraAgent, owner: mira))

        let event = NativeCallCapsuleEvent.spokenLanguageEvent(state, announced: nil, isLanguageChosen: false)
        #expect(event == .translatingYou(language: "uk", producer: miraAgent, owner: mira, isConfirmation: false))
        #expect(event?.action == .changeSpokenLanguage)
        #expect(event?.agent(ownAgent: myAgent) == miraAgent)
        // Said once: the language it named is still yours.
        #expect(NativeCallCapsuleEvent.spokenLanguageEvent(state, announced: "uk", isLanguageChosen: false) == nil)
    }

    @Test
    func changingYourLanguageIsConfirmedWithoutAnAction() {
        var inputs = groupInputs(lanes: [lane(me, "en", by: miraAgent, owner: mira)])
        inputs.myLanguage = "ru"
        let event = NativeCallCapsuleEvent.spokenLanguageEvent(NativeCallTranslationState(inputs), announced: "uk", isLanguageChosen: false)
        #expect(event == .translatingYou(language: "ru", producer: miraAgent, owner: mira, isConfirmation: true))
        #expect(event?.action == nil)
    }

    @Test
    func aOneToOneCallSaysItAndThePrivateCallDoesnt() {
        let lanes = [lane(me, "en", by: johnAgent, owner: john)]
        var direct = inputs(speakers: [john], languages: [john: "en"], lanes: lanes)
        #expect(NativeCallTranslationState(direct).yourTranslator == .init(agent: johnAgent, owner: john))
        #expect(NativeCallCapsuleEvent.spokenLanguageEvent(NativeCallTranslationState(direct), announced: nil, isLanguageChosen: false)
            == .translatingYou(language: "uk", producer: johnAgent, owner: john, isConfirmation: false))
        #expect(NativeCallTranslateMenuItem.items(NativeCallTranslationState(direct)).contains(.spokenLanguage("uk")))

        // The pocket interpreter: your own assistant, the call with it alone.
        direct.isPrivateCall = true
        #expect(NativeCallTranslationState(direct).yourTranslator == nil)
        #expect(NativeCallCapsuleEvent.spokenLanguageEvent(NativeCallTranslationState(direct), announced: nil, isLanguageChosen: false) == nil)
    }

    /// A language you picked is yours: the capsule doesn't ask; the menu's «Я говорю» stays.
    @Test
    func aPickedLanguageIsNeverAskedAbout() {
        let state = groupTranslation(lanes: [lane(me, "en", by: miraAgent, owner: mira)])
        #expect(NativeCallCapsuleEvent.spokenLanguageEvent(state, announced: nil, isLanguageChosen: true) == nil)
        #expect(NativeCallTranslateMenuItem.items(state).contains(.spokenLanguage("uk")))
        // Picked from the capsule's «Змінити»: confirmed, once.
        var inputs = groupInputs(lanes: [lane(me, "en", by: miraAgent, owner: mira)])
        inputs.myLanguage = "ru"
        #expect(NativeCallCapsuleEvent.spokenLanguageEvent(NativeCallTranslationState(inputs), announced: "uk", isLanguageChosen: true)
            == .translatingYou(language: "ru", producer: miraAgent, owner: mira, isConfirmation: true))
    }

    @Test
    func onlyALaneForYourVoiceFromSomeoneElsesAssistantCounts() {
        // Lanes for other speakers, and your own assistant's: nobody translates you.
        let state = groupTranslation(lanes: [lane(alex, "en", by: miraAgent, owner: mira),
                                             lane(mira, "uk", by: myAgent, owner: me),
                                             lane(me, "de", by: myAgent, owner: me)])
        #expect(state.yourTranslator == nil)
        #expect(NativeCallCapsuleEvent.spokenLanguageEvent(state, announced: nil, isLanguageChosen: false) == nil)
    }

    @Test
    func severalAssistantsTranslatingYouMakeOneEventFromTheFirst() {
        let state = groupTranslation(lanes: [lane(me, "en", by: miraAgent, owner: mira),
                                             lane(me, "de", by: alexAgent, owner: alex),
                                             lane(me, "fr", by: miraAgent, owner: mira)])
        #expect(NativeCallCapsuleEvent.spokenLanguageEvent(state, announced: nil, isLanguageChosen: false)
            == .translatingYou(language: "uk", producer: miraAgent, owner: mira, isConfirmation: false))
    }

    @Test
    func anEventAboutYourVoiceGoesStaleWhenNobodyTranslatesYouOrYourLanguageChanges() {
        let event = NativeCallCapsuleEvent.translatingYou(language: "uk", producer: miraAgent, owner: mira, isConfirmation: false)
        #expect(!event.isStale(in: groupTranslation(lanes: [lane(me, "en", by: miraAgent, owner: mira)])))
        #expect(event.isStale(in: groupTranslation(lanes: [])))

        var inputs = groupInputs(lanes: [lane(me, "en", by: miraAgent, owner: mira)])
        inputs.myLanguage = "ru"
        #expect(event.isStale(in: NativeCallTranslationState(inputs)))
        #expect(!NativeCallCapsuleEvent.toolSwitchedOn(language: "uk").isStale(in: NativeCallTranslationState(inputs)))
    }

    @Test
    func theEventWaitsItsTurnBehindAnotherAndIsDroppedOnceStale() {
        var queue = NativeCallCapsuleQueue()
        let listen = NativeCallCapsuleEvent.translationAvailable(language: "uk", producer: bohdanAgent, owner: bohdan)
        let translatingYou = NativeCallCapsuleEvent.translatingYou(language: "uk", producer: miraAgent, owner: mira, isConfirmation: false)
        let shown = [queue.enqueue(listen), queue.enqueue(translatingYou)]
        #expect(shown == [true, false])
        #expect(queue.pending == [translatingYou])

        // You changed your language before its turn: it no longer holds, the confirmation does.
        var inputs = groupInputs(lanes: [lane(me, "en", by: miraAgent, owner: mira)])
        inputs.myLanguage = "ru"
        queue.drop { $0.isStale(in: NativeCallTranslationState(inputs)) }
        #expect(queue.pending.isEmpty)
        #expect(queue.current == listen)
    }

    @Test
    func theMenuSaysWhatYouSpeakWhileSomeoneTranslatesYou() {
        let translated = groupTranslation(lanes: [lane(me, "en", by: miraAgent, owner: mira)])
        #expect(translated.isButtonVisible)
        #expect(NativeCallTranslateMenuItem.items(translated) == [.original(isSelected: true), .own(isRunning: false), .spokenLanguage("uk")])
    }

    /// Operator, 2026-11-12: wherever the 文A button shows, «Я говорю» is in its menu — nobody translating you and a
    /// language you picked long ago don't hide it.
    @Test
    func theMenuAlwaysSaysWhatYouSpeak() {
        let notTranslated = groupTranslation(lanes: [lane(alex, "en", by: miraAgent, owner: mira)])
        #expect(notTranslated.isButtonVisible)
        #expect(NativeCallTranslateMenuItem.items(notTranslated).contains(.spokenLanguage("uk")))

        let chosen = NativeCallTranslationState(inputs(speakers: [john], languages: [john: "en"]))
        #expect(chosen.isButtonVisible)
        #expect(NativeCallTranslateMenuItem.items(chosen).contains(.spokenLanguage("uk")))
    }

    /// An unconfirmed language never makes the 文A button appear on its own account.
    @Test
    func theMenuAsksYourLanguageWhileItIsTheDefault() {
        var inputs = inputs(speakers: [john], languages: [john: "en"])
        inputs.isLanguageChosen = false
        let state = NativeCallTranslationState(inputs)
        #expect(NativeCallTranslateMenuItem.items(state) == [.original(isSelected: true), .own(isRunning: false), .spokenLanguage("uk")])

        var sameLanguage = self.inputs(speakers: [bohdan], languages: [bohdan: "uk"])
        sameLanguage.isLanguageChosen = false
        #expect(!NativeCallTranslationState(sameLanguage).isButtonVisible)
    }

    /// Option A, C2: with your assistant translating, the last action opens it — «Ваш переклад…».
    @Test
    func theMenusOwnItemSaysYoursRunsOnceItDoes() {
        var inputs = inputs(speakers: [john], languages: [john: "en"], lanes: [lane(john, "uk", by: myAgent, owner: me)])
        inputs.isOwnTranslating = true
        #expect(NativeCallTranslateMenuItem.items(NativeCallTranslationState(inputs)).contains(.own(isRunning: true)))
    }

    // MARK: - Every language list's suggestions (operator, 2026-11-12)

    /// The selected language first, then the phone's, then the keyboards', as the catalog has them, one per spoken
    /// language, capped — «Я говорю»'s four.
    @Test
    func suggestionsAreTheSelectedThenThePhonesThenTheKeyboards() {
        let catalog = ["en", "uk", "ru", "de", "pl", "fr", "pt-BR", "pt-PT"]
        let languages = SuggestedLanguages.codes(selected: "ru",
                                                 preferred: ["uk-UA", "ru-RU", "ja-JP"],
                                                 keyboards: ["uk-UA", "emoji", "dictation", "de-DE", "pl-PL", "fr-FR"],
                                                 catalog: catalog,
                                                 limit: 4)
        #expect(languages == ["ru", "uk", "de", "pl"])
        // One per spoken language, in the catalog's exact form.
        #expect(SuggestedLanguages.codes(selected: "pt-BR", preferred: ["pt-PT", "pt_BR", "en-GB"], keyboards: [], catalog: catalog, limit: 5)
            == ["pt-BR", "en"])
    }

    /// Nothing is made up: no English, Ukrainian or Russian the person doesn't use, and nothing outside the catalog.
    @Test
    func suggestionsHaveNoFallback() {
        #expect(SuggestedLanguages.codes(selected: nil, preferred: ["ja-JP"], keyboards: ["emoji"], catalog: ["en", "uk", "ru"], limit: 5).isEmpty)
        #expect(SuggestedLanguages.codes(selected: "uk", preferred: [], keyboards: [], catalog: ["en", "uk"], limit: 4) == ["uk"])
    }

    /// The call's language pages: the free languages, or my own for the neighbour, aren't suggested again.
    @Test
    func theCallsLanguagePagesSuggestWithoutTheirExclusions() {
        let catalog: [VoiceControlsCatalogLanguage] = ["en", "uk", "ru", "de"].map { .init(code: $0, label: $0) }
        #expect(NativeCallLanguagePage.suggested(selected: "uk", catalog: catalog, excluding: ["en"], preferred: ["en-US", "ru-RU"], keyboards: ["de-DE"])
            == ["uk", "ru", "de"])
        #expect(NativeCallLanguagePage.suggested(selected: nil, catalog: catalog, excluding: ["uk"], preferred: ["uk-UA", "en-US"], keyboards: [])
            == ["en"])
    }

    /// The chat tool's list: the suggestions without a search, none with one.
    @Test
    func theChatToolsListSuggestsUntilASearch() {
        let languages = ["en", "uk", "de"]
        #expect(CallTranslationLanguageList.suggested(selected: "de", languages: languages, query: "", preferred: ["uk-UA"], keyboards: ["en-US"])
            == ["de", "uk", "en"])
        #expect(CallTranslationLanguageList.suggested(selected: "de", languages: languages, query: "укр", preferred: ["uk-UA"], keyboards: []).isEmpty)
    }

    @Test
    func theMenuButtonShowsForALaneOfYourVoiceAlone() {
        // Everyone speaks Ukrainian, and only Mira's assistant translates you: the button is the way to «Я говорю».
        let state = groupTranslation(languages: [mira: "uk", alex: "uk"], lanes: [lane(me, "en", by: miraAgent, owner: mira)])
        #expect(state.options.isEmpty)
        #expect(state.isButtonVisible)
    }

    // MARK: - Helpers

    private func groupInputs(languages: [String: String]? = nil,
                             lanes: [NativeCallTranslationLane]) -> NativeCallTranslationState.Inputs {
        self.inputs(speakers: [mira, alex], languages: languages ?? [mira: "en", alex: "de"], lanes: lanes)
    }

    private func groupTranslation(languages: [String: String]? = nil,
                                  lanes: [NativeCallTranslationLane]) -> NativeCallTranslationState {
        NativeCallTranslationState(groupInputs(languages: languages, lanes: lanes))
    }

    private func inputs(speakers: [String],
                        languages: [String: String],
                        lanes: [NativeCallTranslationLane] = [],
                        choice: NativeCallListeningChoice = .original,
                        block: NativeCallTranslationBlock? = nil) -> NativeCallTranslationState.Inputs {
        NativeCallTranslationState.Inputs(ownUserID: me,
                                          myLanguage: "uk",
                                          speakers: speakers,
                                          languages: languages,
                                          lanes: lanes,
                                          ownAgents: [myAgent],
                                          choice: choice,
                                          block: block)
    }

    private func translation(speakers: [String],
                             languages: [String: String] = [:],
                             lanes: [NativeCallTranslationLane] = [],
                             choice: NativeCallListeningChoice = .original,
                             block: NativeCallTranslationBlock? = nil) -> NativeCallTranslationState {
        NativeCallTranslationState(inputs(speakers: speakers, languages: languages, lanes: lanes, choice: choice, block: block))
    }

    private func lane(_ speaker: String, _ language: String, by producer: String, owner: String? = nil) -> NativeCallTranslationLane {
        NativeCallTranslationLane(speaker: speaker, input: .voice, language: language, producer: producer, owner: owner)
    }
}
