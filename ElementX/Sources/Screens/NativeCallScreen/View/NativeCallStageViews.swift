//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083 phase 4, lane call-v2, decisions 339 and 340): what the call's portrait is drawn from:
// the person's backdrop, the stage avatar, the meta line, REC, the way back and a group's faces.

import Compound
import SpiralTokens
import SwiftUI

// MARK: - The person's backdrop

/// The person's own picture as a field behind the call: their photo blurred, or their monogram's colours without
/// one. Content, not bloom (decision 339). A scrim keeps every word over it legible whatever the picture.
/// Question 400: an agent's field without a photo is its Peek's colour, washed as a photo is.
struct NativeCallBackdrop: View {
    enum Tone {
        /// Follows the theme: a light wash under the ink in light, a deep one under white in dark. Only the ink
        /// reads on it, never the grey: the grey drops under 4.5:1 on the light wash.
        case wash
        /// Deep in both themes, under white: a tile whose camera is off.
        case deep
    }

    /// What the field is drawn from while no photo shows, decided as the avatar in front of it decides its fallback.
    enum Fill: Equatable {
        /// The monogram's grey-blue: a person, a room or a group.
        case monogram
        /// The agent's own colour, the one its Peek is drawn on (question 390).
        case agent(id: String)

        init(contentID: String?) {
            if let contentID, AgentAvatar.fallback(contentID: contentID) == .peek {
                self = .agent(id: contentID)
            } else {
                self = .monogram
            }
        }

        var colors: [Color] {
            switch self {
            case .monogram: [.spiral.avatarMonogramTop, .spiral.avatarMonogramBottom]
            case .agent(let id): AgentAvatarPalette.gradient(for: id).colors
            }
        }
    }

    var photoURL: URL?
    /// The incoming call's push carries the photo itself.
    var photoData: Data?
    /// Whose picture the field is: an agent's takes its own colour without a photo.
    var contentID: String?
    /// The avatar's size in front of the field: one thumbnail and one request serve both.
    var thumbnailDiameter = SpiralAvatarSize.xLarge
    var mediaProvider: MediaProviderProtocol?
    let tone: Tone

    @Environment(\.colorScheme) private var colorScheme
    @State private var loadedPhoto: UIImage?

