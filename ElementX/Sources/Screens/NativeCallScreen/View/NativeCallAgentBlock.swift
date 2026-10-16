//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063, native call UI Phase 1): the agent block.
//
// `[slot] name … event >` — a full-width band above the controls in an
// audio call, one tap from the Agent Center. Design: `.pen` screens
// `03 · Call 1:1`, `05 · Group call` and the state reference
// `20 · REF · Agent block`.
//
// The behavioural model is the Element Call fork's `SpiralAgentDock`: the
// slot MORPHS between the identity glyph and the voice wave inside one
// footprint, so nothing reflows when translation starts, and only one
// accent shows at a time. The block itself is presentational — its
// `accessibilityLabel` is what says out loud what the agent is doing.

import Compound
import SwiftUI

/// How the block sits on its screen. One state model, two dressings —
/// the fact shown never depends on the dressing (plan §2).
enum NativeCallAgentBlockStyle {
    /// The full-width band above the controls in an audio call.
    case band
    /// Phase 3 (G5) — the floating dark pill over the video stage
    /// (`06 · Video call 1:1`): fitted width, no chevron, content only.
    /// Video is edge-to-edge, so a full-width band would read as a
    /// second toolbar over the picture.
    case capsule
}

struct NativeCallAgentBlock: View {
    let state: NativeCallAgentBlockState
    let action: () -> Void
    /// The live amplitude for the wave, sampled at display rate while the
    /// slot airs. nil (previews, snapshot tests) draws the static bars.
    var style: NativeCallAgentBlockStyle = .band

