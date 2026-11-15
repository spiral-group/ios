//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383, stage 2): the call's real screens in the lab, fed the lab's voice, with
// every state the operator wants to check one control away: voice or video; a person, one's own assistant, a person
// joining that call, a group; cameras; muted; the agent's states; the bar over chats and over a room. The screens are the
// call's own views on a real view model (preview mocks underneath), so a tap on the corner tile swaps the pictures and
// the Camera control flips the camera exactly as in a call. Fictional names, drawn pictures, no camera.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Combine
import Compound
import SpiralTokens
import SwiftUI

/// What the lab's Call stage shows.
struct CallMotionLabCallSetup: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case person = "Person"
        case assistant = "Assistant"
        /// A call with one's own assistant that a person joins midway: back to the call's usual layout.
        case joined = "Asst + person"
        case group = "Group"

        var id: Self {
            self
        }
    }

    enum AgentState: String, CaseIterable, Identifiable {
        case none = "No agent"
        case speaking = "Speaking"
        case listening = "Listening"
        case waiting = "Waiting"
        case translating = "Translating"
        case paused = "Paused"
        case notes = "Notes"
        case recording = "Recording"
        case error = "Error"
        case leaving = "Leaving"

        var id: Self {
            self
        }
    }

    /// Who one's own assistant is on its page (question 400): two agents without a photo, each on its own colour's
    /// field, and one with a photo.
    enum AssistantLook: String, CaseIterable, Identifiable {
        case violet = "Violet"
        case amber = "Amber"
        case photo = "Photo"

        var id: Self {
            self
        }

        var agentID: String {
            self == .amber ? "@assistant-sam:example.org" : CallMotionLabCallModel.agent
        }

        var displayName: String {
            self == .amber ? "Sam Sample · assistant" : "Alex Sample · assistant"
        }

        var avatarURL: URL? {
            self == .photo ? .mockMXCUserAvatar : nil
        }

        /// Serves the mock photo; the other looks load nothing.
        var mediaProvider: MediaProviderProtocol? {
            self == .photo ? MediaProviderMock(.init()) : nil
        }
    }

    enum Surface: String, CaseIterable, Identifiable {
        case call = "Call"
        case barOverChats = "Bar chats"
        case barOverRoom = "Bar room"

        var id: Self {
            self
        }
    }

    var surface = Surface.call
    var kind = Kind.person
    var isVideo = false
    var groupCount = 4
    /// The far end's drawn picture: bright (the hard case for white words) or dim.
    var isPictureDim = false
    /// The agent is one's own ("Your assistant") or someone else's (named after its owner).
    var isAgentMine = true
    /// A second agent in the call, stacked behind the first in the pill.
    var hasSecondAgent = false
    var isMyCameraOn = true
    var isTheirCameraOn = true
    var isMuted = false
    var agent = AgentState.speaking
    /// Starts with your picture large, as after a tap on the corner tile.
    var isSwapped = false
    var assistantLook = AssistantLook.violet

    static func fromLaunchArguments() -> CallMotionLabCallSetup {
        let defaults = UserDefaults.standard
        var setup = CallMotionLabCallSetup()
        setup.surface = Surface(rawValue: defaults.string(forKey: "SpiralCallMotionLabReal") ?? "") ?? .call
        setup.kind = Kind(rawValue: defaults.string(forKey: "SpiralCallMotionLabCallKind") ?? "") ?? .person
        setup.isVideo = defaults.bool(forKey: "SpiralCallMotionLabCallVideo")
        let count = defaults.integer(forKey: "SpiralCallMotionLabGroupCount")
        setup.groupCount = [3, 4, 6, 8, 12].contains(count) ? count : 4
        setup.isMyCameraOn = defaults.object(forKey: "SpiralCallMotionLabMyCamera") as? Bool ?? true
        setup.isTheirCameraOn = defaults.object(forKey: "SpiralCallMotionLabTheirCamera") as? Bool ?? true
        setup.isMuted = defaults.bool(forKey: "SpiralCallMotionLabMuted")
        setup.agent = AgentState(rawValue: defaults.string(forKey: "SpiralCallMotionLabAgentState") ?? "") ?? .speaking
        setup.isSwapped = defaults.bool(forKey: "SpiralCallMotionLabSwapped")
        setup.isPictureDim = defaults.string(forKey: "SpiralCallMotionLabCallPicture") == "Dim"
        setup.isAgentMine = defaults.object(forKey: "SpiralCallMotionLabAgentMine") as? Bool ?? true
        setup.hasSecondAgent = defaults.bool(forKey: "SpiralCallMotionLabSecondAgent")
        setup.assistantLook = AssistantLook(rawValue: defaults.string(forKey: "SpiralCallMotionLabAssistantLook") ?? "") ?? .violet
        return setup
    }
}