    var body: some View {
        // The agent's colour stays under its photo, so the field changes as its Peek does, when the photo shows.
        LinearGradient(colors: Fill(contentID: contentID).colors, startPoint: .top, endPoint: .bottom)
            .overlay {
                if let photo = loadedPhoto ?? availablePhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay { scrim }
            .clipped()
            .accessibilityHidden(true)
            .task(id: photoURL) { await loadPhoto() }
    }

    private var scrim: some View {
        let opacity = Self.scrimOpacity(tone: tone,
                                        isDark: colorScheme == .dark,
                                        hasPhoto: photoURL != nil || photoData != nil,
                                        fill: Fill(contentID: contentID))
        return tone == .deep ? Color.black.opacity(opacity) : Color.compound.bgCanvasDefault.opacity(opacity)
    }

    /// With a photo, 72 % of the canvas puts the ink at 8.5:1 over a black one and 55 % white at 4.7:1 over a white
    /// one. The monogram's own colours are known, so they show more: the ink at 8.3:1, white at 11:1. Deep: black at
    /// 55 % puts white at 4.7:1 over a white photo; the monogram's light stops need only 35 % for 6.2:1. An agent's
    /// colour is washed as a photo is, so every header reads as one family (question 400).
    /// The washed field's colour at `fraction` of its height, scrim included: what a mark "cut out" of it is ringed in.
    static func fieldColor(contentID: String?, hasPhoto: Bool, isDark: Bool, at fraction: Double) -> Color {
        let fill = Fill(contentID: contentID)
        let colors = fill.colors
        let field = (colors.first ?? .clear).mix(with: colors.last ?? .clear, by: fraction)
        return field.mix(with: .compound.bgCanvasDefault, by: scrimOpacity(tone: .wash, isDark: isDark, hasPhoto: hasPhoto, fill: fill))
    }

    /// The call's own field at `fraction` of its height: the translation badge's cut-out ring (L12).
    static func stageRing(_ viewState: NativeCallScreenViewState, isDark: Bool, at fraction: Double) -> Color {
        fieldColor(contentID: viewState.backdropContentID, hasPhoto: viewState.backdropPhotoURL != nil, isDark: isDark, at: fraction)
    }

    static func scrimOpacity(tone: Tone, isDark: Bool, hasPhoto: Bool, fill: Fill) -> Double {
        let isWashedAsPhoto = hasPhoto || fill != .monogram
        return switch tone {
        case .wash where isDark: isWashedAsPhoto ? 0.55 : 0.3
        case .wash: isWashedAsPhoto ? 0.72 : 0.4
        case .deep: isWashedAsPhoto ? 0.55 : 0.35
        }
    }

    private var thumbnailSize: CGSize {
        Avatars.Size.custom(thumbnailDiameter).scaledSize
    }

    private var photoSource: MediaSourceProxy? {
        photoURL.flatMap { try? MediaSourceProxy(url: $0, mimeType: nil) }
    }

    /// The blurred photo when it needs no waiting: blurred before, or its thumbnail already in memory.
    private var availablePhoto: UIImage? {
        if let photoData {
            return NativeCallBackdropBlur.blurred(key: "\(photoData.hashValue)") { UIImage(data: photoData) }
        }
        guard let photoURL else { return nil }
        return NativeCallBackdropBlur.blurred(key: photoURL.absoluteString) { mediaProvider?.imageFromSource(photoSource, size: thumbnailSize) }
    }

    private func loadPhoto() async {
        loadedPhoto = nil
        guard availablePhoto == nil, let photoURL, let photoSource, let mediaProvider else { return }
        // The field stays the monogram's colours if the photo can't be fetched.
        guard let thumbnail = try? await mediaProvider.loadImageRetryingOnReconnection(photoSource, size: thumbnailSize).value else { return }
        loadedPhoto = NativeCallBackdropBlur.blurred(key: photoURL.absoluteString) { thumbnail }
    }
}

/// The backdrop's blur, done once per person on the thumbnail and cached: a live filter under video would redraw
/// with every frame, on up to nine tiles.
private enum NativeCallBackdropBlur {
    private static let cache = NSCache<NSString, UIImage>()
    private static let context = CIContext()

    static func blurred(key: String, thumbnail: () -> UIImage?) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        guard let thumbnail = thumbnail(), let input = CIImage(image: thumbnail) else { return nil }

        // A twentieth of the picture, about what a 48 pt blur is to a full-screen one.
        let sigma = max(input.extent.width, input.extent.height) / 20
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        guard let image = context.createCGImage(output, from: input.extent) else { return nil }

        let blurred = UIImage(cgImage: image, scale: thumbnail.scale, orientation: thumbnail.imageOrientation)
        cache.setObject(blurred, forKey: key as NSString)
        return blurred
    }
}

extension NativeCallScreenViewState {
    /// The picture the backdrop is made of: the 1:1 peer's photo, else the room's (a DM's single hero).
    var backdropPhotoURL: URL? {
        if let peer = stagePeer, let url = memberProfiles[peer.userID]?.avatarURL {
            return url
        }
        switch roomAvatar {
        case .room(_, _, let avatarURL), .direct(_, _, let avatarURL), .space(_, _, let avatarURL):
            return avatarURL
        case .heroes(let heroes):
            return heroes.count == 1 ? heroes.first?.avatarURL : nil
        case .tombstoned:
            return nil
        }
    }

    /// Whose colour the field takes without a photo: the assistant on its own page (question 400), as the avatar in
    /// front of it shows it, the agent once it joined, the DM's one hero while it rings. People and groups keep theirs.
    var backdropContentID: String? {
        guard isAssistantPage else { return nil }
        return stagePeer?.userID ?? roomAvatar.heroUserID
    }

    /// The call is still being placed: the kind of call is said over the name.
    var isPlacingCall: Bool {
        switch callState {
        case .connecting, .ringing: true
        default: false
        }
    }
}

// MARK: - Who is on the stage