    var body: some View {
        Button(action: action) {
            switch style {
            case .band: band
            case .capsule: capsule
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(UntranslatedL10n.a11yNativeCallAgentBlockHint)
        .accessibilityAddTraits(.isButton)
    }

    /// `03 · Call 1:1`'s agent bar: a white card, the 32pt slot, the name
    /// and the current event right-aligned, a quiet chevron.
    private var band: some View {
        HStack(spacing: 10) {
            NativeCallAgentSlot(event: state.event, agentUserID: state.agentUserID)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Several agents: the block shows the active one, so it
                // has to admit the others exist.
                if let agentCountLine = state.agentCountLine {
                    Text(agentCountLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            eventLabel

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 54)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// The pill carries the same slot and event with no chevron and no
    /// count line — over live video every extra mark is noise, and the
    /// whole pill is already the tap target. Rendered inside the video
    /// stage's forced-dark environment, so the canvas token resolves dark;
    /// the alpha lets the picture read through, as the design's
    /// `#1C1C1EE6` does.
    private var capsule: some View {
        HStack(spacing: 10) {
            NativeCallAgentSlot(event: state.event, agentUserID: state.agentUserID)

            Text(state.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            eventLabel
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(Color.compound.bgCanvasDefault.opacity(0.9), in: Capsule())
    }

    /// One event, never a row of badges (plan §5.4). An interpreter session
    /// lists its languages with the produced one leading and the rest quiet,
    /// which is how `20 · REF · Agent block` renders `EN · DE · UK`.
    @ViewBuilder
    private var eventLabel: some View {
        switch state.event {
        case .airing(.translation(let languages)):
            languageList(languages, isLive: true)
        case .idle(nil, let languages) where !languages.isEmpty:
            languageList(languages, isLive: false)
        default:
            Text(NativeCallAgentStatusCopy.blockWord(state.event) ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(eventHue)
                .lineLimit(1)
        }
    }

    /// Critical for the one state the user must act on, info for a
    /// degraded-but-working one, secondary for rest.
    private var eventHue: Color {
        switch state.event {
        case .failure: .compound.textCriticalPrimary
        case .paused, .original: .compound.textInfoPrimary
        // On the air reads like a translation's leading language: primary.
        case .airing: .compound.textPrimary
        case .idle: .compound.textSecondary
        }
    }

    /// The first language is the one being produced; the rest are the
    /// booth's remaining lanes, dimmed.
    private func languageList(_ languages: [String], isLive: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(languages.prefix(3).enumerated()), id: \.offset) { index, language in
                if index > 0 {
                    Circle()
                        .fill(Color.compound.iconTertiary)
                        .frame(width: 3, height: 3)
                }
                Text(NativeCallAgentStatusCopy.blockLanguageLabel(language, isLeading: index == 0))
                    .font(index == 0 ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(index == 0 && isLive ? AnyShapeStyle(.compound.textPrimary) : AnyShapeStyle(.compound.textSecondary))
                    .lineLimit(1)
            }
        }
    }

    private var accessibilityLabel: String {
        NativeCallAgentStatusCopy.blockAccessibilityLabel(name: state.name, event: state.event)
    }
}

/// The live element: one 30pt footprint that holds the identity glyph, the
/// four-bar wave, or the state glyph for a degraded event. Every variant is
/// laid out identically, so the morph never moves the name next to it —
/// the `SpiralAgentDock` rule of one footprint and one accent at a time.
private struct NativeCallAgentSlot: View {
    let event: NativeCallAgentEvent
    let agentUserID: String

    private static let size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(background)

            switch event {
            case .airing:
                NativeCallVoiceWave(userID: agentUserID, scale: .block)
            case .failure:
                glyph(\.error, tint: .compound.iconCriticalPrimary)
            case .paused:
                glyph(\.pause, tint: .compound.iconInfoPrimary)
            case .original:
                // The ears fell back to the raw voices: the volume mark in
                // the info hue — audible, not broken.
                glyph(\.volumeOn, tint: .compound.iconInfoPrimary)
            case .idle:
                // The identity glyph at rest. The design uses lucide
                // `sparkles`; Compound ships no sparkles/wand/star mark.
                // Operator decision 2026-08-20: use the system `sparkles`
                // symbol (the exact SF match for the design glyph) rather
                // than borrowing an unrelated Compound token.
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.compound.iconTertiary)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeInOut(duration: 0.2), value: event)
        .accessibilityHidden(true)
    }

    private func glyph(_ icon: KeyPath<CompoundIcons, Image>, tint: Color) -> some View {
        CompoundIcon(icon, size: .xSmall, relativeTo: .compound.bodyMD)
            .foregroundStyle(tint)
    }

    /// `20 · REF · Agent block` washes the live slot in `$accent-wash`, a pale
    /// BLUE behind the `$accent` bars. In this brand build Compound's
    /// `bgAccentSubtle` resolves to `green200`, which would put green behind
    /// the (blue) accent bars — so the airing wash uses `bgInfoSubtle`
    /// (`blue200`), the only Compound token in the design's hue family.
    /// That makes airing and paused share a wash where the design separates
    /// them; the two never collide, because the ladder shows ONE event and
    /// the marks differ — a wave versus a pause glyph.
    private var background: Color {
        switch event {
        case .airing: .compound.bgInfoSubtle
        case .failure: .compound.bgCriticalSubtle
        case .paused, .original: .compound.bgInfoSubtle
        case .idle: .compound.bgSubtleSecondary
        }
    }
}

/// Four bars at the heights the design specifies, dancing to the agent's
/// SERVER-reported voice level — the EC fork's `SpiralVoiceWave` idiom.
///
/// The distinction that keeps this a state and not decoration: WHETHER the
/// wave shows is the airing event (document claim ∧ speaking, upstream of
/// this view); HOW TALL the bars stand is the live amplitude, sampled at
/// display rate and settling to stubs the moment the level reads 0. The
// MARK: - Previews

struct NativeCallAgentBlock_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 8) {
            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .airing(.translation(languages: ["en"])),
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .idle(role: nil, languages: ["en"]),
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .airing(.translation(languages: ["en", "de", "uk"])),
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .airing(.conversation),
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .idle(role: .conversation,
                                                           languages: []),
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .idle(role: .recording,
                                                           languages: []),
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .idle(role: nil, languages: []),
                                              agentCountLine: UntranslatedL10n.screenNativeCallAgentBlockCount(1, 2))) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .paused,
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .original,
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .idle(role: .waiting,
                                                           languages: []),
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .failure(.deliveryFailed),
                                              agentCountLine: nil)) { }

            NativeCallAgentBlock(state: .init(name: "Alice's Assistant",
                                              event: .airing(.translation(languages: ["en"])),
                                              agentCountLine: nil),
                                 action: { },
                                 style: .capsule)
                .environment(\.colorScheme, .dark)
        }
        .padding(20)
        .background(Color.compound.bgSubtlePrimary)
        .previewDisplayName("Agent block states")
    }
}
