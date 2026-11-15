//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 401): the call's Assistants sheet live, as in a real call. The call screen
// with its dock runs on a real view model and Agent Center controller; behind them `NativeCallAssistantsLabBackend`
// answers the platform's calls and plays the agents' side. The dock's Assistants button opens the real sheet, and every
// tap in it changes the in-memory platform.
//
// The scenario panel floats in its own window over the status bar, above the sheet at any height: who is in the call,
// your role, the latency of every call, the failure the next action meets, the language, Reset. The language switches
// the app's strings in place (`Bundle.overrideLocalizations` and the SwiftUI locale); text the system draws follows
// the device, so relaunch with `-AppleLanguages "(ru)"` for that. Launch arguments, with `-SpiralCallMotionLab YES
// -SpiralCallMotionLabStage AssistantsLive`: `-SpiralCallMotionLabLiveCast private|person|personAssistant|group`,
// `-SpiralCallMotionLabLiveRole moderator|member`, `-SpiralCallMotionLabLiveLatency 0|300ms|1.5s|4s`,
// `-SpiralCallMotionLabLiveLanguage ru|uk|en|phone` (phone: the app's strings follow `-AppleLanguages`, for the other locales). On a phone with a Debug or Staging build: Settings › Developer options ›
// Call motion lab, Screen › AssistantsLive, then "Show the call"; or the same arguments in the Xcode scheme.
//
// Brief 0085 (question 403): you speak Ukrainian (the lab's phone language); John speaks English; in the group Mira
// English, Alex German, Bohdan Ukrainian. The panel plays the other side — someone else's assistant starts or stops
// translating for you, your own limit runs out, the call rings, you have three assistants — and opens the chat's tool
// "Call translation", which the next call (Reset) starts with. `-SpiralCallMotionLabLiveScenario <name>` plays one of the
// mockup's scenarios from the start: `theyTranslate`, `theyStop`, `consent`, `paused`, `several`, `ringing`, `tool`,
// `toolScreen`, `ownLimit`; ADR-0094's states: `standby` (your assistant stands by: someone else covers everyone),
// `ownerLeft` (the translation you hear stops: its owner left the call), `syncing` (your assistant's new mode is never
// acknowledged; with `-SpiralCallMotionLabLiveJobs translation`), `theirStandby` (someone else's assistant stands by
// in your language), `takeover` (…and takes over when you stop yours, 12 s in; with `-SpiralCallMotionLabLiveJobs
// translation`); question 404's `theyRecord` (someone else's assistant records the call: yours shows «Записує») and
// `theyStopRecording` (…and stops 4 s in: «Продовжити»), with the group or "1:1 + asst" cast; question 409's
// `translatesYou` (Mira's assistant in the group, John's in a 1:1, starts translating you 4 s in — the capsule's
// «Змінити» while your language is the default, the 文A menu's «Я говорю: … ›»). Static ducking's release (2026-11-12):
// "Bohdan translates" (group) or "John translates" (1:1) with "…'s lane never airs" on (`unairedLane` from the launch)
// — the panel says when that person's original comes back to full volume after 4 s of their speech.
//
// Lab round 2 (L1–L5) drives every Assistants sheet screen of `DESIGNS/spiral-agent-center-plan.png` from the launch,
// as the overlay panel can't be tapped by a simulator script:
// - `-SpiralCallMotionLabLiveJobs translation,summary` turns your assistant's jobs on once the platform answers;
// - `-SpiralCallMotionLabLiveSheet <page>` then opens the sheet: `root`, `newTranslation`, `languages` (my language:
//   «Перевод на», or «Я говорю» with the private cast), `inCall`, `foreign`, `recordAsk`, `recordCovered` (the
//   covered «Записує» tapped: the card, question 404), `recordAfterStop` (with `theyStopRecording`: «Продовжити»
//   tapped once theirs stopped), `removeAsk`, `chooser`,
//   `translationTap` (the sheet, then «Перевод» tapped), `spokenLanguage` (the list «Змінити» opens, question 409),
//   `limit` (your limit page), or before the platform answers
//   `loading`, `loading-inCall`, `loading-languages`; `loading-limit` holds the limit page's own read; `settingsLimit`
//   shows the same limit page as the agent's settings draw it, for comparison;
// - `-SpiralCallMotionLabLiveListen uk` hears that track (someone else's, started if missing);
// - `-SpiralCallMotionLabLiveMyLanguage en` speaks that language;
// - `-SpiralCallMotionLabLiveJoinSeconds 600` keeps an assistant on its way;
// - `-SpiralCallMotionLabLiveLatency 6` (any number of seconds) holds every answer of the platform, for the loading
//   states.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Combine
import Compound
import SpiralTokens
import SwiftUI