/// The stage's large avatar: the 1:1 peer, the assistant of an assistant call, or the room before anyone answered.
/// The Aura ring round it bends with the peer's voice (question 383). On the assistant's own page the avatar is larger,
/// its ring reaches further and it carries no agent badge: the whole page says who it is.
struct NativeCallStageAvatar: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    @Environment(\.colorScheme) private var colorScheme

    /// The field's colour where the avatar sits (about 40 % down), scrim included: the badge's cut-out ring.
    private var stageRing: Color {
        NativeCallBackdrop.stageRing(context.viewState, isDark: colorScheme == .dark, at: 0.4)
    }

    /// The assistant's page: the avatar the page is built round.
    static let assistantSize: CGFloat = 168

    var body: some View {
        // An avatar is no text: it stops growing at the largest non-accessibility size.
        stage
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var stage: some View {
        if let peer = context.viewState.stagePeer {
            let isAssistant = context.viewState.isAssistantPage
            let size = isAssistant ? Self.assistantSize : SpiralAvatarSize.xLarge
            NativeCallSpeakingRing(userID: peer.userID, diameter: size, magnitude: isAssistant ? 1.6 : 1) {
                NativeCallLetterAvatar(userID: peer.userID,
                                       profile: context.viewState.memberProfiles[peer.userID],
                                       fallbackName: context.viewState.roomName,
                                       size: size,
                                       mediaProvider: context.mediaProvider)
                    .agentBadge(userID: isAssistant ? nil : peer.userID,
                                avatarURL: context.viewState.memberProfiles[peer.userID]?.avatarURL,
                                avatarSize: size) // Decision 357; none on the assistant's page
                    // L12: the interpreter's other side on the assistant's page, the language you hear the peer in
                    // otherwise.
                    .translationBadge(context.viewState.avatarBadge(for: peer.userID), ring: stageRing)
            }
        } else {
            // No live peer yet (dialing) or none any more (the call ended): the room's identity, a DM's single hero.
            // The assistant's page shows its size from the ring, so nothing jumps when the assistant joins.
            RoomAvatarImage(avatar: context.viewState.roomAvatar,
                            avatarSize: .custom(context.viewState.isAssistantPage ? Self.assistantSize : SpiralAvatarSize.xLarge),
                            mediaProvider: context.mediaProvider)
                .accessibilityHidden(true)
        }
    }
}

/// The Aura ring behind a speaker's avatar of `diameter`, bending with their voice and resting as a faint circle.
struct NativeCallSpeakingRing<Content: View>: View {
    let userID: String
    let diameter: CGFloat
    var magnitude: CGFloat = 1
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background {
                NativeCallAuraRing(userID: userID, diameter: diameter, magnitude: magnitude)
            }
    }
}

// MARK: - The call's line

/// The one line about the call itself: the lock, the signal, the timer once connected (the call state before) and
/// REC. Recording is a property of the call, so this is its only home (G2).
struct NativeCallMetaLine: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    /// White over the picture, the ink on the person's wash.
    var isOverVideo = false
    /// On glass: the primary style, which glass makes vibrant over whatever is behind it.
    var isOnGlass = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes REC goes under the line, so neither is cut.
        let factsLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: CompoundDesignTokens.space1X))
            : AnyLayout(HStackLayout(spacing: CompoundDesignTokens.space1_5X))

        VStack(spacing: CompoundDesignTokens.space1X) {
            factsLayout {
                HStack(spacing: CompoundDesignTokens.space1_5X) {
                    if context.viewState.isRoomEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.compound.bodyXS)
                            .accessibilityHidden(true)
                    }

                    if context.viewState.callState == .connected, context.viewState.connectionQuality != .unknown {
                        NativeCallSignalBars(quality: context.viewState.connectionQuality)
                    }

                    if let connectedAt = context.viewState.callConnectedAt, context.viewState.callState == .connected {
                        Text(connectedAt, style: .timer)
                            .font(.compound.bodyMD)
                            .monospacedDigit()
                    } else {
                        Text(context.viewState.statusText)
                            .font(.compound.bodyMD)
                            .multilineTextAlignment(.center)
                    }
                }

                if context.viewState.isRecording {
                    NativeCallRecordingBadge()
                }
            }

            // Phase 4: what the call is doing, or how long it ran once it ended.
            if let statusDetail = context.viewState.statusDetail {
                HStack(spacing: CompoundDesignTokens.space1X) {
                    // On a picture's wash a hue can't mark the degraded state: the glyph does.
                    if context.viewState.statusDetailIsDegraded {
                        CompoundIcon(\.pause, size: .xSmall, relativeTo: .compound.bodySM)
                            .accessibilityHidden(true)
                    }

                    Text(statusDetail)
                        .font(.compound.bodySM)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .foregroundStyle(isOnGlass ? AnyShapeStyle(.primary) : AnyShapeStyle(isOverVideo ? Color.compound.textOnSolidPrimary : .compound.textPrimary))
    }
}

