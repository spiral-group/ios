//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063, native call UI Phase 1): the agent block, since
// Brief 0083 (decision 340) the assistant's glass pill: `[slot] line [chip]`,
// under the person's name in an audio call and over the dock in a video
// call, one tap from the Agent Center. What it says is
// `NativeCallAgentPillContent` (question 383, variant B): who at rest, what it
// does when it does something.
//
// The behavioural model is the Element Call fork's `SpiralAgentDock`: the
// slot holds the avatar in one footprint, an Aura round it while the agent
// speaks (question 383), so nothing reflows when translation starts, and only
// one accent shows at a time. The block itself is presentational — its `accessibilityLabel` is
// what says out loud what the agent is doing.

import Compound
import SpiralTokens
import SwiftUI

struct NativeCallAgentBlock: View {
    let state: NativeCallAgentBlockState
    let action: () -> Void
    /// The agent's member profile, for its photo at rest; the monogram from
    /// `state.name` without one.
    var profile: NativeCallMemberProfile?
    var mediaProvider: MediaProviderProtocol?
    /// Brief 0085, critique item 7: an event expands the capsule for a few seconds, with its action.
    var event: NativeCallCapsuleEventCopy?
    var eventProfile: NativeCallMemberProfile?
    var onEventAction: () -> Void = { }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = NativeCallAgentPillContent(state)
        ZStack {
            if let event {
                expanded(event)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Button(action: action) {
                    pill(content)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(content.accessibilityLabel)
                .accessibilityHint(UntranslatedL10n.a11yNativeCallAgentBlockHint)
                .accessibilityAddTraits(.isButton)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2), value: event)
    }

    /// The event: the assistant, whose it is on a small line and what happened under it; its button runs the action,
    /// anywhere else opens the sheet. Two lines wide, so it takes the row (Dynamic Island-like).
    private func expanded(_ event: NativeCallCapsuleEventCopy) -> some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            Button(action: action) {
                HStack(spacing: CompoundDesignTokens.space3X) {
                    NativeCallAgentSlot(slot: .avatar(isDimmed: false),
                                        agentUserID: event.agentUserID ?? state.agentUserID,
                                        name: state.name,
                                        otherAgentUserIDs: [],
                                        profile: eventProfile ?? profile,
                                        mediaProvider: mediaProvider)
                        .dynamicTypeSize(.large)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.who)
                            .font(.compound.bodyXS)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(event.line)
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(event.announcement)
            .accessibilityHint(UntranslatedL10n.a11yNativeCallAgentBlockHint)
            .accessibilityAddTraits(.isButton)

            if let title = event.action {
                Button(action: onEventAction) {
                    Text(title)
                        .font(.compound.bodySMSemibold)
                        .lineLimit(1)
                        .padding(.horizontal, CompoundDesignTokens.space4X)
                        .frame(minHeight: 36)
                        .foregroundStyle(Color.compound.textOnSolidPrimary)
                        .background(Color.compound.bgAccentRest, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(.leading, CompoundDesignTokens.space1_5X)
        .padding(.trailing, CompoundDesignTokens.space2X)
        .padding(.vertical, CompoundDesignTokens.space1_5X)
        .frame(maxWidth: .infinity, minHeight: 52)
        .nativeCallSurface(in: RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous), isInteractive: true)
        .accessibilityElement(children: .contain)
    }

    /// Over any picture, so glass rather than a card. The words take the primary style, which glass makes vibrant: it
    /// stays legible as the glass lightens over a bright picture and darkens over a dark one (question 383).
    private func pill(_ content: NativeCallAgentPillContent) -> some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            NativeCallAgentSlot(slot: content.slot,
                                agentUserID: state.agentUserID,
                                name: state.name,
                                otherAgentUserIDs: state.otherAgentUserIDs,
                                profile: profile,
                                mediaProvider: mediaProvider)
                .dynamicTypeSize(.large)

            // At accessibility sizes the chip goes under the line, so neither is cut.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: CompoundDesignTokens.space0_5X))
                : AnyLayout(HStackLayout(spacing: CompoundDesignTokens.space2X))
            layout {
                // The line gives way last: the chip is a few glyphs wide and never truncates.
                Text(content.line)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(content.isCritical ? AnyShapeStyle(.compound.textCriticalPrimary) : AnyShapeStyle(.primary))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .layoutPriority(1)

                if let chip = content.chip {
                    NativeCallAgentPillChip(chip: chip)
                        .fixedSize()
                }
            }
        }
        .padding(.leading, CompoundDesignTokens.space1_5X)
        .padding(.trailing, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space1_5X)
        .frame(minHeight: 44)
        .nativeCallSurface(in: surface, isInteractive: true)
    }

    /// Two lines don't sit in a capsule's round ends.
    private var surface: AnyShape {
        dynamicTypeSize.isAccessibilitySize
            ? AnyShape(RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous))
            : AnyShape(Capsule())
    }
}

/// The capsule over the dock as the call screen draws it: the agent's block, expanded by the current event.
struct NativeCallAgentCapsule: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context

    var body: some View {
        if let block = context.viewState.capsuleBlock {
            let event = context.viewState.capsule.current.map { NativeCallCapsuleEventCopy($0, viewState: context.viewState) }
            NativeCallAgentBlock(state: block,
                                 action: { context.send(viewAction: .showAgentCenterFromPill) },
                                 profile: context.viewState.memberProfiles[block.agentUserID],
                                 mediaProvider: context.mediaProvider,
                                 event: event,
                                 eventProfile: event?.agentUserID.flatMap { context.viewState.memberProfiles[$0] },
                                 onEventAction: { context.send(viewAction: .runCapsuleAction) })
        }
    }
}

