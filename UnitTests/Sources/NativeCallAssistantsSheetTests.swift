//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0083, question 401): what the Assistants sheet's root shows, and the words it uses.

@MainActor
struct NativeCallAssistantsSheetTests {
    // MARK: Layout

    /// Remark 2: until the platform first answers, placeholders, even with agents already on the roster.
    @Test(arguments: [true, false])
    func placeholdersHoldTheSheetUntilThePlatformAnswers(isLoading: Bool) {
        let layout = NativeCallAssistantsLayout(panel: panel(isAvailable: false, isLoading: isLoading))

        #expect(layout.content == .placeholders)
        #expect(!layout.showsUnavailableCard)
    }

    /// Checklist 1: a platform that never answered is the unavailable card, never an empty sheet's "no assistants".
    @Test
    func aPlatformThatNeverAnsweredIsUnavailable() {
        let layout = NativeCallAssistantsLayout(panel: panel(isAvailable: false, isLoading: false, lastError: .unavailable("timeout")))

        #expect(layout.content == .nothing)
        #expect(layout.showsUnavailableCard)
    }

    /// Remark 5: a re-read keeps the content in place.
    @Test
    func aReReadKeepsTheContent() {
        let layout = NativeCallAssistantsLayout(panel: panel(isAvailable: true, isLoading: true))

        #expect(layout.content == .ready)
        #expect(!layout.showsUnavailableCard)
    }

    /// Loading rule (operator, 2026-11-10): until the platform answers, the root is a placeholder, never "Not in the
    /// call" that turns into "Translating" a moment later.
    @Test
    func theRootIsLoadingUntilThePlatformAnswers() {
        let viewModel = NativeCallAssistantsLabModel.make(.empty)
        var state = viewModel.state
        state.agentCenter.isAvailable = false
        state.agentCenter.isLoading = true
        viewModel.state = state

        #expect(NativeCallOwnAssistantStage(viewModel.context) == .loading)
    }

    /// Loading rule: while a join check is out and was never answered, whether the assistant can come is unknown.
    @Test
    func aJoinCheckNeverAnsweredIsPendingWhileItIsOut() {
        let candidate = NativeAgentCenterCandidate(id: "a", mxid: "@assistant-alex:example.org", displayName: "Alex", avatarURL: nil, isRoomMember: true)
        var checking = panel(isAvailable: true, isLoading: false)
        checking.isCheckingJoins = true
        #expect(checking.isJoinCheckPending(candidate))

        checking.joinChecksAsked = ["a"]
        #expect(!checking.isJoinCheckPending(candidate))

        checking.joinChecksAsked = []
        checking.isCheckingJoins = false
        #expect(!checking.isJoinCheckPending(candidate))
    }

    // MARK: The private call (L11)

    /// S1: the private call's translation is the pocket interpreter, and both its sides show — «Я говорю» over
    /// «Человек рядом», never «Перевод на»; between people the one «Перевод на» row. The placeholders match the count.
    @Test
    func thePrivateCallsSheetShowsBothSidesOfThePair() {
        #expect(NativeCallTranslationSettingRow(isPrivateCall: true) == .pocketPair)
        #expect(NativeCallTranslationSettingRow(isPrivateCall: true).rowCount == 2)
        #expect(NativeCallTranslationSettingRow(isPrivateCall: false) == .translateInto)
        #expect(NativeCallTranslationSettingRow(isPrivateCall: false).rowCount == 1)
    }

    /// The neighbour's language page: the last neighbour first, and never my own language.
    @Test
    func theNeighbourListLeavesMyLanguageOut() {
        let catalog: [VoiceControlsCatalogLanguage] = ["en", "uk", "fr", "de"].map { .init(code: $0, label: $0) }
        let languages = NativeCallLanguagePage.neighbourLanguages(catalog: catalog, neighbour: "fr", myLanguage: "uk")
        #expect(languages.first == "fr")
        #expect(!languages.contains("uk"))
        #expect(Set(languages) == ["en", "fr", "de"])
        // A neighbour stored as my own language isn't offered either.
        #expect(!NativeCallLanguagePage.neighbourLanguages(catalog: catalog, neighbour: "uk", myLanguage: "uk").contains("uk"))
    }

