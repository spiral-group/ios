//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftUI

// AGENT-PLATFORM (Brief 0063)
//
// The rendering follows the design set (`03 · Call 1:1`, `05 · Group call`,
// `02 · Outgoing`, `06 · Video call`) with native iOS idioms wherever the
// design's shape IS the system's shape: system grouped backgrounds and label
// colours, SF Symbols, circular call controls, native sheets. Brand colour
// (accent, critical) comes from Compound; everything neutral is semantic
// system colour so dark mode (`04`) is the same screen, not a second theme.

struct NativeCallScreen: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    /// Resolves video descriptors into renderers. Absent in previews and
    /// snapshot tests, which then draw the camera-off placeholder.
    let videoRenderer: NativeCallVideoRendering?
    /// The wave's live amplitude. Absent in previews and snapshot tests,
    /// which then draw the static bars.
    var voiceLevels: NativeCallVoiceLevelReading?
    /// Owns the system PiP session. Absent in previews and snapshot tests.
    var pictureInPicture: NativeCallPictureInPictureController?

    /// The app's own scheme, which the audio layout follows unchanged.
    @Environment(\.colorScheme) private var colorScheme
    /// G9 — the overlay minimized: the whole screen renders as the call
    /// bar, and everything underneath stays tappable.
    @Environment(\.isOverlayMinimized) private var isOverlayMinimized

    var body: some View {
        Group {
            if isOverlayMinimized {
                NativeCallBar(context: context)
            } else {
                fullScreenBody
            }
        }
        // The minimized branch must read the same live source as the full
        // screen. Applying this only to `fullScreenBody` froze the bar wave.
        .environment(\.nativeCallVoiceLevels, voiceLevels)
        // The PiP anchor: PiP starting sets the overlay to `.minimized`,
        // which swaps in a DIFFERENT `toPresentable()` call site — SwiftUI
        // destroys this tree and builds a fresh one. The anchor view AVKit
        // holds (weakly) is therefore OWNED by the controller and merely
        // mounted here, so it survives every rebuild and is still in the
        // window when the app backgrounds — the moment AVKit decides
        // whether to auto-start (minimal Block E, 2026-09-14: a
        // SwiftUI-owned anchor was `window nil` at that moment and the
        // window never appeared).
        .background {
            if context.viewState.isVideoCall, let pictureInPicture {
                NativeCallPictureInPictureAnchor(controller: pictureInPicture)
            }
        }
        .onAppear { applyPictureInPictureContent() }
        .onChange(of: pictureInPictureContent) { _, _ in applyPictureInPictureContent() }
    }

    /// What the floating window should show: the speaking remote tile with
    /// a live picture, else the first remote tile with one, else the remote
    /// peer's identity. Covers BOTH scopes — attempt-1 fed only the 1:1
    /// stage, which left a group call's window pitch black (C3). Nil for
    /// audio calls: PiP is a video affordance (operator decision); audio
    /// survives backgrounding through CallKit and the bar already.
    private var pictureInPictureContent: NativeCallPictureInPictureController.Content? {
        guard context.viewState.isVideoCall else { return nil }

        let remoteVideoTiles = context.viewState.videoTiles.filter { !$0.participant.isLocal && $0.source != nil }
        // The person talking beats the person first in userID order
        // (critic-2 N4): a group window pinned to an arbitrary silent
        // participant reads as broken.
        if let tile = remoteVideoTiles.first(where: \.participant.isSpeaking) ?? remoteVideoTiles.first {
            return .init(source: tile.source, identityKey: tile.participant.userID)
        }

        let remotePeer = context.viewState.humanParticipants.first { !$0.isLocal }
        return .init(source: nil, identityKey: remotePeer?.userID ?? context.viewState.roomName)
    }

    private func applyPictureInPictureContent() {
        guard let pictureInPicture else { return }
        guard let content = pictureInPictureContent else {
            // The call stopped being a video call under an open window —
            // take it down instead of floating a stale tile (critic-2 N2).
            pictureInPicture.contentBecameUnavailable()
            return
        }

        let profile = content.identityKey.hasPrefix("@") ? context.viewState.memberProfiles[content.identityKey] : nil
        let roomAvatar = context.viewState.roomAvatar
        let roomName = context.viewState.roomName
        let mediaProvider = context.mediaProvider
        pictureInPicture.setContent(content) {
            // The same identity sources the call screen renders (wave-1
            // rule): the peer's real profile picture when there is one, the
            // room's avatar (a DM's single hero) when the roster has no
            // remote yet — never a bare letter tile when the real picture
            // is known (attempt-1 C11).
            AnyView(ZStack {
                Color.black
                if let profile {
                    NativeCallLetterAvatar(userID: content.identityKey,
                                           profile: profile,
                                           fallbackName: roomName,
                                           size: 96,
                                           mediaProvider: mediaProvider)
                } else {
                    RoomAvatarImage(avatar: roomAvatar,
                                    avatarSize: .custom(96),
                                    mediaProvider: mediaProvider)
                }
            })
        }
    }

    /// `02`/`03`/`04`'s quiet gradient: a breath of the brand at the top
    /// of the 1:1 audio canvas, fading into the system background. The
    /// group roster keeps the flat canvas — its information lives in
    /// white cards that need the plain contrast.
    @ViewBuilder
    private var canvasBackground: some View {
        if !context.viewState.isVideoCall, !isGroupAudioLayout {
            LinearGradient(colors: [colorScheme == .dark ? Color(red: 0.063, green: 0.063, blue: 0.102) : Color(red: 0.906, green: 0.929, blue: 0.984),
                                    Color(.systemGroupedBackground)],
                           startPoint: .top,
                           endPoint: .center)
                .background(Color(.systemGroupedBackground))
        } else {
            Color(.systemGroupedBackground)
        }
    }

    /// `05 · Group call` uses the nav-row header and the roster; everything
    /// else centres on one person.
    private var isGroupAudioLayout: Bool {
        !context.viewState.isVideoCall && context.viewState.scope == .group
    }

    private var audioBody: some View {
        VStack(spacing: 0) {
            if isGroupAudioLayout {
                groupHeader

                groupRoster
            } else {
                directHeader

                // The identity lives in the header (`02`/`03` share one
                // composition) — below it is calm space.
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            agentBlock

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(canvasBackground.ignoresSafeArea())
    }

    /// `06`: the picture IS the screen — edge to edge, under the status
    /// bar and the home indicator. The header floats on a top scrim, the
    /// capsule and the dock on a bottom one, and a tap on the picture
    /// hides the dock for a clean view (the capsule stays: the agent is
    /// never hidden).
    private var videoBody: some View {
        ZStack {
            videoStage

            VStack(spacing: 0) {
                videoHeader
                    .frame(maxWidth: .infinity)
                    .background {
                        LinearGradient(colors: [.black.opacity(0.45), .clear],
                                       startPoint: .top,
                                       endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                    }

                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    agentCapsule

                    if !context.isVideoChromeHidden {
                        controls
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, context.isVideoChromeHidden ? 10 : 0)
                .frame(maxWidth: .infinity)
                .background {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .top,
                                   endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: context.isVideoChromeHidden)
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: context.viewState.isVideoCall) {
            // Falling back to the audio stage always brings the dock back.
            context.isVideoChromeHidden = false
        }
    }

    private func heldCallPill(_ heldCall: CallKitHeldCall) -> some View {
        Button {
            context.send(viewAction: .swapCalls)
        } label: {
            HStack(spacing: 6) {
                CompoundIcon(\.pause, size: .xSmall, relativeTo: .compound.bodySM)
                Text(UntranslatedL10n.screenNativeCallHeldCallPill(heldCall.displayName))
                    .font(.compound.bodySM)
                    .lineLimit(1)
                Text(UntranslatedL10n.screenNativeCallSwap)
                    .font(.compound.bodySMSemibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.compound.bgSubtleSecondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallSwapToHeldCall(heldCall.displayName))
    }

    private var fullScreenBody: some View {
        Group {
            if context.viewState.isVideoCall {
                videoBody
            } else {
                audioBody
            }
        }
        // G13 — the way back to the chat that is not a hang-up. The call
        // keeps running behind the bar the user lands on. The group header
        // carries its own inline chevron, matching `05`.
        .overlay(alignment: .topLeading) {
            if !isGroupAudioLayout {
                backButton
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            }
        }
        // Brief 0068 Slice 2 — the call parked behind this one, one tap to
        // swap. Top-trailing so it never covers the header's name.
        .overlay(alignment: .topTrailing) {
            if let heldCall = context.viewState.heldCall {
                heldCallPill(heldCall)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
        }
        .alert(item: $context.alertInfo)
        .sheet(isPresented: $context.isAgentCenterPresented) {
            NativeCallAgentCenterSheet(context: context)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $context.isAudioRoutePickerPresented) {
            NativeCallAudioRoutePicker(context: context)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        // Operator decision 2026-08-20: light-first audio call per ADR-0005;
        // dark chrome is contextual to the video stage only. Video is the
        // content and must not be tinted, so its scrims stay dark; an audio
        // call is an app screen like any other and follows the app's theme.
        .environment(\.colorScheme, context.viewState.isVideoCall ? .dark : colorScheme)
    }

    private var backButton: some View {
        Button { context.send(viewAction: .minimize) } label: {
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(context.viewState.isVideoCall ? AnyShapeStyle(.white) : AnyShapeStyle(.compound.textActionAccent))
                .frame(width: 44, height: 44)
                .background(context.viewState.isVideoCall ? AnyShapeStyle(.white.opacity(0.16)) : AnyShapeStyle(.clear), in: Circle())
        }
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallMinimize)
    }

    // MARK: - Headers

    /// `02 · Outgoing` / `03 · Call 1:1`: ONE composition for the whole
    /// life of the call — avatar, name, then the meta line. Ringing and
    /// connected differ only in what the meta line says ("Calling…"
    /// becomes the lock · bars · timer · REC), so answering morphs the
    /// screen instead of rebuilding it (the avatar used to teleport from
    /// the upper block to the centre of an empty stage).
    private var directHeader: some View {
        VStack(spacing: 8) {
            if isPlacingCall {
                Text(context.viewState.isVideoCall
                    ? UntranslatedL10n.screenNativeCallIncomingVideo
                    : UntranslatedL10n.screenNativeCallIncomingVoice)
                    .font(.subheadline)
                    .foregroundStyle(Color(.tertiaryLabel))
            }

            directAvatar

            VStack(spacing: 6) {
                Text(context.viewState.roomName)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 60)

                metaLine

                statusDetailLine
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var isPlacingCall: Bool {
        switch context.viewState.callState {
        case .connecting, .ringing: true
        default: false
        }
    }

    /// The 104pt avatar with the design's glow: the peer's live voice
    /// level breathes a soft accent halo — the same "sound airs now"
    /// mark the agent slot draws, at person scale.
    @ViewBuilder
    private var directAvatar: some View {
        if context.viewState.scope == .group {
            RoomAvatarImage(avatar: context.viewState.roomAvatar,
                            avatarSize: .custom(104),
                            mediaProvider: context.mediaProvider)
                .accessibilityHidden(true)
        } else if let peer = context.viewState.stagePeer {
            NativeCallLetterAvatar(userID: peer.userID,
                                   profile: context.viewState.memberProfiles[peer.userID],
                                   fallbackName: context.viewState.roomName,
                                   size: 104,
                                   mediaProvider: context.mediaProvider)
                .overlay {
                    if peer.isSpeaking {
                        Circle()
                            .strokeBorder(Color.compound.iconAccentPrimary, lineWidth: 3)
                            .padding(-5)
                    }
                }
                .background {
                    if peer.isSpeaking {
                        if let reader = voiceLevels {
                            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { _ in
                                Circle()
                                    .fill(Color.compound.iconAccentPrimary
                                        .opacity(0.12 + 0.25 * reader.voiceLevel(forUserID: peer.userID)))
                                    .padding(-10)
                                    .blur(radius: 14)
                            }
                        } else {
                            Circle()
                                .fill(Color.compound.iconAccentPrimary.opacity(0.22))
                                .padding(-10)
                                .blur(radius: 14)
                        }
                    }
                }
        } else {
            // No live peer yet (dialing) or none any more (the lingering
            // "Call ended" beat): identity comes from the ROOM — a DM's
            // single hero carries the recipient's real picture — never from
            // the call roster, which only knows who is connected right now.
            // This was the letter placeholder flashing before and after the
            // remote's presence.
            RoomAvatarImage(avatar: context.viewState.roomAvatar,
                            avatarSize: .custom(104),
                            mediaProvider: context.mediaProvider)
                .accessibilityHidden(true)
        }
    }

    /// `05 · Group call`: inline back chevron, room title with the counts
    /// under it, the REC pill on the right.
    private var groupHeader: some View {
        HStack(spacing: 10) {
            Button { context.send(viewAction: .minimize) } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.compound.textActionAccent)
                    .frame(width: 34, height: 44)
            }
            .accessibilityLabel(UntranslatedL10n.a11yNativeCallMinimize)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.viewState.roomName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if context.viewState.isRoomEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }

                    Text(context.viewState.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let connectedAt = context.viewState.callConnectedAt, context.viewState.callState == .connected {
                        Text("·").font(.footnote).foregroundStyle(Color(.tertiaryLabel))
                        Text(connectedAt, style: .timer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Spacer()

            if context.viewState.isRecording {
                recordingPill
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// `06 · Video call`: name over the top scrim with the meta line under.
    private var videoHeader: some View {
        VStack(spacing: 4) {
            Text(context.viewState.roomName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            metaLine

            statusDetailLine
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    /// The one quiet line about the call itself: lock, the live timer once
    /// connected (the call state before that) and REC. Recording is a
    /// property of the CALL, so this is its only home on the screen (G2).
    private var metaLine: some View {
        HStack(spacing: 6) {
            if context.viewState.isRoomEncrypted {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }

            if context.viewState.callState == .connected, context.viewState.connectionQuality != .unknown {
                NativeCallSignalBars(quality: context.viewState.connectionQuality)
            }

            if let connectedAt = context.viewState.callConnectedAt, context.viewState.callState == .connected {
                Text(connectedAt, style: .timer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(context.viewState.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if context.viewState.isRecording {
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(Color(.tertiaryLabel))

                recordingBadge
            }
        }
    }

    /// Phase 4 — what the call is doing, or how long it ran once it ended
    /// (`18 · Call states`).
    @ViewBuilder
    private var statusDetailLine: some View {
        if let statusDetail = context.viewState.statusDetail {
            Text(statusDetail)
                .font(.footnote)
                .foregroundStyle(context.viewState.statusDetailIsDegraded
                    ? AnyShapeStyle(.compound.textInfoPrimary)
                    : AnyShapeStyle(.secondary))
        }
    }

    /// A dot and the word, as `03 · Call 1:1` draws it. Presentational: the
    /// label below is what VoiceOver reads.
    private var recordingBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.compound.iconCriticalPrimary)
                .frame(width: 6, height: 6)

            Text(UntranslatedL10n.screenNativeCallRecordingBadge)
                .font(.caption.weight(.bold))
                .foregroundStyle(.compound.textCriticalPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallRecording)
    }

    /// `05` puts REC in a soft critical pill on the nav row.
    private var recordingPill: some View {
        recordingBadge
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.compound.bgCriticalSubtle, in: Capsule())
    }

    // MARK: - Stages

    /// `03` / `02`: the other person, large and centred — the layout every
    /// phone call has trained users on.
    /// `05`: white person cards. G1 — agents are never listed among humans;
    /// they live in the block and in the Agent Center instead.
    private var groupRoster: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(context.viewState.humanParticipants) { participant in
                    NativeCallParticipantRow(participant: participant,
                                             profile: context.viewState.memberProfiles[participant.userID],
                                             coveredLanguage: coveredLanguageName(for: participant),
                                             mediaProvider: context.mediaProvider)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .frame(maxHeight: .infinity)
    }

    /// A video call gives the picture the screen: one party fills it and
    /// the other sits in a draggable corner tile. G14: a TAP on the small
    /// tile swaps who is large, a DRAG moves it to any corner, and a
    /// double-tap on our own picture flips the camera.
    private var videoStage: some View {
        ZStack {
            let remoteTiles = context.viewState.videoTiles.filter { !$0.participant.isLocal }
            let localTile = context.viewState.videoTiles.first(where: \.participant.isLocal)

            if context.viewState.scope.isOneToOne {
                let stage = NativeCallVideoStage.tiles(remote: remoteTiles.first,
                                                       local: localTile,
                                                       isSelfVideoLarge: context.isSelfVideoLarge)

                if let largeTile = stage.large {
                    // The header already names the 1:1 peer — the full-bleed
                    // stage carries neither a ring, a caption nor corners
                    // (`06`): the picture IS the screen.
                    NativeCallVideoTileView(tile: largeTile,
                                            renderer: videoRenderer,
                                            displayName: displayName(for: largeTile.participant),
                                            profile: context.viewState.memberProfiles[largeTile.participant.userID],
                                            mediaProvider: context.mediaProvider,
                                            avatarSize: 104,
                                            showsSpeakingRing: false,
                                            showsCaption: false,
                                            cornerRadius: 0)
                        .ignoresSafeArea()
                        .onTapGesture(count: 2) {
                            if largeTile.participant.isLocal {
                                context.send(viewAction: .switchCamera)
                            }
                        }
                        .onTapGesture {
                            context.isVideoChromeHidden.toggle()
                        }
                } else {
                    Color(.systemFill).ignoresSafeArea()
                }

                if let smallTile = stage.small {
                    NativeCallDraggableTile(tile: smallTile,
                                            renderer: videoRenderer,
                                            displayName: displayName(for: smallTile.participant),
                                            profile: context.viewState.memberProfiles[smallTile.participant.userID],
                                            mediaProvider: context.mediaProvider,
                                            onTap: remoteTiles.isEmpty
                                                ? (smallTile.participant.isLocal ? { context.send(viewAction: .switchCamera) } : nil)
                                                : { context.isSelfVideoLarge.toggle() },
                                            onDoubleTap: smallTile.participant.isLocal
                                                ? { context.send(viewAction: .switchCamera) }
                                                : nil)
                }
            } else {
                // Small groups (`07`): a grid that stays legible on a
                // phone, EVERYONE in it — the design has no floating self
                // tile in a group. ADR-0076 caps the native group at
                // eight. Agents are never tiles; they ride the capsule.
                //
                // Sized by NativeCallGridLayout from BOTH axes (audit
                // A7-8): the old width-derived 3:4 tiles overflowed an
                // iPad by a full row, and the ScrollView answer was
                // reverted because scrolling a call hides participants.
                let gridTiles = remoteTiles + (localTile.map { [$0] } ?? [])
                NativeCallGrid(spacing: 8, topInset: 96, bottomInset: 168) {
                    ForEach(gridTiles) { tile in
                        NativeCallVideoTileView(tile: tile,
                                                renderer: videoRenderer,
                                                displayName: displayName(for: tile.participant),
                                                profile: context.viewState.memberProfiles[tile.participant.userID],
                                                mediaProvider: context.mediaProvider,
                                                avatarSize: 56)
                            .onTapGesture(count: 2) {
                                if tile.participant.isLocal {
                                    context.send(viewAction: .switchCamera)
                                }
                            }
                            .onTapGesture {
                                context.isVideoChromeHidden.toggle()
                            }
                    }
                }
            }
        }
    }

    private func displayName(for participant: NativeCallParticipant) -> String? {
        context.viewState.memberProfiles[participant.userID]?.displayName
    }

    /// The language a covered speaker is heard in — the Live agent's
    /// document names it per speaker (`05`'s `Covered in English`).
    private func coveredLanguageName(for participant: NativeCallParticipant) -> String? {
        guard let language = context.viewState.agents.coveredSpeakers[participant.userID] else { return nil }
        return NativeCallAgentStatusCopy.languageName(language)
    }

    // MARK: - Agent block

    /// G1: the full-width band above the controls. It exists only while an
    /// agent is in the call, and it is one tap from the same Agent Center
    /// the control row opens.
    @ViewBuilder
    private var agentBlock: some View {
        if let block = context.viewState.agentBlock {
            NativeCallAgentBlock(state: block,
                                 action: { context.send(viewAction: .showAgentCenter) })
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }

    /// Phase 3 (G5): the same block state dressed as a floating capsule
    /// over the video stage — one fact, one place, two dressings.
    @ViewBuilder
    private var agentCapsule: some View {
        if let block = context.viewState.agentBlock {
            NativeCallAgentBlock(state: block,
                                 action: { context.send(viewAction: .showAgentCenter) },
                                 style: .capsule)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Dock

    /// The circular call controls (`03`: mic, speaker, agent, end — the
    /// audio call has no camera in the dock; `06` adds it for video).
    /// Personal listening lives in the Agent Center's WHAT YOU HEAR section
    /// (Phase 2, operator decision — the dock shortcut is dropped).
    /// ONE dock for the one call (`02`–`07`): `Agent · Mute · Video ·
    /// Sound/Flip · End`, identical in both states. The fourth slot is
    /// contextual — Sound in audio (long-press: the routes sheet), the
    /// camera Flip once video is live (the speaker is automatic then).
    /// Equal flexible slots keep five circles on any phone.
    private var controls: some View {
        HStack(spacing: 0) {
            agentButton
            dockSlot(microphoneButton)
            dockSlot(cameraButton)
            if context.viewState.isVideoCall {
                dockSlot(flipButton)
            } else {
                dockSlot(speakerButton)
            }
            dockSlot(endButton)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func dockSlot(_ button: some View) -> some View {
        button.frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var agentButton: some View {
        if context.viewState.agents.panel.isAvailable {
            dockSlot(NativeCallControlButton(systemName: "sparkles",
                                             title: UntranslatedL10n.screenNativeCallControlAgent,
                                             style: .accent,
                                             titleColor: dockTitleColor,
                                             accessibilityLabel: UntranslatedL10n.screenNativeCallAgentCenterOpen) {
                    context.send(viewAction: .showAgentCenter)
                })
        }
    }

    private var microphoneButton: some View {
        NativeCallControlButton(systemName: context.viewState.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                                title: UntranslatedL10n.screenNativeCallControlMute,
                                style: dockStyle(isEngaged: !context.viewState.isMicrophoneEnabled),
                                titleColor: dockTitleColor,
                                accessibilityLabel: context.viewState.isMicrophoneEnabled
                                    ? UntranslatedL10n.a11yNativeCallMuteMicrophone
                                    : UntranslatedL10n.a11yNativeCallUnmuteMicrophone) {
            context.send(viewAction: .toggleMicrophone)
        }
    }

    private var cameraButton: some View {
        // The slashed glyph alone carries the off state — inverting the
        // circle made the DEFAULT state the loudest thing in the dock.
        NativeCallControlButton(systemName: context.viewState.isCameraEnabled ? "video.fill" : "video.slash.fill",
                                title: UntranslatedL10n.screenNativeCallControlVideo,
                                style: dockStyle(isEngaged: false),
                                titleColor: dockTitleColor,
                                accessibilityLabel: context.viewState.isCameraEnabled
                                    ? UntranslatedL10n.a11yNativeCallCameraOff
                                    : UntranslatedL10n.a11yNativeCallCameraOn) {
            context.send(viewAction: .toggleCamera)
        }
    }

    private var speakerButton: some View {
        NativeCallControlButton(systemName: context.viewState.isSpeakerEnabled ? "speaker.wave.2.fill" : "speaker.wave.2",
                                title: UntranslatedL10n.screenNativeCallControlSound,
                                style: dockStyle(isEngaged: context.viewState.isSpeakerEnabled),
                                titleColor: dockTitleColor,
                                accessibilityLabel: context.viewState.isSpeakerEnabled
                                    ? UntranslatedL10n.a11yNativeCallDisableSpeaker
                                    : UntranslatedL10n.a11yNativeCallEnableSpeaker,
                                accessibilityHint: UntranslatedL10n.a11yNativeCallAudioRoutes) {
            context.send(viewAction: .toggleSpeaker)
        }
        // G8 — the long-press always reaches the route picker, even
        // when only the phone's own outputs exist right now.
        .simultaneousGesture(LongPressGesture().onEnded { _ in
            context.send(viewAction: .showAudioRoutes)
        })
    }

    /// `06`/`07`'s fourth slot: flip the capture device. The double-tap
    /// on the self tile stays as the shortcut gesture.
    private var flipButton: some View {
        NativeCallControlButton(systemName: "arrow.triangle.2.circlepath.camera",
                                title: UntranslatedL10n.screenNativeCallControlFlip,
                                style: dockStyle(isEngaged: false),
                                titleColor: dockTitleColor,
                                accessibilityLabel: UntranslatedL10n.a11yNativeCallSwitchCamera) {
            context.send(viewAction: .switchCamera)
        }
    }

    private var endButton: some View {
        NativeCallControlButton(systemName: "phone.down.fill",
                                title: UntranslatedL10n.screenNativeCallControlEnd,
                                style: .critical,
                                titleColor: dockTitleColor,
                                accessibilityLabel: UntranslatedL10n.a11yNativeCallEnd) {
            context.send(viewAction: .hangUp)
        }
    }

    /// The dock captions read quietly on both canvases.
    private var dockTitleColor: Color {
        context.viewState.isVideoCall ? .white.opacity(0.7) : Color(.secondaryLabel)
    }

    private func dockStyle(isEngaged: Bool) -> NativeCallControlButton.Style {
        if context.viewState.isVideoCall {
            return isEngaged ? .videoEngaged : .video
        }
        return isEngaged ? .audioEngaged : .audio
    }
}

// MARK: - Previews

struct NativeCallScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    /// G1/G2/G4 in context: an agent airing a translation, a live recording
    /// and a mixed roster, so the block, the REC badge and `4 people · 2
    /// agents` are all snapshotted on the real screen rather than in
    /// isolation — and with them the light-first audio theme.
    static let agentViewModel = makeAgentViewModel()
    /// The same screen with no agent attached: the block must be ABSENT and
    /// the status line must fall back to people alone.
    static let noAgentViewModel = makeNoAgentViewModel()
    /// Phase 3 (G5): the same airing agent over the video stage — the
    /// block dresses as a floating dark capsule instead of the band.
    static let videoAgentViewModel = makeVideoAgentViewModel()

    static var previews: some View {
        NativeCallScreen(context: viewModel.context, videoRenderer: nil)
            .previewDisplayName("Connecting")

        NativeCallScreen(context: agentViewModel.context, videoRenderer: nil)
            .previewDisplayName("Agent airing · recording")

        NativeCallScreen(context: noAgentViewModel.context, videoRenderer: nil)
            .previewDisplayName("No agent")

        NativeCallScreen(context: videoAgentViewModel.context, videoRenderer: nil)
            .previewDisplayName("Video call · agent capsule")

        NativeCallScreen(context: makeGroupVideoViewModel().context, videoRenderer: nil)
            .previewDisplayName("Video call · group grid")

        NativeCallScreen(context: makeChromeHiddenViewModel().context, videoRenderer: nil)
            .previewDisplayName("Video call · chrome hidden")

        NativeCallScreen(context: makeRingingViewModel().context, videoRenderer: nil)
            .previewDisplayName("Outgoing ringing")

        // `04 · Call 1:1 · dark` comes for free from the semantic colours —
        // this snapshot is the proof.
        NativeCallScreen(context: noAgentViewModel.context, videoRenderer: nil)
            .environment(\.colorScheme, .dark)
            .previewDisplayName("Dark 1-1")

        NativeCallScreen(context: makeAssistantCallViewModel().context, videoRenderer: nil)
            .previewDisplayName("Assistant call")
    }

    /// A call WITH one's own assistant: the agent is the peer on the stage,
    /// named in the header, with the 1:1 timer — not a "waiting for others"
    /// room with an agent capsule (operator report 2026-09-11).
    static func makeAssistantCallViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel(scope: .assistant)
        viewModel.state.callState = .connected
        viewModel.state.roomName = "Alice's assistant"
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true),
                                        participant("@assistant-alice:matrix.org", role: .agent, isSpeaking: true)]
        viewModel.state.memberProfiles = ["@assistant-alice:matrix.org": .init(displayName: "Alice's assistant")]
        viewModel.state.agentClaims.speaking = ["@assistant-alice:matrix.org"]
        return viewModel
    }

    /// `05`/`07`: a group is the ROOM, not whoever happens to be first in the
    /// roster. Previews that leave the room identity at its empty default
    /// cannot tell a correct group header from one that fell back to a
    /// participant — which is exactly how the header shipped showing a peer's
    /// face under a group's name. Naming the room here is what makes the
    /// group snapshots load-bearing.
    static func applyGroupRoomIdentity(to viewModel: NativeCallScreenViewModel) {
        viewModel.state.roomName = "Design team"
        viewModel.state.roomAvatar = .room(id: "!design-team:matrix.org",
                                           name: "Design team",
                                           avatarURL: nil)
    }

    /// `06b`: a tap hid the dock — the capsule alone above the picture.
    static func makeChromeHiddenViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeVideoAgentViewModel()
        viewModel.state.bindings.isVideoChromeHidden = true
        return viewModel
    }

    /// `02 · Outgoing call`: the callee named large, `Calling…` under it.
    static func makeRingingViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel()
        viewModel.state.callState = .ringing
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true)]
        return viewModel
    }

    /// `07 · Video call · group`: four people in the 2×2 grid — the local
    /// preview is IN the grid, not floating.
    static func makeGroupVideoViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel(isVideoCall: true)
        viewModel.state.scope = .group
        applyGroupRoomIdentity(to: viewModel)
        viewModel.state.callState = .connected
        let local = participant("@alice:matrix.org", isLocal: true)
        let remotes = [participant("@bob:matrix.org", isSpeaking: true),
                       participant("@carol:matrix.org"),
                       participant("@dave:matrix.org", isMuted: true)]
        viewModel.state.participants = [local] + remotes + [participant("@assistant-alice:matrix.org", role: .agent)]
        viewModel.state.memberProfiles = ["@alice:matrix.org": .init(displayName: "Alice Kovalenko"),
                                          "@bob:matrix.org": .init(displayName: "Bohdan Serhiienko"),
                                          "@carol:matrix.org": .init(displayName: "Marta Illienko"),
                                          "@dave:matrix.org": .init(displayName: "Yurii Tkach"),
                                          "@assistant-alice:matrix.org": .init(displayName: "Alice's Assistant")]
        viewModel.state.videoTiles = (remotes + [local]).map { NativeCallVideoTile(participant: $0, source: nil) }
        viewModel.state.agentClaims.documents = ["@assistant-alice:matrix.org": .make(languages: ["en"])]
        viewModel.state.agentClaims.speaking = ["@assistant-alice:matrix.org"]
        viewModel.state.agentCenter.isAvailable = true
        return viewModel
    }

    /// A connected group audio call with two agents, one of them airing,
    /// and a live recording session — `05 · Group call` in one frame.
    static func makeAgentViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel()
        viewModel.state.scope = .group
        applyGroupRoomIdentity(to: viewModel)
        viewModel.state.callState = .connected
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true),
                                        participant("@bob:matrix.org", isSpeaking: true),
                                        participant("@carol:matrix.org"),
                                        participant("@dave:matrix.org", isMuted: true),
                                        participant("@assistant-alice:matrix.org", role: .agent),
                                        participant("@notetaker-bob:matrix.org", role: .agent)]
        viewModel.state.memberProfiles = ["@alice:matrix.org": .init(displayName: "Alice Kovalenko"),
                                          "@bob:matrix.org": .init(displayName: "Bohdan Serhiienko"),
                                          "@carol:matrix.org": .init(displayName: "Marta Illienko"),
                                          "@dave:matrix.org": .init(displayName: "Yurii Tkach"),
                                          "@assistant-alice:matrix.org": .init(displayName: "Alice's Assistant")]
        // The wave is the agent's document claim confirmed by the speaking
        // signal (the SpiralAgentDock rule), never a timer. REC is the
        // recorder's DOCUMENT claim — the REST session below is control.
        viewModel.state.agentClaims.documents = ["@assistant-alice:matrix.org": .make(languages: ["de"], recording: true)]
        viewModel.state.agentClaims.speaking = ["@assistant-alice:matrix.org"]
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.sessions = [session(agentMxid: "@assistant-alice:matrix.org",
                                                        sessionID: "session-1",
                                                        isRecording: true),
                                                session(agentMxid: "@notetaker-bob:matrix.org",
                                                        sessionID: "session-2",
                                                        isRecording: false)]
        return viewModel
    }

    static func makeVideoAgentViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel(isVideoCall: true)
        viewModel.state.callState = .connected
        let remote = participant("@bob:matrix.org", isSpeaking: true)
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true),
                                        remote,
                                        participant("@assistant-alice:matrix.org", role: .agent)]
        viewModel.state.videoTiles = [NativeCallVideoTile(participant: remote, source: nil)]
        viewModel.state.agentClaims.documents = ["@assistant-alice:matrix.org": .make(languages: ["en"])]
        viewModel.state.agentClaims.speaking = ["@assistant-alice:matrix.org"]
        viewModel.state.agentCenter.isAvailable = true
        return viewModel
    }

    /// A connected 1:1: the big centred avatar of `03 · Call 1:1`.
    static func makeNoAgentViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel()
        viewModel.state.callState = .connected
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true),
                                        participant("@bob:matrix.org", isSpeaking: true)]
        viewModel.state.memberProfiles = ["@bob:matrix.org": .init(displayName: "Bohdan Serhiienko")]
        return viewModel
    }

    static func participant(_ userID: String,
                            role: NativeCallParticipant.Role = .human,
                            isSpeaking: Bool = false,
                            isLocal: Bool = false,
                            isMuted: Bool = false) -> NativeCallParticipant {
        NativeCallParticipant(id: "\(userID):DEVICE",
                              userID: userID,
                              role: role,
                              mediaState: .connected,
                              isSpeaking: isSpeaking,
                              isAudioEnabled: !isMuted,
                              isLocal: isLocal)
    }

    static func session(agentMxid: String, sessionID: String, isRecording: Bool) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: sessionID,
                                 agentMxid: agentMxid,
                                 canControl: true,
                                 isEnding: false,
                                 recording: .init(isEnabled: isRecording, revision: 1, delivery: .notArmed, isStopped: false),
                                 summary: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                 translation: .unknown,
                                 conversation: .unknown)
    }

    /// A preview/session pair that never touches LiveKit: the default
    /// transport allocates a `Room`, a 256-key HKDF provider and a delegate
    /// registration — per preview, and again inside PreviewTests and
    /// AccessibilityTests.
    static func makePreviewTransport() -> NativeCallTransportMock {
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@alice:matrix.org:DEVICE"
        transport.underlyingIsLocalSpeaking = false
        transport.underlyingLocalConnectionQuality = .unknown
        transport.underlyingIsMicrophoneEnabled = true
        transport.underlyingIsCameraEnabled = false
        transport.setSubscriptionsAuthorizedIdentitiesIsTrackExcludedClosure = { _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }
        return transport
    }

    static func makeViewModel(isVideoCall: Bool = false, scope: NativeCallScope = .direct) -> NativeCallScreenViewModel {
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "@alice:matrix.org:DEVICE"
        rtcSession.updates = Empty().eraseToAnyPublisher()

        return NativeCallScreenViewModel(session: NativeCallSession(rtcSession: rtcSession,
                                                                    isRoomEncrypted: true,
                                                                    notifyRoom: true,
                                                                    configuration: .init(media: isVideoCall ? .video : .audio, scope: scope),
                                                                    transport: makePreviewTransport()),
                                         callKitService: CallKitServiceMock(.init()),
                                         agentCenter: NativeAgentCenterController(agentPlatformService: nil,
                                                                                  roomID: "!room:matrix.org",
                                                                                  roomMemberMxids: { [] },
                                                                                  inviteAgent: { _ in false }),
                                         appMediator: AppMediatorMock(.init()),
                                         isVideoCall: isVideoCall,
                                         roomID: "!room:matrix.org",
                                         roomName: "Bohdan Serhiienko",
                                         scope: scope,
                                         // What a real DM's coordinator feeds: the single
                                         // hero. The dialing/ended header renders identity
                                         // from this, not from the (empty) call roster.
                                         roomAvatar: .heroes([UserProfile(userID: "@bohdan:matrix.org",
                                                                          displayName: "Bohdan Serhiienko")]))
    }
}