/// REC as white on the critical fill (4.5:1), so it reads on a person's wash and on the picture.
struct NativeCallRecordingBadge: View {
    var body: some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            Circle()
                .fill(Color.compound.iconOnSolidPrimary)
                .frame(width: 6, height: 6)

            Text(UntranslatedL10n.screenNativeCallRecordingBadge)
                .font(.compound.bodyXSSemibold)
                .foregroundStyle(.compound.textOnSolidPrimary)
        }
        .padding(.horizontal, CompoundDesignTokens.space2X)
        .padding(.vertical, CompoundDesignTokens.space0_5X)
        .background(Color.compound.bgCriticalPrimary, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallRecording)
    }
}

/// G13: the way back to the chat that is not a hang-up; the call keeps running behind the bar.
struct NativeCallBackButton: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context

    var body: some View {
        Button { context.send(viewAction: .minimize) } label: {
            Image(systemName: "chevron.down")
                .font(.compound.bodyLGSemibold)
                .foregroundStyle(.compound.iconPrimary)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: 44, height: 44)
                .nativeCallSurface(in: Circle(), isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallMinimize)
    }
}

/// Brief 0068 Slice 2: the call parked behind this one, one tap to swap, under the header.
struct NativeCallHeldCallPill: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context

    var body: some View {
        if let heldCall = context.viewState.heldCall {
            Button {
                context.send(viewAction: .swapCalls)
            } label: {
                HStack(spacing: CompoundDesignTokens.space1_5X) {
                    CompoundIcon(\.pause, size: .xSmall, relativeTo: .compound.bodySM)

                    Text(UntranslatedL10n.screenNativeCallHeldCallPill(heldCall.displayName))
                        .font(.compound.bodySM)
                        .lineLimit(1)

                    Text(UntranslatedL10n.screenNativeCallSwap)
                        .font(.compound.bodySMSemibold)
                }
                .foregroundStyle(.compound.textPrimary)
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .frame(minHeight: 44)
                .nativeCallSurface(in: Capsule(), isInteractive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UntranslatedL10n.a11yNativeCallSwapToHeldCall(heldCall.displayName))
            .padding(.horizontal, CompoundDesignTokens.space4X)
        }
    }
}

// MARK: - The people of a group

/// A group's people as the Spotlight (question 383, the operator's pick, matching the video's Focus): whoever has held
/// the floor large at the centre in their Aura, everyone else in a strip under them, as many whole faces as fit (four
/// on a usual phone) and the rest by scrolling, each in their own Aura with their name and state on glass. A change of
/// speaker crossfades on a spring. Agents are never among them (G1).
struct NativeCallPeopleSpotlight: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var minimumFaceTile: CGFloat = 76

    /// The Aura's reach round a strip face, which the strip makes room for.
    private static let faceAuraRoom: CGFloat = 12

    var body: some View {
        let people = context.viewState.humanParticipants.filter { !$0.isLocal } + context.viewState.humanParticipants.filter(\.isLocal)
        let stage = people.first { $0.userID == context.viewState.groupFocusUserID } ?? people.first
        let strip = people.filter { $0.id != stage?.id }

        // As the video's Focus: the strip sits at the foot, just above the pill and the dock, and the speaker centres
        // in the space between the header and the strip. In the scrolling fallback the spacers fold to their minimum.
        VStack(spacing: 0) {
            Spacer(minLength: CompoundDesignTokens.space6X)

            if let stage {
                NativeCallPersonFace(context: context, participant: stage, size: SpiralAvatarSize.xLarge)
                    .id(stage.id)
                    .transition(.opacity)
            }

            Spacer(minLength: CompoundDesignTokens.space6X)

            if !strip.isEmpty {
                NativeCallTileStrip(items: strip,
                                    minimumTileLength: minimumFaceTile,
                                    spacing: CompoundDesignTokens.space2X,
                                    crossInset: Self.faceAuraRoom) { participant, width in
                    NativeCallStripFace(context: context, participant: participant, width: width)
                }
                .padding(.horizontal, CompoundDesignTokens.space6X)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0), value: stage?.id)
    }
}