struct CallMotionLabAssistantsLiveStage: View {
    enum Language: String, CaseIterable, Identifiable {
        case russian = "ru"
        case ukrainian = "uk"
        case english = "en"
        /// The device's own language: any locale the app ships, from `-AppleLanguages`.
        case phone

        var id: Self {
            self
        }

        var title: String {
            self == .phone ? "📱" : rawValue.uppercased()
        }

        var localizations: [String]? {
            self == .phone ? nil : [rawValue]
        }

        var locale: Locale {
            self == .phone ? .current : Locale(identifier: rawValue)
        }
    }

    /// Brief 0085: a mockup scenario played from the launch, as the panel would.
    enum Scenario: String {
        /// 3.1: someone else's assistant starts translating into your language.
        case theyTranslate
        /// 4.1: …and stops on its limit.
        case theyStop
        /// 9.1: you haven't allowed AI.
        case consent
        /// 9.2: your assistant is paused.
        case paused
        /// 9.3: you have three assistants.
        case several
        /// 9.4: the call still rings.
        case ringing
        /// 5.2: the chat's tool is on.
        case tool
        /// 5.1: the chat's tool screen, open.
        case toolScreen
        /// L5 2.4: your translation stops on your own limit.
        case ownLimit
        /// Row 10: your assistant stands by, someone else's covers everyone.
        case standby
        /// Row 6: the translation you hear stops, its owner left the call.
        case ownerLeft
        /// Row 11: your assistant's new mode waits for the runtime.
        case syncing
        /// D10: someone else's assistant stands by in your language.
        case theirStandby
        /// D10: …and takes over your lanes when you stop yours.
        case takeover
        /// Question 404: someone else's assistant records the call (Mira's in the group, John's in "1:1 + asst"), so
        /// yours can't — as the group and that 1:1 start anyway; named for the launch.
        case theyRecord
        /// Question 404: …and stops recording 4 s in: «Продовжити».
        case theyStopRecording
        /// Question 409: Mira's assistant starts translating you 4 s in (the group), John's (a 1:1).
        case translatesYou
        /// 2026-11-12: 4 s in, Bohdan's assistant translates Mira (the group) or John's translates him (a 1:1), and that
        /// lane never airs.
        case unairedLane
    }

    /// Lab round 2: what the launch does once the call is up, so each sheet screen can be captured.
    struct Script {
        var jobs: [NativeCallAssistantJob] = []
        var sheet: String?
        var listen: String?
        var myLanguage: String?

        static func fromLaunchArguments() -> Script {
            let defaults = UserDefaults.standard
            let jobs = (defaults.string(forKey: "SpiralCallMotionLabLiveJobs") ?? "").split(separator: ",").compactMap { name -> NativeCallAssistantJob? in
                switch name {
                case "translation": .translation
                case "summary": .summary
                case "recording": .recording
                case "conversation": .conversation
                default: nil
                }
            }
            return Script(jobs: jobs,
                          sheet: defaults.string(forKey: "SpiralCallMotionLabLiveSheet"),
                          listen: defaults.string(forKey: "SpiralCallMotionLabLiveListen"),
                          myLanguage: defaults.string(forKey: "SpiralCallMotionLabLiveMyLanguage"))
        }

        var isEmpty: Bool {
            jobs.isEmpty && sheet == nil && listen == nil
        }
    }

    struct Settings: Equatable {
        var cast: NativeCallAssistantsLabBackend.Cast
        var role: NativeCallAssistantsLabBackend.Role
        var latency: NativeCallAssistantsLabBackend.Latency
        var language: Language

        static func fromLaunchArguments() -> Settings {
            let defaults = UserDefaults.standard
            return Settings(cast: .init(rawValue: defaults.string(forKey: "SpiralCallMotionLabLiveCast") ?? "") ?? .onePerson,
                            role: .init(rawValue: defaults.string(forKey: "SpiralCallMotionLabLiveRole") ?? "") ?? .moderator,
                            latency: .init(rawValue: defaults.string(forKey: "SpiralCallMotionLabLiveLatency") ?? "") ?? .short,
                            language: .init(rawValue: defaults.string(forKey: "SpiralCallMotionLabLiveLanguage") ?? "") ?? .english)
        }
    }

    @Environment(\.nativeCallVoiceLevels) private var levels
    @State private var renderer = CallMotionLabVideoRenderer()
    @State private var settings = Settings.fromLaunchArguments()
    @State private var lab: NativeCallAssistantsLiveLab?
    @State private var hitArea = CallMotionLabOverlayHitArea()
    /// The chat's tool outlives a call, as a chat's tool does (scenario 5.2).
    @State private var tool: NativeCallTranslationTool?
    @State private var toolScreen: CallTranslationToolScreenViewModel?
    /// `settingsLimit`: the limit page as the agent's settings draw it.
    @State private var settingsLimitPage: NativeCallAgentLimitPage?

