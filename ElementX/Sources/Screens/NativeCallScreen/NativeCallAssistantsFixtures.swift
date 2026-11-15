//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 387): every state of the "Assistants" sheet on a real call view model, for the
// previews and the call motion lab (`-SpiralCallMotionLabAssistants <state>`). Fictional names only.

import Combine
import Foundation

enum NativeCallAssistantsLabState: String, CaseIterable, Identifiable {
    case empty = "1 Empty"
    case listeningNotesRecording = "2 Listening, notes, recording"
    case delivered = "2b Recording delivered, notes failed"
    case talks = "3 Talks with you"
    case translatingYou = "4 Translates you"
    case twoAssistants = "5 Yours and someone else's"
    case moderator = "5b Someone else's, moderator"
    case removalRefused = "5c Removal from chat refused"
    case paused = "6a Paused"
    case consentOwner = "6b Own AI consent"
    case consentRoom = "6c Room AI consent"
    case askToJoin = "6d Ask-to-join chat"
    case budget = "6e Weekly limit"
    case categoryPaused = "6f Calls paused by the limit"
    case translationPaused = "6g Translation paused, notes go on"
    case joining = "7 Joining"
    case stillJoining = "8 Still joining"
    case joinFailed = "8b Couldn't join"
    case standby = "10 Standing by"
    case nothingToTranslate = "10b Nothing to translate"
    case syncing = "11 Starting the translation"
    case ownerLeft = "13 Someone else's, owner left"
    case pocketInterpreter = "12 Private call, pocket interpreter"
    case lateSessionList = "F7 Own, controls late"
    case unavailable = "Unavailable"

    var id: Self {
        self
    }
}

enum NativeCallAssistantsLabModel {
    static let me = "@alex:example.org"
    static let myAgent = "@assistant-alex:example.org"
    static let person = "@mira:example.org"
    static let personAgent = "@assistant-mira:example.org"
    static let sessionID = "lab-own-session"
    static let candidateID = "lab-own-agent"

    static func make(_ state: NativeCallAssistantsLabState) -> NativeCallScreenViewModel {
        let isPrivate = state == .pocketInterpreter
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "\(me):DEVICE"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        let viewModel = NativeCallScreenViewModel(session: NativeCallSession(rtcSession: rtcSession,
                                                                             isRoomEncrypted: true,
                                                                             notifyRoom: false,
                                                                             configuration: .init(media: .audio, scope: isPrivate ? .assistant : .group),
                                                                             transport: NativeCallScreen_Previews.makePreviewTransport()),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  agentCenter: NativeAgentCenterController(agentPlatformService: nil,
                                                                                           roomID: "!lab:example.org",
                                                                                           roomMemberMxids: { [] },
                                                                                           inviteAgent: { _ in false }),
                                                  appMediator: AppMediatorMock(.init()),
                                                  audioRouting: .inert,
                                                  isVideoCall: false,
                                                  roomID: "!lab:example.org",
                                                  roomName: isPrivate ? "Alex Sample · assistant" : "Planning",
                                                  scope: isPrivate ? .assistant : .group)
        var viewState = viewModel.state
        viewState.callState = .connected
        viewState.agentCenter = snapshot(state)
        viewState.participants = participants(state)
        viewState.memberProfiles = [me: .init(displayName: "Alex Sample"),
                                    myAgent: .init(displayName: "Alex Sample · assistant"),
                                    person: .init(displayName: "Mira Testova"),
                                    personAgent: .init(displayName: "Mira Testova · assistant")]
        viewState.agentClaims.documents = documents(state)
        if state == .nothingToTranslate {
            viewState.bindings.assistantConfirmation = .nothingToTranslate
        }
        viewModel.state = viewState
        return viewModel
    }

    // MARK: - Pieces

