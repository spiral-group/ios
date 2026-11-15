//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the group call in the call-motion lab with the operator's picks: audio as
// the Spotlight (the speaker large, the others in the call's whole-tile strip), video as Focus (the speaker on the
// stage, the others in the filmstrip), every tile's edge bending with its voice (the call's Aura edge). Simulated
// people take turns through the call's own stage rule, each with a voice of their own through the SFU copy; with Mic,
// "you" are the Mac's microphone. Drawn pictures only: no faces.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Compound
import SpiralTokens
import SwiftUI

struct CallMotionGroupStage: View {
    enum Layout: String, CaseIterable, Identifiable {
        /// Audio: whoever has the floor, large at the centre; the others in the strip.
        case spotlight = "Spotlight"
        /// Video: whoever has the floor fills the stage; the others in the filmstrip.
        case focus = "Focus"

        var id: Self {
            self
        }

        var isVideo: Bool {
            self == .focus
        }
    }

    let layout: Layout
    let count: Int
    let levels: CallMotionLabGroupLevels

    var body: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            header

            Group {
                switch layout {
                case .spotlight: spotlight
                case .focus: focus
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(duration: 0.45, bounce: 0), value: levels.turn)

            NativeCallAgentBlock(state: NativeCallAgentBlockState(name: "Alex Sample · assistant",
                                                                  event: .airing(.translation(languages: ["en", "uk"])),
                                                                  agentUserID: CallMotionLabGroupLevels.agentID,
                                                                  isOwn: true)) { }
            NativeCallGlassDock(controls: CallMotionLabControls.controls, showsCaptions: !layout.isVideo)
        }
        .background {
            NativeCallBackdrop(tone: .wash)
                .ignoresSafeArea()
        }
        .environment(\.nativeCallVoiceLevels, levels)
        .environment(\.colorScheme, layout.isVideo ? .dark : colorScheme)
        .environment(\.nativeCallIsOverPicture, layout.isVideo)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var people: [CallMotionLabGroupLevels.Person] {
        Array(levels.people.prefix(count))
    }

    private var header: some View {
        VStack(spacing: CompoundDesignTokens.space1X) {
            Text("Book club")
                .font(.compound.headingSMSemibold)
            Text("\(count) people · 1 agent")
                .font(.compound.bodyMD)
        }
        // No foreground style of its own: the glass's default vibrant text (an experiment against the call's header).
        .padding(.horizontal, CompoundDesignTokens.space5X)
        .padding(.vertical, CompoundDesignTokens.space2X)
        .nativeCallSurface(in: Capsule())
    }

    // MARK: - Audio

    /// Everyone but the speaker, you last, as in the call.
    private func strip(without speaker: CallMotionLabGroupLevels.Person) -> [CallMotionLabGroupLevels.Person] {
        let others = people.filter { $0.id != speaker.id }
        return others.filter { $0.id != CallMotionLabGroupLevels.youID } + others.filter { $0.id == CallMotionLabGroupLevels.youID }
    }

    private var spotlight: some View {
        let speaker = people.first { $0.id == levels.turn } ?? people[0]
        let others = strip(without: speaker)
        return VStack(spacing: CompoundDesignTokens.space8X) {
            Spacer(minLength: 0)
            face(speaker, size: SpiralAvatarSize.xLarge)
                .id(speaker.id)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            Spacer(minLength: 0)
            // The call's strip: whole faces inside the margins, four on a usual phone, the rest by scrolling.
            NativeCallTileStrip(items: others, minimumTileLength: 76, spacing: CompoundDesignTokens.space2X, crossInset: 12) { person, width in
                face(person, size: min(64, width - 24))
                    .frame(width: width)
            }
            .padding(.horizontal, CompoundDesignTokens.space6X)
        }
    }

    private func face(_ person: CallMotionLabGroupLevels.Person, size: CGFloat) -> some View {
        VStack(spacing: CompoundDesignTokens.space4X) {
            NativeCallSpeakingRing(userID: person.id, diameter: size) {
                NativeCallLetterAvatar(userID: person.id, profile: nil, fallbackName: person.name, size: size, mediaProvider: nil)
            }
            label(person)
        }
    }

    // MARK: - Video