struct CallMotionLabRealScreens: View {
    let setup: CallMotionLabCallSetup

    @Environment(\.nativeCallVoiceLevels) private var levels
    @State private var speakingLevels = CallMotionLabSpeakingLevels()
    @State private var renderer = CallMotionLabVideoRenderer()
    @State private var model: NativeCallScreenViewModel?

    var body: some View {
        // A ZStack, not a Group: an empty Group has no view for the task to run on.
        ZStack {
            Color.clear
            if let model {
                switch setup.surface {
                case .call:
                    NativeCallScreen(context: model.context, videoRenderer: renderer, voiceLevels: speakingLevels)
                case .barOverChats:
                    VStack(spacing: 0) {
                        NativeCallBar(context: model.context)
                        CallMotionLabChatList()
                    }
                    .environment(\.nativeCallVoiceLevels, speakingLevels)
                case .barOverRoom:
                    VStack(spacing: 0) {
                        NativeCallBar(context: model.context)
                        CallMotionLabRoom()
                    }
                    .environment(\.nativeCallVoiceLevels, speakingLevels)
                }
            }
        }
        .onChange(of: setup.isPictureDim, initial: true) { _, isDim in renderer.isDim = isDim }
        .task(id: setup) {
            let model = CallMotionLabCallModel.make(setup, renderer: renderer)
            self.model = model
            speakingLevels.base = levels
            speakingLevels.speaking = Set(model.context.viewState.participants.filter(\.isSpeaking).map(\.userID))
            // A group: everyone a voice of their own, one at a time; Mic drives only you.
            if setup.kind == .group, let you = levels as? CallMotionLabLevels {
                let group = CallMotionLabGroupLevels(you: you)
                group.count = setup.groupCount
                speakingLevels.group = group
            } else {
                speakingLevels.group = nil
            }
            // `-SpiralCallMotionLabSelfTest YES`: the smoke check presses the dock's toggles and the swap as a tap would.
            if UserDefaults.standard.bool(forKey: "SpiralCallMotionLabSelfTest") {
                for action in [NativeCallScreenViewAction.toggleCamera, .toggleMicrophone, .swapVideos, .switchCamera,
                               .swapVideos, .toggleMicrophone, .toggleCamera] {
                    try? await Task.sleep(for: .milliseconds(400))
                    model.context.send(viewAction: action)
                }
            }
        }
    }
}

/// Each participant's own level, as a call reports it: only someone speaking has one, so only their ring or tile edge
/// moves. A person or the assistant: the lab's voice for whoever the setup marks as speaking. A group: everyone their
/// own simulated voice, taking turns (the Group stage's people), with Mic driving only you; the agent only while its
/// state says it speaks.
final class CallMotionLabSpeakingLevels: NativeCallVoiceLevelReading {
    weak var base: NativeCallVoiceLevelReading?
    var speaking: Set<String> = []
    var group: CallMotionLabGroupLevels?