    /// L11: in the private call neither «Перевод» nor «Разговор» is greyed by the other — a tap switches; between
    /// people, talking still greys translation and translating greys talk.
    @Test
    func inThePrivateCallTalkAndTranslationNeverGreyEachOther() {
        func button(_ job: NativeCallAssistantJob, _ facts: NativeCallAssistantDockState.Facts) -> NativeCallAssistantDockState.Button? {
            NativeCallAssistantDockState(facts).buttons.first { $0.job == job }
        }
        var talking = NativeCallAssistantDockState.Facts(isTalking: true)
        #expect(button(.translation, talking)?.isEnabled == false)
        talking.switchesTalkAndTranslation = true
        #expect(button(.translation, talking)?.isEnabled == true)

        var translating = NativeCallAssistantDockState.Facts(isTranslating: true, isTalkUnavailable: true)
        #expect(button(.conversation, translating)?.isEnabled == false)
        translating.switchesTalkAndTranslation = true
        #expect(button(.conversation, translating)?.isEnabled == true)

        // The switch in flight rings «Перевод».
        talking.pending = .translation
        #expect(button(.translation, talking)?.isPending == true)
    }

    // MARK: The translation badge (L12)

    /// One visual everywhere: the avatar badge «文 UA» is the call's only translation mark; no «文 → UA» pill under a
    /// name is left on the stage, the tiles or a 1:1 call.
    @Test
    func noUnderNamePillRemains() throws {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ElementX/Sources/Screens/NativeCallScreen/View")
        let files = try FileManager.default.contentsOfDirectory(atPath: views.path).filter { $0.hasSuffix(".swift") }
        #expect(files.count > 5)
        for file in files {
            let text = try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8)
            #expect(!text.contains("文 →"), "\(file) still draws the under-name pill")
            #expect(!text.contains("NativeCallHeardInBadge"), "\(file) still uses the old pill")
        }
    }

    // MARK: Copy

    /// L6: the profile and your limit are always in the own assistant's menu; removing it only while it is in the call.
    @Test
    func theOwnAssistantsMenuDependsOnWhetherItIsInTheCall() {
        #expect(NativeCallOwnAssistantMenuItem.items(isRemovableFromCall: true) == [.profile, .limit, .removeFromCall])
        #expect(NativeCallOwnAssistantMenuItem.items(isRemovableFromCall: false) == [.profile, .limit])
    }

    /// L8: the resting height is the measured tallest root for the text size, the same for every root state (the
    /// state is no input), and at AX sizes never taller than `.medium`.
    @Test
    func theRestingHeightIsTheMeasuredRootWhateverTheState() {
        NativeCallAssistantsDetent.store(412, for: .xLarge)
        let translating = NativeCallAssistantsLabModel.make(.translatingYou)
        let notInCall = NativeCallAssistantsLabModel.make(.empty)
        #expect(translating.context.viewState.agents != notInCall.context.viewState.agents)

        let height = NativeCallAssistantsDetent.resting(measured: NativeCallAssistantsDetent.measured(for: .xLarge), maximum: 900, isAccessibilitySize: false)
        #expect(height == 412)
        // AX sizes: a root taller than half stays at about `.medium`, so the call stays in view.
        #expect(NativeCallAssistantsDetent.resting(measured: 700, maximum: 900, isAccessibilitySize: true) == 450)
        #expect(NativeCallAssistantsDetent.resting(measured: 700, maximum: 900, isAccessibilitySize: false) == 700)
        // Not measured yet: half, never a guess that jumps.
        #expect(NativeCallAssistantsDetent.resting(measured: nil, maximum: 900, isAccessibilitySize: false) == 450)
    }

    /// Rows 10–11: starting while the runtime syncs (REST), else standing by, else the document's own line.
    @Test
    func theTranslationLineSaysStartingThenStandby() {
        #expect(NativeCallAssistantsCopy.translationStatus(isSyncing: true, isStandby: true) == UntranslatedL10n.screenNativeCallAssistantsStatusStarting)
        #expect(NativeCallAssistantsCopy.translationStatus(isSyncing: false, isStandby: true) == UntranslatedL10n.screenNativeCallAssistantsStatusStandby)
        #expect(NativeCallAssistantsCopy.translationStatus(isSyncing: false, isStandby: false) == nil)
    }

    /// A standby with nobody to translate says so; «takes over» is only for a standby another assistant covers.
    @Test
    func aStandbyWithNobodyToTranslateSaysNothingToTranslate() {
        #expect(NativeCallAssistantsCopy.translationStatus(isSyncing: false, isStandby: true, isNothingToTranslate: true)
            == UntranslatedL10n.screenNativeCallAssistantsStatusNothingToTranslate)
        #expect(NativeCallAssistantsCopy.translationStatus(isSyncing: true, isStandby: true, isNothingToTranslate: true)
            == UntranslatedL10n.screenNativeCallAssistantsStatusStarting)
        #expect(NativeCallAssistantsCopy.translationStatus(isSyncing: false, isStandby: false, isNothingToTranslate: true) == nil)
    }

    /// Remark 13: a removal names only what is still to be posted, and asks nothing when there is nothing.
    @Test
    func aRemovalNamesOnlyWhatIsStillToBePosted() {
        #expect(NativeCallAssistantsCopy.removeConfirmation(isRecording: true, isTakingNotes: true) == UntranslatedL10n.screenNativeCallAssistantsRemoveConfirmMessage)
        #expect(NativeCallAssistantsCopy.removeConfirmation(isRecording: true, isTakingNotes: false) == UntranslatedL10n.screenNativeCallAssistantsRemoveConfirmRecording)
        #expect(NativeCallAssistantsCopy.removeConfirmation(isRecording: false, isTakingNotes: true) == UntranslatedL10n.screenNativeCallAssistantsRemoveConfirmNotes)
        #expect(NativeCallAssistantsCopy.removeConfirmation(isRecording: false, isTakingNotes: false) == nil)
    }

    /// Board A: someone else's assistant in one sentence from your side, the main thing first.
    @Test
    func someoneElsesAssistantIsOneSentenceFromYourSide() {
        typealias Copy = NativeCallAssistantsCopy

        #expect(Copy.foreignStatus(translatesYou: "English", translates: "English", talks: false, records: false, takesNotes: false)
            == UntranslatedL10n.screenNativeCallAssistantsForeignStatusTranslatesYou("English"))
        #expect(Copy.foreignStatus(translatesYou: "English", translates: "English", talks: false, records: true, takesNotes: false)
            == "\(UntranslatedL10n.screenNativeCallAssistantsForeignStatusTranslatesYou("English")) · \(UntranslatedL10n.screenNativeCallAssistantsForeignStatusAlsoRecords)")
        #expect(Copy.foreignStatus(translatesYou: nil, translates: nil, talks: false, records: true, takesNotes: false)
            == UntranslatedL10n.screenNativeCallAssistantsForeignStatusRecordsYou)
        #expect(Copy.foreignStatus(translatesYou: nil, translates: nil, talks: true, records: false, takesNotes: true)
            == "\(UntranslatedL10n.screenNativeCallAssistantsForeignTalks) · \(UntranslatedL10n.screenNativeCallAssistantsForeignStatusAlsoNotes)")
        #expect(Copy.foreignStatus(translatesYou: nil, translates: nil, talks: false, records: false, takesNotes: false)
            == UntranslatedL10n.screenNativeCallAssistantsForeignListening)
    }

    /// Board A: the add an own agent was sent with is kept by its MXID, so its group holds those rows while it joins.
    @Test
    func theAddSentIsKeptForTheJoiningRows() {
        let viewModel = NativeCallAssistantsLabModel.make(.empty)
        let params = VoiceAttachParams(translation: nil, recording: false, summary: true, conversation: true)

        viewModel.context.send(viewAction: .attachAgentConfigured(agentID: NativeCallAssistantsLabModel.candidateID, params: params))

        #expect(viewModel.context.viewState.attachesSent[NativeCallAssistantsLabModel.myAgent] == params)
    }

    /// Board A: "My limit" opens the agent's weekly Limit page; without a platform there is none to open.
    @Test
    func myLimitOpensTheLimitPageOnlyWithAPlatform() {
        let viewModel = NativeCallAssistantsLabModel.make(.budget)

        viewModel.context.send(viewAction: .showAgentLimit(agentMxid: NativeCallAssistantsLabModel.myAgent))

        #expect(viewModel.context.agentLimitPage == nil)
    }

    /// L5 4.1: someone else's agent on the pill opens the sheet on "In the call"; the dock, and one's own agent, on
    /// your assistant.
    @Test(arguments: [(state: NativeCallAssistantsLabState.moderator, fromPill: true, opensInTheCall: true),
                      (.moderator, false, false),
                      (.twoAssistants, true, false)])
    func theSheetOpensOnThePageWithSomethingToDo(state: NativeCallAssistantsLabState, fromPill: Bool, opensInTheCall: Bool) {
        let viewModel = NativeCallAssistantsLabModel.make(state)

        viewModel.context.send(viewAction: fromPill ? .showAgentCenterFromPill : .showAgentCenter)

        #expect(viewModel.context.viewState.bindings.agentCenterPage == (opensInTheCall ? .inTheCall : nil))
        #expect(viewModel.context.isAgentCenterPresented)
    }

    /// "+ Add your translation" opens the sheet's root with nothing asked, where Translation's question rests — the same
    /// path as the Assistant button (1.0.3, operator: «щоб був один сценарій»).
    @Test
    func addingYourTranslationOpensTheSameRoot() {
        let viewModel = NativeCallAssistantsLabModel.make(.empty)
        viewModel.context.assistantConfirmation = .start(.summary)

        viewModel.context.send(viewAction: .addOwnTranslation)

        #expect(viewModel.context.isAgentCenterPresented)
        #expect(viewModel.context.viewState.bindings.agentCenterPage == nil)
        #expect(viewModel.context.assistantConfirmation == nil)
    }

    /// Brief 0085, scenario 9.3: with several own assistants and none picked for the chat, a tap asks which.
    @Test
    func severalAssistantsAskWhichFirst() {
        let viewModel = NativeCallAssistantsLabModel.make(.empty)
        var state = viewModel.state
        state.agentCenter.candidates.append(NativeAgentCenterCandidate(id: "second", mxid: "@assistant-alex-2:example.org",
                                                                       displayName: "Work assistant", avatarURL: nil, isRoomMember: true))
        viewModel.state = state

        viewModel.context.send(viewAction: .toggleAssistantJob(.summary))

        #expect(viewModel.context.assistantPickerJob == .summary)
        #expect(viewModel.context.isAgentCenterPresented)
        #expect(viewModel.context.viewState.attachesSent.isEmpty)
    }

    /// Scenario 2.1: with one own assistant, a tap brings it for that job.
    @Test
    func aTapOnAJobBringsTheOnlyAssistant() {
        let viewModel = NativeCallAssistantsLabModel.make(.empty)

        viewModel.context.send(viewAction: .toggleAssistantJob(.summary))

        #expect(viewModel.context.viewState.attachesSent[NativeCallAssistantsLabModel.myAgent]?.summary == true)
    }

    /// Scenario 9.1: a blocked translation opens the sheet on its reason instead of trying.
    @Test
    func aBlockedTranslationOpensTheSheetOnItsReason() {
        let viewModel = NativeCallAssistantsLabModel.make(.consentOwner)

        viewModel.context.send(viewAction: .produceTranslation)

        #expect(viewModel.context.viewState.translation.block == .aiConsentOwner)
        #expect(viewModel.context.isAgentCenterPresented)
        #expect(viewModel.context.viewState.attachesSent.isEmpty)
    }

    // MARK: One recording per call (question 404)

    /// Someone else's assistant records: «Запис» is a dimmed «Записує» that still takes a tap (it says who), never red
    /// or ringed; a refusal of your start doesn't turn it red either.
    @Test
    func someoneElsesRecordingCoversYourRecordingButton() throws {
        var facts = NativeCallAssistantDockState.Facts(recordingCover: .recording)
        facts.refused = .recording
        facts.pending = .recording
        let button = try #require(NativeCallAssistantDockState(facts).buttons.first { $0.job == .recording })

        #expect(button.isCovered)
        #expect(!button.isEnabled)
        #expect(!button.isRefused)
        #expect(!button.isPending)
        Bundle.overrideLocalizations = ["uk"]
        defer { Bundle.overrideLocalizations = nil }
        #expect(NativeCallAssistantsCopy.title(button) == "Записує")
    }

    /// Once theirs stopped, yours is live again as «Продовжити»: a new recording, a new file.
    @Test
    func aStoppedRecordingOffersToContinueWithYours() throws {
        let button = try #require(NativeCallAssistantDockState(.init(recordingCover: .stopped)).buttons.first { $0.job == .recording })

        #expect(button.isEnabled)
        #expect(!button.isCovered)
        #expect(button.cover == .stopped)
        Bundle.overrideLocalizations = ["uk"]
        defer { Bundle.overrideLocalizations = nil }
        #expect(NativeCallAssistantsCopy.title(button) == "Продовжити")
    }

    /// Your own recording is the call's one: it never shows as covered, and the other buttons never do.
    @Test
    func yourOwnRecordingIsNeverCovered() {
        let buttons = NativeCallAssistantDockState(.init(isRecording: true, recordingCover: .recording)).buttons

        #expect(buttons.allSatisfy { $0.cover == nil })
        #expect(buttons.first { $0.job == .recording }?.isOn == true)
    }

    /// Covered while theirs records, «Продовжити» once it stopped and until yours starts; nothing after yours.
    @Test
    func theCoverFollowsTheirRecordingUntilYoursStarts() {
        var tracker = NativeCallRecordingCoverTracker()
        let now = Date()

        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: nil, now: now)
        #expect(tracker.cover == nil)
        tracker.update(recorders: [mira], undetermined: [], isOwnRecording: false, refusal: nil, now: now)
        #expect(tracker.cover == cover(mira, .recording))
        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: nil, now: now)
        #expect(tracker.cover == cover(mira, .stopped))
        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: nil, now: now.addingTimeInterval(60))
        #expect(tracker.cover == cover(mira, .stopped))
        tracker.update(recorders: [], undetermined: [], isOwnRecording: true, refusal: nil, now: now)
        #expect(tracker.cover == nil)
        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: nil, now: now)
        #expect(tracker.cover == nil)
    }

    /// A second recorder (a race lost elsewhere) never swaps the one already named.
    @Test
    func theRecorderShownStaysNamedWhileItRecords() {
        var tracker = NativeCallRecordingCoverTracker()
        let bohdan = NativeCallRecordingCoverTracker.Recorder(agentMxid: "@assistant-bohdan:example.org", ownerMxid: "@bohdan:example.org")

        tracker.update(recorders: [mira], undetermined: [], isOwnRecording: false, refusal: nil, now: Date())
        tracker.update(recorders: [bohdan, mira], undetermined: [], isOwnRecording: false, refusal: nil, now: Date())

        #expect(tracker.cover == cover(mira, .recording))
    }

    /// The race: a start refused with `409 /errors/recording-covered` covers the button at once, hands over to the
    /// documents when they say who records, and that recording's stop then offers «Продовжити».
    @Test
    func aRefusedStartIsCoveredUntilTheDocumentsSpeak() {
        var tracker = NativeCallRecordingCoverTracker()
        let now = Date()
        let refusal = NativeAgentCenterRecordingRefusal(cover: VoiceRecordingCover(agentMxid: mira.agentMxid, ownerMxid: mira.ownerMxid), at: now)

        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: refusal, now: now.addingTimeInterval(1))
        #expect(tracker.cover == cover(mira, .recording))
        tracker.update(recorders: [mira], undetermined: [], isOwnRecording: false, refusal: refusal, now: now.addingTimeInterval(2))
        #expect(tracker.cover == cover(mira, .recording))
        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: refusal, now: now.addingTimeInterval(3))
        #expect(tracker.cover == cover(mira, .stopped))
    }

    /// A refusal no document ever confirms covers the button for a while only, then lapses to nothing: nothing was
    /// seen recording, so nothing "stopped". It may name no one.
    @Test
    func aRefusalTheDocumentsNeverConfirmLapses() {
        var tracker = NativeCallRecordingCoverTracker()
        let now = Date()
        let refusal = NativeAgentCenterRecordingRefusal(cover: VoiceRecordingCover(agentMxid: nil, ownerMxid: nil), at: now)

        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: refusal, now: now.addingTimeInterval(1))
        #expect(tracker.cover == NativeCallRecordingCover(agentMxid: nil, ownerMxid: nil, phase: .recording))
        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: refusal, now: now.addingTimeInterval(NativeCallRecordingCoverTracker.refusalWindow + 1))
        #expect(tracker.cover == nil)
    }

    /// A recorder whose document went missing while it is still in the call hasn't stopped: nothing moves.
    @Test
    func aMissingDocumentIsNotAStop() {
        var tracker = NativeCallRecordingCoverTracker()
        tracker.update(recorders: [mira], undetermined: [], isOwnRecording: false, refusal: nil, now: Date())

        tracker.update(recorders: [], undetermined: [mira.agentMxid], isOwnRecording: false, refusal: nil, now: Date())
        #expect(tracker.cover == cover(mira, .recording))
        tracker.update(recorders: [], undetermined: [], isOwnRecording: false, refusal: nil, now: Date())
        #expect(tracker.cover == cover(mira, .stopped))
    }

    /// The owner the refusal named stays when the document that takes over names none.
    @Test
    func theRefusalsOwnerOutlivesADocumentWithout() {
        var tracker = NativeCallRecordingCoverTracker()
        let refusal = NativeAgentCenterRecordingRefusal(cover: VoiceRecordingCover(agentMxid: mira.agentMxid, ownerMxid: mira.ownerMxid), at: Date())
        let anonymous = NativeCallRecordingCoverTracker.Recorder(agentMxid: mira.agentMxid, ownerMxid: nil)

        tracker.update(recorders: [anonymous], undetermined: [], isOwnRecording: false, refusal: refusal, now: Date())

        #expect(tracker.cover == cover(mira, .recording))
    }

    /// «Продовжити» only where yours can start: after your own recording stopped in this call, no offer and no row.
    @Test
    func noContinueOnceYourOwnRecordingStopped() throws {
        let button = try #require(NativeCallAssistantDockState(.init(isRecordingStopped: true, recordingCover: .stopped)).buttons.first { $0.job == .recording })

        #expect(button.cover == nil)
        #expect(!button.isEnabled)
    }

    // MARK: How translation starts (1.0.3, the operator's pick B)

    /// The platform has your translation on while its lanes start: the button is Stop, as the Translation button would
    /// stop it, and a pick is held for «Translate into …».
    @Test
    func aTranslationOnWhileItsLanesStartIsRunning() {
        let viewModel = NativeCallAssistantsLabModel.make(.translatingYou)
        var state = viewModel.state
        state.agentClaims.documents = [NativeCallAssistantsLabModel.myAgent: .make()]
        viewModel.state = state
        #expect(viewModel.context.viewState.agents.ownAgents.first?.shown.isTranslating == false)

        #expect(translationAction(viewModel) == .stop)
        viewModel.context.send(viewAction: .pickTranslationLanguage("fr"))
        #expect(viewModel.context.viewState.pickedTranslationLanguage == "fr")
        #expect(translationAction(viewModel) == .translateInto(language: "fr"))
    }

    /// Your assistant is in the call but its session isn't read yet: the buttons are inert, so Start isn't offered.
    @Test
    func noStartOnAnAssistantWhoseSessionIsntRead() throws {
        let viewModel = NativeCallAssistantsLabModel.make(.lateSessionList)
        guard case .inCall(let agent) = NativeCallOwnAssistantStage(viewModel.context) else {
            Issue.record("Expected your assistant in the call")
            return
        }
        #expect(agent.control == nil)

        #expect(translationAction(viewModel) == nil)
    }

    private let mira = NativeCallRecordingCoverTracker.Recorder(agentMxid: "@assistant-mira:example.org", ownerMxid: "@mira:example.org")

    private func cover(_ recorder: NativeCallRecordingCoverTracker.Recorder, _ phase: NativeCallRecordingCover.Phase) -> NativeCallRecordingCover {
        NativeCallRecordingCover(agentMxid: recorder.agentMxid, ownerMxid: recorder.ownerMxid, phase: phase)
    }

    // MARK: Helpers

    private func translationAction(_ viewModel: NativeCallScreenViewModel) -> NativeCallTranslationAction? {
        NativeCallTranslationAction(stage: NativeCallOwnAssistantStage(viewModel.context), viewState: viewModel.context.viewState)
    }

    private func panel(isAvailable: Bool, isLoading: Bool, lastError: NativeAgentCenterError? = nil) -> NativeCallAgentPresentation.Panel {
        NativeCallAgentPresentation.Panel(isAvailable: isAvailable, isLoading: isLoading, lastError: lastError, candidates: [], catalog: [])
    }
}