/// One face of the Spotlight's strip: the face in its Aura, the name and the muted mark on a glass label, and under it
/// the person's state in one short line (connecting, on hold, translated…).
private struct NativeCallStripFace: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let participant: NativeCallParticipant
    let width: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The face leaves room for its Aura inside the tile, the strip above and below it.
        let size = min(64, width - 24)
        let name = participant.isLocal
            ? L10n.commonYou
            : context.viewState.memberProfiles[participant.userID]?.displayName ?? NativeCallFallbackName.make(mxid: participant.userID)

        VStack(spacing: CompoundDesignTokens.space2X) {
            NativeCallSpeakingRing(userID: participant.userID, diameter: size) {
                NativeCallLetterAvatar(userID: participant.userID,
                                       profile: context.viewState.memberProfiles[participant.userID],
                                       fallbackName: name,
                                       size: size,
                                       mediaProvider: context.mediaProvider)
                    .agentBadge(userID: participant.userID, avatarURL: context.viewState.memberProfiles[participant.userID]?.avatarURL, avatarSize: size)
                    .translationBadge(context.viewState.avatarBadge(for: participant.userID), size: .compact(avatarSize: size),
                                      ring: NativeCallBackdrop.stageRing(context.viewState, isDark: colorScheme == .dark, at: 0.8))
            }

            VStack(spacing: CompoundDesignTokens.space0_5X) {
                HStack(spacing: CompoundDesignTokens.space1X) {
                    if !participant.isAudioEnabled, !participant.isOnHold {
                        Image(systemName: "mic.slash.fill")
                            .font(.compound.bodyXS)
                            .accessibilityLabel(UntranslatedL10n.a11yNativeCallParticipantMuted)
                    }
                    Text(name)
                        .font(.compound.bodyXSSemibold)
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, CompoundDesignTokens.space2X)
                .padding(.vertical, CompoundDesignTokens.space1X)
                .nativeCallSurface(in: Capsule())

                if let state = participant.stateText {
                    Text(state)
                        .font(.compound.bodyXS)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: width)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(width: width)
        .accessibilityElement(children: .combine)
        .accessibilityValue(participant.isSpeaking ? UntranslatedL10n.a11yNativeCallParticipantSpeaking : "")
    }
}