    func voiceLevel(forUserID userID: String) -> Double {
        if let group {
            guard userID == CallMotionLabCallModel.agent else { return group.voiceLevel(forUserID: userID) }
            return speaking.contains(userID) ? group.voiceLevel(forUserID: CallMotionLabGroupLevels.agentID) : 0
        }
        return speaking.contains(userID) ? base?.voiceLevel(forUserID: userID) ?? 0 : 0
    }

    var loudestVoiceLevel: Double {
        if let group {
            return group.loudestVoiceLevel
        }
        return speaking.isEmpty ? 0 : base?.loudestVoiceLevel ?? 0
    }
}

/// Builds the call's real view model for a setup: the preview's mocks underneath, the people and the agent's facts on
/// top, and a transport whose camera flip turns the lab's drawn camera round.
enum CallMotionLabCallModel {
    static let me = "@you:example.org"
    static let person = "@mira:example.org"
    static let agent = "@assistant-alex:example.org"
    static let secondAgent = "@assistant-mira:example.org"
    private static let groupNames = ["Mira Testova", "Oleh Primer", "Iryna Zrazok", "Taras Demo", "Sofia Mock", "Danylo Test", "Olena Fiction",
                                     "Marko Sample", "Hanna Example", "Petro Placeholder", "Daria Specimen"]