    private var focus: some View {
        let speaker = people.first { $0.id == levels.turn } ?? people[0]
        let others = strip(without: speaker)
        return VStack(spacing: CompoundDesignTokens.space2X) {
            tile(speaker)
                .id(speaker.id)
                .transition(.opacity)
            // The call's filmstrip: whole tiles inside the stage's margins.
            NativeCallTileStrip(items: others, minimumTileLength: 80, spacing: CompoundDesignTokens.space2X, crossInset: NativeCallTileAuraEdge.reach) { person, width in
                tile(person, isSmall: true).frame(width: width, height: width * 4 / 3)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space3X)
    }

    private func tile(_ person: CallMotionLabGroupLevels.Person, isSmall: Bool = false) -> some View {
        let radius = isSmall ? SpiralRadius.block : SpiralRadius.listCard
        return CallMotionSamplePicture(scene: person.index.isMultiple(of: 2) ? .bright : .dim)
            .hueRotation(.degrees(Double(person.index) * 47))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                label(person, isSmall: isSmall)
                    .padding(isSmall ? CompoundDesignTokens.space1X : CompoundDesignTokens.space2X)
            }
            .overlay {
                NativeCallTileAuraEdge(userID: person.id, cornerRadius: radius)
            }
    }

    /// The name and the muted mark on glass: legible over any picture.
    private func label(_ person: CallMotionLabGroupLevels.Person, isSmall: Bool = false) -> some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            if person.isMuted {
                Image(systemName: "mic.slash.fill")
                    .font(.compound.bodyXS)
            }
            Text(person.name)
                .font(isSmall ? .compound.bodyXSSemibold : .compound.bodySMSemibold)
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, CompoundDesignTokens.space2X)
        .padding(.vertical, CompoundDesignTokens.space1X)
        .nativeCallSurface(in: Capsule())
    }
}

/// People taking turns, each a simulated voice through its own SFU copy; "you" are the lab's own source (the Mac's
/// microphone with Mic). The agent translates while someone else speaks.
@Observable
final class CallMotionLabGroupLevels: NativeCallVoiceLevelReading {
    struct Person: Identifiable {
        let id: String
        let name: String
        let index: Int
        let isMuted: Bool
    }

    static let agentID = "@agent-group:example.org"
    static let youID = "@you:example.org"

    let people: [Person] = [
        Person(id: youID, name: L10n.commonYou, index: 0, isMuted: false),
        Person(id: "@p1:example.org", name: "Maria", index: 1, isMuted: false),
        Person(id: "@p2:example.org", name: "Oleh", index: 2, isMuted: false),
        Person(id: "@p3:example.org", name: "Iryna", index: 3, isMuted: true),
        Person(id: "@p4:example.org", name: "Taras", index: 4, isMuted: false),
        Person(id: "@p5:example.org", name: "Sofia", index: 5, isMuted: false),
        Person(id: "@p6:example.org", name: "Danylo", index: 6, isMuted: false),
        Person(id: "@p7:example.org", name: "Olena", index: 7, isMuted: false),
        Person(id: "@p8:example.org", name: "Marko", index: 8, isMuted: false),
        Person(id: "@p9:example.org", name: "Hanna", index: 9, isMuted: true),
        Person(id: "@p10:example.org", name: "Petro", index: 10, isMuted: false),
        Person(id: "@p11:example.org", name: "Daria", index: 11, isMuted: false)
    ]

    /// Who is on the stage: the spotlight and the focus follow it, moved by the call's own rule (a sustained turn of
    /// `NativeCallGroupFocus.sustainedTurn`), so the short interjections below leave it where it is.
    private(set) var turn = "@p1:example.org"
    /// How many people are on the stage: turns go round them only.
    var count = 4

