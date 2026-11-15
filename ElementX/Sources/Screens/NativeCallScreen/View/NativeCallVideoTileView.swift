//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063 Slice 5): the leaf that turns a derived video
// descriptor into pixels. This is the ONLY view that talks to the renderer,
// which is what keeps LiveKit out of the rest of the screen.

import Compound
import SpiralTokens
import SwiftUI

struct NativeCallVideoTileView: View {
    let tile: NativeCallVideoTile
    /// Resolves the descriptor. Optional so previews and snapshot tests
    /// render the placeholder instead of allocating a media engine.
    let renderer: NativeCallVideoRendering?
    /// The person's profile name for the caption; the raw MXID is a
    /// debugging artefact, not a caption.
    var displayName: String?
    /// Drawn when the camera is off (`07`): a face, not a crossed-out
    /// camera glyph.
    var profile: NativeCallMemberProfile?
    var mediaProvider: MediaProviderProtocol?
    /// Avatar diameter for the camera-off state — the full-bleed stage
    /// gets a large one, a grid tile a small one.
    var avatarSize: CGFloat = SpiralAvatarSize.medium
    /// The full-bleed 1:1 tile skips the speaking ring — an outline around
    /// the whole stage reads as chrome, not as a speaking mark.
    var showsSpeakingRing = true
    /// The full-bleed 1:1 tile has no caption either: the header already
    /// names the person (`06 · Video call`).
    var showsCaption = true
    /// A filmstrip thumbnail's caption (question 383): the smaller label, close to the corner, so it leaves the face.
    var isCaptionCompact = false
    /// 0 for the full-bleed stage, a token for grid cells and the corner tile.
    let cornerRadius: CGFloat
    /// The 1:1 stage: a camera that is off is the voice call's portrait (decision 342). Nil keeps a tile's own field.
    var portrait: NativeCallScreenViewModel.Context?