/// The one glyph beside the line, in the quiet style inside the same glass: no second surface, no tint (decision 346).
private struct NativeCallAgentPillChip: View {
    let chip: NativeCallAgentPillContent.Chip

    var body: some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            Image(systemName: symbol)
            if case .translation(let codes, let more) = chip {
                // Codes read left to right in every layout direction.
                Text((codes + (more > 0 ? ["+\(more)"] : [])).joined(separator: " · "))
                    .monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .font(.compound.bodySMSemibold)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var symbol: String {
        switch chip {
        case .listening: "ear"
        case .translation: "translate"
        case .originalVoice: "speaker.wave.2"
        case .notes: "list.bullet.clipboard"
        }
    }
}

/// The live element: one 32pt footprint that holds the agent's avatar, with
/// its Aura while it speaks, or the state glyph for a failure or a pause. Every
/// variant is laid out identically, so the morph never moves the line next to
/// it — the `SpiralAgentDock` rule of one footprint and one accent at a time.
/// A second agent sits stacked behind it, its own Aura showing when it speaks.
private struct NativeCallAgentSlot: View {
    let slot: NativeCallAgentPillContent.Slot
    let agentUserID: String
    let name: String
    let otherAgentUserIDs: [String]
    let profile: NativeCallMemberProfile?
    let mediaProvider: MediaProviderProtocol?

    private static let size: CGFloat = 32
    private static let stackedSize: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(background)

            switch slot {
            case .avatar(let isDimmed):
                // The assistant as an entity is its avatar (Brief 0083, critique F5); sparkles mark agents as a function
                // only. Question 383, the operator's pick: a small Aura round it bends with its voice and fades with the
                // spring when it stops.
                avatar
                    .opacity(isDimmed ? 0.45 : 1)
                    .background {
                        NativeCallAuraRing(userID: agentUserID, diameter: Self.size, restingVisibility: 0)
                    }
            case .failure:
                glyph(\.error, tint: .compound.iconCriticalPrimary)
            case .paused:
                glyph(\.pause, tint: .compound.iconInfoPrimary)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .overlay(alignment: .bottomTrailing) {
            if let second = otherAgentUserIDs.first {
                stacked(second)
                    .offset(x: 5, y: 3)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: slot)
        .accessibilityHidden(true)
    }

    private var avatar: some View {
        NativeCallLetterAvatar(userID: agentUserID.isEmpty ? nil : agentUserID,
                               profile: profile,
                               fallbackName: name,
                               size: Self.size,
                               mediaProvider: mediaProvider)
    }

    /// The second agent's face, or the count of the others when there are more than one.
    private func stacked(_ second: String) -> some View {
        Group {
            if otherAgentUserIDs.count > 1 {
                Text("+\(otherAgentUserIDs.count)")
                    .font(.compound.bodyXSSemibold)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.compound.textPrimary)
                    .frame(width: Self.stackedSize, height: Self.stackedSize)
                    .background(Color.compound.bgSubtleSecondary, in: Circle())
            } else {
                NativeCallLetterAvatar(userID: second, profile: nil, fallbackName: name, size: Self.stackedSize, mediaProvider: nil)
                    .background {
                        NativeCallAuraRing(userID: second, diameter: Self.stackedSize, restingVisibility: 0)
                    }
            }
        }
        .overlay { Circle().stroke(Color.compound.bgCanvasDefault, lineWidth: 1.5) }
    }

    private func glyph(_ icon: KeyPath<CompoundIcons, Image>, tint: Color) -> some View {
        CompoundIcon(icon, size: .xSmall, relativeTo: .compound.bodyMD)
            .foregroundStyle(tint)
    }

    /// Behind the avatar the quiet wash; a failure's or a pause's glyph sits on its own hue.
    private var background: Color {
        switch slot {
        case .avatar: .compound.bgSubtleSecondary
        case .failure: .compound.bgCriticalSubtle
        case .paused: .compound.bgInfoSubtle
        }
    }
}

// MARK: - Previews

struct NativeCallAgentBlock_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        // Few enough in each to stay whole at accessibility sizes.
        states([.init(name: "Alex Sample · assistant", event: .idle(role: nil, languages: []), isOwn: true),
                .init(name: "Mira Testova · assistant", event: .airing(.conversation)),
                .init(name: "Alex Sample · assistant", event: .idle(role: .conversation, languages: []), isOwn: true)])
            .previewDisplayName("Agent pill at rest")

        states([.init(name: "Alex Sample · assistant", event: .airing(.translation(languages: ["en", "de", "uk"])), isOwn: true),
                .init(name: "Alex Sample · assistant", event: .paused, isOwn: true),
                .init(name: "Alex Sample · assistant", event: .original, isOwn: true),
                .init(name: "Alex Sample · assistant", event: .idle(role: .summary, languages: []), isOwn: true, isTakingNotes: true)])
            .previewDisplayName("Agent pill functions")

        states([.init(name: "Alex Sample · assistant", event: .failure(.deliveryFailed), isOwn: true, failedDelivery: .summary),
                .init(name: "Alex Sample · assistant", event: .idle(role: nil, languages: []), isOwn: true, isLeaving: true),
                .init(name: "Alex Sample · assistant", event: .idle(role: nil, languages: []), isOwn: true,
                      otherAgentUserIDs: ["@assistant-mira:matrix.org"])])
            .previewDisplayName("Agent pill failure, leaving, two agents")
    }

    private static func states(_ states: [NativeCallAgentBlockState]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                NativeCallAgentBlock(state: state) { }
            }
        }
        .padding(20)
        .background { NativeCallBackdrop(tone: .wash) }
    }
}