    var body: some View {
        ZStack {
            Color.clear
            if let lab {
                NativeCallScreen(context: lab.viewModel.context, videoRenderer: renderer, voiceLevels: levels)
                    // The app's strings are read as they are drawn: a new language draws them again.
                    .id(settings.language)
            }
        }
        .environment(\.locale, settings.language.locale)
        .sheet(isPresented: Binding { toolScreen != nil } set: { if !$0 { toolScreen = nil } }) {
            if let toolScreen {
                ElementNavigationStack {
                    CallTranslationToolScreen(context: toolScreen.context)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.actionDone) { self.toolScreen = nil }
                            }
                        }
                }
                .environment(\.locale, settings.language.locale)
            }
        }
        .sheet(item: $settingsLimitPage) { page in
            ElementNavigationStack {
                AgentUsageScreen(context: page.viewModel.context)
            }
            .environment(\.locale, settings.language.locale)
        }
        .background {
            if let lab {
                CallMotionLabOverlayWindow(hitArea: hitArea) {
                    CallMotionLabAssistantsLivePanel(settings: $settings,
                                                     backend: lab.backend,
                                                     hitArea: hitArea,
                                                     reset: reset,
                                                     setRinging: lab.setRinging,
                                                     showTool: showTool)
                }
            }
        }
        .onAppear {
            Bundle.overrideLocalizations = settings.language.localizations
            // Every lab starts with you speaking Ukrainian, as the phone says.
            NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
            reset()
        }
        .onDisappear {
            Bundle.overrideLocalizations = nil
            lab = nil
        }
        .onChange(of: settings.language) { _, language in
            Bundle.overrideLocalizations = language.localizations
        }
        .onChange(of: settings.latency) { _, latency in
            lab?.backend.latency = latency
        }
        .onChange(of: settings.cast) { reset() }
        // 2026-11-12: the covered person talks, for their original's never-aired release.
        .task(id: lab.map(ObjectIdentifier.init)) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                lab?.backend.advanceCoveredVoice(by: 0.1, now: Date())
            }
        }
        .onChange(of: settings.role) { reset() }
    }

    private func reset() {
        if let lab {
            tool = lab.backend.tool
        }
        let scenario = Scenario(rawValue: UserDefaults.standard.string(forKey: "SpiralCallMotionLabLiveScenario") ?? "")
        if lab == nil, scenario == .tool {
            tool = NativeCallTranslationTool(isEnabled: true, language: "uk", translatesIfNobodyDoes: true)
        }
        let defaults = UserDefaults.standard
        let joinSeconds = defaults.string(forKey: "SpiralCallMotionLabLiveJoinSeconds").flatMap(Double.init)
        let backend = NativeCallAssistantsLabBackend(cast: settings.cast, role: settings.role, latency: settings.latency, tool: tool,
                                                     joinDuration: joinSeconds.map { .milliseconds(Int($0 * 1000)) } ?? .milliseconds(2500))
        if let seconds = defaults.string(forKey: "SpiralCallMotionLabLiveLatency").flatMap(Double.init) {
            backend.latencyOverride = .milliseconds(Int(seconds * 1000))
        }
        switch scenario {
        case .consent: backend.block = .consentOwner
        case .paused: backend.setPaused(true)
        case .several: backend.hasSeveralAssistants = true
        case .syncing: backend.syncDuration = .seconds(600)
        case .standby: backend.startOwnStandby()
        case .theirStandby, .takeover: backend.startForeignStandby()
        case .unairedLane: backend.isCoveredLaneSilent = true
        case .theyTranslate, .theyStop, .ringing, .tool, .toolScreen, .ownLimit, .ownerLeft, .theyRecord, .theyStopRecording, .translatesYou, nil:
            break
        }
        let script = Script.fromLaunchArguments()
        if let language = script.myLanguage {
            NativeCallAssistantsLiveLab.myLanguageStore.setChosen(language)
        }
        let lab = NativeCallAssistantsLiveLab(backend: backend)
        self.lab = lab
        if !script.isEmpty || scenario == .ownLimit {
            Task {
                await lab.play(script, exhaustingLimit: scenario == .ownLimit) { viewModel in
                    settingsLimitPage = NativeCallAgentLimitPage(viewModel: viewModel)
                }
            }
        }
        switch scenario {
        case .theyTranslate, .theyStop, .unairedLane:
            Task {
                try? await Task.sleep(for: .seconds(4))
                backend.startForeignTranslation()
                guard scenario == .theyStop else { return }
                // Long enough to pick it in the 文A menu first.
                try? await Task.sleep(for: .seconds(20))
                backend.stopForeignTranslation(reason: .aiLimit)
            }
        case .ownerLeft:
            // Heard first (`-SpiralCallMotionLabLiveListen uk` starts it), then its owner is gone.
            Task {
                try? await Task.sleep(for: .seconds(6))
                backend.stopForeignTranslation(reason: .ownerLeft)
            }
        case .takeover:
            // Your assistant translates first (`-SpiralCallMotionLabLiveJobs translation`), then you stop it.
            Task {
                try? await Task.sleep(for: .seconds(12))
                lab.viewModel.context.send(viewAction: .toggleAssistantJob(.translation))
            }
        case .ringing:
            lab.setRinging(true)
        case .toolScreen:
            showTool()
        case .theyStopRecording:
            Task {
                try? await Task.sleep(for: .seconds(4))
                backend.stopForeignRecording()
            }
        case .translatesYou:
            Task {
                try? await Task.sleep(for: .seconds(4))
                backend.startTranslatingYou()
            }
        case .consent, .paused, .several, .tool, .ownLimit, .standby, .syncing, .theirStandby, .theyRecord, nil:
            break
        }
    }

    /// "Перевод звонков" in the call: the same screen as the chat's Tools, read and stored through the call.
    private func showTool() {
        guard let lab else { return }
        toolScreen = CallTranslationToolScreenViewModel(service: lab.controller,
                                                        myLanguageStore: NativeCallAssistantsLiveLab.myLanguageStore,
                                                        cachedCatalog: NativeCallAssistantsLabBackend.catalog)
    }
}