    static func make(_ setup: CallMotionLabCallSetup, renderer: CallMotionLabVideoRenderer) -> NativeCallScreenViewModel {
        let scope: NativeCallScope = switch setup.kind {
        case .person: .direct
        case .assistant, .joined: .assistant
        case .group: .group
        }
        // The look picks the assistant on its own page only, so a group's and a joined call's agent stay as they were.
        let look = setup.kind == .assistant ? setup.assistantLook : .violet
        let agent = look.agentID
        let roomName = switch setup.kind {
        case .person, .joined: "Mira Testova"
        case .assistant: look.displayName
        case .group: "Book club"
        }

        let transport = NativeCallScreen_Previews.makePreviewTransport()
        transport.localIdentity = "\(me):DEVICE"
        transport.switchCameraClosure = { [weak renderer] in
            await MainActor.run { renderer?.isFlipped.toggle() }
        }
        // Every stub the dock can reach answers: a nil one traps (the camera toggle crashed in setMedia).
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "\(me):DEVICE"
        rtcSession.updates = Empty().eraseToAnyPublisher()
        rtcSession.setMediaReturnValue = .success(())
        rtcSession.joinEncryptMediaNotificationMediaLanguageReturnValue = .success(())
        rtcSession.leaveReturnValue = .success(())
        rtcSession.membershipsReturnValue = .success([])
        let model = NativeCallScreenViewModel(session: NativeCallSession(rtcSession: rtcSession,
                                                                         isRoomEncrypted: true,
                                                                         notifyRoom: true,
                                                                         configuration: .init(media: setup.isVideo ? .video : .audio, scope: scope),
                                                                         transport: transport),
                                              callKitService: CallKitServiceMock(.init()),
                                              agentCenter: NativeAgentCenterController(agentPlatformService: nil,
                                                                                       roomID: "!lab:example.org",
                                                                                       roomMemberMxids: { [] },
                                                                                       inviteAgent: { _ in false }),
                                              appMediator: AppMediatorMock(.init()),
                                              audioRouting: .inert,
                                              mediaProvider: look.mediaProvider,
                                              isVideoCall: setup.isVideo,
                                              roomID: "!lab:example.org",
                                              roomName: roomName,
                                              scope: scope,
                                              roomAvatar: .heroes([setup.kind == .assistant
                                                      ? UserProfile(userID: agent, displayName: roomName, avatarURL: look.avatarURL)
                                                      : UserProfile(userID: person, displayName: roomName)]))

        var state = model.state
        state.callState = .connected
        state.callConnectedAt = Date(timeIntervalSinceNow: -42)
        state.isMicrophoneEnabled = !setup.isMuted
        state.isCameraEnabled = setup.isVideo && setup.isMyCameraOn
        state.agentCenter.isAvailable = true
        state.agentCenter.isConfigured = true
        state.bindings.isSelfVideoLarge = setup.isSwapped

        let hasAgent = setup.kind == .assistant || setup.kind == .joined || setup.agent != .none
        let agentState = setup.agent == .none ? CallMotionLabCallSetup.AgentState.listening : setup.agent
        let speaking = agentState == .speaking || agentState == .translating

        var people: [(id: String, name: String)] = []
        switch setup.kind {
        case .person, .joined: people = [(person, "Mira Testova")]
        case .assistant: people = []
        case .group: people = (1..<setup.groupCount).map { ("@p\($0):example.org", groupNames[($0 - 1) % groupNames.count]) }
        }

        var participants = [NativeCallScreen_Previews.participant(me, isLocal: true, isMuted: setup.isMuted)]
        participants += people.enumerated().map { index, person in
            NativeCallScreen_Previews.participant(person.id, isSpeaking: index == 0 && !speaking, isMuted: index == 2)
        }
        var profiles: [String: NativeCallMemberProfile] = [me: .init(displayName: "You")]
        for person in people {
            profiles[person.id] = .init(displayName: person.name)
        }
        if hasAgent {
            participants.append(NativeCallScreen_Previews.participant(agent, role: .agent, isSpeaking: speaking))
            profiles[agent] = .init(displayName: look.displayName, avatarURL: look.avatarURL)
            state.agentClaims.documents = [agent: claim(agentState)]
            state.agentClaims.speaking = speaking ? [agent] : []
            // One's own agent has a session one controls; someone else's has none on this device.
            if setup.isAgentMine || agentState == .error {
                state.agentCenter = NativeAgentCenterSnapshot(isConfigured: true, isAvailable: true, isLoading: false,
                                                              sessions: [session(agent: agent, isFailed: agentState == .error)])
            }
            if setup.hasSecondAgent {
                participants.append(NativeCallScreen_Previews.participant(secondAgent, role: .agent, isSpeaking: false))
                profiles[secondAgent] = .init(displayName: "Mira Testova · assistant")
                state.agentClaims.documents[secondAgent] = .make()
            }
        }
        state.participants = participants
        state.memberProfiles = profiles

        if setup.isVideo {
            let own = participants[0]
            var tiles = [NativeCallVideoTile(participant: own, source: setup.isMyCameraOn ? CallMotionLabVideoRenderer.ownSource : nil)]
            for (index, participant) in participants.dropFirst().enumerated() where participant.role == .human {
                tiles.insert(NativeCallVideoTile(participant: participant,
                                                 source: setup.isTheirCameraOn ? CallMotionLabVideoRenderer.source(for: index) : nil),
                             at: tiles.count - 1)
            }
            state.videoTiles = tiles
            state.isPeerSettled = true
        }
        model.state = state
        return model
    }

    private static func claim(_ state: CallMotionLabCallSetup.AgentState) -> SpiralAgentStateReader.AgentClaim {
        switch state {
        case .none, .listening, .speaking: .make(conversation: true)
        case .waiting: .make(conversation: true, callGate: .waiting)
        case .translating: .make(translation: .producing("en", speakers: ["@bob:example.org"]))
        case .paused: .make(translation: .init(isActive: false, style: nil, source: .override, forLanguage: "en", pocket: nil, owner: nil,
                                               lanes: [], stoppedReason: .translationPaused))
        case .notes: .make(recording: true, summaryArmed: true)
        case .recording, .error: .make(recording: true)
        case .leaving: .make(conversation: true, lifecycle: .leaving)
        }
    }

