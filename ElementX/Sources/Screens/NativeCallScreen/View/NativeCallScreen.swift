//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion // AGENT-PLATFORM (Brief 0083)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize // AGENT-PLATFORM (Brief 0083, question 383)
    /// The corner tile's corner, held here so it stays put when a swap changes what is in it (question 383).
    @State private var cornerTileCorner: Alignment = .topTrailing // AGENT-PLATFORM (Brief 0083)
    // AGENT-PLATFORM (Brief 0083, question 383): the group filmstrip's smallest tiles, larger with the text.
    @ScaledMetric(relativeTo: .caption) private var filmstripTileWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .caption) private var filmstripTileHeight: CGFloat = 60
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled // AGENT-PLATFORM (Brief 0083)

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
        // AGENT-PLATFORM (Brief 0083, question 383): a group's stage holds still while VoiceOver reads it.
        .onChange(of: isVoiceOverEnabled, initial: true) { _, isRunning in
            context.send(viewAction: .voiceOverStatusChanged(isRunning: isRunning))
        }
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
        // A group's window shows whoever its stage shows (question 383): the same sustained-turn rule, no flicker.
        let staged = remoteVideoTiles.first { $0.participant.userID == context.viewState.groupFocusUserID }
        if let tile = staged ?? remoteVideoTiles.first(where: \.participant.isSpeaking) ?? remoteVideoTiles.first {
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
                                           size: SpiralAvatarSize.large, // AGENT-PLATFORM (Brief 0083, decision 300b)
                                           mediaProvider: mediaProvider)
                } else {
                    RoomAvatarImage(avatar: roomAvatar,
                                    avatarSize: .custom(SpiralAvatarSize.large), // AGENT-PLATFORM (Brief 0083, decision 300b)
                                    mediaProvider: mediaProvider)
                }
            })
        }
    }

    /// `06`: the picture IS the screen — edge to edge, under the status
    /// bar and the home indicator. A tap on the picture hides the dock for a
    /// clean view (the assistant stays: the agent is never hidden).
    private var videoBody: some View {
        Group {
            if context.viewState.scope.isOneToOne {
                oneToOneVideoBody
            } else {
                groupVideoBody
            }
        }
        // AGENT-PLATFORM (Brief 0083, decision 340): the one animation of the dock's hide and show. State-driven, so a
        // tap midway reverses it from where it is.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.32, bounce: 0),
                   value: context.isVideoChromeHidden)
        // Question 383: the header, the pill and the dock float over a live picture here.
        .environment(\.nativeCallIsOverPicture, true)
        .background(Color.black.ignoresSafeArea())
        .onChange(of: context.viewState.isVideoCall) {
            // Falling back to the audio stage always brings the dock back.
            context.isVideoChromeHidden = false
        }
    }

    // AGENT-PLATFORM (Brief 0083, decisions 339 and 340): the portrait's 1:1 video. The header, the pill and the dock
    // float over the picture on shades, and the small tile's corners lie between them.
    private var oneToOneVideoBody: some View {
        ZStack {
            oneToOneVideoStage
                // The person comes after the name and before the corner tile, not last behind the dock.
                .accessibilitySortPriority(context.viewState.isPersonOnStage ? 1 : 0)

            VStack(spacing: 0) {
                videoHeader(onGlass: !context.viewState.isPersonOnStage)
                    .accessibilitySortPriority(context.viewState.isPersonOnStage ? 2 : 0)

                // The room stays when there is no small tile: the header and the dock keep to their edges.
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
                    .overlay { videoSmallTile }
                    .transaction(stillUnderReduceMotion)

                videoChrome
            }
        }
    }

    // AGENT-PLATFORM (Brief 0083, decisions 339 and 340): the portrait's group video. The room's field behind rounded
    // tiles that fill everything between the header and the dock; hiding the dock gives its space to the tiles.
    private var groupVideoBody: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            videoHeader(onGlass: false)

            // Question 383, the operator's pick (Focus): whoever has held the floor fills the stage, everyone else in
            // a filmstrip under it. Agents never: they ride the pill.
            groupVideoFocus
                .frame(maxHeight: .infinity)
                .transaction(stillUnderReduceMotion)

            videoChrome
        }
        .background {
            NativeCallBackdrop(photoURL: context.viewState.backdropPhotoURL,
                               contentID: context.viewState.backdropContentID,
                               mediaProvider: context.mediaProvider,
                               tone: .wash)
                .ignoresSafeArea()
        }
    }

    // AGENT-PLATFORM (Brief 0083, decisions 339 and 340): the assistant's pill, and the dock until a tap hides it. The
    // dock slides down a little and fades; the pill is never hidden, so it glides down into the room. Under Reduce
    // Motion the two arrangements cross-fade instead (the `id`), and nothing moves.
    private var videoChrome: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            if let line = context.viewState.limitLine {
                NativeCallLimitLine(text: line)
                    .padding(.horizontal, CompoundDesignTokens.space4X)
            }

            NativeCallAgentCapsule(context: context)
                .padding(.horizontal, CompoundDesignTokens.space4X)

            if !context.isVideoChromeHidden {
                NativeCallGlassDock(controls: controls, showsCaptions: false)
                    .transition(.offset(y: CompoundDesignTokens.space6X).combined(with: .opacity))
            }
        }
        .padding(.bottom, context.isVideoChromeHidden ? 10 : 0)
        .frame(maxWidth: .infinity)
        .id(reduceMotion && context.isVideoChromeHidden)
        .transition(.opacity)
    }

    /// What the dock's hide or show re-lays out jumps under Reduce Motion, behind the cross-fade, rather than move.
    private func stillUnderReduceMotion(_ transaction: inout Transaction) {
        if reduceMotion {
            transaction.animation = nil
        }
    }

    private var fullScreenBody: some View {
        Group {
            if context.viewState.isVideoCall, !context.viewState.isAssistantPage {
                videoBody
            } else if context.viewState.isVideoCall {
                assistantVideoBody
            } else {
                NativeCallPortraitLayout(context: context, controls: controls) // AGENT-PLATFORM (Brief 0083, decision 340)
            }
        }
        .alert(item: $context.alertInfo)
        // L8: the Assistants sheet's resting height, measured here before it opens.
        .background { NativeCallAssistantsDetentMeasurer() }
        .sheet(isPresented: $context.isAgentCenterPresented,
               onDismiss: { context.send(viewAction: .dismissAgentCenter) },
               content: {
                   NativeCallAgentCenterSheet(context: context)
                       .presentationDragIndicator(.visible)
               })
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

    /// The assistant's page carries a video call too (question 383): it stays the assistant's, with your picture in the
    /// corner. A tap on the corner swaps them: your picture fills the screen, with no shades (the header on its capsule,
    /// the controls on the dark material over a live picture), and the assistant, its avatar in its Aura, takes the
    /// corner. Another tap swaps back.
    private var assistantVideoBody: some View {
        let ownTile = context.viewState.videoTiles.first(where: \.participant.isLocal)
        let isOwnPictureLarge = context.isSelfVideoLarge && ownTile != nil
        return ZStack {
            if isOwnPictureLarge, let ownTile {
                NativeCallVideoTileView(tile: ownTile,
                                        renderer: videoRenderer,
                                        displayName: displayName(for: ownTile.participant),
                                        profile: context.viewState.memberProfiles[ownTile.participant.userID],
                                        mediaProvider: context.mediaProvider,
                                        avatarSize: SpiralAvatarSize.xLarge,
                                        showsSpeakingRing: false,
                                        // No caption and its shade over your own full-screen picture.
                                        showsCaption: false,
                                        // swiftlint:disable:next spiral_raw_corner_radius - the picture fills the screen, edge to edge
                                        cornerRadius: 0)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 0) {
                    videoHeader(onGlass: true)
                    // What the page's line says (an error, a recording) stays in sight here too; the interpreter's badge
                    // (L12) too, as the avatar it marks is out of sight.
                    if let event = context.viewState.agentBlock?.event, NativeCallAgentStatusCopy.assistantPageLine(event) != nil {
                        NativeCallAssistantStateLine(event: event)
                            .padding(.horizontal, CompoundDesignTokens.space4X)
                            .padding(.vertical, CompoundDesignTokens.space1_5X)
                            .nativeCallSurface(in: Capsule())
                            .padding(.top, CompoundDesignTokens.space1X)
                    } else if let badge = context.viewState.interpreterBadge {
                        NativeCallTranslationBadge(badge: badge)
                            .padding(.top, CompoundDesignTokens.space1X)
                    }
                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                        .overlay { assistantCornerTile }
                    NativeCallGlassDock(controls: controls, showsCaptions: false)
                }
                .environment(\.nativeCallIsOverPicture, true)
                .transition(.opacity)
            } else {
                // The corner tile keeps to the page's stage, between the way back and the dock, as on the 1:1 video.
                NativeCallPortraitLayout(context: context, controls: controls, cornerTile: ownTile.map { ownTile in
                    AnyView(NativeCallDraggableTile(tile: ownTile,
                                                    renderer: videoRenderer,
                                                    displayName: displayName(for: ownTile.participant),
                                                    profile: context.viewState.memberProfiles[ownTile.participant.userID],
                                                    mediaProvider: context.mediaProvider,
                                                    corner: $cornerTileCorner) {
                            context.send(viewAction: .swapVideos)
                        })
                })
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0), value: isOwnPictureLarge)
        .background(Color.black.ignoresSafeArea())
    }

    /// The assistant in the corner while your picture is large: its avatar in its Aura on its own field.
    @ViewBuilder
    private var assistantCornerTile: some View {
        if let assistant = context.viewState.stagePeer {
            NativeCallDraggableTile(corner: $cornerTileCorner, onSwap: { context.send(viewAction: .swapVideos) }) {
                NativeCallSpeakingRing(userID: assistant.userID, diameter: SpiralAvatarSize.medium) {
                    NativeCallLetterAvatar(userID: assistant.userID,
                                           profile: context.viewState.memberProfiles[assistant.userID],
                                           fallbackName: context.viewState.roomName,
                                           size: SpiralAvatarSize.medium,
                                           mediaProvider: context.mediaProvider)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    NativeCallBackdrop(photoURL: context.viewState.backdropPhotoURL,
                                       contentID: context.viewState.backdropContentID,
                                       mediaProvider: context.mediaProvider,
                                       tone: .deep)
                }
                .clipShape(RoundedRectangle(cornerRadius: SpiralRadius.bubble, style: .continuous))
                .accessibilityLabel(displayName(for: assistant) ?? context.viewState.roomName)
            }
        }
    }

    /// `06 · Video call`: the name with the meta line under it, the way back beside them. Over a picture they sit on the
    /// system's glass instead of a shade (question 383, decision 346), so the picture stays uncovered.
    private func videoHeader(onGlass: Bool) -> some View {
        VStack(spacing: CompoundDesignTokens.space1X) {
            if onGlass {
                // The words are the glass's own content in the primary style, which glass keeps legible over any picture.
                videoTitle(onGlass: true)
                    .padding(.horizontal, CompoundDesignTokens.space5X)
                    .padding(.vertical, CompoundDesignTokens.space2X)
                    .nativeCallSurface(in: Capsule())
                    .padding(.horizontal, CompoundDesignTokens.space14X)
            } else {
                videoTitle(onGlass: false)
                    .padding(.horizontal, CompoundDesignTokens.space14X)
            }

            NativeCallHeldCallPill(context: context)
                .padding(.top, CompoundDesignTokens.space1X)
        }
        .padding(.vertical, CompoundDesignTokens.space1X)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            NativeCallBackButton(context: context)
                .padding(.horizontal, CompoundDesignTokens.space3X)
        }
        // Brief 0085: what you hear, top right.
        .overlay(alignment: .topTrailing) {
            NativeCallTranslateButton(context: context)
                .padding(.horizontal, CompoundDesignTokens.space3X)
        }
    }

    private func videoTitle(onGlass: Bool) -> some View {
        VStack(spacing: CompoundDesignTokens.space1X) {
            Text(context.viewState.roomName)
                .font(.compound.headingSMSemibold)
                .foregroundStyle(onGlass ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.compound.textOnSolidPrimary))
                .multilineTextAlignment(.center)
                .lineLimit(onGlass && !dynamicTypeSize.isAccessibilitySize ? 1 : 2)
                .minimumScaleFactor(onGlass ? 0.8 : 1)

            NativeCallMetaLine(context: context, isOverVideo: !onGlass, isOnGlass: onGlass)
        }
    }

    // MARK: - Stages

    /// A 1:1 video call gives the picture the screen: one party fills it
    /// and the other sits in a draggable corner tile.
    @ViewBuilder
    private var oneToOneVideoStage: some View {
        if let largeTile = context.viewState.videoStage.large {
            // The header already names the 1:1 peer — the full-bleed
            // stage carries neither a ring, a caption nor corners
            // (`06`): the picture IS the screen.
            NativeCallVideoTileView(tile: largeTile,
                                    renderer: videoRenderer,
                                    displayName: displayName(for: largeTile.participant),
                                    profile: context.viewState.memberProfiles[largeTile.participant.userID],
                                    mediaProvider: context.mediaProvider,
                                    avatarSize: SpiralAvatarSize.xLarge, // AGENT-PLATFORM (Brief 0083, decisions 300b and 340)
                                    showsSpeakingRing: false,
                                    showsCaption: false,
                                    // swiftlint:disable:next spiral_raw_corner_radius - the stage has no corners
                                    cornerRadius: 0,
                                    portrait: largeTile.participant.isLocal ? nil : context) // AGENT-PLATFORM (Brief 0083, decision 342)
                .ignoresSafeArea()
                .onTapGesture {
                    context.isVideoChromeHidden.toggle()
                }
                .accessibilityActions { showControlsAction }
        } else {
            Color(.systemFill).ignoresSafeArea()
        }
    }

    /// G14: a TAP on the small tile swaps who is large, a DRAG moves it to any corner.
    @ViewBuilder
    private var videoSmallTile: some View {
        if let smallTile = context.viewState.videoStage.small {
            let hasRemoteTile = context.viewState.videoTiles.contains { !$0.participant.isLocal }
            // Decision 341: a tap swaps the pictures, never flips the camera (that is the Camera control's alone).
            NativeCallDraggableTile(tile: smallTile,
                                    renderer: videoRenderer,
                                    displayName: displayName(for: smallTile.participant),
                                    profile: context.viewState.memberProfiles[smallTile.participant.userID],
                                    mediaProvider: context.mediaProvider,
                                    corner: $cornerTileCorner,
                                    onSwap: hasRemoteTile ? { context.send(viewAction: .swapVideos) } : nil)
        }
    }

    /// The group's Focus: the stage is `groupFocusUserID`'s tile (moved only by a sustained turn), the filmstrip the
    /// others, ourselves last. Portrait puts the strip under the stage, landscape beside it, so the stage keeps most
    /// of the screen either way. A change of speaker crossfades on a spring; under Reduce Motion it fades.
    private var groupVideoFocus: some View {
        let tiles = context.viewState.videoTiles.filter { !$0.participant.isLocal }
            + context.viewState.videoTiles.filter(\.participant.isLocal)
        let stage = tiles.first { $0.participant.userID == context.viewState.groupFocusUserID } ?? tiles.first
        let strip = tiles.filter { $0.id != stage?.id }

        return GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            let layout = isWide
                ? AnyLayout(HStackLayout(spacing: CompoundDesignTokens.space2X))
                : AnyLayout(VStackLayout(spacing: CompoundDesignTokens.space2X))

            layout {
                if let stage {
                    groupTile(stage, cornerRadius: SpiralRadius.listCard, avatarSize: SpiralAvatarSize.large)
                        .id(stage.id)
                        .transition(.opacity)
                }

                if !strip.isEmpty {
                    NativeCallTileStrip(items: strip,
                                        axis: isWide ? .vertical : .horizontal,
                                        minimumTileLength: isWide ? filmstripTileHeight : filmstripTileWidth,
                                        spacing: CompoundDesignTokens.space2X,
                                        crossInset: NativeCallTileAuraEdge.reach) { tile, length in
                        // Portrait thumbnails under a portrait stage, landscape ones beside a landscape stage.
                        groupTile(tile, cornerRadius: SpiralRadius.block, avatarSize: SpiralAvatarSize.small, isCompact: true)
                            .frame(width: isWide ? length * 4 / 3 : length, height: isWide ? length : length * 4 / 3)
                    }
                    .frame(maxHeight: isWide ? .infinity : nil)
                }
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space3X)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0), value: stage?.id)
    }

    /// One of the group's pictures, its edge bending while its person speaks (the Aura edge).
    private func groupTile(_ tile: NativeCallVideoTile, cornerRadius: CGFloat, avatarSize: CGFloat, isCompact: Bool = false) -> some View {
        NativeCallVideoTileView(tile: tile,
                                renderer: videoRenderer,
                                displayName: displayName(for: tile.participant),
                                profile: context.viewState.memberProfiles[tile.participant.userID],
                                mediaProvider: context.mediaProvider,
                                avatarSize: avatarSize,
                                showsSpeakingRing: false,
                                isCaptionCompact: isCompact,
                                cornerRadius: cornerRadius)
            .overlay {
                NativeCallTileAuraEdge(userID: tile.participant.userID, cornerRadius: cornerRadius)
            }
            .onTapGesture {
                context.isVideoChromeHidden.toggle()
            }
            .accessibilityActions { showControlsAction }
    }

    // AGENT-PLATFORM (Brief 0083, decision 340): with the dock hidden VoiceOver has nothing to reach it by but this.
    @ViewBuilder
    private var showControlsAction: some View {
        if context.isVideoChromeHidden {
            Button(UntranslatedL10n.a11yNativeCallShowControls) {
                context.isVideoChromeHidden = false
            }
        }
    }

    private func displayName(for participant: NativeCallParticipant) -> String? {
        context.viewState.memberProfiles[participant.userID]?.displayName
    }

    // MARK: - Controls

    // AGENT-PLATFORM (Brief 0083, decisions 300d and 340): the controls as one model the glass dock draws. ONE dock
    // for the one call (`02`–`07`): `Assistant · Mute · Video · Sound/Flip · End`. The fourth slot is contextual —
    // Sound in audio (long-press: the routes sheet), the camera Flip once video is live (the speaker is automatic
    // then). Personal listening lives in the Agent Center's WHAT YOU HEAR section.
    private var controls: [NativeCallControl] {
        var controls = [NativeCallControl]()
        // From the first frame: waiting for the platform's answer made the dock jump from three buttons to four
        // (question 401, remark 4). Until it answers, the sheet says it is loading, or unavailable.
        if context.viewState.agents.panel.isConfigured {
            controls.append(.init(id: "assistant",
                                  symbol: .spiral("spiral.peek.layers"),
                                  title: UntranslatedL10n.screenNativeCallControlAgent,
                                  kind: .assistant(isInCall: context.viewState.agentBlock != nil),
                                  accessibilityLabel: UntranslatedL10n.screenNativeCallAgentCenterOpen) {
                    context.send(viewAction: .showAgentCenter)
                })
        }
        controls.append(.init(id: "microphone",
                              symbol: .system(context.viewState.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill"),
                              title: UntranslatedL10n.screenNativeCallControlMute,
                              kind: .toggle(isOn: !context.viewState.isMicrophoneEnabled),
                              accessibilityLabel: context.viewState.isMicrophoneEnabled
                                  ? UntranslatedL10n.a11yNativeCallMuteMicrophone
                                  : UntranslatedL10n.a11yNativeCallUnmuteMicrophone) {
                context.send(viewAction: .toggleMicrophone)
            })
        // The slashed glyph alone carries the off state — inverting the
        // control made the DEFAULT state the loudest thing in the dock.
        controls.append(.init(id: "camera",
                              symbol: .system(context.viewState.isCameraEnabled ? "video.fill" : "video.slash.fill"),
                              title: UntranslatedL10n.screenNativeCallControlVideo,
                              kind: .toggle(isOn: false),
                              accessibilityLabel: context.viewState.isCameraEnabled
                                  ? UntranslatedL10n.a11yNativeCallCameraOff
                                  : UntranslatedL10n.a11yNativeCallCameraOn) {
                context.send(viewAction: .toggleCamera)
            })
        if context.viewState.isVideoCall {
            controls.append(.init(id: "flip",
                                  symbol: .system("arrow.triangle.2.circlepath.camera"),
                                  title: UntranslatedL10n.screenNativeCallControlFlip,
                                  kind: .toggle(isOn: false),
                                  accessibilityLabel: UntranslatedL10n.a11yNativeCallSwitchCamera) {
                    context.send(viewAction: .switchCamera)
                })
        } else {
            // G8 — the long-press always reaches the route picker, even
            // when only the phone's own outputs exist right now.
            controls.append(.init(id: "speaker",
                                  symbol: .system(context.viewState.isSpeakerEnabled ? "speaker.wave.2.fill" : "speaker.wave.2"),
                                  title: UntranslatedL10n.screenNativeCallControlSound,
                                  kind: .toggle(isOn: context.viewState.isSpeakerEnabled),
                                  accessibilityLabel: context.viewState.isSpeakerEnabled
                                      ? UntranslatedL10n.a11yNativeCallDisableSpeaker
                                      : UntranslatedL10n.a11yNativeCallEnableSpeaker,
                                  accessibilityHint: UntranslatedL10n.a11yNativeCallAudioRoutes,
                                  longPressAction: { context.send(viewAction: .showAudioRoutes) }) {
                    context.send(viewAction: .toggleSpeaker)
                })
        }
        controls.append(.init(id: "end",
                              symbol: .system("phone.down.fill"),
                              title: UntranslatedL10n.screenNativeCallControlEnd,
                              kind: .end,
                              accessibilityLabel: UntranslatedL10n.a11yNativeCallEnd) {
                context.send(viewAction: .hangUp)
            })
        return controls
    }
}

