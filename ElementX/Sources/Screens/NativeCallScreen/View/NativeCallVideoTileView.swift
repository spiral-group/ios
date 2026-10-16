//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063 Slice 5): the leaf that turns a derived video
// descriptor into pixels. This is the ONLY view that talks to the renderer,
// which is what keeps LiveKit out of the rest of the screen.

import Compound
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
    var avatarSize: CGFloat = 72
    /// The full-bleed 1:1 tile skips the speaking ring — an outline around
    /// the whole stage reads as chrome, not as a speaking mark.
    var showsSpeakingRing = true
    /// The full-bleed 1:1 tile has no caption either: the header already
    /// names the person (`06 · Video call`).
    var showsCaption = true
    /// 0 for the full-bleed stage, 14 for grid cells and the corner tile.
    var cornerRadius: CGFloat = 14

    var body: some View {
        ZStack {
            Color.compound.bgSubtlePrimary

            if let source = tile.source, let videoView = renderer?.videoView(for: source) {
                videoView
            } else {
                placeholder
            }

            // G10 — the SFU paused this stream to save the channel: the
            // sound stays and the picture self-restores. Saying so is the
            // difference between degradation and a silent freeze.
            if tile.isStreamPaused {
                VStack(spacing: 6) {
                    CompoundIcon(\.videoCallOff, size: .small, relativeTo: .compound.bodySM)
                        .foregroundStyle(.compound.iconInfoPrimary)
                    Text(UntranslatedL10n.screenNativeCallVideoPaused)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textInfoPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.compound.bgCanvasDefault.opacity(0.55))
            }

            if showsSpeakingRing, tile.participant.isSpeaking {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.compound.iconAccentPrimary, lineWidth: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(alignment: .bottomLeading) {
            if showsCaption, let captionText {
                caption(captionText)
            }
        }
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
    /// still has a face (`07 · Video call · group`). The caption already
    /// carries the name, so the tile shows the person, not a glyph.
    private var placeholder: some View {
        NativeCallLetterAvatar(userID: tile.participant.userID,
                               profile: profile,
                               fallbackName: displayName,
                               size: avatarSize,
                               mediaProvider: mediaProvider)
    }

    private func caption(_ text: String) -> some View {
        HStack(spacing: 4) {
            if !tile.participant.isAudioEnabled, !tile.participant.isOnHold {
                CompoundIcon(\.micOff, size: .xSmall, relativeTo: .compound.bodySM)
                    .foregroundStyle(.compound.iconSecondary)
            }
            Text(text)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.compound.bgCanvasDefault.opacity(0.6), in: Capsule())
        .padding(8)
    }

    private var accessibilityLabel: String {
        var parts = [captionText ?? tile.participant.userID]
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
