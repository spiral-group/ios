//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the call-motion lab. The operator's picks, in the call's own views, driven
// by a simulated voice or the Mac's microphone: the Aura ring with the loudness calibration, the agent pill's every
// state, the real call screens in every state (the bar, the video header, the assistant's page), and the group stage.
//
// Two ways in: Developer options › Call motion lab, or launch with `-SpiralCallMotionLab YES`, which opens the lab
// instead of the app (no account needed). Staging and Debug builds only: an App Store build has no lab compiled in.

#if DEBUG || SPIRAL_STAGING

import Compound
import SpiralTokens
import SwiftUI

struct CallMotionLabScreen: View {
    enum Stage: String, CaseIterable, Identifiable {
        case ring = "Ring"
        case pill = "Pill"
        /// The call's real screens: the bar, the video header and the assistant's page live here.
        case real = "Call"
        case group = "Group"
        /// Decision 386: the agent's own symbols in their places and colour treatments.
        case icon = "Icon"
        /// Question 387: the call's "Assistants" sheet in every state.
        case assistants = "Assistants"
        /// Question 401: the same sheet live, on a mocked platform, to tap through as in a real call.
        case assistantsLive = "AssistantsLive"
        /// 1.0.3: how call translation starts — the live sheet's Start, Stop and «Translate into …» (operator's pick B).
        case translationStart = "TranslationStart"
        /// 1.0.3: the Assistants sheet as it ships after the operator's pick C — each job asked, Translation at rest.
        case jobConfirm = "JobConfirm"
        /// Question 390: the agents' own colours; question 393: the agent badge.
        case avatars = "Avatars"

        var id: Self {
            self
        }
    }

    enum TextSize: String, CaseIterable, Identifiable {
        case standard = "Default"
        case large = "XXL"
        case accessibility = "AX3"