/// One live call: the real view model and controller over the lab's platform, fed the roster the platform plays.
final class NativeCallAssistantsLiveLab {
    let backend: NativeCallAssistantsLabBackend
    let viewModel: NativeCallScreenViewModel
    private let session: NativeCallSession
    let controller: NativeAgentCenterController
    private let sessionDelegate: LabSessionDelegate
    private var documents: [String: SpiralAgentStateReader.AgentClaim] = [:]
    private var languages: [String: String] = [:]

    init(backend: NativeCallAssistantsLabBackend, audioRouting: NativeCallAudioRouting = .inert, haptics: NativeCallHaptics = .system) {
        self.backend = backend
        let me = NativeCallAssistantsLabBackend.me
        let transport = NativeCallScreen_Previews.makePreviewTransport()
        transport.localIdentity = "\(me):DEVICE"
        // Every stub the dock can reach answers: a nil one traps.
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "\(me):DEVICE"
        rtcSession.updates = Empty().eraseToAnyPublisher()
        rtcSession.setMediaReturnValue = .success(())
        rtcSession.joinEncryptMediaNotificationMediaLanguageReturnValue = .success(())
        rtcSession.leaveReturnValue = .success(())
        rtcSession.membershipsReturnValue = .success([])
        session = NativeCallSession(rtcSession: rtcSession,
                                    isRoomEncrypted: true,
                                    notifyRoom: false,
                                    configuration: .init(media: .audio, scope: backend.scope),
                                    transport: transport)
        controller = NativeAgentCenterController(agentPlatformService: backend.makeService(),
                                                 roomID: NativeCallAssistantsLabBackend.roomID,
                                                 roomMemberMxids: { backend.roomMembers },
                                                 inviteAgent: { _ in true },
                                                 canKick: { backend.canKick },
                                                 kickAgent: { await backend.kick($0) },
                                                 translationPort: backend)
        let peer = backend.peer
        viewModel = NativeCallScreenViewModel(session: session,
                                              callKitService: CallKitServiceMock(.init()),
                                              agentCenter: controller,
                                              appMediator: AppMediatorMock(.init()),
                                              haptics: haptics,
                                              audioRouting: audioRouting,
                                              isVideoCall: false,
                                              roomID: NativeCallAssistantsLabBackend.roomID,
                                              roomName: backend.roomName,
                                              scope: backend.scope,
                                              roomAvatar: .heroes([UserProfile(userID: peer, displayName: backend.roomName)]),
                                              memberProfiles: Just(backend.profiles).eraseToAnyPublisher(),
                                              myLanguageStore: Self.myLanguageStore,
                                              languageCatalog: Self.languageCatalog)
        // The unstarted media session re-derives an empty call on any input (the "You hear" choice): the lab's roster
        // stays the only one the screen hears.
        sessionDelegate = LabSessionDelegate(screen: viewModel)
        session.delegate = sessionDelegate
        var state = viewModel.state
        state.callState = .connected
        state.callConnectedAt = Date(timeIntervalSinceNow: -42)
        viewModel.state = state

        apply(backend.roster, ringsDoorbell: false)
        backend.onRosterChange = { [weak self] roster in
            self?.apply(roster, ringsDoorbell: true)
        }
        // What the screen's `start()` does for the Agent Center, without a media session to start.
        Task { [controller, viewModel] in
            await controller.reload()
            if let code = viewModel.state.myLanguageCode {
                await controller.publishMyLanguage(code)
            }
            await controller.refreshJoinChecks()
        }
    }

