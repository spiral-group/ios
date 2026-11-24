//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

#if DEBUG || SPIRAL_STAGING

import AVFoundation
import Combine
@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0085): the live lab's call, end to end through the real view model and controller.

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NativeCallTranslationLabTests {
    @Test
    func theButtonShowsOnceThePlatformAnswersInACallWithAnotherLanguage() async {
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
        let lab = NativeCallAssistantsLiveLab(backend: NativeCallAssistantsLabBackend(cast: .onePerson, role: .moderator, latency: .none))
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        await waitUntil { lab.viewModel.context.viewState.translation.isButtonVisible }

        #expect(lab.viewModel.context.viewState.agentCenter.translationFacts.languages[NativeCallAssistantsLabBackend.john] == "en")
        let state = lab.viewModel.context.viewState
        #expect(state.translation.speakers == [NativeCallAssistantsLabBackend.john])
        #expect(state.translation.myLanguage == "uk")
        #expect(state.scope == .direct)
        #expect(state.translation.isButtonVisible)
    }

    /// Scenario 1.2 → 1.3: "Translate into Ukrainian" brings your assistant, and you hear it as soon as it runs.
    @Test(arguments: [NativeCallAssistantsLabBackend.Latency.none, .short])
    func translatingIntoYourLanguageBringsYourAssistantAndYouHearIt(latency: NativeCallAssistantsLabBackend.Latency) async {
        let lab = makeLab(.onePerson, latency: latency)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        await waitUntil { lab.viewModel.context.viewState.translation.isButtonVisible }

        lab.viewModel.context.send(viewAction: .produceTranslation)
        await waitUntil(seconds: 8) { lab.viewModel.context.viewState.translation.listeningLanguage == "uk" }

        let state = lab.viewModel.context.viewState
        #expect(state.listeningChoice == .language("uk"))
        #expect(state.translation.ownLanguage == "uk")
        #expect(state.capsule.current == .ownTranslating(language: "uk", speakers: [NativeCallAssistantsLabBackend.john]))
    }

    /// Scenarios 3.1 and 4.1: someone else's lane brings "Listen"; when it stops, you are back on the original with
    /// "Continue".
    @Test
    func someoneElsesLaneOffersListenAndItsStopOffersContinue() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }

        lab.backend.startForeignTranslation()
        await waitUntil { lab.viewModel.context.viewState.capsule.current != nil }
        #expect(lab.viewModel.context.viewState.capsule.current
            == .translationAvailable(language: "uk", producer: NativeCallAssistantsLabBackend.bohdanAgent, owner: NativeCallAssistantsLabBackend.bohdan))

        lab.viewModel.context.send(viewAction: .runCapsuleAction)
        #expect(lab.viewModel.context.viewState.translation.listeningLanguage == "uk")
        #expect(lab.viewModel.context.viewState.translation.badges == [NativeCallAssistantsLabBackend.mira: "uk"])

        lab.backend.stopForeignTranslation(reason: .aiLimit)
        await waitUntil { lab.viewModel.context.viewState.capsule.current != nil }
        // D10: the language holds for the takeover window first; nobody takes it over here.
        await waitUntil(seconds: 6) { lab.viewModel.context.viewState.listeningChoice == .original }
        #expect(lab.viewModel.context.viewState.listeningChoice == .original)
        #expect(lab.viewModel.context.viewState.capsule.current
            == .translationStopped(language: "uk", producer: NativeCallAssistantsLabBackend.bohdanAgent,
                                   owner: NativeCallAssistantsLabBackend.bohdan, reason: .limitReached))
    }

    /// Row 6 (ADR-0094 D6): the owner of the lane you hear left the call; its assistant leaves too, and you are back on
    /// the original with "The owner left · Continue", from its last document.
    @Test
    func theOwnerLeavingStopsTheLaneYouHearWithItsReason() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        lab.backend.startForeignTranslation()
        await waitUntil { lab.viewModel.context.viewState.translation.options.contains { $0.language == "uk" } }
        lab.viewModel.context.send(viewAction: .setListeningChoice(.language("uk")))

        lab.backend.stopForeignTranslation(reason: .ownerLeft)
        await waitUntil(seconds: 6) { lab.viewModel.context.viewState.listeningChoice == .original }
        await waitUntil { lab.viewModel.context.viewState.capsule.current?.action == .continueTranslation(language: "uk") }

        #expect(lab.viewModel.context.viewState.capsule.current
            == .translationStopped(language: "uk", producer: NativeCallAssistantsLabBackend.bohdanAgent,
                                   owner: NativeCallAssistantsLabBackend.bohdan, reason: .ownerLeft))
    }

    /// Scenario 5.2: the chat's tool switches translation on at the call's start, and says so with "Cancel".
    @Test
    func theChatsToolSwitchesTranslationOnAtTheStart() async {
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
        let backend = NativeCallAssistantsLabBackend(cast: .onePerson, role: .moderator, latency: .none,
                                                     tool: NativeCallTranslationTool(isEnabled: true, language: "uk", translatesIfNobodyDoes: true),
                                                     joinDuration: .milliseconds(10))
        let lab = NativeCallAssistantsLiveLab(backend: backend)
        await waitUntil { lab.viewModel.context.viewState.capsule.current != nil }

        #expect(lab.viewModel.context.viewState.capsule.current == .toolSwitchedOn(language: "uk"))
        await waitUntil { lab.viewModel.context.viewState.translation.listeningLanguage == "uk" }
        #expect(lab.viewModel.context.viewState.translation.ownLanguage == "uk")
    }

    /// L2: in a group, the capsule shows the assistant producing what you hear — Bohdan's Ukrainian, not Mira's English.
    @Test
    func theCapsuleShowsTheProducerOfWhatYouHear() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        #expect(lab.viewModel.context.viewState.agentBlock?.agentUserID == NativeCallAssistantsLabBackend.miraAgent)

        lab.backend.startForeignTranslation()
        await waitUntil { lab.viewModel.context.viewState.translation.options.contains { $0.language == "uk" } }
        lab.viewModel.context.send(viewAction: .setListeningChoice(.language("uk")))

        #expect(lab.viewModel.context.viewState.agentBlock?.agentUserID == NativeCallAssistantsLabBackend.bohdanAgent)
    }

    /// L1: the language picked in the sheet is the one your assistant produces, and the one you hear.
    @Test
    func changingYourLanguageMovesYourTranslationToIt() async {
        let lab = makeLab(.onePerson)
        await waitUntil { lab.viewModel.context.viewState.translation.isButtonVisible }
        lab.viewModel.context.send(viewAction: .produceTranslation)
        await waitUntil(seconds: 8) { lab.viewModel.context.viewState.translation.listeningLanguage == "uk" }

        lab.viewModel.context.send(viewAction: .setMyLanguage("de"))
        await waitUntil(seconds: 8) { lab.viewModel.context.viewState.translation.ownLanguage == "de" }

        #expect(lab.viewModel.context.viewState.translation.ownLanguage == "de")
        await waitUntil { lab.viewModel.context.viewState.translation.listeningLanguage == "de" }
        #expect(lab.viewModel.context.viewState.listeningChoice == .language("de"))
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// L4.3: a language someone else already translates everyone into is heard, free — your assistant isn't called.
    @Test
    func aLanguageAlreadyTranslatedIsHeardNotProducedAgain() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        lab.viewModel.context.send(viewAction: .setMyLanguage("en"))
        #expect(lab.viewModel.context.viewState.translation.production == nil)

        lab.viewModel.context.send(viewAction: .produceTranslation)

        #expect(lab.viewModel.context.viewState.listeningChoice == .language("en"))
        #expect(lab.viewModel.context.viewState.attachesSent.isEmpty)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Operator, 2026-11-15: Start in a 1:1 with someone who speaks the language «Translate into» names asks the platform
    /// for nothing — it would only stand by — and the sheet says why in the buttons' place. «Got it» brings the buttons
    /// back with translation off. Since 1.0.3 the Translation button itself only brings its question back: the card
    /// comes from Start (operator, 2026-11-21).
    @Test
    func translationIntoALanguageEveryoneSpeaksSendsNothingAndSaysWhy() async throws {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        // John speaks English.
        context.send(viewAction: .setMyLanguage("en"))
        context.send(viewAction: .showAgentCenter)

        context.send(viewAction: .tapAssistantJob(.translation))
        #expect(context.assistantConfirmation == .start(.translation))
        #expect(context.viewState.attachesSent.isEmpty)

        context.send(viewAction: .produceTranslation)

        #expect(context.assistantConfirmation == .nothingToTranslate)
        #expect(context.isAgentCenterPresented)
        #expect(context.viewState.attachesSent.isEmpty)
        #expect(lab.backend.ownSession == nil)
        let card = try #require(NativeCallAssistantsCopy.nothingToTranslateCard(context.viewState.translation, context: context))
        #expect(card.title == UntranslatedL10n.screenNativeCallAssistantsNothingToTranslateOne("John", NativeCallTranslationCopy.languageName("en")))
        #expect(card.detail == UntranslatedL10n.screenNativeCallAssistantsNothingToTranslateDetail)

        // «Got it».
        context.assistantConfirmation = nil
        #expect(context.viewState.agents.ownAgents.first?.shown.isTranslating != true)
        #expect(lab.backend.ownSession == nil)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// The card closes on its own once there is something to translate: here «Translate into» moved to Ukrainian.
    @Test
    func theNothingToTranslateCardClosesOnceSomeoneNeedsTheLanguage() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .setMyLanguage("en"))
        context.send(viewAction: .showAgentCenter)
        context.send(viewAction: .produceTranslation)
        #expect(context.assistantConfirmation == .nothingToTranslate)

        context.send(viewAction: .setMyLanguage("uk"))

        #expect(context.assistantConfirmation == nil)
        #expect(lab.backend.ownSession == nil)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Someone else in the group speaks another language: the button only picks Translation (1.0.3, pick C), and its
    /// question's Start brings your assistant.
    @Test
    func translationIntoALanguageSomeoneLacksStartsFromItsQuestion() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        // Mira speaks English, Alex German, Bohdan Ukrainian.
        context.send(viewAction: .setMyLanguage("uk"))
        context.send(viewAction: .showAgentCenter)

        context.send(viewAction: .tapAssistantJob(.translation))
        #expect(context.assistantConfirmation == .start(.translation))
        #expect(context.viewState.attachesSent.isEmpty)

        context.send(viewAction: .produceTranslation)
        await waitUntil { lab.backend.ownSession != nil }
        #expect(lab.backend.ownSession != nil)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// D6 (dev walk, 403): once the five-second event about a stopped lane is gone, the 文A menu still offers it as a
    /// stopped track; its «Продолжить» brings your own assistant, and the track goes once its lane runs.
    @Test
    func aStoppedLaneStaysInTheMenuAfterTheEventAndContinues() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        lab.backend.startForeignTranslation()
        await waitUntil { lab.viewModel.context.viewState.translation.options.contains { $0.language == "uk" } }
        lab.viewModel.context.send(viewAction: .setListeningChoice(.language("uk")))
        await waitUntil(seconds: 6) { lab.viewModel.context.viewState.capsule.current == nil }

        lab.backend.stopForeignTranslation(reason: .aiLimit)
        await waitUntil { lab.viewModel.context.viewState.capsule.current?.action == .continueTranslation(language: "uk") }
        await waitUntil(seconds: 7) { lab.viewModel.context.viewState.capsule.current == nil }
        #expect(lab.viewModel.context.viewState.capsule.current == nil)
        #expect(NativeCallTranslateMenuItem.items(lab.viewModel.context.viewState.translation).contains(.stopped(language: "uk")))

        lab.viewModel.context.send(viewAction: .continueTranslation(language: "uk"))
        await waitUntil(seconds: 8) { lab.viewModel.context.viewState.translation.ownLanguage == "uk" }
        let state = lab.viewModel.context.viewState
        #expect(state.translation.ownLanguage == "uk")
        #expect(state.stoppedTrackLanguages.isEmpty)
        #expect(!NativeCallTranslateMenuItem.items(state.translation).contains(.stopped(language: "uk")))
    }

    /// D6 with 403 b (pre-merge review): «Продолжить» on a stopped track in a language that isn't yours produces THAT
    /// language — it becomes yours, as the language you choose to hear does — not yours, which may need no production
    /// at all (a dead tap). The track goes once acted on.
    @Test
    func continuingAStoppedTrackInAnotherLanguageProducesThatLanguage() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .setMyLanguage("de"))
        await waitUntil { lab.backend.publishedLanguage == "de" }
        lab.backend.startForeignTranslation()
        await waitUntil { context.viewState.translation.options.contains { $0.language == "de" } }
        context.send(viewAction: .setListeningChoice(.language("de")))
        lab.backend.stopForeignTranslation(reason: .aiLimit)
        await waitUntil { context.viewState.stoppedTrackLanguages == ["de"] }
        await waitUntil(seconds: 6) { context.viewState.listeningChoice == .original }
        context.send(viewAction: .setMyLanguage(nil))
        #expect(context.viewState.myLanguage == "uk")

        context.send(viewAction: .continueTranslation(language: "de"))
        #expect(context.viewState.stoppedTrackLanguages.isEmpty)
        #expect(context.viewState.myLanguage == "de")
        await waitUntil(seconds: 8) { context.viewState.translation.ownLanguage == "de" }

        #expect(context.viewState.translation.ownLanguage == "de")
        await waitUntil { context.viewState.listeningChoice == .language("de") }
        #expect(context.viewState.listeningChoice == .language("de"))
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// D10 (dev walk, 403): you stop your own translation while someone else's assistant stands by in that language. It
    /// takes over; you stay on the language throughout, the button keeps its code, and its lane is no "free" news.
    @Test
    func stoppingYourOwnTranslationKeepsTheLanguageWhileAStandbyTakesOver() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        lab.backend.startForeignStandby()
        lab.viewModel.context.send(viewAction: .produceTranslation)
        await waitUntil(seconds: 8) { lab.viewModel.context.viewState.translation.ownLanguage == "uk" }
        await waitUntil { lab.viewModel.context.viewState.translation.listeningLanguage == "uk" }
        await waitUntil(seconds: 6) { lab.viewModel.context.viewState.capsule.current == nil }

        lab.viewModel.context.send(viewAction: .toggleAssistantJob(.translation))
        await waitUntil { lab.viewModel.context.viewState.translation.ownLanguage == nil }
        // The gap: no lane in the language, and still the language chosen and shown.
        #expect(lab.viewModel.context.viewState.listeningChoice == .language("uk"))
        #expect(lab.viewModel.context.viewState.translation.listeningLanguage == "uk")

        await waitUntil { lab.viewModel.context.viewState.translation.options.first { $0.language == "uk" }?.producers == [NativeCallAssistantsLabBackend.bohdanAgent] }
        let state = lab.viewModel.context.viewState
        #expect(state.translation.options.first { $0.language == "uk" }?.producers == [NativeCallAssistantsLabBackend.bohdanAgent])
        #expect(state.listeningChoice == .language("uk"))
        #expect(state.translation.listeningLanguage == "uk")
        #expect(state.takeoverLanguage == nil)
        #expect(state.capsule.current == nil)
        // Its lane is no news: you were already on the language (Mira's English is, never having been seen).
        #expect(state.translation.options.first { $0.language == "uk" }?.isNew == false)
    }

    /// D10 (pre-merge review): the lane you hear is someone else's and it stops; your own assistant stands by in that
    /// language and takes it over a moment later. You stay on the language throughout, and hear yours.
    @Test
    func yourStandbyTakingOverSomeoneElsesStoppedLaneKeepsYouOnTheLanguage() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        lab.backend.startOwnStandby()
        await waitUntil { context.viewState.agents.ownAgents.first?.live.isStandby == true }
        await waitUntil { context.viewState.translation.options.contains { $0.language == "uk" } }
        context.send(viewAction: .setListeningChoice(.language("uk")))

        lab.backend.stopForeignTranslation(reason: .ownerStopped)
        await waitUntil { !context.viewState.translation.options.contains { $0.language == "uk" } }
        // The gap: nobody airs Ukrainian, and it is still the language chosen and shown.
        #expect(context.viewState.listeningChoice == .language("uk"))
        #expect(context.viewState.translation.listeningLanguage == "uk")

        await waitUntil { context.viewState.translation.ownLanguage == "uk" }
        #expect(context.viewState.translation.ownLanguage == "uk")
        #expect(context.viewState.listeningChoice == .language("uk"))
        #expect(context.viewState.translation.listeningLanguage == "uk")
    }

    /// D10: your standby takes the stopped lane over only after the takeover window (the sweeper's late case): you fall
    /// back to the original meanwhile, and its lanes bring you back to the language.
    @Test
    func yourStandbyTakingOverLateBringsYouBackToTheLanguage() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        lab.backend.takeoverDuration = .seconds(4)
        await waitUntil { context.viewState.agentCenter.isAvailable }
        lab.backend.startOwnStandby()
        await waitUntil { context.viewState.agents.ownAgents.first?.live.isStandby == true }
        await waitUntil { context.viewState.translation.options.contains { $0.language == "uk" } }
        context.send(viewAction: .setListeningChoice(.language("uk")))

        lab.backend.stopForeignTranslation(reason: .ownerStopped)
        await waitUntil(seconds: 6) { context.viewState.listeningChoice == .original }
        #expect(context.viewState.listeningChoice == .original)

        await waitUntil(seconds: 6) { context.viewState.listeningChoice == .language("uk") }
        #expect(context.viewState.translation.ownLanguage == "uk")
        #expect(context.viewState.listeningChoice == .language("uk"))
    }

    /// D10: with nobody to take over, your own stop falls back to the original once the takeover window runs out.
    @Test
    func stoppingYourOwnTranslationWithNobodyToTakeOverFallsBackToTheOriginal() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        lab.viewModel.context.send(viewAction: .produceTranslation)
        await waitUntil(seconds: 8) { lab.viewModel.context.viewState.translation.listeningLanguage == "uk" }

        lab.viewModel.context.send(viewAction: .toggleAssistantJob(.translation))
        await waitUntil { lab.viewModel.context.viewState.translation.ownLanguage == nil }
        #expect(lab.viewModel.context.viewState.listeningChoice == .language("uk"))

        await waitUntil(seconds: 6) { lab.viewModel.context.viewState.listeningChoice == .original }
        #expect(lab.viewModel.context.viewState.listeningChoice == .original)
        #expect(lab.viewModel.context.viewState.translation.listeningLanguage == nil)
    }

    /// D10 (dev walk, 403): someone else's assistant on standby (`active: false`, `lanes: []`, `for_language` set) reads
    /// «В резерве · украинский» in «В звонке» and on its page, and no surface — its page's buttons, the capsule — shows it
    /// as translating.
    @Test
    func someoneElsesStandbyReadsAsStandbyNotTranslating() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.agentCenter.isAvailable }
        lab.backend.startForeignStandby()
        await waitUntil { lab.viewModel.context.viewState.agents.agents.contains { $0.mxid == NativeCallAssistantsLabBackend.bohdanAgent } }

        let context = lab.viewModel.context
        guard let standby = context.viewState.agents.agents.first(where: { $0.mxid == NativeCallAssistantsLabBackend.bohdanAgent }) else {
            Issue.record("Bohdan's assistant isn't in the call")
            return
        }
        let ukrainian = NativeCallAgentStatusCopy.languageList(["uk"], catalog: context.viewState.agents.panel.catalog)
        #expect(standby.shown.isStandby)
        #expect(NativeCallAssistantsCopy.foreignStatus(standby, context: context) == UntranslatedL10n.screenNativeCallAssistantsForeignStandby(ukrainian))
        #expect(NativeCallAssistantsCopy.foreignRows(standby, context: context).map(\.title) == [UntranslatedL10n.screenNativeCallAssistantsForeignStandby(ukrainian)])
        #expect(standby.shown.event == .idle(role: nil, languages: []))
        #expect(NativeCallAgentPillContent(NativeCallAgentBlockState(standby, among: context.viewState.agents.agents)).chip == nil)
    }

    /// L11 (operator, 2026-11-11): in the private call «Перевод» while talking opens the neighbour's language, preselected;
    /// the pick turns the talk off, then the interpreter on — in that order. «Разговор» while interpreting turns the
    /// translation off, waits for the runtime to leave the interpreter, then turns the talk on.
    @Test
    func inThePrivateCallOneTapSwitchesBetweenTalkAndInterpreter() async {
        let lab = makeLab(.privateCall)
        let context = lab.viewModel.context
        func own() -> NativeCallAgentPresentation.Agent? {
            context.viewState.agents.ownAgents.first
        }
        await waitUntil { context.viewState.agentCenter.isAvailable && own()?.shown.isConversationActive == true }
        #expect(own()?.shown.isConversationActive == true)

        context.send(viewAction: .toggleAssistantJob(.translation))
        #expect(context.viewState.bindings.isNeighbourLanguagePresented)
        #expect(lab.backend.writeLog.isEmpty)

        context.send(viewAction: .setNeighbourLanguage("fr"))
        #expect(context.viewState.switchingAssistantJob == .translation)
        await waitUntil(seconds: 8) { own()?.shown.languages == ["uk", "fr"] && own()?.control?.translation.isSyncing == false }
        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr"])
        #expect(own()?.shown.isConversationActive == false)
        #expect(context.viewState.switchingAssistantJob == nil)

        context.send(viewAction: .toggleAssistantJob(.conversation))
        #expect(context.viewState.switchingAssistantJob == .conversation)
        await waitUntil(seconds: 15) { own()?.shown.isConversationActive == true && lab.backend.writeLog.count == 4 }
        await waitUntil { context.viewState.switchingAssistantJob == nil }
        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr", "translation off", "conversation on"])
        #expect(own()?.shown.isConversationActive == true)
        #expect(own()?.shown.isTranslating == false)
        #expect(context.viewState.agentCenter.lastError == nil)
    }

    /// S1: «Я говорю» changed while the pocket interpreter runs re-sends the pair with the new side; picking the
    /// neighbour's language as yours swaps the two sides, so the pair is never one language twice.
    @Test
    func changingMyLanguageInThePrivateCallMovesThePairAndNeverDoublesIt() async {
        let lab = makeLab(.privateCall)
        let context = lab.viewModel.context
        func own() -> NativeCallAgentPresentation.Agent? {
            context.viewState.agents.ownAgents.first
        }
        await waitUntil { context.viewState.agentCenter.isAvailable && own()?.shown.isConversationActive == true }
        context.send(viewAction: .setNeighbourLanguage("fr"))
        await waitUntil(seconds: 8) { own()?.shown.languages == ["uk", "fr"] && context.viewState.switchingAssistantJob == nil }
        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr"])

        context.send(viewAction: .setMyLanguage("de"))
        await waitUntil(seconds: 8) { own()?.shown.languages == ["de", "fr"] }
        #expect(lab.backend.writeLog.last == "translation pocket de fr")
        #expect(context.viewState.neighbourLanguage == "fr")

        context.send(viewAction: .setMyLanguage("fr"))
        await waitUntil(seconds: 8) { own()?.shown.languages == ["fr", "de"] }
        #expect(lab.backend.writeLog.last == "translation pocket fr de")
        #expect(context.viewState.myLanguageCode == "fr")
        #expect(context.viewState.neighbourLanguage == "de")
        #expect(context.viewState.agentCenter.lastError == nil)

        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
        NativeCallAssistantsLiveLab.myLanguageStore.setNeighbourLanguage("fr")
    }

    /// DEBT B21: «Я говорю» picked while the talk→interpreter switch runs — the interpreter isn't on yet, so the pick
    /// sends nothing then — still ends with the pair the sheet shows: it is sent once the switch's pair lands.
    @Test
    func myLanguagePickedDuringTheSwitchToTheInterpreterIsSentAfterIt() async {
        let lab = makeLab(.privateCall, latency: .short)
        let context = lab.viewModel.context
        func own() -> NativeCallAgentPresentation.Agent? {
            context.viewState.agents.ownAgents.first
        }
        await waitUntil { context.viewState.agentCenter.isAvailable && own()?.shown.isConversationActive == true }

        context.send(viewAction: .setNeighbourLanguage("fr"))
        #expect(context.viewState.switchingAssistantJob == .translation)
        context.send(viewAction: .setMyLanguage("de"))

        await waitUntil(seconds: 8) { own()?.shown.languages == ["de", "fr"] && own()?.control?.translation.isSyncing == false }
        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr", "translation pocket de fr"])
        #expect(context.viewState.myLanguageCode == "de")
        #expect(context.viewState.neighbourLanguage == "fr")
        #expect(context.viewState.agentCenter.lastError == nil)

        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
        NativeCallAssistantsLiveLab.myLanguageStore.setNeighbourLanguage("fr")
    }

    /// DEBT B21: two quick «Я говорю» picks while the interpreter runs — the second arrives while the first is written,
    /// and the in-flight write takes no second one — end on the last pick, not the first.
    @Test
    func aSecondQuickPickOfMyLanguageIsNotLost() async {
        let lab = makeLab(.privateCall, latency: .short)
        let context = lab.viewModel.context
        func own() -> NativeCallAgentPresentation.Agent? {
            context.viewState.agents.ownAgents.first
        }
        await waitUntil { context.viewState.agentCenter.isAvailable && own()?.shown.isConversationActive == true }
        context.send(viewAction: .setNeighbourLanguage("fr"))
        await waitUntil(seconds: 8) { own()?.shown.languages == ["uk", "fr"] && context.viewState.switchingAssistantJob == nil }

        context.send(viewAction: .setMyLanguage("de"))
        context.send(viewAction: .setMyLanguage("es"))

        await waitUntil(seconds: 8) { own()?.shown.languages == ["es", "fr"] && own()?.control?.translation.isSyncing == false }
        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr", "translation pocket de fr", "translation pocket es fr"])
        #expect(context.viewState.myLanguageCode == "es")
        #expect(context.viewState.agentCenter.lastError == nil)

        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
        NativeCallAssistantsLiveLab.myLanguageStore.setNeighbourLanguage("fr")
    }

    /// A swipe-down closes the sheet on any page: the neighbour's language or the pick of an assistant. Opened again,
    /// it starts on its own page, not on the stale one.
    @Test
    func dismissingTheSheetClearsThePageItWasOn() async {
        let lab = makeLab(.privateCall)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable && context.viewState.agents.ownAgents.first?.shown.isConversationActive == true }
        context.send(viewAction: .toggleAssistantJob(.translation))
        #expect(context.viewState.bindings.isNeighbourLanguagePresented)

        context.send(viewAction: .dismissAgentCenter)
        #expect(!context.viewState.bindings.isNeighbourLanguagePresented)

        let several = makeLab(.onePerson)
        several.backend.hasSeveralAssistants = true
        await several.controller.reload()
        await waitUntil { several.viewModel.context.viewState.agents.panel.candidates.count > 1 }
        several.viewModel.context.send(viewAction: .toggleAssistantJob(.summary))
        #expect(several.viewModel.context.viewState.bindings.assistantPickerJob == .summary)

        several.viewModel.context.send(viewAction: .dismissAgentCenter)
        #expect(several.viewModel.context.viewState.bindings.assistantPickerJob == nil)
    }

    /// L11 (pre-merge review): while a one-tap switch runs its two writes, the other button can't race them — a tap on
    /// «Разговор» mid-switch to the interpreter (or on «Перевод» mid-switch to the talk) does nothing.
    @Test
    func theOtherButtonCantRaceASwitch() async {
        let lab = makeLab(.privateCall)
        let context = lab.viewModel.context
        func own() -> NativeCallAgentPresentation.Agent? {
            context.viewState.agents.ownAgents.first
        }
        await waitUntil { context.viewState.agentCenter.isAvailable && own()?.shown.isConversationActive == true }

        context.send(viewAction: .setNeighbourLanguage("fr"))
        context.send(viewAction: .toggleAssistantJob(.conversation))
        await waitUntil(seconds: 8) { own()?.shown.languages == ["uk", "fr"] && context.viewState.switchingAssistantJob == nil }
        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr"])
        #expect(context.viewState.agentCenter.lastError == nil)

        context.send(viewAction: .toggleAssistantJob(.conversation))
        context.send(viewAction: .toggleAssistantJob(.translation))
        await waitUntil(seconds: 15) { own()?.shown.isConversationActive == true && context.viewState.switchingAssistantJob == nil }
        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr", "translation off", "conversation on"])
        #expect(context.viewState.agentCenter.lastError == nil)
    }

    /// L11 (pre-merge review): the switch to the talk waits up to ten seconds for the runtime; the call ending meanwhile
    /// ends the switch — no write lands after it.
    @Test
    func aSwitchDoesntOutliveTheCall() async {
        let lab = makeLab(.privateCall)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable && context.viewState.agents.ownAgents.first?.shown.isConversationActive == true }
        context.send(viewAction: .setNeighbourLanguage("fr"))
        await waitUntil(seconds: 8) {
            context.viewState.agents.ownAgents.first?.control?.translation.isSyncing == false && context.viewState.switchingAssistantJob == nil
        }

        context.send(viewAction: .toggleAssistantJob(.conversation))
        await waitUntil { lab.backend.writeLog.count == 3 }
        #expect(context.viewState.switchingAssistantJob == .conversation, "the switch waits for the runtime to leave the interpreter")
        lab.viewModel.stop()
        await waitUntil(seconds: 4) { lab.backend.writeLog.count == 4 }

        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr", "translation off"])
        #expect(context.viewState.switchingAssistantJob == nil)
    }

    /// L12 (operator's option A): while the pocket interpreter runs, the assistant's avatar carries «文 FR» — the
    /// neighbour's language only, ringed while its mode syncs — and the page says no "UA · FR" pair; it goes when the
    /// translation stops.
    @Test
    func thePrivateCallsAvatarCarriesTheNeighboursLanguageOnly() async {
        let lab = makeLab(.privateCall)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable && context.viewState.agents.ownAgents.first?.shown.isConversationActive == true }
        #expect(context.viewState.interpreterBadge == nil)

        context.send(viewAction: .setNeighbourLanguage("fr"))
        await waitUntil(seconds: 6) { context.viewState.interpreterBadge != nil }
        #expect(context.viewState.interpreterBadge == NativeCallAvatarBadge(language: "fr", isPending: true))
        await waitUntil(seconds: 6) { context.viewState.interpreterBadge?.isPending == false }
        #expect(context.viewState.interpreterBadge == NativeCallAvatarBadge(language: "fr", isPending: false))
        #expect(context.viewState.agentBlock.flatMap { NativeCallAgentStatusCopy.assistantPageLine($0.event) } == nil)

        guard let control = context.viewState.agents.ownAgents.first?.control else {
            Issue.record("Your assistant isn't in the call")
            return
        }
        context.send(viewAction: .disableAgentTranslation(sessionID: control.sessionID))
        await waitUntil(seconds: 6) { context.viewState.interpreterBadge == nil }
        #expect(context.viewState.interpreterBadge == nil)
    }

    /// Question 407: the person beside you must hear the translation. Moved to the earpiece, the call goes back to
    /// the speaker when the pocket interpreter starts — once; the translation running never moves it again.
    @Test
    func thePocketInterpreterMovesTheCallFromTheEarpieceToTheSpeakerOnce() async {
        let routing = NativeCallAudioRoutingRecorder()
        let lab = makeLab(.privateCall, audioRouting: routing)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable && context.viewState.agents.ownAgents.first?.shown.isConversationActive == true }
        #expect(context.viewState.isSpeakerEnabled, "the private call starts on the speaker")
        context.send(viewAction: .toggleSpeaker)
        #expect(!context.viewState.isSpeakerEnabled)

        context.send(viewAction: .setNeighbourLanguage("fr"))
        #expect(context.viewState.isSpeakerEnabled)
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.languages == ["uk", "fr"] && context.viewState.switchingAssistantJob == nil }

        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr"])
        #expect(routing.speakerRequests == [false, true])
        #expect(context.viewState.isSpeakerEnabled)
    }

    /// Question 407: the earpiece picked after the interpreter started is kept while it runs.
    @Test
    func anEarpiecePickedAfterTheInterpreterStartsIsKept() async {
        let routing = NativeCallAudioRoutingRecorder()
        let lab = makeLab(.privateCall, audioRouting: routing)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable && context.viewState.agents.ownAgents.first?.shown.isConversationActive == true }
        context.send(viewAction: .toggleSpeaker)
        context.send(viewAction: .setNeighbourLanguage("fr"))
        context.send(viewAction: .toggleSpeaker)
        #expect(!context.viewState.isSpeakerEnabled)

        await waitUntil(seconds: 8) {
            context.viewState.agents.ownAgents.first?.control?.translation.isSyncing == false && context.viewState.switchingAssistantJob == nil
        }

        #expect(context.viewState.agents.ownAgents.first?.shown.languages == ["uk", "fr"])
        #expect(routing.speakerRequests == [false, true, false])
        #expect(!context.viewState.isSpeakerEnabled)
    }

    /// Question 407: headphones, Bluetooth or a car keep the interpreter's sound; it never moves to the speaker.
    @Test
    func headphonesKeepThePocketInterpreterOffTheSpeaker() async {
        let routing = NativeCallAudioRoutingRecorder()
        routing.hasExternalOutput = true
        let lab = makeLab(.privateCall, audioRouting: routing)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable && context.viewState.agents.ownAgents.first?.shown.isConversationActive == true }
        #expect(!context.viewState.isSpeakerEnabled)

        context.send(viewAction: .setNeighbourLanguage("fr"))
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.languages == ["uk", "fr"] && context.viewState.switchingAssistantJob == nil }

        #expect(lab.backend.writeLog == ["conversation off", "translation pocket uk fr"])
        #expect(routing.speakerRequests.isEmpty)
        #expect(!context.viewState.isSpeakerEnabled)
    }

    /// Question 407: a car kit that does hands-free only counts as connected — the interpreter's sound stays in the car.
    @Test
    func aHandsFreeCarKitKeepsThePocketInterpreterOffTheSpeaker() async {
        let routing = NativeCallAudioRoutingRecorder()
        routing.hasHandsFreeInput = true
        let lab = makeLab(.privateCall, audioRouting: routing)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable && context.viewState.agents.ownAgents.first?.shown.isConversationActive == true }

        context.send(viewAction: .setNeighbourLanguage("fr"))
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.languages == ["uk", "fr"] && context.viewState.switchingAssistantJob == nil }

        #expect(routing.speakerRequests.isEmpty)
        #expect(!context.viewState.isSpeakerEnabled)
    }

    /// L12, one visual everywhere: listening in Ukrainian, a speaker your translation covers carries «文 UA» on their
    /// avatar (the stage's or a tile's), read as "You hear them in Ukrainian"; one it doesn't cover carries nothing.
    @Test
    func aCoveredSpeakersAvatarCarriesTheBadgeAndAnUncoveredOneDoesnt() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        lab.backend.startForeignTranslation()
        await waitUntil { context.viewState.translation.options.contains { $0.language == "uk" } }
        #expect(context.viewState.avatarBadge(for: NativeCallAssistantsLabBackend.mira) == nil)

        context.send(viewAction: .setListeningChoice(.language("uk")))
        let covered = context.viewState.avatarBadge(for: NativeCallAssistantsLabBackend.mira)
        #expect(covered == NativeCallAvatarBadge(language: "uk", isPending: false, kind: .heardIn))
        #expect(covered?.accessibilityLabel == UntranslatedL10n.a11yNativeCallParticipantHeardIn(NativeCallTranslationCopy.languageName("uk")))
        // Bohdan's assistant covers Mira only; Bohdan speaks Ukrainian.
        #expect(context.viewState.avatarBadge(for: NativeCallAssistantsLabBackend.alex) == nil)
        #expect(context.viewState.avatarBadge(for: NativeCallAssistantsLabBackend.bohdan) == nil)
        #expect(context.viewState.avatarBadge(for: NativeCallAssistantsLabBackend.me) == nil)
        #expect(context.viewState.interpreterBadge == nil)
    }

    /// Question 404: Mira's assistant records the group call, so yours shows as covered by her; when hers stops,
    /// «Продовжити».
    @Test
    func someoneElsesRecordingCoversYoursUntilItStops() async {
        let lab = makeLab(.group)
        await waitUntil { lab.viewModel.context.viewState.recordingCover != nil }
        #expect(lab.viewModel.context.viewState.recordingCover
            == NativeCallRecordingCover(agentMxid: NativeCallAssistantsLabBackend.miraAgent, ownerMxid: NativeCallAssistantsLabBackend.mira, phase: .recording))

        lab.backend.stopForeignRecording()
        await waitUntil { lab.viewModel.context.viewState.recordingCover?.phase == .stopped }

        #expect(lab.viewModel.context.viewState.recordingCover
            == NativeCallRecordingCover(agentMxid: NativeCallAssistantsLabBackend.miraAgent, ownerMxid: NativeCallAssistantsLabBackend.mira, phase: .stopped))
    }

    /// Question 404, layout C: a tap on the covered «Записує» puts the card in the buttons' place — Mira by name, as
    /// the subject — and «Зрозуміло» brings the buttons back for good: nothing the platform says next reopens it.
    @Test
    func aTapOnTheCoveredRecordingOpensTheCardUntilGotIt() async throws {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.recordingCover?.phase == .recording }
        context.send(viewAction: .showAgentCenter)

        context.send(viewAction: .tapAssistantJob(.recording))

        #expect(context.assistantConfirmation == .recordingCovered)
        #expect(lab.backend.ownSession == nil)
        let card = try #require(NativeCallAssistantsCopy.recordingCoveredCard(context.viewState.recordingCover, context: context))
        #expect(card.title == UntranslatedL10n.screenNativeCallAssistantsRecordingCovered("Mira"))
        #expect(card.detail == UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredCardDetail)

        // «Зрозуміло».
        context.assistantConfirmation = nil
        lab.backend.startForeignTranslation()
        await waitUntil { context.viewState.translation.options.contains { $0.language == "uk" } }

        #expect(context.assistantConfirmation == nil)
        #expect(context.viewState.recordingCover?.phase == .recording)
    }

    /// Question 404, layout C: hers stops while the card is open — the buttons come back, «Продовжити» among them, and
    /// the card can't be opened on a recording that isn't there.
    @Test
    func theirRecordingStoppingClosesTheCard() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.recordingCover?.phase == .recording }
        context.send(viewAction: .showAgentCenter)
        context.send(viewAction: .tapAssistantJob(.recording))
        #expect(context.assistantConfirmation == .recordingCovered)

        lab.backend.stopForeignRecording()
        await waitUntil { context.viewState.recordingCover?.phase == .stopped }

        #expect(context.assistantConfirmation == nil)
        #expect(NativeCallAssistantsCopy.recordingCoveredCard(context.viewState.recordingCover, context: context) == nil)
        let button = NativeCallAssistantDockState(.init(recordingCover: context.viewState.recordingCover?.phase)).buttons.first { $0.job == .recording }
        #expect(button?.cover == .stopped)
    }

    /// Question 404: «Продовжити» asks «Записувати дзвінок?» as any start does, its line saying Mira's stopped and
    /// yours is a file of its own; «Записувати» then starts yours.
    @Test
    func continueAsksWithTheStoppedRecordingsLine() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.recordingCover?.phase == .recording }
        lab.backend.stopForeignRecording()
        await waitUntil { context.viewState.recordingCover?.phase == .stopped }
        context.send(viewAction: .showAgentCenter)

        context.send(viewAction: .tapAssistantJob(.recording))

        #expect(context.assistantConfirmation == .start(.recording))
        #expect(NativeCallAssistantsCopy.recordingConfirmationDetail(context.viewState.recordingCover, context: context)
            == UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessageAfterOther("Mira"))

        // «Записувати».
        context.assistantConfirmation = nil
        context.send(viewAction: .toggleAssistantJob(.recording))
        await waitUntil { context.viewState.recordingCover == nil }
        #expect(lab.backend.ownSession != nil)
    }

    /// Question 404: the confirmation's line by the cover — the usual one with nobody else's recording, the owner's
    /// name once theirs stopped, "the previous recording" when the owner is unknown.
    @Test
    func theRecordingConfirmationsLineFollowsTheCover() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        let stopped = NativeCallRecordingCover(agentMxid: NativeCallAssistantsLabBackend.miraAgent, ownerMxid: nil, phase: .stopped)
        let covering = NativeCallRecordingCover(agentMxid: NativeCallAssistantsLabBackend.miraAgent, ownerMxid: nil, phase: .recording)

        #expect(NativeCallAssistantsCopy.recordingConfirmationDetail(nil, context: context) == UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessage)
        #expect(NativeCallAssistantsCopy.recordingConfirmationDetail(stopped, context: context) == UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessageAfterSomeone)
        #expect(NativeCallAssistantsCopy.recordingCoveredCard(covering, context: context)?.title == UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredSomeone)
    }

    /// Question 404: a start the platform refuses as covered stays covered, with no reason on the add row; in the sheet
    /// that asked, the card says whose at once.
    @Test
    func aRecordingStartTheCallAlreadyHasIsRefusedAsCovered() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .showAgentCenter)

        context.send(viewAction: .toggleAssistantJob(.recording))
        await waitUntil { context.viewState.agentCenter.recordingRefusal != nil }

        let state = context.viewState
        #expect(state.agentCenter.recordingRefusal?.cover == VoiceRecordingCover(agentMxid: NativeCallAssistantsLabBackend.miraAgent, ownerMxid: NativeCallAssistantsLabBackend.mira))
        #expect(state.agentCenter.joinFailures.isEmpty)
        #expect(state.recordingCover?.phase == .recording)
        #expect(lab.backend.ownSession == nil)
        #expect(context.assistantConfirmation == .recordingCovered)
    }

    /// Question 404: a refusal with the sheet closed opens nothing — the next open starts on the buttons.
    @Test
    func aRefusalWithTheSheetClosedOpensNoCard() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }

        context.send(viewAction: .toggleAssistantJob(.recording))
        await waitUntil { context.viewState.agentCenter.recordingRefusal != nil }

        #expect(context.assistantConfirmation == nil)
    }

    // MARK: - Someone translates you (question 409)

    /// Mira's assistant starts translating you: the capsule says it with «Змінити», which opens the list «Моя мова» is
    /// picked in; a pick changes your language and the capsule confirms it without an action.
    @Test
    func someoneTranslatingYouIsSaidAndChangeConfirmsTheNewLanguage() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        #expect(context.viewState.capsule.current == nil)

        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.capsule.current != nil }
        #expect(context.viewState.capsule.current
            == .translatingYou(language: "uk", producer: NativeCallAssistantsLabBackend.miraAgent, owner: NativeCallAssistantsLabBackend.mira, isConfirmation: false))
        #expect(NativeCallTranslateMenuItem.items(context.viewState.translation).contains(.spokenLanguage("uk")))

        context.send(viewAction: .runCapsuleAction)
        #expect(context.isAgentCenterPresented)
        #expect(context.agentCenterPage == .spokenLanguage)
        #expect(context.viewState.capsule.current == nil)

        context.send(viewAction: .setMyLanguage("ru"))
        #expect(context.viewState.capsule.current
            == .translatingYou(language: "ru", producer: NativeCallAssistantsLabBackend.miraAgent, owner: NativeCallAssistantsLabBackend.mira, isConfirmation: true))
        #expect(context.viewState.capsule.current?.action == nil)
        // The same membership republish as any change of «Моя мова».
        await waitUntil { lab.backend.membershipLanguages[NativeCallAssistantsLabBackend.me] == "ru" }
        #expect(lab.backend.membershipLanguages[NativeCallAssistantsLabBackend.me] == "ru")
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Once per call: translating you again after a pause says nothing new.
    @Test
    func translatingYouIsSaidOncePerCall() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.capsule.current != nil }

        lab.backend.stopTranslatingYou()
        await waitUntil { context.viewState.translation.yourTranslator == nil }
        // Stale once nobody translates you.
        #expect(context.viewState.capsule.current == nil)

        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.translation.yourTranslator != nil }
        #expect(context.viewState.capsule.current == nil)
    }

    /// The menu's «Я говорю» opens the same list.
    @Test
    func theMenusISpeakOpensTheList() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }

        context.send(viewAction: .showSpokenLanguage)

        #expect(context.isAgentCenterPresented)
        #expect(context.agentCenterPage == .spokenLanguage)
    }

    /// A 1:1 with a person too: John's assistant starts translating you.
    @Test
    func aOneToOneCallSaysWhoTranslatesYou() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }

        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.capsule.current != nil }

        #expect(context.viewState.capsule.current
            == .translatingYou(language: "uk", producer: NativeCallAssistantsLabBackend.johnAgent, owner: NativeCallAssistantsLabBackend.john, isConfirmation: false))
    }

    /// A language you picked before is yours: nothing is asked, and the menu's «Я говорю» stays.
    @Test
    func aPickedLanguageIsNeverAskedAboutInTheCall() async {
        NativeCallAssistantsLiveLab.myLanguageStore.setChosen(nil)
        let lab = NativeCallAssistantsLiveLab(backend: NativeCallAssistantsLabBackend(cast: .onePerson, role: .moderator, latency: .none,
                                                                                      joinDuration: .milliseconds(10)),
                                              haptics: .none)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }

        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.translation.yourTranslator != nil }

        #expect(context.viewState.capsule.current == nil)
        #expect(NativeCallTranslateMenuItem.items(context.viewState.translation).contains(.spokenLanguage("uk")))
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Not in the private call with your own assistant (the pocket interpreter): its lanes carry your voice, and
    /// nothing is said.
    @Test
    func thePrivateCallNeverSaysWhoTranslatesYou() async {
        let lab = makeLab(.privateCall)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .setNeighbourLanguage("fr"))
        context.send(viewAction: .toggleAssistantJob(.translation))
        await waitUntil { context.viewState.agents.ownAgents.first?.shown.isTranslating == true }

        #expect(context.viewState.translation.yourTranslator == nil)
        #expect(context.viewState.capsule.current == nil)
        #expect(!NativeCallTranslateMenuItem.items(context.viewState.translation).contains { if case .spokenLanguage = $0 { true } else { false } })
    }

    // MARK: - The capsule's tap (operator, 2026-11-12)

    /// An event with an action for you taps the hand once as it shows; the action-less confirmation doesn't.
    @Test
    func anEventWithAnActionTapsOnceAndAConfirmationDoesnt() async {
        let taps = TapCounter()
        let lab = makeLab(.group, haptics: taps.haptics)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }

        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.capsule.current != nil }
        #expect(taps.count == 1)

        context.send(viewAction: .runCapsuleAction)
        context.send(viewAction: .setMyLanguage("ru"))
        #expect(context.viewState.capsule.current?.action == nil)
        #expect(taps.count == 1)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// The call through the earpiece: the phone is at the ear, no tap. The speaker and headphones let it through.
    @Test(arguments: [(AVAudioSession.Port.builtInReceiver, 0), (.builtInSpeaker, 1), (.headphones, 1)])
    func theTapFollowsTheRoute(output: AVAudioSession.Port, taps expected: Int) async {
        let taps = TapCounter()
        let lab = makeLab(.group, haptics: taps.haptics, output: output)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }

        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.capsule.current != nil }

        #expect(context.viewState.capsule.current?.action == .changeSpokenLanguage)
        #expect(taps.count == expected)
    }

    /// Review of 2026-11-12: an event dropped before it showed — the lane blinked — is said when the lane comes back.
    @Test
    func anEventDroppedUnshownIsSaidWhenTheLaneComesBack() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        lab.backend.startForeignTranslation()
        await waitUntil { context.viewState.capsule.current != nil }
        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.capsule.pending.count == 1 }

        lab.backend.stopTranslatingYou()
        await waitUntil { context.viewState.capsule.pending.isEmpty }
        context.send(viewAction: .runCapsuleAction)
        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.capsule.current != nil }

        #expect(context.viewState.capsule.current?.action == .changeSpokenLanguage)
    }

    /// Review of 2026-11-12: a change made while nobody translates you isn't confirmed when someone starts again.
    @Test
    func aChangeWhileNobodyTranslatesYouIsntConfirmedLater() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.capsule.current != nil }
        lab.backend.stopTranslatingYou()
        await waitUntil { context.viewState.translation.yourTranslator == nil }

        context.send(viewAction: .setMyLanguage("ru"))
        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.translation.yourTranslator != nil }

        #expect(context.viewState.capsule.current == nil)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Review of 2026-11-12: «Я говорю»'s languages are there before the platform answers, from the kept catalog.
    @Test
    func theKeptCatalogServesTheListsBeforeThePlatformAnswers() {
        let backend = NativeCallAssistantsLabBackend(cast: .group, role: .moderator, latency: .none)
        backend.latencyOverride = .seconds(60)
        let lab = NativeCallAssistantsLiveLab(backend: backend, haptics: .none)

        #expect(!lab.viewModel.context.viewState.agentCenter.isAvailable)
        #expect(lab.viewModel.context.viewState.languageCodes.contains("uk"))
    }

    /// An event waiting its turn taps when it shows, not when it is queued.
    @Test
    func aQueuedEventTapsWhenItShows() async {
        let taps = TapCounter()
        let lab = makeLab(.group, haptics: taps.haptics)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }

        lab.backend.startForeignTranslation()
        await waitUntil { context.viewState.capsule.current != nil }
        lab.backend.startTranslatingYou()
        await waitUntil { context.viewState.translation.yourTranslator != nil }
        #expect(context.viewState.capsule.pending.count == 1)
        #expect(taps.count == 1)

        // «Слухати»: the next event shows.
        context.send(viewAction: .runCapsuleAction)
        #expect(context.viewState.capsule.current?.action == .changeSpokenLanguage)
        #expect(taps.count == 2)
    }

    // MARK: How translation starts (1.0.3, the operator's pick B)

    /// Off: a language picked in «Translate into» is yours at once, and «Start translation» starts it; then Stop.
    @Test
    func aLanguagePickedWhileOffIsStartedByStartThenStopShows() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.translation.isButtonVisible }
        context.send(viewAction: .showAgentCenter)
        #expect(translationAction(context) == .start)

        context.send(viewAction: .pickTranslationLanguage("de"))
        #expect(context.viewState.myLanguage == "de")
        #expect(context.viewState.pickedTranslationLanguage == nil)
        #expect(translationAction(context) == .start)

        context.send(viewAction: .produceTranslation)
        await waitUntil(seconds: 8) { context.viewState.translation.ownLanguage == "de" }
        await waitUntil { translationAction(context) == .stop }
        #expect(translationAction(context) == .stop)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Running: a pick only offers «Translate into …»; nothing moves until it is tapped, then the button is Stop again.
    @Test
    func aLanguagePickedWhileRunningMovesOnlyOnTranslateInto() async {
        let lab = await makeLabTranslating()
        let context = lab.viewModel.context

        context.send(viewAction: .pickTranslationLanguage("de"))
        #expect(translationAction(context) == .translateInto(language: "de"))
        try? await Task.sleep(for: .milliseconds(300))
        #expect(context.viewState.myLanguage == "uk")
        #expect(context.viewState.translation.ownLanguage == "uk")
        #expect(!lab.backend.writeLog.contains { $0.contains("de") })

        context.send(viewAction: .applyPickedTranslationLanguage)
        #expect(context.viewState.pickedTranslationLanguage == nil)
        await waitUntil(seconds: 8) { context.viewState.translation.ownLanguage == "de" }
        #expect(context.viewState.myLanguage == "de")
        #expect(translationAction(context) == .stop)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Picking the language it already translates into takes «Translate into …» away again.
    @Test
    func pickingTheRunningLanguageAgainLeavesStop() async {
        let lab = await makeLabTranslating()
        let context = lab.viewModel.context

        context.send(viewAction: .pickTranslationLanguage("de"))
        context.send(viewAction: .pickTranslationLanguage("uk"))

        #expect(translationAction(context) == .stop)
        #expect(context.viewState.pickedTranslationLanguage == nil)
    }

    /// A pick never applied is dropped with the sheet, and by the Translation button, which only turns it off.
    @Test
    func closingTheSheetOrTheTranslationButtonDropsThePick() async {
        let lab = await makeLabTranslating()
        let context = lab.viewModel.context

        context.send(viewAction: .pickTranslationLanguage("de"))
        context.send(viewAction: .dismissAgentCenter)
        #expect(context.viewState.pickedTranslationLanguage == nil)
        #expect(context.viewState.myLanguage == "uk")

        context.send(viewAction: .showAgentCenter)
        context.send(viewAction: .pickTranslationLanguage("de"))
        context.send(viewAction: .tapAssistantJob(.translation))
        #expect(context.viewState.pickedTranslationLanguage == nil)
        await waitUntil(seconds: 8) { context.viewState.translation.ownLanguage == nil }
        await waitUntil { translationAction(context) == .start }
        #expect(translationAction(context) == .start)
        #expect(context.viewState.myLanguage == "uk")
    }

    /// A switch that fails leaves your language moved and the translation where it was: picking the language again
    /// offers «Translate into …», which retries it.
    @Test
    func aFailedSwitchIsRetriedByTranslateInto() async {
        let lab = await makeLabTranslating()
        let context = lab.viewModel.context
        context.send(viewAction: .pickTranslationLanguage("de"))
        lab.backend.nextFailure = .network
        context.send(viewAction: .applyPickedTranslationLanguage)
        await waitUntil { context.viewState.agentCenter.lastError != nil }
        await waitUntil { context.viewState.agentActionsInFlight.isEmpty }
        #expect(context.viewState.myLanguage == "de")
        #expect(context.viewState.translation.ownLanguage == "uk")

        context.send(viewAction: .pickTranslationLanguage("de"))
        #expect(translationAction(context) == .translateInto(language: "de"))
        context.send(viewAction: .applyPickedTranslationLanguage)
        await waitUntil(seconds: 8) { context.viewState.translation.ownLanguage == "de" }

        #expect(context.viewState.translation.ownLanguage == "de")
        #expect(translationAction(context) == .stop)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// «Translate into …» tapped while a translation write is still out keeps the pick and sends nothing more.
    @Test
    func translateIntoWaitsForAWriteStillOut() async {
        let lab = await makeLabTranslating()
        let context = lab.viewModel.context
        lab.backend.latencyOverride = .milliseconds(500)
        lab.backend.latency = .short
        context.send(viewAction: .pickTranslationLanguage("de"))
        context.send(viewAction: .applyPickedTranslationLanguage)

        context.send(viewAction: .pickTranslationLanguage("fr"))
        context.send(viewAction: .applyPickedTranslationLanguage)

        #expect(context.viewState.pickedTranslationLanguage == "fr")
        #expect(context.viewState.myLanguage == "de")
        await waitUntil(seconds: 8) { context.viewState.translation.ownLanguage == "de" }
        #expect(translationAction(context) == .translateInto(language: "fr"))
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// A pick held for «Translate into …» goes when the translation stops on its own, here on your limit.
    @Test
    func aHeldPickGoesWhenTheTranslationStopsOnItsOwn() async {
        let lab = await makeLabTranslating()
        let context = lab.viewModel.context
        context.send(viewAction: .pickTranslationLanguage("de"))
        #expect(context.viewState.pickedTranslationLanguage == "de")

        lab.backend.exhaustOwnLimit()
        await waitUntil(seconds: 5) { context.viewState.pickedTranslationLanguage == nil }

        #expect(context.viewState.pickedTranslationLanguage == nil)
        #expect(context.viewState.myLanguage == "uk")
    }

    /// A start that fails leaves nothing waiting: the button is Start again, and translation is off.
    @Test
    func aFailedStartIsStartAgain() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.translation.isButtonVisible }
        context.send(viewAction: .showAgentCenter)
        // The assistant comes for notes first, so the start is a write on its session.
        context.send(viewAction: .toggleAssistantJob(.summary))
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.isSummaryArmed == true }
        await waitUntil { context.viewState.agentActionsInFlight.isEmpty }

        lab.backend.nextFailure = .network
        context.send(viewAction: .produceTranslation)
        await waitUntil { context.viewState.agentCenter.lastError != nil }
        await waitUntil { context.viewState.agentActionsInFlight.isEmpty }

        #expect(context.viewState.agentCenter.lastError != nil)
        #expect(context.viewState.agentActionsInFlight.isEmpty)
        #expect(context.viewState.agents.ownAgents.first?.shown.isTranslating != true)
        #expect(translationAction(context) == .start)
    }

    /// The private call's interpreter moves with «Я говорю» at once: nothing is held there (L11).
    @Test
    func thePrivateCallsPickIsNeverHeld() async {
        let lab = makeLab(.privateCall)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .setNeighbourLanguage("en"))
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.isTranslating == true }

        context.send(viewAction: .pickTranslationLanguage("de"))

        #expect(context.viewState.pickedTranslationLanguage == nil)
        #expect(context.viewState.myLanguage == "de")
        #expect(translationAction(context) == nil)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    @MainActor
    private final class TapCounter {
        private(set) var count = 0

        var haptics: NativeCallHaptics {
            NativeCallHaptics(connected: { }, ended: { }, capsuleEvent: { self.count += 1 })
        }
    }

    private func makeLab(_ cast: NativeCallAssistantsLabBackend.Cast,
                         latency: NativeCallAssistantsLabBackend.Latency = .none,
                         audioRouting: NativeCallAudioRoutingRecorder? = nil,
                         haptics: NativeCallHaptics = .none,
                         output: AVAudioSession.Port? = nil) -> NativeCallAssistantsLiveLab {
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
        let routing = output.map { port in
            NativeCallAudioRouting(availableRoutes: {
                                       NativeCallAudioRoutes.build(activeOutputs: [NativeCallAudioPort(type: port, name: "Out", uid: "out")],
                                                                   availableInputs: [])
                                   },
                                   hasExternalRoute: { port == .headphones },
                                   setSpeakerEnabled: { _ in },
                                   selectRoute: { _ in },
                                   followRouteChange: { _ in },
                                   speakerChanges: Empty().eraseToAnyPublisher())
        }
        return NativeCallAssistantsLiveLab(backend: NativeCallAssistantsLabBackend(cast: cast, role: .moderator, latency: latency,
                                                                                   joinDuration: latency == .none ? .milliseconds(10) : .milliseconds(2500)),
                                           audioRouting: routing ?? audioRouting?.routing ?? .inert,
                                           haptics: haptics)
    }

    /// A 1:1 call with your assistant translating into Ukrainian, the sheet open.
    private func makeLabTranslating() async -> NativeCallAssistantsLiveLab {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.translation.isButtonVisible }
        context.send(viewAction: .showAgentCenter)
        context.send(viewAction: .produceTranslation)
        await waitUntil(seconds: 8) { context.viewState.translation.ownLanguage == "uk" }
        await waitUntil { context.viewState.agents.ownAgents.first?.shown.isTranslating == true }
        await waitUntil { context.viewState.agentActionsInFlight.isEmpty }
        return lab
    }

    private func translationAction(_ context: NativeCallScreenViewModel.Context) -> NativeCallTranslationAction? {
        NativeCallTranslationAction(stage: NativeCallOwnAssistantStage(context), viewState: context.viewState)
    }

    private func waitUntil(seconds: Int = 3, _ condition: () -> Bool) async {
        for _ in 0..<(seconds * 100) where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

// MARK: - 1.0.3: each job asks before it starts

extension NativeCallTranslationLabTests {
    /// 1.0.3, the call lab's pick C: Notes and Talk ask before they start, under the buttons; a second tap on the ringed
    /// button takes the question back; the platform hears nothing until the question's action.
    @Test(arguments: [NativeCallAssistantJob.summary, .conversation])
    func notesAndTalkAskBeforeTheyStart(job: NativeCallAssistantJob) async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .showAgentCenter)

        context.send(viewAction: .tapAssistantJob(job))
        #expect(context.assistantConfirmation == .start(job))
        #expect(context.viewState.attachesSent.isEmpty)

        context.send(viewAction: .tapAssistantJob(job))
        #expect(context.assistantConfirmation == nil)

        context.send(viewAction: .tapAssistantJob(job))
        // The question's action, as the sheet sends it.
        context.send(viewAction: .confirmAssistantJob(job))
        #expect(context.assistantConfirmation == nil)
        await waitUntil { lab.backend.ownSession != nil }
        #expect(lab.backend.ownSession != nil)
    }

    /// Another job's question gives way to Translation's when its button is tapped, and the platform hears nothing.
    @Test
    func theTranslationButtonBringsItsQuestionBack() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .showAgentCenter)
        context.send(viewAction: .tapAssistantJob(.summary))
        #expect(context.assistantConfirmation == .start(.summary))

        context.send(viewAction: .tapAssistantJob(.translation))

        #expect(context.assistantConfirmation == .start(.translation))
        #expect(context.viewState.attachesSent.isEmpty)
        #expect(lab.backend.ownSession == nil)
    }

    /// Follow-up review: Start answers Translation's question, so a refusal or a failed join after it shows its reason
    /// rather than the question again.
    @Test
    func startClearsTranslationsQuestion() async {
        let lab = makeLab(.group)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .setMyLanguage("uk"))
        context.send(viewAction: .showAgentCenter)
        context.send(viewAction: .tapAssistantJob(.translation))
        #expect(context.assistantConfirmation == .start(.translation))

        context.send(viewAction: .produceTranslation)

        #expect(context.assistantConfirmation == nil)
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Follow-up review: «Try again» after a refused turn-off retries the turn-off, not nothing.
    @Test
    func tryAgainRetriesARefusedTurnOff() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .confirmAssistantJob(.summary))
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.isSummaryArmed == true }
        await waitUntil { context.viewState.agentActionsInFlight.isEmpty }
        lab.backend.nextFailure = .network
        context.send(viewAction: .tapAssistantJob(.summary))
        await waitUntil { context.viewState.agentCenter.lastError != nil }
        await waitUntil { context.viewState.agentActionsInFlight.isEmpty }
        #expect(context.viewState.agents.ownAgents.first?.shown.isSummaryArmed == true)

        context.send(viewAction: .retryAssistantJob(.summary))

        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.isSummaryArmed != true }
        #expect(context.viewState.agents.ownAgents.first?.shown.isSummaryArmed != true)
    }

    /// Follow-up review: «Try again» after a refused «Translate into …» moves the translation, not stops it.
    @Test
    func tryAgainRetriesARefusedLanguageSwitch() async {
        let lab = await makeLabTranslating()
        let context = lab.viewModel.context
        context.send(viewAction: .pickTranslationLanguage("de"))
        lab.backend.nextFailure = .network
        context.send(viewAction: .applyPickedTranslationLanguage)
        await waitUntil { context.viewState.agentCenter.lastError != nil }
        await waitUntil { context.viewState.agentActionsInFlight.isEmpty }
        #expect(context.viewState.translation.ownLanguage == "uk")

        context.send(viewAction: .retryAssistantJob(.translation))

        await waitUntil(seconds: 8) { context.viewState.translation.ownLanguage == "de" }
        #expect(context.viewState.translation.ownLanguage == "de")
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
    }

    /// Review finding: a yes to a job that turned on meanwhile (another device, a room tool) never turns it off.
    @Test
    func aYesToAJobAlreadyOnLeavesItOn() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .showAgentCenter)
        context.send(viewAction: .tapAssistantJob(.summary))
        context.send(viewAction: .toggleAssistantJob(.summary))
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.isSummaryArmed == true }

        context.send(viewAction: .confirmAssistantJob(.summary))

        #expect(context.assistantConfirmation == nil)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(context.viewState.agents.ownAgents.first?.shown.isSummaryArmed == true)
    }

    /// Review finding: a join that failed is no dead end — the tapped job's question comes again and its yes retries.
    @Test
    func aFailedJoinIsRetriedByTheQuestion() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .showAgentCenter)
        lab.backend.nextFailure = .network
        context.send(viewAction: .confirmAssistantJob(.summary))
        try? await Task.sleep(for: .milliseconds(200))
        await waitUntil { context.viewState.agentActionsInFlight.isEmpty }
        #expect(lab.backend.ownSession == nil)

        context.send(viewAction: .tapAssistantJob(.summary))
        #expect(context.assistantConfirmation == .start(.summary))
        context.send(viewAction: .confirmAssistantJob(.summary))

        await waitUntil(seconds: 8) { lab.backend.ownSession != nil }
        #expect(lab.backend.ownSession != nil)
    }

    /// A job already on turns off at once, without a question.
    @Test
    func aJobAlreadyOnTurnsOffWithoutAQuestion() async {
        let lab = makeLab(.onePerson)
        let context = lab.viewModel.context
        await waitUntil { context.viewState.agentCenter.isAvailable }
        context.send(viewAction: .toggleAssistantJob(.summary))
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.isSummaryArmed == true }
        context.send(viewAction: .showAgentCenter)

        context.send(viewAction: .tapAssistantJob(.summary))

        #expect(context.assistantConfirmation == nil)
        await waitUntil(seconds: 8) { context.viewState.agents.ownAgents.first?.shown.isSummaryArmed != true }
        #expect(context.viewState.agents.ownAgents.first?.shown.isSummaryArmed != true)
    }
}

#endif