        var id: Self {
            self
        }

        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .standard: .large
            case .large: .xxLarge
            case .accessibility: .accessibility3
            }
        }
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: Self {
            self
        }

        var scheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// Nil when the lab is the app (launched with the argument): there is nothing to go back to.
    let onClose: (() -> Void)?

    @State private var levels: CallMotionLabLevels
    @State private var stage: Stage
    @State private var scene: CallMotionSamplePicture.Scene
    @State private var pillCase: CallMotionAgentPill.Case
    @State private var isPillOverVideo: Bool
    @State private var showsAllPillStates: Bool
    @State private var callSetup: CallMotionLabCallSetup
    @State private var assistantsState: NativeCallAssistantsLabState
    @State private var textSize: TextSize
    @State private var groupLayout: CallMotionGroupStage.Layout
    @State private var groupCount: Int
    @State private var groupLevels: CallMotionLabGroupLevels
    @State private var iconTreatment: CallMotionIconStage.Treatment
    /// The operator's comparison (question 383): the call's surfaces over a picture as Liquid Glass (the call's) or the dark
    /// material.
    @State private var isGlassOverVideo: Bool
    @State private var theme: Theme
    @State private var detent: PresentationDetent
    @State private var isRightToLeft: Bool
    @State private var isPanelShown: Bool
    @State private var connectedAt = Date(timeIntervalSinceNow: -42)
    @AppStorage(CallMotionLabScreen.launchKey) private var opensAtLaunch = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var systemColorScheme

    /// The defaults key `-SpiralCallMotionLab YES` sets; stored, it keeps the lab as the app on the next launch.
    static let launchKey = "SpiralCallMotionLab"

    /// Launch arguments open the lab on a given view, for screenshots and for showing one variant:
    /// `-SpiralCallMotionLabStage Pill -SpiralCallMotionLabTheme Dark`, `-SpiralCallMotionLabSource Mic` (`Speech`,
    /// `Manual`), `-SpiralCallMotionLabPillCase "Taking notes"` (the pill above the dock),
    /// `-SpiralCallMotionLabPillBackground Video`, `-SpiralCallMotionLabPillAllStates NO`,
    /// `-SpiralCallMotionLabStage Call` with `-SpiralCallMotionLabCallKind Assistant|Person|"Asst + person"|Group`,
    /// `-SpiralCallMotionLabAssistantLook Violet|Amber|Photo` (the assistant's page and the Ring stage, question 400),
    /// `…CallVideo YES`, `…MyCamera NO`, `…TheirCamera NO`, `…Swapped YES`, `…Muted YES`, `…AgentState Error`,
    /// `-SpiralCallMotionLabReal "Bar chats"` (the call's real screens); `-SpiralCallMotionLabTextSize AX3`,
    /// `-SpiralCallMotionLabRightToLeft YES`; `-SpiralCallMotionLabStage Icon -SpiralCallMotionLabIconTreatment Logo`;
    /// `-SpiralCallMotionLabStage Assistants -SpiralCallMotionLabAssistants "4 Translates you"` (the call's Assistants
    /// sheet, question 387; its menu at the top picks the other states); `-SpiralCallMotionLabStage AssistantsLive` (the
    /// same sheet live on a mocked platform, question 401; its own arguments are in `CallMotionLabAssistantsLiveStage`);
    /// `-SpiralCallMotionLabStage Avatars` (the agent
    /// badge, question 393, and the agents' colours, question 390);
    /// `-SpiralCallMotionLabStage Group -SpiralCallMotionLabVariant Focus -SpiralCallMotionLabGroupCount 6`;
    /// `-SpiralCallMotionLabPanel small` starts with the panel folded, `hidden` without it (swipe the folded panel
    /// down to hide it, the button top right brings it back); `-SpiralCallMotionLabSilent`, `…Raw`,
    /// and `…LogCost` (each `YES`) set the rest; `-SpiralCallMotionLabOverVideo Material`
    /// puts the dark material over pictures, `-SpiralCallMotionLabCallPicture Dim` dims the far end's picture, and
    /// `-SpiralCallMotionLabGroupEveryoneSpeaks YES` has the whole group talk at once (the cost run's worst case).
    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        let defaults = UserDefaults.standard
        let variant = defaults.string(forKey: "SpiralCallMotionLabVariant") ?? ""
        _stage = State(initialValue: Stage(rawValue: defaults.string(forKey: "SpiralCallMotionLabStage") ?? "") ?? .ring)
        _pillCase = State(initialValue: CallMotionAgentPill.Case(rawValue: defaults.string(forKey: "SpiralCallMotionLabPillCase") ?? "") ?? .translating)
        _isPillOverVideo = State(initialValue: defaults.string(forKey: "SpiralCallMotionLabPillBackground") == "Video")
        _showsAllPillStates = State(initialValue: defaults.object(forKey: "SpiralCallMotionLabPillAllStates") as? Bool ?? true)
        _callSetup = State(initialValue: CallMotionLabCallSetup.fromLaunchArguments())
        _assistantsState = State(initialValue: NativeCallAssistantsLabState(rawValue: defaults.string(forKey: "SpiralCallMotionLabAssistants") ?? "") ?? .empty)
        _textSize = State(initialValue: TextSize(rawValue: defaults.string(forKey: "SpiralCallMotionLabTextSize") ?? "") ?? .standard)
        _groupLayout = State(initialValue: CallMotionGroupStage.Layout(rawValue: variant) ?? .spotlight)
        let count = defaults.integer(forKey: "SpiralCallMotionLabGroupCount")
        _groupCount = State(initialValue: [3, 4, 6, 8, 12].contains(count) ? count : 4)
        _isGlassOverVideo = State(initialValue: defaults.string(forKey: "SpiralCallMotionLabOverVideo") != "Material")
        _iconTreatment = State(initialValue: CallMotionIconStage.Treatment(rawValue: defaults.string(forKey: "SpiralCallMotionLabIconTreatment") ?? "") ?? .monochrome)
        _scene = State(initialValue: CallMotionSamplePicture.Scene(rawValue: defaults.string(forKey: "SpiralCallMotionLabPicture") ?? "") ?? .bright)
        _theme = State(initialValue: Theme(rawValue: defaults.string(forKey: "SpiralCallMotionLabTheme") ?? "") ?? .system)
        _isRightToLeft = State(initialValue: defaults.bool(forKey: "SpiralCallMotionLabRightToLeft"))
        _detent = State(initialValue: defaults.string(forKey: "SpiralCallMotionLabPanel") == "small" ? Self.foldedPanel : .medium)
        // The Assistants sheet and the Avatars column need the screen; the button top right brings the panel back.
        _isPanelShown = State(initialValue: defaults.string(forKey: "SpiralCallMotionLabPanel") != "hidden"
            && ![Stage.assistants.rawValue, Stage.assistantsLive.rawValue, Stage.translationStart.rawValue, Stage.jobConfirm.rawValue, Stage.avatars.rawValue].contains(defaults.string(forKey: "SpiralCallMotionLabStage")))
        let levels = CallMotionLabLevels()
        levels.isPlaying = !defaults.bool(forKey: "SpiralCallMotionLabSilent")
        levels.isThroughSFU = !defaults.bool(forKey: "SpiralCallMotionLabRaw")
        levels.source = CallMotionLabLevels.Source(rawValue: defaults.string(forKey: "SpiralCallMotionLabSource") ?? "") ?? .speech
        _levels = State(initialValue: levels)
        _groupLevels = State(initialValue: CallMotionLabGroupLevels(you: levels))
    }

    private static let foldedPanel = PresentationDetent.height(200)

    var body: some View {
        stageView
            .environment(\.nativeCallPrefersMaterialOverPicture, !isGlassOverVideo)
            .environment(\.nativeCallVoiceLevels, levels)
            .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
            .dynamicTypeSize(textSize.dynamicTypeSize)
            .preferredColorScheme(theme.scheme)
            .overlay(alignment: .topTrailing) {
                if !isPanelShown {
                    Button("Controls", systemImage: "slider.horizontal.3") { isPanelShown = true }
                        .labelStyle(.iconOnly)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.iconPrimary)
                        .frame(width: 44, height: 44)
                        .spiralGlass(in: Circle(), isInteractive: true)
                        .padding(.horizontal, CompoundDesignTokens.space3X)
                        // The live call's 文A button has that corner (Brief 0085): the lab's controls sit under it.
                        .padding(.top, stage == .assistantsLive || stage == .translationStart || stage == .jobConfirm ? 56 : 0)
                }
            }
            .sheet(isPresented: $isPanelShown) {
                panel
                    .presentationDetents([Self.foldedPanel, .medium, .large], selection: $detent)
                    .presentationBackgroundInteraction(.enabled)
                    .interactiveDismissDisabled(detent != Self.foldedPanel)
                    .preferredColorScheme(theme.scheme)
            }
            .onAppear { CallMotionLabMeter.shared.start() }
            .onDisappear {
                CallMotionLabMeter.shared.stop()
                levels.isPlaying = false
            }
    }

    /// The call's header, pill and dock over a picture: the dark material (the call's choice) or Liquid Glass.
    private var overVideoPicker: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            Text("Over video")
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
            Picker("Over video", selection: $isGlassOverVideo) {
                Text("Dark material").tag(false)
                Text("Liquid Glass").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Stages

    @ViewBuilder
    private var stageView: some View {
        switch stage {
        case .ring: ringStage
        case .icon: CallMotionIconStage(treatment: iconTreatment)
        case .pill: pillStage
        case .real: CallMotionLabRealScreens(setup: callSetup)
        case .assistants: CallMotionLabAssistantsStage(state: $assistantsState, canPresent: !isPanelShown)
        case .assistantsLive: CallMotionLabAssistantsLiveStage()
        case .translationStart: CallMotionLabTranslationStartStage()
        case .jobConfirm: CallMotionLabJobConfirmStage()
        case .avatars: CallMotionLabAvatarsStage(theme: $theme)
        case .group:
            CallMotionGroupStage(layout: groupLayout, count: groupCount, levels: groupLevels)
                .onAppear { groupLevels.count = groupCount }
                .onChange(of: groupCount) { _, count in groupLevels.count = count }
        }
    }

    /// The Ring stage takes the Call stage's assistant: its colour's field, or its photo's (question 400).
    private var ringStage: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            avatarWithRing

            VStack(spacing: CompoundDesignTokens.space2X) {
                Text("Assistant")
                    .font(.compound.headingXLBold)
                Text(connectedAt, style: .timer)
                    .font(.compound.bodyMD)
                    .monospacedDigit()
            }
            .foregroundStyle(.compound.textPrimary)
        }
        .padding(.bottom, 160)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            NativeCallBackdrop(photoURL: look.avatarURL, contentID: look.agentID, mediaProvider: look.mediaProvider, tone: .wash)
                .ignoresSafeArea()
        }
    }

    private var look: CallMotionLabCallSetup.AssistantLook {
        callSetup.assistantLook
    }

    /// The call's own ring (the Aura), fed the lab's voice: where the loudness calibration is judged.
    private var avatarWithRing: some View {
        NativeCallSpeakingRing(userID: look.agentID, diameter: SpiralAvatarSize.xLarge) {
            NativeCallLetterAvatar(userID: look.agentID,
                                   profile: .init(displayName: look.displayName, avatarURL: look.avatarURL),
                                   fallbackName: "Assistant",
                                   size: SpiralAvatarSize.xLarge,
                                   mediaProvider: look.mediaProvider)
        }
    }

    /// The pill in its place above the dock, over the voice call's field or the video picture; above it, every state.
    private var pillStage: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            Spacer(minLength: 0)

            if showsAllPillStates {
                // Every content of the call's pill (variant B), the call's own view.
                ScrollView {
                    VStack(spacing: CompoundDesignTokens.space2X) {
                        ForEach(CallMotionAgentPill.Case.allCases) { pillCase in
                            VStack(spacing: CompoundDesignTokens.space0_5X) {
                                Text(pillCase.rawValue)
                                    .font(.compound.bodyXS)
                                    .foregroundStyle(.secondary)
                                pill(pillCase)
                            }
                        }
                    }
                    .padding(.vertical, CompoundDesignTokens.space4X)
                }
                .scrollIndicators(.hidden)
            } else if !isPillOverVideo {
                NativeCallLetterAvatar(userID: Self.peerID, profile: nil, fallbackName: "Assistant", size: SpiralAvatarSize.xLarge, mediaProvider: nil)
                Text("Assistant")
                    .font(.compound.headingXLBold)
                    .foregroundStyle(.compound.textPrimary)
                Spacer(minLength: 0)
            }

            pill(pillCase)
            NativeCallGlassDock(controls: CallMotionLabControls.controls, showsCaptions: !isPillOverVideo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isPillOverVideo {
                CallMotionSamplePicture(scene: scene)
                    .ignoresSafeArea()
            } else {
                NativeCallBackdrop(tone: .wash)
                    .ignoresSafeArea()
            }
        }
        // As the call does: the video stage is dark whatever the theme, its surfaces over the picture.
        .environment(\.colorScheme, isPillOverVideo ? .dark : (theme.scheme ?? systemColorScheme))
        .environment(\.nativeCallIsOverPicture, isPillOverVideo)
    }

    private func pill(_ pillCase: CallMotionAgentPill.Case) -> some View {
        NativeCallAgentBlock(state: pillCase.state(agentUserID: Self.peerID)) { }
            .padding(.horizontal, CompoundDesignTokens.space4X)
    }

    private static let peerID = "@assistant-alex:example.org" // An agent's namespace, so it draws as one (question 389).

    // MARK: - The panel

    private var panel: some View {
        Form {
            Section {
                Picker("Screen", selection: $stage) {
                    ForEach(Stage.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                variantPicker

                meterRow
            }

            if stage == .real {
                Section("The call") {
                    Picker("Call", selection: $callSetup.kind) {
                        ForEach(CallMotionLabCallSetup.Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if callSetup.kind == .assistant {
                        assistantLookPicker
                    }
                    if callSetup.kind == .group {
                        Picker("People", selection: $callSetup.groupCount) {
                            ForEach([3, 4, 6, 8, 12], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Toggle("Video", isOn: $callSetup.isVideo)
                    if callSetup.isVideo {
                        overVideoPicker
                        Picker("Their picture", selection: $callSetup.isPictureDim) {
                            Text("Bright").tag(false)
                            Text("Dim").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Toggle("My camera", isOn: $callSetup.isMyCameraOn)
                        Toggle("Their camera", isOn: $callSetup.isTheirCameraOn)
                        Toggle("My picture large (as after a tap on the corner tile)", isOn: $callSetup.isSwapped)
                    }
                    Toggle("Muted", isOn: $callSetup.isMuted)
                    Picker("The agent", selection: $callSetup.agent) {
                        ForEach(CallMotionLabCallSetup.AgentState.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("The agent is mine", isOn: $callSetup.isAgentMine)
                    Toggle("A second agent", isOn: $callSetup.hasSecondAgent)
                    Text("Tap the corner tile to swap the pictures, again to swap back; the Camera control flips your camera.")
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
            }

            if stage == .pill {
                Section("Pill") {
                    Picker("Above the dock", selection: $pillCase) {
                        ForEach(CallMotionAgentPill.Case.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Background", selection: $isPillOverVideo) {
                        Text("Voice call").tag(false)
                        Text("Video").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isPillOverVideo {
                        Picker("Picture", selection: $scene) {
                            ForEach(CallMotionSamplePicture.Scene.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        overVideoPicker
                    }
                    Toggle("Every state above", isOn: $showsAllPillStates)
                }
            }

            Section("Voice") {
                HStack(spacing: CompoundDesignTokens.space3X) {
                    Button(levels.isPlaying ? "Pause" : "Play", systemImage: levels.isPlaying ? "pause.fill" : "play.fill") {
                        levels.isPlaying.toggle()
                    }
                    .buttonStyle(.borderedProminent)

                    Picker("Source", selection: $levels.source) {
                        ForEach(CallMotionLabLevels.Source.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .onChange(of: levels.source) { _, source in
                    levels.slider = source == .manual ? -24 : 0
                }

                if levels.source == .microphone {
                    SwiftUI.TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Text("\(levels.microphoneStatus) · Mac mic \(Int(levels.microphoneDecibels)) dBFS, sent as a phone would")
                            .font(.compound.bodySM)
                            .monospacedDigit()
                    }
                }

                if levels.source != .microphone {
                    VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
                        Text(levels.source == .manual ? "Level \(Int(levels.slider)) dBov" : "Loudness \(levels.slider >= 0 ? "+" : "")\(Int(levels.slider)) dB")
                            .font(.compound.bodySM)
                        Slider(value: $levels.slider, in: levels.source == .manual ? -60 ... -6 : -12...12, step: 1)
                    }
                }

                Toggle("Through the SFU (a level every 400 ms, as in a call)", isOn: $levels.isThroughSFU)
            }

            Section("Look") {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Right to left", isOn: $isRightToLeft)
                Picker("Text size", selection: $textSize) {
                    ForEach(TextSize.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                // The call's own views read these from the system, so the lab follows Settings.
                Text("Reduce Motion \(systemReduceMotion ? "on" : "off") · Low Power Mode \(NativeCallLowPowerMode.shared.isEnabled ? "on" : "off") (Settings)")
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }

            Section("Cost") {
                costReadout
            }

            Section {
                if let onClose {
                    Button("Close the lab", role: .cancel, action: onClose)
                } else {
                    Toggle("Open the lab at launch", isOn: $opensAtLaunch)
                }
            }
        }
    }

    @ViewBuilder
    private var variantPicker: some View {
        switch stage {
        case .icon:
            Picker("Colour", selection: $iconTreatment) {
                ForEach(CallMotionIconStage.Treatment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        case .ring:
            assistantLookPicker
            Text("The call's Aura ring: the voice and the loudness calibration, on the assistant's field.")
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        case .pill:
            Text("The call's pill: who at rest, what it does when it does something (variant B).")
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        case .group:
            Picker("Layout", selection: $groupLayout) {
                ForEach(CallMotionGroupStage.Layout.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("People", selection: $groupCount) {
                ForEach([3, 4, 6, 8, 12], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            if groupLayout == .focus {
                overVideoPicker
            }
        case .real:
            Picker("Shows", selection: $callSetup.surface) {
                ForEach(CallMotionLabCallSetup.Surface.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        case .assistants:
            Picker("State", selection: $assistantsState) {
                ForEach(NativeCallAssistantsLabState.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Show the sheet") { isPanelShown = false }
            Text("The call's Assistants sheet (question 387). The panel steps aside for it; the menu at the top picks the state.")
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        case .assistantsLive:
            Button("Show the call") { isPanelShown = false }
            Text("The Assistants sheet live (question 401): the dock's Assistants button opens it, and every tap changes a mocked platform. The pill over the clock sets the scenario.")
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        case .translationStart:
            Button("Show the call") { isPanelShown = false }
            Text("How call translation starts (1.0.3, B): the live sheet's Start, Stop and Translate into …, opened from the 文A menu or the Assistant button. The pill over the clock plays its states.")
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        case .jobConfirm:
            Button("Show the call") { isPanelShown = false }
            Text("The Assistants sheet after the 1.0.3 pick C: each job asked under the buttons, Translation's question at rest, the 文A menu on the same root. The pill over the clock picks the cast and plays a tap.")
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        case .avatars:
            Text("Agents without a picture, each in its own colour (question 390); the palette itself at the bottom.")
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        }
    }

    /// One's own assistant on its page: its colour without a photo, or a photo (question 400).
    private var assistantLookPicker: some View {
        Picker("Assistant", selection: $callSetup.assistantLook) {
            ForEach(CallMotionLabCallSetup.AssistantLook.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// What reaches the drawings (the SFU's level) and where the speaker's scale puts it: the mapping, live.
    private var meterRow: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let amplitude = levels.loudestVoiceLevel
            let decibels = amplitude > 0 ? 20 * log10(amplitude) : nil
            let mapped = levels.isPlaying ? levels.mappedLevel : 0
            HStack(spacing: CompoundDesignTokens.space4X) {
                meter(title: decibels.map { String(format: "In %.0f dBov", $0) } ?? "In: silent",
                      value: decibels.map { ($0 + 60) / 60 } ?? 0)
                meter(title: String(format: "Motion %.2f", mapped), value: mapped)
            }
        }
    }

    private func meter(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            Text(title)
                .font(.compound.bodySM)
                .monospacedDigit()
            ProgressView(value: min(1, max(0, value)))
        }
        .frame(maxWidth: .infinity)
    }

    private var costReadout: some View {
        let reading = CallMotionLabMeter.shared.reading
        return VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            Text("Drawing: \(String(format: "%.0f", reading.drawMicroseconds)) µs a frame, \(reading.framesPerSecond) frames a second")
            Text("Main thread: \(String(format: "%.1f", reading.mainThreadPercent)) % · app: \(String(format: "%.1f", reading.processPercent)) % of a core")
            Text("Includes the lab's own panel. Simulator numbers: compare variants, not devices.")
                .foregroundStyle(.compound.textSecondary)
        }
        .font(.compound.bodySM)
        .monospacedDigit()
    }
}

/// The app when it is launched as the lab: no session, no account, just the lab.
final class CallMotionLabAppCoordinator: AppCoordinatorProtocol, SecureWindowManagerDelegate {
    let windowManager: SecureWindowManagerProtocol

    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: CallMotionLabScreen.launchKey)
    }

    init(appDelegate: AppDelegate) {
        windowManager = WindowManager(appDelegate: appDelegate)
        windowManager.delegate = self
    }

    func start() { }

    func toPresentable() -> AnyView {
        AnyView(CallMotionLabScreen())
    }

    func windowManagerDidConfigureWindows(_ windowManager: SecureWindowManagerProtocol) { }

    func handlePotentialPhishingAttempt(url: URL, openURLAction: @escaping (URL) -> Void) -> Bool {
        false
    }

    func handleDeepLink(_ url: URL, isExternalURL: Bool, windowType: SecondaryWindowType?) -> Bool {
        false
    }

    func handleAppRoute(_ appRoute: AppRoute, windowType: SecondaryWindowType?) { }

    func handleUserActivity(_ activity: NSUserActivity) { }
}

#endif