private struct NativeCallPersonFace: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let participant: NativeCallParticipant
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let profile = context.viewState.memberProfiles[participant.userID]
        // The space keeps the speaking rings off the name.
        VStack(spacing: CompoundDesignTokens.space6X) {
            NativeCallSpeakingRing(userID: participant.userID, diameter: size) {
                NativeCallLetterAvatar(userID: participant.userID,
                                       profile: profile,
                                       fallbackName: NativeCallFallbackName.make(mxid: participant.userID),
                                       size: size,
                                       mediaProvider: context.mediaProvider)
                    .agentBadge(userID: participant.userID, avatarURL: context.viewState.memberProfiles[participant.userID]?.avatarURL, avatarSize: size) // Decision 357
                    .translationBadge(context.viewState.avatarBadge(for: participant.userID),
                                      ring: NativeCallBackdrop.stageRing(context.viewState, isDark: colorScheme == .dark, at: 0.4))
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            VStack(spacing: CompoundDesignTokens.space0_5X) {
                HStack(spacing: CompoundDesignTokens.space1X) {
                    if !participant.isAudioEnabled, !participant.isOnHold {
                        Image(systemName: "mic.slash.fill")
                            .font(.compound.bodyXS)
                            .accessibilityLabel(UntranslatedL10n.a11yNativeCallParticipantMuted)
                    }

                    // People, never raw MXIDs (audit A6-5): profiles arrive async. Oneself is "You", as on video.
                    Text(participant.isLocal ? L10n.commonYou : profile?.displayName ?? NativeCallFallbackName.make(mxid: participant.userID))
                        .font(.compound.bodySMSemibold)
                        .lineLimit(1)

                }

                if let stateText {
                    Text(stateText)
                        .font(.compound.bodyXS)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.compound.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(participant.isSpeaking ? UntranslatedL10n.a11yNativeCallParticipantSpeaking : "")
    }

    private var stateText: String? {
        participant.stateText
    }
}

/// L12, one visual everywhere: the translation mark, «文 UA», at an avatar's bottom-trailing edge — the pocket
/// interpreter's on the assistant's page, the language you hear a person in on the stage and on every tile. A blue
/// pill, ringed and not filled while its mode syncs (the look of a job asked for and not on yet), cut out of the field
/// by a ring in the field's own colour. Compact on a tile's small avatar, out on its bottom-trailing corner.
struct NativeCallTranslationBadge: View {
    enum Size: Equatable {
        case regular
        /// On a tile's avatar of this diameter.
        case compact(avatarSize: CGFloat)
    }

    let badge: NativeCallAvatarBadge
    var size = Size.regular
    /// The field's colour under it, for the cut-out ring; nil draws none (the pill over a picture).
    var ring: Color?

    var body: some View {
        // The glyph for translation and the code, which read left to right in every layout direction.
        Text(verbatim: "文 \(NativeCallAgentPillContent.code(badge.language))")
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(badge.isPending ? Color.compound.textPrimary : Color.compound.textOnSolidPrimary)
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, size == .regular ? CompoundDesignTokens.space1_5X : 3)
            .padding(.vertical, size == .regular ? CompoundDesignTokens.space0_5X : 0.5)
            .background(badge.isPending ? Color.clear : Color.compound.bgAccentRest, in: Capsule())
            .overlay {
                if badge.isPending {
                    Capsule().strokeBorder(Color.compound.bgAccentRest, lineWidth: 1.5)
                }
            }
            .padding(ring == nil ? 0 : ringWidth)
            .background(ring ?? .clear, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(badge.accessibilityLabel)
            .animation(.easeInOut(duration: 0.2), value: badge)
    }

    private var font: Font {
        switch size {
        case .regular: .compound.bodyXSSemibold
        // A tile's avatar is small: the smallest text style (11 pt at the default size; Compound's smallest is 12 pt),
        // so the name keeps its width.
        case .compact: .caption2.weight(.semibold)
        }
    }

    private var ringWidth: CGFloat {
        size == .regular ? 3 : 1.5
    }
}

extension View {
    /// L12: `badge` at this avatar's bottom-trailing edge, overlapping it. On a tile's small avatar it sits on the
    /// circle's bottom-trailing point, about half outside it, so it covers little of the face (operator, L12).
    func translationBadge(_ badge: NativeCallAvatarBadge?, size: NativeCallTranslationBadge.Size = .regular, ring: Color) -> some View {
        overlay(alignment: .bottomTrailing) {
            if let badge {
                switch size {
                case .regular:
                    NativeCallTranslationBadge(badge: badge, size: size, ring: ring)
                        .offset(x: CompoundDesignTokens.space1X, y: -CompoundDesignTokens.space1X)
                        .transition(.scale.combined(with: .opacity))
                case .compact(let avatarSize):
                    // Centred on the circle's bottom-trailing point at 45°.
                    let corner = avatarSize / 2 * (1 + 1 / 2.squareRoot())
                    NativeCallTranslationBadge(badge: badge, size: size, ring: ring)
                        .position(x: corner, y: corner)
                        .frame(width: avatarSize, height: avatarSize)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: badge)
    }
}

extension NativeCallParticipant {
    /// Most specific fact first: the media path, then a hold or a reconnection. Speaking and muted have their marks; a
    /// hold outranks the muted mark, the microphone being muted underneath. The translation heard is the badge's.
    var stateText: String? {
        switch mediaState {
        case .connecting: return UntranslatedL10n.screenNativeCallParticipantConnecting
        case .waitingForKeys: return UntranslatedL10n.screenNativeCallParticipantWaitingForKeys
        case .connected: break
        }
        if isOnHold {
            return UntranslatedL10n.screenNativeCallStatusOnHold
        }
        if isReconnecting {
            return UntranslatedL10n.screenNativeCallParticipantReconnecting
        }
        return nil
    }
}