// MARK: - Previews

struct NativeCallScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    /// G1/G2/G4 in context: an agent airing a translation, a live recording
    /// and a mixed roster, so the pill, REC and `4 people · 2 agents` are
    /// all snapshotted on the real screen rather than in isolation.
    static let agentViewModel = makeAgentViewModel()
    /// The same screen with no agent attached: the pill must be ABSENT and
    /// the status line must fall back to people alone.
    static let noAgentViewModel = makeNoAgentViewModel()
    /// Still pictures in place of live video (Brief 0083, decision 340).
    static let videoRenderer = NativeCallPreviewVideoRenderer()

    static var previews: some View {
        NativeCallScreen(context: viewModel.context, videoRenderer: nil)
            .previewDisplayName("Connecting")

        NativeCallScreen(context: makeRingingViewModel().context, videoRenderer: nil)
            .previewDisplayName("Outgoing ringing")

        NativeCallScreen(context: noAgentViewModel.context, videoRenderer: nil)
            .previewDisplayName("No agent")

        NativeCallScreen(context: makeLimitStopViewModel().context, videoRenderer: nil)
            .previewDisplayName("Translation paused by the AI limit")

        NativeCallScreen(context: makePhotoViewModel().context, videoRenderer: nil)
            .previewDisplayName("1-1 with a photo")

        NativeCallScreen(context: makeTranslatingViewModel().context, videoRenderer: nil)
            .previewDisplayName("1-1 with the assistant translating and recording")

        NativeCallScreen(context: makeAssistantCallViewModel().context, videoRenderer: nil)
            .previewDisplayName("Assistant call")

        NativeCallScreen(context: makeHeldCallViewModel().context, videoRenderer: nil)
            .previewDisplayName("Held call")

        NativeCallScreen(context: agentViewModel.context, videoRenderer: nil)
            .previewDisplayName("Agent airing · recording")

        NativeCallScreen(context: makeVideoViewModel().context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · agent capsule")

        NativeCallScreen(context: makeVideoViewModel(remoteFrame: nil).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · peer's camera off")

        NativeCallScreen(context: makeVideoViewModel(remoteFrame: nil, hasPeerPhoto: true).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · peer's camera off with a photo")

        NativeCallScreen(context: makeVideoViewModel(remoteFrame: nil, isPeerOnHold: true).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · peer on hold")

        NativeCallScreen(context: makeVideoViewModel(isChromeHidden: true).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · chrome hidden")

        NativeCallScreen(context: makeGroupVideoViewModel(people: 2).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · group of 2")

        NativeCallScreen(context: makeGroupVideoViewModel(people: 3).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · group of 3")

        NativeCallScreen(context: makeGroupVideoViewModel(people: 4).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · group grid")

        NativeCallScreen(context: makeGroupVideoViewModel(people: 4, hasCamerasOff: true).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · group with cameras off")

        NativeCallScreen(context: makeGroupVideoViewModel(people: 6).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · group of 6")

        NativeCallScreen(context: makeGroupVideoViewModel(people: 8).context, videoRenderer: videoRenderer)
            .previewDisplayName("Video call · group of 8")
    }

    /// A 1:1 with another call parked behind it: the pill under the header swaps them.
    static func makeHeldCallViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeNoAgentViewModel()
        viewModel.state.heldCall = CallKitHeldCall(roomID: "!held:matrix.org", displayName: "Marta Illienko")
        return viewModel
    }

    /// A connected 1:1 with the peer's photo, which the backdrop is made of.
    static func makePhotoViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel(mediaProvider: MediaProviderMock(.init()))
        viewModel.state.callState = .connected
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.isConfigured = true
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true),
                                        participant("@bob:matrix.org", isSpeaking: true)]
        viewModel.state.memberProfiles = ["@bob:matrix.org": .init(displayName: "Mira Testova", avatarURL: .mockMXCUserAvatar)]
        return viewModel
    }

    /// A 1:1 with one's assistant in it, translating everyone into Ukrainian and recording.
    static func makeTranslatingViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel()
        viewModel.state.callState = .connected
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true),
                                        participant("@bob:matrix.org"),
                                        participant("@assistant-alice:matrix.org", role: .agent, isSpeaking: true)]
        viewModel.state.memberProfiles = ["@alice:matrix.org": .init(displayName: "Alice Kovalenko"),
                                          "@bob:matrix.org": .init(displayName: "Mira Testova"),
                                          "@assistant-alice:matrix.org": .init(displayName: "Alice's Assistant")]
        viewModel.state.agentClaims.documents = ["@assistant-alice:matrix.org": .make(translation: .producing("uk", speakers: ["@bob:matrix.org"]), recording: true)]
        viewModel.state.agentClaims.speaking = ["@assistant-alice:matrix.org"]
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.isConfigured = true
        viewModel.state.agentCenter.sessions = [session(agentMxid: "@assistant-alice:matrix.org",
                                                        sessionID: "session-1",
                                                        isRecording: true)]
        return viewModel
    }

    /// A call WITH one's own assistant: the agent is the peer on the stage,
    /// named in the header, with the 1:1 timer — not a "waiting for others"
    /// room with an agent capsule (operator report 2026-09-11).
    static func makeAssistantCallViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel(scope: .assistant)
        viewModel.state.callState = .connected
        viewModel.state.roomName = "Alice's assistant"
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.isConfigured = true
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

    /// `02 · Outgoing call`: the callee named large, `Calling…` under it.
    static func makeRingingViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel()
        viewModel.state.callState = .ringing
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.isConfigured = true
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true)]
        return viewModel
    }

    /// `07 · Video call · group`: the local picture is IN the grid, not
    /// floating; every other camera off when asked, the first with a photo.
    static func makeGroupVideoViewModel(people count: Int, hasCamerasOff: Bool = false) -> NativeCallScreenViewModel {
        let names = ["Alice Kovalenko", "Mira Testova", "Marta Illienko", "Yurii Tkach",
                     "Olena Shevchuk", "Taras Melnyk", "Iryna Bondar", "Dmytro Savchenko"]
        let viewModel = makeViewModel(isVideoCall: true, mediaProvider: MediaProviderMock(.init()))
        viewModel.state.scope = .group
        applyGroupRoomIdentity(to: viewModel)
        viewModel.state.callState = .connected
        viewModel.state.isCameraEnabled = true

        let people = (0..<count).map { participant("@person\($0):matrix.org", isSpeaking: $0 == 1, isLocal: $0 == 0, isMuted: $0 == 2) }
        viewModel.state.memberProfiles["@assistant-alice:matrix.org"] = .init(displayName: "Alice's Assistant")
        for (index, person) in people.enumerated() {
            viewModel.state.memberProfiles[person.userID] = .init(displayName: names[index],
                                                                  avatarURL: hasCamerasOff && index == 1 ? .mockMXCUserAvatar : nil)
        }
        viewModel.state.participants = people + [participant("@assistant-alice:matrix.org", role: .agent)]
        viewModel.state.videoTiles = people.enumerated().map { index, person in
            NativeCallVideoTile(participant: person, source: hasCamerasOff && index % 2 == 1 ? nil : videoSource(frame: index))
        }
        viewModel.state.agentClaims.documents = ["@assistant-alice:matrix.org": .make(translation: .producing("uk", speakers: ["@bob:matrix.org"]), recording: true)]
        viewModel.state.agentClaims.speaking = ["@assistant-alice:matrix.org"]
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.isConfigured = true
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
                                          "@bob:matrix.org": .init(displayName: "Mira Testova"),
                                          "@carol:matrix.org": .init(displayName: "Marta Illienko"),
                                          "@dave:matrix.org": .init(displayName: "Yurii Tkach"),
                                          "@assistant-alice:matrix.org": .init(displayName: "Alice's Assistant")]
        // The wave is the agent's document claim confirmed by the speaking
        // signal (the SpiralAgentDock rule), never a timer. REC is the
        // recorder's DOCUMENT claim — the REST session below is control.
        viewModel.state.agentClaims.documents = ["@assistant-alice:matrix.org": .make(translation: .producing("de", speakers: ["@bob:matrix.org"]), recording: true)]
        viewModel.state.agentClaims.speaking = ["@assistant-alice:matrix.org"]
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.isConfigured = true
        viewModel.state.agentCenter.sessions = [session(agentMxid: "@assistant-alice:matrix.org",
                                                        sessionID: "session-1",
                                                        isRecording: true),
                                                session(agentMxid: "@notetaker-bob:matrix.org",
                                                        sessionID: "session-2",
                                                        isRecording: false)]
        return viewModel
    }

    /// `06 · Video call`: the peer's picture with ours in the corner, the assistant translating and recording. With
    /// the peer's camera off, the person fills the screen and ours stays in the corner.
    static func makeVideoViewModel(remoteFrame: Int? = 0,
                                   isChromeHidden: Bool = false,
                                   hasPeerPhoto: Bool = false,
                                   isPeerOnHold: Bool = false) -> NativeCallScreenViewModel {
        let viewModel = makeViewModel(isVideoCall: true, mediaProvider: hasPeerPhoto ? MediaProviderMock(.init()) : nil)
        viewModel.state.callState = .connected
        viewModel.state.isCameraEnabled = true
        let local = participant("@alice:matrix.org", isLocal: true)
        var remote = participant("@bob:matrix.org", isSpeaking: !isPeerOnHold)
        remote.isOnHold = isPeerOnHold
        viewModel.state.participants = [local, remote, participant("@assistant-alice:matrix.org", role: .agent)]
        viewModel.state.memberProfiles = ["@bob:matrix.org": .init(displayName: "Mira Testova",
                                                                   avatarURL: hasPeerPhoto ? .mockMXCUserAvatar : nil),
                                          "@assistant-alice:matrix.org": .init(displayName: "Alice's Assistant")]
        viewModel.state.videoTiles = [NativeCallVideoTile(participant: remote, source: remoteFrame.map(videoSource)),
                                      NativeCallVideoTile(participant: local, source: videoSource(frame: 2))]
        viewModel.state.isPeerSettled = true
        viewModel.state.agentClaims.documents = ["@assistant-alice:matrix.org": .make(translation: .producing("en", speakers: ["@bob:matrix.org"]), recording: true)]
        viewModel.state.agentClaims.speaking = ["@assistant-alice:matrix.org"]
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.isConfigured = true
        viewModel.state.bindings.isVideoChromeHidden = isChromeHidden
        return viewModel
    }

    static func videoSource(frame: Int) -> NativeCallVideoSource {
        NativeCallVideoSource(identity: "\(frame)", trackID: "\(frame)", isLocal: false)
    }

    /// A connected 1:1: the big centred avatar of `03 · Call 1:1`.
    static func makeNoAgentViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeViewModel()
        viewModel.state.callState = .connected
        viewModel.state.agentCenter.isAvailable = true
        viewModel.state.agentCenter.isConfigured = true
        viewModel.state.participants = [participant("@alice:matrix.org", isLocal: true),
                                        participant("@bob:matrix.org", isSpeaking: true)]
        viewModel.state.memberProfiles = ["@bob:matrix.org": .init(displayName: "Mira Testova")]
        return viewModel
    }

    /// D7, D10, question 395: the call translation cap paused the owner's assistant's translation; it stays for its
    /// notes, and only the owner's screen says so.
    static func makeLimitStopViewModel() -> NativeCallScreenViewModel {
        let viewModel = makeNoAgentViewModel()
        let assistant = "@assistant-alice:matrix.org"
        viewModel.state.participants.append(participant(assistant, role: .agent))
        viewModel.state.memberProfiles[assistant] = .init(displayName: "Alice's Assistant")
        viewModel.state.agentClaims.documents = [assistant: .make(summaryArmed: true)]
        var paused = NativeAgentCenterTranslation.unknown
        paused.effective.forLanguage = "uk"
        paused.effective.stoppedReason = .translationPaused
        paused.effective.pause = .untilChanged
        viewModel.state.agentCenter.ownAgentMxids = [assistant]
        viewModel.state.agentCenter.sessions = [NativeAgentCenterSession(sessionID: "session-1",
                                                                         agentMxid: assistant,
                                                                         canControl: true,
                                                                         isEnding: false,
                                                                         recording: .init(isEnabled: false, revision: 1, delivery: .notArmed, isStopped: false),
                                                                         summary: .init(isEnabled: true, revision: 1, delivery: .notArmed, isStopped: false),
                                                                         translation: paused,
                                                                         conversation: .unknown)]
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
        transport.setSubscriptionsAuthorizedIdentitiesStagedVideoIdentitiesIsTrackExcludedClosure = { _, _, _ in true }
        transport.setEncryptionKeyIndexIdentityClosure = { _, _, _ in }
        return transport
    }

    static func makeViewModel(isVideoCall: Bool = false,
                              scope: NativeCallScope = .direct,
                              mediaProvider: MediaProviderProtocol? = nil) -> NativeCallScreenViewModel { // AGENT-PLATFORM (Brief 0083)
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
                                         audioRouting: .inert, // AGENT-PLATFORM (407)
                                         mediaProvider: mediaProvider, // AGENT-PLATFORM (Brief 0083)
                                         isVideoCall: isVideoCall,
                                         roomID: "!room:matrix.org",
                                         roomName: "Mira Testova",
                                         scope: scope,
                                         // What a real DM's coordinator feeds: the single
                                         // hero. The dialing/ended header renders identity
                                         // from this, not from the (empty) call roster.
                                         roomAvatar: .heroes([UserProfile(userID: "@mira:matrix.org",
                                                                          displayName: "Mira Testova")]))
    }
}

/// Stills from the development assets in place of live video.
final class NativeCallPreviewVideoRenderer: NativeCallVideoRendering {
    private static let frames = ["preview_video", "portrait_test_image", "preview_image", "test_rotated_image",
                                 "landscape_test_image", "preview_avatar_room"]

    func videoView(for source: NativeCallVideoSource) -> AnyView? {
        let frame = Self.frames[(Int(source.identity) ?? 0) % Self.frames.count]
        guard let url = Bundle.main.url(forResource: frame, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 900, height: 900)) else {
            return nil
        }
        return AnyView(Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped())
    }

    func canRenderPictureInPictureVideo(for source: NativeCallVideoSource) -> Bool {
        false
    }

    func pictureInPictureVideoView(for source: NativeCallVideoSource) -> UIView? {
        nil
    }

    func tearDownPictureInPictureVideoView(_ view: UIView) { }
}