    /// You speak Ukrainian here, whatever the device does; a pick on "My language" stays until the stage closes.
    static let myLanguageStore = NativeCallMyLanguageStore(defaults: UserDefaults(suiteName: "SpiralCallMotionLab") ?? .standard) { "uk_UA" }
    /// The lab's catalog, kept as the device keeps the real one: "As on the phone" resolves from the first frame.
    static let languageCatalog: NativeCallLanguageCatalogCache = {
        let cache = NativeCallLanguageCatalogCache(defaults: UserDefaults(suiteName: "SpiralCallMotionLab") ?? .standard, now: Date.init)
        cache.store(NativeCallAssistantsLabBackend.catalog)
        return cache
    }()

    /// Lab round 2: the launch's script — jobs on, a track heard, then the sheet on a page.
    func play(_ script: CallMotionLabAssistantsLiveStage.Script,
              exhaustingLimit: Bool,
              showSettingsLimit: (AgentUsageScreenViewModel) -> Void) async {
        let context = viewModel.context
        // The loading states: the sheet opens at once, on a page if asked (`loading`, `loading-inCall`,
        // `loading-languages`), before the platform answers.
        if let sheet = script.sheet, sheet.hasPrefix("loading"), sheet != "loading-limit" {
            context.send(viewAction: .showAgentCenter)
            switch sheet {
            case "loading-inCall": context.agentCenterPage = .inTheCall
            case "loading-languages": context.agentCenterPage = .myLanguage
            default: break
            }
            return
        }
        while !viewModel.state.agentCenter.isAvailable {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let latency = backend.latencyOverride ?? backend.latency.duration
        for (index, job) in script.jobs.enumerated() {
            if job == .translation, backend.cast == .privateCall {
                context.send(viewAction: .setNeighbourLanguage("fr"))
            } else {
                context.send(viewAction: .toggleAssistantJob(job))
            }
            // The first job brings the assistant; while it is kept on its way, the rest can't be asked yet.
            let joins = index == 0 && backend.joinDuration < .seconds(10) ? backend.joinDuration : .zero
            if index == 0, joins == .zero, backend.joinDuration >= .seconds(10) { break }
            try? await Task.sleep(for: joins + latency * 4 + .seconds(1))
        }
        if exhaustingLimit {
            backend.exhaustOwnLimit()
            try? await Task.sleep(for: latency * 2 + .seconds(1))
        }
        if let language = script.listen {
            if !viewModel.state.translation.options.contains(where: { $0.language == language }) {
                backend.startForeignTranslation()
                try? await Task.sleep(for: latency * 2 + .seconds(1))
            }
            context.send(viewAction: .setListeningChoice(.language(language)))
        }
        switch script.sheet {
        case "root":
            context.send(viewAction: .showAgentCenter)
        case "newTranslation":
            context.send(viewAction: .addOwnTranslation)
        case "languages":
            context.send(viewAction: .showAgentCenter)
            context.agentCenterPage = .myLanguage
        case "inCall":
            context.send(viewAction: .showAgentCenter)
            context.agentCenterPage = .inTheCall
        case "foreign":
            context.send(viewAction: .showAgentCenter)
            context.agentCenterPage = .foreign(mxid: backend.foreignAgentMxids.first ?? "")
        case "removeAsk":
            context.send(viewAction: .showAgentCenter)
            context.agentCenterPage = .foreign(mxid: backend.foreignAgentMxids.first ?? "")
            try? await Task.sleep(for: .milliseconds(800))
            context.assistantConfirmation = .removeFromChat(agentMxid: backend.foreignAgentMxids.first ?? "")
        case "recordAsk":
            context.send(viewAction: .showAgentCenter)
            context.assistantConfirmation = .recording
        case "recordCovered":
            // Question 404: the sheet, then the covered «Записує» tapped — the card says whose recording it is.
            context.send(viewAction: .showAgentCenter)
            while viewModel.state.recordingCover?.phase != .recording {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(600))
            context.send(viewAction: .tapAssistantJob(.recording))
        case "recordAfterStop":
            // Question 404 (`theyStopRecording`): theirs stopped, then «Продовжити» tapped — «Записувати дзвінок?» says
            // hers stopped and yours is a file of its own.
            context.send(viewAction: .showAgentCenter)
            while viewModel.state.recordingCover?.phase != .stopped {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(600))
            context.send(viewAction: .tapAssistantJob(.recording))
        case "chooser":
            context.send(viewAction: .showAgentCenter)
            context.agentCenterPage = .chooser(.translation)
        case "spokenLanguage":
            context.send(viewAction: .showSpokenLanguage)
        case "translationTap":
            // L11: «Перевод» tapped in the sheet — in the private call while talking, the neighbour's language opens.
            context.send(viewAction: .showAgentCenter)
            try? await Task.sleep(for: .milliseconds(600))
            context.send(viewAction: .toggleAssistantJob(.translation))
        case "limit", "loading-limit":
            if script.sheet == "loading-limit" {
                // The page's own read waits a minute: its placeholders stay to be seen.
                backend.latencyOverride = .seconds(60)
            }
            context.send(viewAction: .showAgentCenter)
            try? await Task.sleep(for: .milliseconds(600))
            context.send(viewAction: .showAgentLimit(agentMxid: NativeCallAssistantsLabBackend.myAgent))
        case "settingsLimit":
            if let viewModel = controller.makeUsageViewModel(agentID: NativeCallAssistantsLabBackend.agentID) {
                showSettingsLimit(viewModel)
            }
        default:
            break
        }
    }

    /// The call rings until someone answers (scenario 9.4).
    func setRinging(_ isRinging: Bool) {
        backend.setRinging(isRinging)
        var state = viewModel.state
        state.callState = isRinging ? .ringing : .connected
        viewModel.state = state
    }

    /// The transport's part: the roster, the documents and the memberships' languages; a changed document or language
    /// rings the doorbell. What one hears is the screen's own pick here: the lab has no media.
    private func apply(_ roster: NativeCallAssistantsLabBackend.Roster, ringsDoorbell: Bool) {
        viewModel.nativeCallSession(session, didChangeParticipants: roster.participants)
        viewModel.nativeCallSession(session, didChangeAgentClaims: roster.claims)
        let changed = documents != roster.claims.documents || languages != roster.languages
        documents = roster.claims.documents
        languages = roster.languages
        if ringsDoorbell, changed {
            viewModel.nativeCallSessionDidChangeAgentState(session)
        }
    }
}

/// Forwards the media session's news to the screen, except who is in the call, what they claim and what one hears:
/// those are the lab's.
private final class LabSessionDelegate: NativeCallSessionDelegate {
    private weak var screen: NativeCallScreenViewModel?