    /// The turn the simulation is on; `turn` follows it outside the render that moved it.
    @ObservationIgnored private var currentTurn = "@p1:example.org"
    @ObservationIgnored private let you: CallMotionLabLevels
    @ObservationIgnored private var speakers: [String: CallMotionLabSpeaker] = [:]
    @ObservationIgnored private var sfus: [String: CallMotionLabSFU] = [:]
    @ObservationIgnored private var random = CallMotionLabRandom(seed: 0x6A0)
    @ObservationIgnored private var turnLeft = 2.5
    @ObservationIgnored private var lastTime: Double?
    @ObservationIgnored private var focus = NativeCallGroupFocus()
    /// `-SpiralCallMotionLabGroupEveryoneSpeaks YES`: the cost run's worst case, every voice at once.
    @ObservationIgnored private let everyoneSpeaks = UserDefaults.standard.bool(forKey: "SpiralCallMotionLabGroupEveryoneSpeaks")
    @ObservationIgnored private var simulatedTime = 0.0
    /// Someone saying "yes" over the speaker for under a second: it must not move the stage.
    @ObservationIgnored private var interjector: String?
    @ObservationIgnored private var interjectionLeft = 0.0

    init(you: CallMotionLabLevels) {
        self.you = you
        for (index, person) in people.enumerated() where person.id != Self.youID {
            speakers[person.id] = CallMotionLabSpeaker(seed: UInt64(100 + index))
            sfus[person.id] = CallMotionLabSFU()
        }
        speakers[Self.agentID] = CallMotionLabSpeaker(seed: 99)
        sfus[Self.agentID] = CallMotionLabSFU()
    }

    func voiceLevel(forUserID userID: String) -> Double {
        if userID == Self.youID {
            return you.source == .microphone ? you.voiceLevel(forUserID: userID) : 0
        }
        advanceToNow()
        return sfus[userID]?.reported ?? 0
    }

    var loudestVoiceLevel: Double {
        people.prefix(count).map { voiceLevel(forUserID: $0.id) }.max() ?? 0
    }

    private func advanceToNow() {
        let now = CACurrentMediaTime()
        defer { lastTime = now }
        guard let lastTime, you.isPlaying else { return }
        var remaining = min(now - lastTime, 1)
        while remaining > 0 {
            let step = min(remaining, 0.01)
            simulatedTime += step
            turnLeft -= step
            if turnLeft <= 0 {
                nextTurn()
            }
            interject(step: step)
            for (id, _) in sfus {
                let isTalking = everyoneSpeaks || id == currentTurn || id == interjector || (id == Self.agentID && currentTurn != Self.youID)
                let decibels = speakers[id].map { var speaker = $0
                    let level = speaker.advance(by: step)
                    speakers[id] = speaker
                    return isTalking ? level : CallMotionLabSpeaker.silenceDecibels
                } ?? CallMotionLabSpeaker.silenceDecibels
                sfus[id]?.advance(by: step, decibels: decibels)
            }
            remaining -= step
        }
        let stage = people.prefix(count).map(\.id).filter { $0 != Self.youID }
        focus.update(at: simulatedTime, candidates: stage, speaking: Set([currentTurn, interjector].compactMap { $0 }))
        if let focused = focus.focused, focused != publishedTurn {
            publishedTurn = focused
            Task { @MainActor [weak self] in self?.turn = focused }
        }
    }

    /// The stage last handed to `turn`.
    @ObservationIgnored private var publishedTurn = "@p1:example.org"

    /// Now and then someone else says a word over the speaker, for 0.3 to 0.7 s.
    private func interject(step: Double) {
        if interjector != nil {
            interjectionLeft -= step
            if interjectionLeft <= 0 {
                interjector = nil
            }
            return
        }
        guard random.next(in: 0...1) < step / 3 else { return }
        let candidates = people.prefix(count).filter { $0.id != Self.youID && !$0.isMuted && $0.id != currentTurn }
        guard !candidates.isEmpty else { return }
        let pick = Int(random.next(in: 0...Double(candidates.count - 1)).rounded())
        interjector = candidates[min(pick, candidates.count - 1)].id
        interjectionLeft = random.next(in: 0.3...0.7)
    }

    /// The next person to speak: anyone on the stage but you, the muted and whoever just spoke.
    private func nextTurn() {
        let candidates = people.prefix(count).filter { $0.id != Self.youID && !$0.isMuted && $0.id != currentTurn }
        guard !candidates.isEmpty else { return }
        let pick = Int(random.next(in: 0...Double(candidates.count - 1)).rounded())
        currentTurn = candidates[min(pick, candidates.count - 1)].id
        turnLeft = random.next(in: 2...4.5)
    }
}

#endif
