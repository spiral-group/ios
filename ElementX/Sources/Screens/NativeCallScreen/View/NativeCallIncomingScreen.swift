//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063, native call UI Phase 6 / G15): the in-app
// incoming call screen (`01 · Incoming · in-app`).
//
// CallKit owns the primary incoming path — locked device, system ring,
// Recents. This surface exists ONLY for the cases CallKit does not cover:
// a build/region where CallKit is unavailable (the `reportNewIncomingCall`
// failure path) and, later, a group ring. It carries the same
// accept/decline semantics and must never appear alongside a CallKit ring
// for the same call — the ONE call site that presents it is the CallKit
// failure branch.

import Combine
import Compound
import SpiralTokens
import SwiftUI

enum NativeCallIncomingScreenAction {
    case accept
    case decline
}

@MainActor
final class NativeCallIncomingScreenCoordinator: CoordinatorProtocol {
    struct Parameters {
        let callerDisplayName: String
        /// The caller's avatar thumbnail as the VoIP push carried it. Raw
        /// `Data` rather than a URL: this screen can ring before any media
        /// provider is reachable — the push is the only source there is.
        let callerAvatarData: Data?
        let isVoiceCall: Bool
        /// The design's agent preflight line ("Your assistant will join ·
        /// EN · UK"); nil hides the row. Filled by the caller when the
        /// room's standing rules are known.
        let agentPreflightText: String?
    }

    private let parameters: Parameters
    private let actionsSubject: PassthroughSubject<NativeCallIncomingScreenAction, Never> = .init()
    var actions: AnyPublisher<NativeCallIncomingScreenAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: Parameters) {
        self.parameters = parameters
    }

    /// The user's decision, as the screen's buttons send it.
    func send(_ action: NativeCallIncomingScreenAction) {
        actionsSubject.send(action)
    }

    func toPresentable() -> AnyView {
        AnyView(NativeCallIncomingScreen(callerDisplayName: parameters.callerDisplayName,
                                         callerAvatarData: parameters.callerAvatarData,
                                         isVoiceCall: parameters.isVoiceCall,
                                         agentPreflightText: parameters.agentPreflightText) { [weak self] action in
                self?.send(action)
            })
    }
}

struct NativeCallIncomingScreen: View {
    let callerDisplayName: String
    var callerAvatarData: Data?
    let isVoiceCall: Bool
    let agentPreflightText: String?
    let onAction: (NativeCallIncomingScreenAction) -> Void

    /// The caller's picture fills the screen, as in the call itself (Brief 0083, decision 340).
    var body: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            Spacer(minLength: 0)

            identity

            Spacer(minLength: 0)

            // What will happen once answered: a fact, not a control, so plain words. No glyph: the push carries no
            // assistant to draw, and sparkles mark agents as a function, never an assistant as an entity (critique F5).
            if let agentPreflightText {
                Text(agentPreflightText)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, CompoundDesignTokens.space6X)
            }

            // The Phone app's pair: Decline leading, Accept trailing, each a large round button over its word.
            HStack(alignment: .top, spacing: 0) {
                answerButton(title: L10n.actionDecline, icon: \.endCall, background: .compound.bgCriticalPrimary) {
                    onAction(.decline)
                }
                .frame(maxWidth: .infinity)

                // The green white reads on in both themes (decision 307).
                answerButton(title: L10n.actionAccept,
                             icon: isVoiceCall ? \.voiceCall : \.videoCall,
                             background: .spiral.successFill) {
                    onAction(.accept)
                }
                .frame(maxWidth: .infinity)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, CompoundDesignTokens.space6X)
            .padding(.bottom, CompoundDesignTokens.space8X)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            NativeCallBackdrop(photoData: callerAvatarData, tone: .wash)
                .ignoresSafeArea()
        }
    }

    private var callerPhoto: UIImage? {
        callerAvatarData.flatMap(UIImage.init(data:))
    }

    /// `01 · Incoming · in-app`: the face, then the kind, the name and the fact, in the calling screen's places.
    /// Only the ink reads on the backdrop.
    private var identity: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            // The push's avatar thumbnail when it carried one; the monogram without.
            Group {
                if let callerPhoto {
                    Image(uiImage: callerPhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: SpiralAvatarSize.xLarge, height: SpiralAvatarSize.xLarge)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                } else {
                    NativeCallLetterAvatar(userID: nil,
                                           profile: nil,
                                           fallbackName: callerDisplayName,
                                           size: SpiralAvatarSize.xLarge,
                                           mediaProvider: nil)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            VStack(spacing: CompoundDesignTokens.space2X) {
                Text(isVoiceCall
                    ? UntranslatedL10n.screenNativeCallIncomingVoice
                    : UntranslatedL10n.screenNativeCallIncomingVideo)
                    .font(.compound.bodyMD)

                Text(callerDisplayName)
                    .font(.compound.headingXLBold)
                    .multilineTextAlignment(.center)

                Text(UntranslatedL10n.screenNativeCallIncomingIsCalling)
                    .font(.compound.headingSM)
            }
        }
        .foregroundStyle(.compound.textPrimary)
        .padding(.horizontal, CompoundDesignTokens.space6X)
    }

    private func answerButton(title: String,
                              icon: KeyPath<CompoundIcons, Image>,
                              background: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: CompoundDesignTokens.space2X) {
                CompoundIcon(icon, size: .custom(30), relativeTo: .compound.headingLG)
                    .foregroundStyle(.compound.iconOnSolidPrimary)
                    .frame(width: 76, height: 76)
                    .background(background, in: Circle())

                Text(title)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Previews

struct NativeCallIncomingScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        NativeCallIncomingScreen(callerDisplayName: "Marta Illienko",
                                 isVoiceCall: false,
                                 agentPreflightText: "Your assistant will join · EN · UK") { _ in }
            .previewDisplayName("Incoming video")

        NativeCallIncomingScreen(callerDisplayName: "Marta Illienko",
                                 isVoiceCall: true,
                                 agentPreflightText: nil) { _ in }
            .previewDisplayName("Incoming voice")

        NativeCallIncomingScreen(callerDisplayName: "Marta Illienko",
                                 callerAvatarData: Bundle.main.url(forResource: "preview_avatar_user", withExtension: "jpg")
                                     .flatMap { try? Data(contentsOf: $0) },
                                 isVoiceCall: true,
                                 agentPreflightText: "Your assistant will join · EN · UK") { _ in }
            .previewDisplayName("Incoming with a photo")
    }
}