    init(screen: NativeCallScreenViewModel) {
        self.screen = screen
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeState state: NativeCallSessionState) { }
    func nativeCallSession(_ session: NativeCallSession, didChangeParticipants participants: [NativeCallParticipant]) { }
    func nativeCallSession(_ session: NativeCallSession, didChangeListening listening: NativeCallListeningState) { }
    func nativeCallSession(_ session: NativeCallSession, didChangeAgentClaims claims: NativeCallAgentClaims) { }
    func nativeCallSessionDidChangeAgentState(_ session: NativeCallSession) { }

    func nativeCallSession(_ session: NativeCallSession, didSendRingNotification eventID: String) {
        screen?.nativeCallSession(session, didSendRingNotification: eventID)
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeVideoTiles tiles: [NativeCallVideoTile]) {
        screen?.nativeCallSession(session, didChangeVideoTiles: tiles)
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeActiveVideo hasActiveVideo: Bool, isSpeakerEnabled: Bool) {
        screen?.nativeCallSession(session, didChangeActiveVideo: hasActiveVideo, isSpeakerEnabled: isSpeakerEnabled)
    }

    func nativeCallSession(_ session: NativeCallSession, didChangeConnectionQuality quality: NativeCallConnectionQuality) {
        screen?.nativeCallSession(session, didChangeConnectionQuality: quality)
    }
}

// MARK: - The scenario panel

private struct CallMotionLabAssistantsLivePanel: View {
    @Binding var settings: CallMotionLabAssistantsLiveStage.Settings
    @Bindable var backend: NativeCallAssistantsLabBackend
    let hitArea: CallMotionLabOverlayHitArea
    let reset: () -> Void
    let setRinging: (Bool) -> Void
    let showTool: () -> Void

