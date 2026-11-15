//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083 phase 4, lane call-v2, decisions 339 and 340): the audio call as a portrait. The person
// fills the screen: their picture as the backdrop, a large avatar that rings while they speak, the assistant as a
// glass pill under their name, and one big glass dock with End across it.

import Compound
import SpiralTokens
import SwiftUI

struct NativeCallPortraitLayout: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let controls: [NativeCallControl]
    /// Your own picture's corner tile on the assistant's page with the camera on: it keeps to the space between the
    /// way back and the dock.
    var cornerTile: AnyView?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: CompoundDesignTokens.space4X) {
            HStack(spacing: CompoundDesignTokens.space2X) {
                NativeCallBackButton(context: context)
                Spacer()
                NativeCallTranslateButton(context: context)
            }
            .animation(.easeInOut(duration: 0.25), value: context.viewState.translation.isButtonVisible)
            .padding(.horizontal, CompoundDesignTokens.space3X)

            NativeCallHeldCallPill(context: context)

            // A large group or an accessibility size scrolls: nothing is cut.
            ViewThatFits(in: .vertical) {
                stage

                ScrollView {
                    stage
                }
            }
            // The full width between the header and the dock: the corner tile's corners are the screen's, never the
            // stage's narrow column round the avatar (question 383).
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { cornerTile }

            // The pill sits just above the dock, as in a video call (question 383), so the speaker centres in the space
            // left. The assistant's own page has none: its state is the line under its name.
            if !isAssistantPage {
                limitLine
                assistantPill
            }

            NativeCallGlassDock(controls: controls)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            NativeCallBackdrop(photoURL: context.viewState.backdropPhotoURL,
                               contentID: context.viewState.backdropContentID,
                               mediaProvider: context.mediaProvider,
                               tone: .wash)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var stage: some View {
        if context.viewState.scope == .group {
            groupStage
        } else {
            personStage
        }
    }

    private var personStage: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            NativeCallStageAvatar(context: context)

            VStack(spacing: CompoundDesignTokens.space2X) {
                if context.viewState.isPlacingCall {
                    Text(context.viewState.isVideoCall
                        ? UntranslatedL10n.screenNativeCallIncomingVideo
                        : UntranslatedL10n.screenNativeCallIncomingVoice)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textPrimary)
                }

                if isAssistantPage {
                    assistantTitle
                } else {
                    Text(context.viewState.roomName)
                        .font(.compound.headingXLBold)
                        .foregroundStyle(.compound.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }

                NativeCallMetaLine(context: context)

                if isAssistantPage {
                    assistantStateLine
                }
            }
            .padding(.horizontal, CompoundDesignTokens.space6X)
        }
    }

    /// A 1:1 call with one's own assistant is the assistant's page (question 383): the assistant at the centre, its
    /// voice drawn once on its ring, its state one line, no pill.
    private var isAssistantPage: Bool {
        context.viewState.isAssistantPage
    }

    /// The assistant's name on one line and its role under it, instead of "Name · assistant" in two heavy lines.
    private var assistantTitle: some View {
        let displayName = context.viewState.stagePeer.flatMap { context.viewState.memberProfiles[$0.userID]?.displayName }
        let title = NativeCallAssistantTitle(displayName: displayName ?? context.viewState.roomName)
        return VStack(spacing: CompoundDesignTokens.space0_5X) {
            Text(title.name)
                .font(.compound.headingLGBold)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.7)

            if let role = title.role {
                Text(role)
                    .font(.compound.bodyLG)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.compound.textPrimary)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var assistantStateLine: some View {
        if let line = context.viewState.limitLine {
            NativeCallLimitLine(text: line)
        } else if let event = context.viewState.agentBlock?.event {
            NativeCallAssistantStateLine(event: event)
        }
    }

    @ViewBuilder
    private var limitLine: some View {
        if let line = context.viewState.limitLine {
            NativeCallLimitLine(text: line)
                .padding(.horizontal, CompoundDesignTokens.space4X)
        }
    }

    private var groupStage: some View {
        VStack(spacing: CompoundDesignTokens.space8X) {
            VStack(spacing: CompoundDesignTokens.space2X) {
                Text(context.viewState.roomName)
                    .font(.compound.headingLGBold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                NativeCallMetaLine(context: context)
            }
            .padding(.horizontal, CompoundDesignTokens.space6X)

            NativeCallPeopleSpotlight(context: context)
        }
    }

    private var assistantPill: some View {
        NativeCallAgentCapsule(context: context)
            .padding(.horizontal, CompoundDesignTokens.space4X)
    }
}

/// The AI limit stopped the owner's assistant mid-call (D7, D10): one quiet line on its own capsule, the owner's only;
/// everyone else just stops hearing the assistant. It wraps rather than truncates at large sizes.
struct NativeCallLimitLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.compound.bodyMDSemibold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        } icon: {
            CompoundIcon(\.pause, size: .xSmall, relativeTo: .compound.bodyMD)
                .foregroundStyle(.secondary)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space2X)
        .nativeCallSurface(in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// What the pill would say on the assistant's page, only when its Aura can't show it (an error, translation, a
/// recording), as one quiet line; an error keeps its glyph, so it doesn't rest on colour alone (question 383).
struct NativeCallAssistantStateLine: View {
    let event: NativeCallAgentEvent

    var body: some View {
        if let line = NativeCallAgentStatusCopy.assistantPageLine(event) {
            HStack(spacing: CompoundDesignTokens.space1_5X) {
                if case .failure = event {
                    CompoundIcon(\.error, size: .xSmall, relativeTo: .compound.bodyMD)
                        .foregroundStyle(.compound.iconCriticalPrimary)
                        .accessibilityHidden(true)
                }

                Text(line)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .animation(.easeInOut(duration: 0.2), value: event)
        }
    }
}