    var body: some View {
        ZStack {
            Color.compound.bgSubtlePrimary

            if let source = tile.source, let videoView = renderer?.videoView(for: source) {
                videoView
            } else {
                cameraOff
            }

            // G10 — the SFU paused this stream to save the channel: the
            // sound stays and the picture self-restores. Saying so is the
            // difference between degradation and a silent freeze.
            if tile.isStreamPaused {
                VStack(spacing: 6) {
                    CompoundIcon(\.videoCallOff, size: .small, relativeTo: .compound.bodySM)
                    Text(UntranslatedL10n.screenNativeCallVideoPaused)
                        .font(.compound.bodySM)
                }
                .foregroundStyle(.compound.textOnSolidPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.55))
            }

            if showsCaption, let captionText {
                caption(captionText)
            }

            if showsSpeakingRing, tile.participant.isSpeaking {
                speakingRing
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// `You` on our own preview (the design's PiP label); the profile name
    /// on everyone else. A raw MXID is a debugging artefact, never a
    /// caption — an unresolved profile shows none.
    private var captionText: String? {
        let name = tile.participant.isLocal ? L10n.commonYou : displayName
        // Brief 0068: a held peer's tile says so — their camera is dark and
        // their microphone muted underneath, neither of which is the fact.
        guard let name else { return name }
        if tile.participant.isOnHold {
            return "\(name) · \(UntranslatedL10n.screenNativeCallStatusOnHold)"
        }
        if tile.participant.isReconnecting {
            return "\(name) · \(UntranslatedL10n.screenNativeCallParticipantReconnecting)"
        }
        return name
    }

    /// A camera that is off is a STATE, not an absence — and the state
    /// still has a face (`07 · Video call · group`): the person's field
    /// with their avatar, like the audio call's portrait.
    @ViewBuilder
    private var cameraOff: some View {
        if let portrait {
            NativeCallBackdrop(photoURL: portrait.viewState.backdropPhotoURL, contentID: portrait.viewState.backdropContentID,
                               mediaProvider: mediaProvider, tone: .wash)
                .overlay {
                    NativeCallStageAvatar(context: portrait)
                        .overlay(alignment: .bottom) { portraitFacts }
                }
        } else {
            NativeCallBackdrop(photoURL: profile?.avatarURL, thumbnailDiameter: avatarSize, mediaProvider: mediaProvider, tone: .deep)
                .overlay {
                    NativeCallLetterAvatar(userID: tile.participant.userID,
                                           profile: profile,
                                           fallbackName: displayName,
                                           size: avatarSize,
                                           mediaProvider: mediaProvider)
                        .agentBadge(userID: tile.participant.userID, avatarURL: profile?.avatarURL, avatarSize: avatarSize) // Decision 357
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
        }
    }

    /// What the corner tile's caption says of the person, under the stage's avatar. Hung below it, so a fact coming
    /// or going doesn't move the face.
    private var portraitFacts: some View {
        let facts = tile.stageFacts

        return HStack(spacing: CompoundDesignTokens.space1X) {
            if facts.isMuted {
                CompoundIcon(\.micOff, size: .xSmall, relativeTo: .compound.bodySM)
            }

            if let state = facts.state {
                Text(state)
            }
        }
        .font(.compound.bodySMSemibold)
        .foregroundStyle(.compound.textPrimary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .fixedSize()
        .alignmentGuide(.bottom) { $0[.top] - CompoundDesignTokens.space8X }
    }

    /// The person's name on a small glass label at the tile's foot, the mute mark beside it, the same label as the
    /// audio strip's faces (question 383). One line, cut with "…"; over a picture the surface is the dark material, so
    /// it reads on bright and dim pictures alike.
    private func caption(_ text: String) -> some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            if !tile.participant.isAudioEnabled, !tile.participant.isOnHold {
                CompoundIcon(\.micOff, size: .xSmall, relativeTo: .compound.bodySM)
            }

            Text(text)
                .font(isCaptionCompact ? .compound.bodyXSSemibold : .compound.bodySMSemibold)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.primary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, CompoundDesignTokens.space2X)
        .padding(.vertical, CompoundDesignTokens.space1X)
        .nativeCallSurface(in: Capsule())
        .padding(isCaptionCompact ? CompoundDesignTokens.space1X : CompoundDesignTokens.space2X)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    /// White with a dark edge inside it: one of the two holds 3:1 on any picture.
    private var speakingRing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.compound.iconOnSolidPrimary, lineWidth: 3)

            RoundedRectangle(cornerRadius: cornerRadius - 3, style: .continuous)
                .strokeBorder(.black.opacity(0.45), lineWidth: 1)
                .padding(3)
        }
    }

    private var accessibilityLabel: String {
        var parts = [captionText ?? tile.participant.userID]
        if portrait != nil, let state = tile.stageFacts.state, !parts[0].contains(state) {
            parts.append(state)
        }
        if tile.source == nil {
            parts.append(UntranslatedL10n.screenNativeCallCameraOff)
        }
        if tile.isStreamPaused {
            parts.append(UntranslatedL10n.screenNativeCallVideoPaused)
        }
        if !tile.participant.isAudioEnabled {
            parts.append(UntranslatedL10n.a11yNativeCallParticipantMuted)
        }
        return parts.joined(separator: ", ")
    }
}

extension NativeCallVideoTile {
    /// What the stage says of the person under their avatar. A peer whose media dropped is reconnecting, whatever their
    /// link reports, and says nothing about the microphone: it reads muted only because their media is gone.
    var stageFacts: (isMuted: Bool, state: String?) {
        if participant.isOnHold {
            return (false, UntranslatedL10n.screenNativeCallStatusOnHold)
        }
        if participant.mediaState != .connected {
            return (false, UntranslatedL10n.screenNativeCallParticipantReconnecting)
        }
        return (!participant.isAudioEnabled,
                participant.isReconnecting ? UntranslatedL10n.screenNativeCallParticipantReconnecting : nil)
    }
}