    private static let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "en", label: "English"),
                                                                  .init(code: "fr", label: "French"),
                                                                  .init(code: "uk", label: "Ukrainian")]

    private static let candidate = NativeAgentCenterCandidate(id: candidateID,
                                                              mxid: myAgent,
                                                              displayName: "Alex Sample · assistant",
                                                              avatarURL: nil,
                                                              isRoomMember: true)

    private static func snapshot(_ state: NativeCallAssistantsLabState) -> NativeAgentCenterSnapshot {
        var snapshot = NativeAgentCenterSnapshot(isConfigured: true, isAvailable: true,
                                                 isLoading: false,
                                                 sessions: [],
                                                 candidates: [candidate],
                                                 availableLanguages: catalog)
        snapshot.ownAgentMxids = [myAgent]
        switch state {
        case .empty, .moderator:
            break
        case .removalRefused:
            snapshot.lastError = .unavailable("kick refused")
            snapshot.lastErrorScope = .foreign(personAgent)
        case .delivered:
            snapshot.sessions = [NativeAgentCenterSession(sessionID: sessionID, agentMxid: myAgent, canControl: true, isEnding: false,
                                                          recording: .init(isEnabled: true, revision: 2, delivery: .delivered(target: "owner_dm"), isStopped: true),
                                                          summary: .init(isEnabled: true, revision: 2, delivery: .failed, isStopped: false),
                                                          translation: .unknown,
                                                          conversation: .init(isAvailable: true, revision: 0))]
        case .listeningNotesRecording:
            snapshot.sessions = [session(recording: true, summary: true)]
        case .talks:
            snapshot.sessions = [session(conversation: .init(isAvailable: true, revision: 1))]
        case .translatingYou:
            snapshot.sessions = [session(translation: translation(.init(source: "override", style: "simultaneous", forLanguage: "en",
                                                                        lanes: [.init(speaker: person, language: "en")])))]
        case .twoAssistants:
            snapshot.sessions = [session()]
        case .paused:
            snapshot.candidates = [NativeAgentCenterCandidate(id: candidateID, mxid: myAgent, displayName: candidate.displayName,
                                                              avatarURL: nil, isRoomMember: true, isPaused: true)]
        case .consentOwner:
            snapshot.joinChecks = [candidateID: .aiConsentOwner]
        case .consentRoom:
            snapshot.joinChecks = [candidateID: .aiConsentRoom]
        case .askToJoin:
            snapshot.joinChecks = [candidateID: .askToJoin]
        case .budget:
            snapshot.joinChecks = [candidateID: .budgetReached]
        case .categoryPaused:
            snapshot.joinChecks = [candidateID: .categoryPaused(.untilChanged)]
        case .translationPaused:
            var paused = NativeAgentCenterTranslation.unknown
            paused.effective.forLanguage = "en"
            paused.effective.stoppedReason = .translationPaused
            paused.effective.pause = .untilChanged
            snapshot.sessions = [session(summary: true, translation: paused)]
        case .joining:
            snapshot.sessions = [session()]
            snapshot.joinStartedAt = [sessionID: Date()]
        case .stillJoining:
            snapshot.sessions = [session()]
            snapshot.joinStartedAt = [sessionID: Date(timeIntervalSinceNow: -25)]
        case .joinFailed:
            snapshot.joinFailures = [candidateID: .failed]
        case .standby:
            snapshot.sessions = [session(translation: translation(.init(source: "room_tool", style: "simultaneous", forLanguage: "en", isStandby: true)))]
        case .nothingToTranslate:
            // Mira speaks English too: «Translate into English» would translate nobody.
            snapshot.translationFacts.languages = [person: "en"]
        case .syncing:
            snapshot.sessions = [session(translation: translation(.init(source: "override", style: "simultaneous", forLanguage: "en", isSyncing: true)))]
        case .ownerLeft:
            break
        case .pocketInterpreter:
            snapshot.sessions = [session(translation: translation(.init(source: "override", style: "consecutive", pocket: ["en", "fr"],
                                                                        lanes: [.init(speaker: me, language: "en"), .init(speaker: me, language: "fr")])))]
        case .lateSessionList:
            snapshot.sessions = []
        case .unavailable:
            snapshot = NativeAgentCenterSnapshot(isConfigured: true, isAvailable: false, isLoading: false)
            snapshot.lastError = .unavailable("lab")
        }
        if state == .moderator || state == .removalRefused {
            snapshot.canRemoveOthersFromChat = true
        }
        return snapshot
    }

    private static func participants(_ state: NativeCallAssistantsLabState) -> [NativeCallParticipant] {
        var people = [participant(me, isLocal: true)]
        if state != .pocketInterpreter {
            people.append(participant(person))
        }
        switch state {
        case .empty, .paused, .consentOwner, .consentRoom, .askToJoin, .budget, .categoryPaused, .joining, .stillJoining, .joinFailed, .unavailable,
             .nothingToTranslate:
            break
        case .twoAssistants:
            people += [participant(myAgent, role: .agent), participant(personAgent, role: .agent)]
        case .moderator, .removalRefused, .ownerLeft:
            people.append(participant(personAgent, role: .agent))
        default:
            people.append(participant(myAgent, role: .agent, isSpeaking: state == .talks))
        }
        return people
    }

    private static func documents(_ state: NativeCallAssistantsLabState) -> [String: SpiralAgentStateReader.AgentClaim] {
        switch state {
        case .listeningNotesRecording: [myAgent: .make(recording: true, summaryArmed: true)]
        case .talks: [myAgent: .make(conversation: true)]
        case .delivered: [myAgent: .make()]
        case .translatingYou: [myAgent: .make(translation: live(for: "en", owner: me, lanes: [.init(speaker: person, language: "en")]))]
        case .standby: [myAgent: .make(translation: standby(for: "en", owner: me))]
        case .syncing: [myAgent: .make(translation: standby(for: "en", owner: me))]
        case .pocketInterpreter:
            [myAgent: .make(translation: .init(isActive: true, style: .consecutive, source: .override, forLanguage: nil, pocket: ["en", "fr"],
                                               owner: me, lanes: [.init(speaker: me, language: "en"), .init(speaker: me, language: "fr")],
                                               stoppedReason: nil))]
        case .twoAssistants:
            [myAgent: .make(),
             personAgent: .make(translation: live(for: "en", owner: person, lanes: [.init(speaker: me, language: "en")]), recording: true)]
        case .moderator, .removalRefused:
            // Translates you into English: a lane Mira hears.
            [personAgent: .make(translation: live(for: "en", owner: person, lanes: [.init(speaker: me, language: "en")]), recording: true)]
        case .ownerLeft:
            [personAgent: .make(translation: .init(isActive: false, style: nil, source: .override, forLanguage: "en", pocket: nil,
                                                   owner: person, lanes: [], stoppedReason: .ownerLeft),
                                recording: true)]
        case .lateSessionList: [myAgent: .make()]
        case .translationPaused:
            [myAgent: .make(translation: .init(isActive: false, style: nil, source: .override, forLanguage: "en", pocket: nil,
                                               owner: me, lanes: [], stoppedReason: .translationPaused),
                            summaryArmed: true)]
        default: [:]
        }
    }

    private static func live(for language: String, owner: String, lanes: [VoiceTranslationLane]) -> SpiralAgentStateReader.TranslationClaim {
        .init(isActive: true, style: .simultaneous, source: .override, forLanguage: language, pocket: nil, owner: owner, lanes: lanes, stoppedReason: nil)
    }

    private static func standby(for language: String, owner: String) -> SpiralAgentStateReader.TranslationClaim {
        .init(isActive: false, style: .simultaneous, source: .roomTool, forLanguage: language, pocket: nil, owner: owner, lanes: [], stoppedReason: nil)
    }

    private static func session(recording: Bool = false,
                                summary: Bool = false,
                                translation: NativeAgentCenterTranslation = .unknown,
                                conversation: NativeAgentCenterConversation = .init(isAvailable: true, revision: 0)) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: sessionID,
                                 agentMxid: myAgent,
                                 canControl: true,
                                 isEnding: false,
                                 recording: .init(isEnabled: recording, revision: 1, delivery: recording ? .pending : .notArmed, isStopped: false),
                                 summary: .init(isEnabled: summary, revision: 1, delivery: .notArmed, isStopped: false),
                                 translation: translation,
                                 conversation: translation.isOn ? .init(isAvailable: false, revision: conversation.revision) : conversation)
    }

    private static func translation(_ effective: VoiceControlsEffective) -> NativeAgentCenterTranslation {
        NativeAgentCenterTranslation(effective: effective, revision: 1)
    }

    private static func participant(_ userID: String,
                                    role: NativeCallParticipant.Role = .human,
                                    isLocal: Bool = false,
                                    isSpeaking: Bool = false) -> NativeCallParticipant {
        NativeCallParticipant(id: "\(userID):DEVICE",
                              userID: userID,
                              role: role,
                              mediaState: .connected,
                              isSpeaking: isSpeaking,
                              isAudioEnabled: true,
                              isLocal: isLocal)
    }
}