    private var isExpanded: Bool {
        hitArea.isExpanded
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if isExpanded {
                    // Open, the panel takes every touch: a tap outside it closes it.
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { setExpanded(false) }
                }

                VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
                    pill
                    if isExpanded {
                        card
                    }
                }
                // In the status bar's place, clear of the sheet at its full height.
                .padding(.top, max(CompoundDesignTokens.space1X, (geometry.safeAreaInsets.top - 30) / 2))
                .padding(.leading, CompoundDesignTokens.space4X)
            }
            .ignoresSafeArea()
        }
    }

    private var pill: some View {
        Button { setExpanded(!isExpanded) } label: {
            HStack(spacing: CompoundDesignTokens.space1X) {
                Image(systemName: backend.nextFailure == .none ? "slider.horizontal.3" : "exclamationmark.triangle.fill")
                Text("\(settings.cast.shortTitle) · \(settings.latency.shortTitle)")
            }
            .font(.compound.bodyXSSemibold)
            .foregroundStyle(backend.nextFailure == .none ? Color.compound.textPrimary : Color.compound.textCriticalPrimary)
            .padding(.horizontal, CompoundDesignTokens.space2X)
            .frame(height: 30)
            .spiralGlass(in: Capsule(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scenario")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { hitArea.pillFrame = $0 }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
            row("Who is in the call") {
                Picker("Who is in the call", selection: $settings.cast) {
                    ForEach(NativeCallAssistantsLabBackend.Cast.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            row("Your role") {
                Picker("Your role", selection: $settings.role) {
                    ForEach(NativeCallAssistantsLabBackend.Role.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            row("Latency of every call") {
                Picker("Latency", selection: $settings.latency) {
                    ForEach(NativeCallAssistantsLabBackend.Latency.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            row("The next action meets") {
                Picker("The next action meets", selection: $backend.nextFailure) {
                    ForEach(NativeCallAssistantsLabBackend.Failure.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            row("Language") {
                Picker("Language", selection: $settings.language) {
                    ForEach(CallMotionLabAssistantsLiveStage.Language.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            row("Your assistant can't come") {
                Picker("Your assistant can't come", selection: $backend.block) {
                    Text("It can").tag(NativeCallAssistantsLabBackend.Block?.none)
                    ForEach(NativeCallAssistantsLabBackend.Block.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            Group {
                Toggle("Your assistant is paused", isOn: Binding { backend.isPaused } set: { backend.setPaused($0) })
                Toggle("You have three assistants", isOn: $backend.hasSeveralAssistants)
                Toggle("The call rings", isOn: Binding { backend.isRinging } set: { setRinging($0) })
            }
            .font(.compound.bodySM)

            if backend.cast != .privateCall {
                row("Translation, the other side") {
                    HStack(spacing: CompoundDesignTokens.space2X) {
                        Button(backend.cast == .group ? "Bohdan translates" : "John translates") { backend.startForeignTranslation() }
                            .disabled(backend.isSomeoneTranslatingForYou)
                        Button("Stops: limit") { backend.stopForeignTranslation(reason: .aiLimit) }
                            .disabled(!backend.isSomeoneTranslatingForYou)
                        Button("Stops: owner") { backend.stopForeignTranslation(reason: .ownerStopped) }
                            .disabled(!backend.isSomeoneTranslatingForYou)
                        Button("Owner left") { backend.stopForeignTranslation(reason: .ownerLeft) }
                            .disabled(!backend.isSomeoneTranslatingForYou)
                        Button("Stands by") { backend.startForeignStandby() }
                            .disabled(backend.isSomeoneTranslatingForYou)
                    }
                    .font(.compound.bodySMSemibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                // Question 409: the capsule's «Змінити», the 文A menu's «Я говорю».
                let translator = backend.cast == .group ? "Mira" : "John"
                Button(backend.isTranslatingYou ? "\(translator) stops translating you" : "\(translator) translates you") {
                    if backend.isTranslatingYou { backend.stopTranslatingYou() } else { backend.startTranslatingYou() }
                }
                .font(.compound.bodySMSemibold)
                // 2026-11-12: with "… translates" on, the lane for them never airs — they speak another language.
                Toggle("\(backend.coveredSpeakerName)'s lane never airs", isOn: $backend.isCoveredLaneSilent)
                    .font(.compound.bodySM)
                Text(coveredOriginalLine)
                    .font(.compound.bodyXS)
                    .foregroundStyle(.compound.textSecondary)
                HStack(spacing: CompoundDesignTokens.space2X) {
                    Button("Your limit runs out") { backend.exhaustOwnLimit() }
                    Spacer()
                    Button("Chat tool…") {
                        setExpanded(false)
                        showTool()
                    }
                }
                .font(.compound.bodySMSemibold)
            }

            Text(platformLine)
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)

            HStack(spacing: CompoundDesignTokens.space2X) {
                Button("Lift limits") { backend.liftBlocks() }
                Spacer()
                Button("Reset", role: .destructive) {
                    setExpanded(false)
                    reset()
                }
            }
            .font(.compound.bodySMSemibold)
        }
        .padding(CompoundDesignTokens.space4X)
        .frame(width: 340)
        .background(.compound.bgCanvasDefault, in: RoundedRectangle(cornerRadius: SpiralRadius.block))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            Text(title)
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
            content()
        }
    }

    /// What the platform holds now, beyond the picks above.
    private var platformLine: String {
        var facts: [String] = []
        switch backend.block {
        case .weeklyLimit: facts.append("weekly limit reached")
        case .callsPaused: facts.append("calls paused")
        case .consentOwner: facts.append("your AI consent missing")
        case .consentRoom: facts.append("someone's AI consent missing")
        case nil: break
        }
        if backend.isTranslationCapped {
            facts.append("call translation paused")
        }
        if backend.tool?.isEnabled == true {
            facts.append("the chat's translation tool is on")
        }
        let session = backend.ownSession.map { "your assistant \($0.phase)" } ?? "your assistant not in the call"
        return "Platform: " + ([session] + facts).joined(separator: " · ")
    }

    /// What your ears get of the covered person while you listen in your language; the call screen says nothing of it.
    private var coveredOriginalLine: String {
        let name = backend.coveredSpeakerName
        let voice = backend.isCoveredSpeaking ? "speaking" : "silent"
        return switch backend.coveredOriginal {
        case .notCovered: "\(name)'s original: not translated for you · \(voice)"
        case .ducked: "\(name)'s original: ducked · \(voice)"
        case .heardInFull: "\(name)'s original: full volume (no lane aired after 4 s of speech) · \(voice)"
        }
    }

    private func setExpanded(_ isExpanded: Bool) {
        hitArea.isExpanded = isExpanded
        hitArea.onExpandedChange?()
    }
}

// MARK: - A window over the sheet

/// What the overlay window takes touches for: its pill, or everything while the panel is open.
@Observable
final class CallMotionLabOverlayHitArea {
    @ObservationIgnored var pillFrame: CGRect = .zero
    var isExpanded = false
    @ObservationIgnored var onExpandedChange: (() -> Void)?
}

/// Puts `content` in a window of its own above the app's, so it stays reachable over a sheet at any height. The
/// window passes every touch outside `hitArea` through to the app.
private struct CallMotionLabOverlayWindow<Content: View>: UIViewRepresentable {
    let hitArea: CallMotionLabOverlayHitArea
    @ViewBuilder let content: () -> Content

    func makeUIView(context: Context) -> Anchor {
        Anchor(hitArea: hitArea, rootView: AnyView(content()))
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        anchor.host.rootView = AnyView(content())
    }

    static func dismantleUIView(_ anchor: Anchor, coordinator: ()) {
        anchor.tearDown()
    }

    final class Anchor: UIView {
        let host: Host
        private let hitArea: CallMotionLabOverlayHitArea
        private var window_: PassthroughWindow?

        init(hitArea: CallMotionLabOverlayHitArea, rootView: AnyView) {
            self.hitArea = hitArea
            host = Host(rootView: rootView)
            host.view.backgroundColor = .clear
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene else {
                tearDown()
                return
            }
            guard window_ == nil else { return }
            let overlay = PassthroughWindow(windowScene: scene, hitArea: hitArea)
            overlay.windowLevel = .alert + 1
            overlay.backgroundColor = .clear
            overlay.rootViewController = host
            overlay.isHidden = false
            window_ = overlay
            hitArea.onExpandedChange = { [weak self] in self?.fitWindow() }
            fitWindow()
        }

        /// Folded, the window is the status bar's strip: a window over the whole screen, even a clear one, stops the
        /// app's window from drawing its updates. Open, it takes the screen, and every touch.
        private func fitWindow() {
            guard let window_, let screen = window_.windowScene?.screen.bounds else { return }
            let stripHeight = max(window?.safeAreaInsets.top ?? 0, 54)
            window_.frame = hitArea.isExpanded ? screen : CGRect(x: 0, y: 0, width: screen.width, height: stripHeight)
        }

        func tearDown() {
            window_?.isHidden = true
            window_?.rootViewController = nil
            window_ = nil
        }
    }

    /// The scenario pill takes the clock's place; the safe area stays the same on a phone with a Dynamic Island. A popover
    /// in the sheet (a removal's confirmation) brings the clock back over the pill until the stage is opened again.
    final class Host: UIHostingController<AnyView> {
        override var prefersStatusBarHidden: Bool {
            true
        }
    }

    final class PassthroughWindow: UIWindow {
        private let hitArea: CallMotionLabOverlayHitArea

        init(windowScene: UIWindowScene, hitArea: CallMotionLabOverlayHitArea) {
            self.hitArea = hitArea
            super.init(windowScene: windowScene)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard hitArea.isExpanded || hitArea.pillFrame.insetBy(dx: -8, dy: -8).contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }
}

#endif
