//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3, operator's pick B 2026-11-19): how call translation starts, played live. The call runs on the
// same mocked platform as "AssistantsLive" (`NativeCallAssistantsLiveLab`): the real call screen and the real
// Assistants sheet, whose bottom button carries the state — «Start translation», «Stop translation», and «Translate
// into …» for a language picked while it runs (`NativeCallTranslationAction`).
//
// The pill over the clock opens the panel: the way in (the 文A menu or the dock's Assistant button) and the four states
// played from a fresh call — Idle (just opened), Picked (Russian chosen), Running (your assistant translates into
// Russian) and Changed (French picked while it runs). Launch arguments, with
// `-SpiralCallMotionLab YES -SpiralCallMotionLabStage TranslationStart`: `-SpiralCallMotionLabStartEntry Menu|Assistant`,
// `-SpiralCallMotionLabStartStep Idle|Picked|Running|Changed`. Text follows the device: `-AppleLanguages "(ru)"`.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Combine
import Compound
import SpiralTokens
import SwiftUI

struct CallMotionLabTranslationStartStage: View {
    /// How the sheet opens.
    enum Entry: String, CaseIterable, Identifiable {
        /// The 文A menu's «Add your own translation…».
        case menu = "Menu"
        /// The dock's Assistant button.
        case assistant = "Assistant"

        var id: Self {
            self
        }
    }

    /// The states each variant is judged in, each played from a fresh call.
    enum Step: String, CaseIterable, Identifiable {
        case idle = "Idle"
        case picked = "Picked"
        case running = "Running"
        case changed = "Changed"

        var id: Self {
            self
        }
    }

    /// The language picked in Picked and Running; Changed picks the second while it runs.
    static let pickedLanguage = "ru"
    static let changedLanguage = "fr"