    private static func session(agent: String, isFailed: Bool) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: "lab-session",
                                 agentMxid: agent,
                                 canControl: true,
                                 isEnding: false,
                                 recording: .init(isEnabled: true, revision: 1, delivery: isFailed ? .failed : .notArmed, isStopped: false),
                                 summary: .init(isEnabled: isFailed, revision: 1, delivery: isFailed ? .failed : .notArmed, isStopped: false),
                                 translation: .unknown,
                                 conversation: .unknown)
    }
}

/// Draws the lab's pictures for every video source: the far end bright or dim by person, our own camera the other
/// way round once the Camera control has flipped it.
@Observable
final class CallMotionLabVideoRenderer: NativeCallVideoRendering {
    static let ownSource = NativeCallVideoSource(identity: "\(CallMotionLabCallModel.me):DEVICE", trackID: "", isLocal: true)

    var isFlipped = false
    /// The far end's pictures the other way round: the bright ones dim and the dim ones bright.
    var isDim = false

    static func source(for index: Int) -> NativeCallVideoSource {
        NativeCallVideoSource(identity: "remote-\(index)", trackID: "track-\(index)", isLocal: false)
    }

    func videoView(for source: NativeCallVideoSource) -> AnyView? {
        if source == Self.ownSource {
            return AnyView(CallMotionSamplePicture(scene: isFlipped ? .bright : .dim))
        }
        let index = Int(source.trackID.dropFirst("track-".count)) ?? 0
        return AnyView(CallMotionSamplePicture(scene: index.isMultiple(of: 2) != isDim ? .bright : .dim)
            .hueRotation(.degrees(Double(index) * 47)))
    }

    func canRenderPictureInPictureVideo(for source: NativeCallVideoSource) -> Bool {
        false
    }

    func pictureInPictureVideoView(for source: NativeCallVideoSource) -> UIView? {
        nil
    }

    func tearDownPictureInPictureVideoView(_ view: UIView) { }
}

/// A chat list with neutral names, as the bar sits over Chats.
struct CallMotionLabChatList: View {
    private static let chats: [(title: String, preview: String)] = [
        ("Mira Testova", "Call started"),
        ("Book club", "Next week we read chapter four"),
        ("Weekend plans", "The weather looks fine for Saturday"),
        ("Design review", "Sheet two is the one"),
        ("Running group", "Seven tomorrow at the park")
    ]

    var body: some View {
        List(Self.chats, id: \.title) { chat in
            HStack(spacing: CompoundDesignTokens.space3X) {
                Text(String(chat.title.prefix(1)))
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textOnSolidPrimary)
                    .frame(width: SpiralAvatarSize.medium, height: SpiralAvatarSize.medium)
                    .background(Color.compound.iconAccentPrimary.opacity(0.75), in: Circle())

                VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
                    Text(chat.title)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                    Text(chat.preview)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, CompoundDesignTokens.space1X)
        }
        .listStyle(.plain)
    }
}

/// A room's timeline in outline, neutral words, as the bar sits over a room.
struct CallMotionLabRoom: View {
    private static let messages: [(text: String, isOwn: Bool)] = [
        ("Shall we go over the plan for Saturday?", false),
        ("Yes, calling you now", true),
        ("The park at ten, then lunch", false),
        ("Sounds good", true)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: CompoundDesignTokens.space2X) {
                ForEach(Array(Self.messages.enumerated()), id: \.offset) { _, message in
                    Text(message.text)
                        .font(.compound.bodyLG)
                        .foregroundStyle(message.isOwn ? .compound.textOnSolidPrimary : .compound.textPrimary)
                        .padding(.horizontal, CompoundDesignTokens.space4X)
                        .padding(.vertical, CompoundDesignTokens.space2X)
                        .background(message.isOwn ? Color.spiral.ownBubble : Color.compound.bgSubtleSecondary,
                                    in: RoundedRectangle(cornerRadius: SpiralRadius.bubble, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading)
                }
            }
            .padding(CompoundDesignTokens.space4X)
        }
        .background(Color.compound.bgCanvasDefault)
    }
}

#endif