    @Environment(\.nativeCallVoiceLevels) private var levels
    @State private var renderer = CallMotionLabVideoRenderer()
    @State private var entry: Entry
    @State private var step: Step?
    @State private var lab: NativeCallAssistantsLiveLab?
    @State private var hitArea = CallMotionLabOverlayHitArea()
    @State private var playing: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        _entry = State(initialValue: Entry(rawValue: defaults.string(forKey: "SpiralCallMotionLabStartEntry") ?? "") ?? .assistant)
        _step = State(initialValue: Step(rawValue: defaults.string(forKey: "SpiralCallMotionLabStartStep") ?? ""))
    }

    var body: some View {
        ZStack {
            Color.clear
            if let lab {
                NativeCallScreen(context: lab.viewModel.context, videoRenderer: renderer, voiceLevels: levels)
                    .id(ObjectIdentifier(lab))
            }
        }
        .background {
            if lab != nil {
                CallMotionLabOverlayWindow(hitArea: hitArea) {
                    CallMotionLabTranslationStartPanel(entry: $entry,
                                                       step: step,
                                                       hitArea: hitArea,
                                                       open: open,
                                                       play: play,
                                                       reset: { step = nil; reset() })
                }
            }
        }
        .onAppear {
            if let step {
                play(step)
            } else {
                reset()
            }
        }
        .onDisappear {
            playing?.cancel()
            lab = nil
        }
    }

    /// A fresh call: you and John, your assistant not in it, nothing picked (you speak Ukrainian, as the phone says).
    private func reset() {
        playing?.cancel()
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
        let backend = NativeCallAssistantsLabBackend(cast: .onePerson, role: .moderator, latency: .short, joinDuration: .milliseconds(1500))
        lab = NativeCallAssistantsLiveLab(backend: backend)
    }

    /// Opens the sheet the chosen way.
    private func open() {
        guard let context = lab?.viewModel.context else { return }
        switch entry {
        case .menu: context.send(viewAction: .addOwnTranslation)
        case .assistant: context.send(viewAction: .showAgentCenter)
        }
    }

    /// A fresh call brought to the step, then the sheet opened the chosen way.
    private func play(_ step: Step) {
        self.step = step
        reset()
        guard let lab else { return }
        let viewModel = lab.viewModel
        let context = viewModel.context
        let entry = entry
        playing = Task { @MainActor in
            while !viewModel.state.agentCenter.isAvailable {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .milliseconds(600))
            if step != .idle {
                context.send(viewAction: .setMyLanguage(Self.pickedLanguage))
            }
            if step == .running || step == .changed {
                context.send(viewAction: .produceTranslation)
                for _ in 0..<150 where viewModel.state.agents.ownAgents.first?.shown.isTranslating != true {
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { return }
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
            if Task.isCancelled { return }
            switch entry {
            case .menu: context.send(viewAction: .addOwnTranslation)
            case .assistant: context.send(viewAction: .showAgentCenter)
            }
            if step == .changed {
                // Picked in the open sheet's «Translate into», as a person would: held for «Translate into …».
                try? await Task.sleep(for: .milliseconds(400))
                context.send(viewAction: .pickTranslationLanguage(Self.changedLanguage))
            }
        }
    }
}

/// The scenario pill over the clock and its panel.
private struct CallMotionLabTranslationStartPanel: View {
    @Binding var entry: CallMotionLabTranslationStartStage.Entry
    let step: CallMotionLabTranslationStartStage.Step?
    let hitArea: CallMotionLabOverlayHitArea
    let open: () -> Void
    let play: (CallMotionLabTranslationStartStage.Step) -> Void
    let reset: () -> Void

    private var isExpanded: Bool {
        hitArea.isExpanded
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if isExpanded {
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
                .padding(.top, max(CompoundDesignTokens.space1X, (geometry.safeAreaInsets.top - 30) / 2))
                .padding(.leading, CompoundDesignTokens.space4X)
            }
            .ignoresSafeArea()
        }
    }

    private var pill: some View {
        Button { setExpanded(!isExpanded) } label: {
            HStack(spacing: CompoundDesignTokens.space1X) {
                Image(systemName: "slider.horizontal.3")
                Text(([entry.rawValue, step?.rawValue].compactMap(\.self)).joined(separator: " · "))
            }
            .font(.compound.bodyXSSemibold)
            .foregroundStyle(Color.compound.textPrimary)
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
            row("The sheet opens from") {
                Picker("The sheet opens from", selection: $entry) {
                    Text("文A menu").tag(CallMotionLabTranslationStartStage.Entry.menu)
                    Text("Assistant button").tag(CallMotionLabTranslationStartStage.Entry.assistant)
                }
                .pickerStyle(.segmented)
            }
            row("Play from a fresh call") {
                HStack(spacing: CompoundDesignTokens.space2X) {
                    ForEach(CallMotionLabTranslationStartStage.Step.allCases) { step in
                        Button(step.rawValue) {
                            setExpanded(false)
                            play(step)
                        }
                    }
                }
                .font(.compound.bodySMSemibold)
            }
            Text("Picked: Russian. Running: your assistant translates into Russian. Changed: French picked while it runs.")
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
            HStack(spacing: CompoundDesignTokens.space2X) {
                Button("Open the sheet") {
                    setExpanded(false)
                    open()
                }
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

    private func setExpanded(_ isExpanded: Bool) {
        hitArea.isExpanded = isExpanded
        hitArea.onExpandedChange?()
    }
}

// MARK: - 1.0.3: a confirmation for every job

// AGENT-PLATFORM (1.0.3, operator's pick C 2026-11-21): the live Assistants sheet as it ships — a button only picks its
// job; Notes, Talk and Recording ask under the buttons; Translation's question is where the sheet rests; the 文A menu
// opens the same root. Each step is a tap played from a fresh call on the mocked platform, in any of the lab's casts.
// Launch arguments, with `-SpiralCallMotionLab YES -SpiralCallMotionLabStage JobConfirm`:
// `-SpiralCallMotionLabJobStep <Step>`, `-SpiralCallMotionLabJobCast private|person|personAssistant|group`.
struct CallMotionLabJobConfirmStage: View {
    /// A tap on a job, with your assistant not in the call yet or already in it.
    enum Step: String, CaseIterable, Identifiable {
        case notes = "Notes"
        case talk = "Talk"
        case record = "Record"
        case notesInCall = "NotesInCall"
        case talkInCall = "TalkInCall"
        case recordInCall = "RecordInCall"
        /// Your assistant already talking: the sheet as it reads then (the info block).
        case talking = "Talking"
        /// The Translation circle tapped (C asks about it too).
        case translate = "Translate"
        case translateInCall = "TranslateInCall"
        /// The 文A menu's «Add your own translation…»: the same root with Translation picked.
        case translateFromMenu = "TranslateFromMenu"
        /// «Translate into» English, which John already speaks: the question waits, Start says there is nothing to do.
        case nothingToTranslate = "Nothing"

        var id: Self {
            self
        }

        var job: NativeCallAssistantJob {
            switch self {
            case .notes, .notesInCall: .summary
            case .talk, .talkInCall, .talking: .conversation
            case .record, .recordInCall: .recording
            case .translate, .translateInCall, .translateFromMenu, .nothingToTranslate: .translation
            }
        }

        var isInCall: Bool {
            switch self {
            case .notes, .talk, .record, .translate, .translateFromMenu, .nothingToTranslate: false
            case .notesInCall, .talkInCall, .recordInCall, .talking, .translateInCall: true
            }
        }

        var shortTitle: String {
            switch self {
            case .notes: "Notes"
            case .talk: "Talk"
            case .record: "Rec"
            case .notesInCall: "Notes"
            case .talkInCall: "Talk"
            case .recordInCall: "Rec"
            case .talking: "Talking"
            case .translate, .translateInCall: "Transl"
            case .translateFromMenu: "文A menu"
            case .nothingToTranslate: "Into EN"
            }
        }
    }

    @Environment(\.nativeCallVoiceLevels) private var levels
    @State private var renderer = CallMotionLabVideoRenderer()
    @State private var cast: NativeCallAssistantsLabBackend.Cast
    @State private var step: Step?
    @State private var lab: NativeCallAssistantsLiveLab?
    @State private var hitArea = CallMotionLabOverlayHitArea()
    @State private var playing: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        _cast = State(initialValue: NativeCallAssistantsLabBackend.Cast(rawValue: defaults.string(forKey: "SpiralCallMotionLabJobCast") ?? "") ?? .onePerson)
        _step = State(initialValue: Step(rawValue: defaults.string(forKey: "SpiralCallMotionLabJobStep") ?? ""))
    }

    var body: some View {
        ZStack {
            Color.clear
            if let lab {
                NativeCallScreen(context: lab.viewModel.context, videoRenderer: renderer, voiceLevels: levels)
                    .id(ObjectIdentifier(lab))
            }
        }
        .background {
            if lab != nil {
                CallMotionLabOverlayWindow(hitArea: hitArea) {
                    CallMotionLabJobConfirmPanel(cast: $cast, step: step, hitArea: hitArea, play: play, reset: { step = nil; reset() })
                }
            }
        }
        .onAppear {
            if let step {
                play(step)
            } else {
                reset()
            }
        }
        .onChange(of: cast) { _, _ in
            if let step {
                play(step)
            } else {
                reset()
            }
        }
        .onDisappear {
            playing?.cancel()
            lab = nil
        }
    }

    /// A fresh call in the picked cast, your assistant not in it.
    private func reset() {
        playing?.cancel()
        NativeCallAssistantsLiveLab.myLanguageStore.clearChoice()
        let backend = NativeCallAssistantsLabBackend(cast: cast, role: .moderator, latency: .short, joinDuration: .milliseconds(1500))
        lab = NativeCallAssistantsLiveLab(backend: backend)
    }

    /// A fresh call; for the in-call steps your assistant comes first (with Notes on, or Recording for NotesInCall); then
    /// the sheet opens and the job is tapped as a person would.
    private func play(_ step: Step) {
        self.step = step
        reset()
        guard let lab else { return }
        let viewModel = lab.viewModel
        let context = viewModel.context
        playing = Task { @MainActor in
            while !viewModel.state.agentCenter.isAvailable {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .milliseconds(600))
            if step.isInCall {
                context.send(viewAction: .toggleAssistantJob(step == .notesInCall ? .recording : .summary))
                for _ in 0..<150 where viewModel.state.agents.ownAgents.first?.shown.presence != .present {
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { return }
                }
                try? await Task.sleep(for: .milliseconds(800))
            }
            if step == .talking {
                context.send(viewAction: .toggleAssistantJob(.conversation))
                for _ in 0..<150 where viewModel.state.agents.ownAgents.first?.shown.isConversationActive != true {
                    try? await Task.sleep(for: .milliseconds(100))
                    if Task.isCancelled { return }
                }
            }
            if Task.isCancelled { return }
            if step == .nothingToTranslate {
                context.send(viewAction: .setMyLanguage("en"))
                try? await Task.sleep(for: .milliseconds(300))
            }
            if step == .translateFromMenu {
                context.send(viewAction: .addOwnTranslation)
                return
            }
            context.send(viewAction: .showAgentCenter)
            try? await Task.sleep(for: .milliseconds(700))
            // Translation is already picked when the sheet opens in C.
            // Translation's question is already where the sheet rests.
            if Task.isCancelled || step == .talking || step.job == .translation { return }
            context.send(viewAction: .tapAssistantJob(step.job))
        }
    }
}

/// The scenario pill over the clock and its panel.
private struct CallMotionLabJobConfirmPanel: View {
    @Binding var cast: NativeCallAssistantsLabBackend.Cast
    let step: CallMotionLabJobConfirmStage.Step?
    let hitArea: CallMotionLabOverlayHitArea
    let play: (CallMotionLabJobConfirmStage.Step) -> Void
    let reset: () -> Void

    private var isExpanded: Bool {
        hitArea.isExpanded
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if isExpanded {
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
                .padding(.top, max(CompoundDesignTokens.space1X, (geometry.safeAreaInsets.top - 30) / 2))
                .padding(.leading, CompoundDesignTokens.space4X)
            }
            .ignoresSafeArea()
        }
    }

    private var pill: some View {
        Button { setExpanded(!isExpanded) } label: {
            HStack(spacing: CompoundDesignTokens.space1X) {
                Image(systemName: "slider.horizontal.3")
                Text(([cast.shortTitle, step.map { ($0.isInCall ? "In call · " : "") + $0.shortTitle }].compactMap(\.self)).joined(separator: " · "))
            }
            .font(.compound.bodyXSSemibold)
            .foregroundStyle(Color.compound.textPrimary)
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
            row("Cast") {
                Picker("Cast", selection: $cast) {
                    ForEach(NativeCallAssistantsLabBackend.Cast.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            row("Assistant not in the call yet") {
                steps([.translate, .notes, .talk, .record])
            }
            row("Assistant already in the call") {
                steps([.translateInCall, .notesInCall, .talkInCall, .recordInCall])
            }
            row("Assistant already talking · from the menu") {
                steps([.talking, .translateFromMenu, .nothingToTranslate])
            }
            Text("A button only picks its job. Notes, Talk and Recording ask under the buttons; Translation's question is where the sheet rests; the 文A menu opens the same root.")
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
            HStack(spacing: CompoundDesignTokens.space2X) {
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

    private func steps(_ steps: [CallMotionLabJobConfirmStage.Step]) -> some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            ForEach(steps) { step in
                Button(step.shortTitle) {
                    setExpanded(false)
                    play(step)
                }
            }
        }
        .font(.compound.bodySMSemibold)
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            Text(title)
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
            content()
        }
    }

    private func setExpanded(_ isExpanded: Bool) {
        hitArea.isExpanded = isExpanded
        hitArea.onExpandedChange?()
    }
}

#endif
