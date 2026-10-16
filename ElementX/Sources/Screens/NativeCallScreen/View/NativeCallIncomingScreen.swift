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

    var body: some View {
        VStack(spacing: 0) {
            // `01 · Incoming · in-app`: everything about WHO leads from
            // the top — the kind, the face, the name, the fact.
            VStack(spacing: 16) {
                Text(isVoiceCall
                    ? UntranslatedL10n.screenNativeCallIncomingVoice
                    : UntranslatedL10n.screenNativeCallIncomingVideo)
                    .font(.body)
                    .foregroundStyle(Color(.tertiaryLabel))

                // The push's avatar thumbnail when it carried one; the
                // letter placeholder was all this screen ever showed even
                // when the caller's picture was sitting in the payload.
                if let callerAvatarData, let avatar = UIImage(data: callerAvatarData) {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 160, height: 160)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                } else {
                    NativeCallLetterAvatar(userID: nil,
                                           profile: nil,
                                           fallbackName: callerDisplayName,
                                           size: 160,
                                           mediaProvider: nil)
                }

                VStack(spacing: 8) {
                    Text(callerDisplayName)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(UntranslatedL10n.screenNativeCallIncomingIsCalling)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 24)

            Spacer()

            // The agent preflight pill sits alone mid-screen — a fact
            // about what will happen, not a control.
            if let agentPreflightText {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGroupedBackground), in: Circle())

                    Text(agentPreflightText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                .padding(.trailing, 20)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }

            Spacer()

            HStack(spacing: 0) {
                Spacer()

                answerButton(title: L10n.actionDecline,
                             icon: \.endCall,
                             background: .compound.iconCriticalPrimary) {
                    onAction(.decline)
                }

                Spacer()
                Spacer()

                answerButton(title: L10n.actionAccept,
                             icon: isVoiceCall ? \.voiceCall : \.videoCall,
                             background: .compound.iconSuccessPrimary) {
                    onAction(.accept)
                }

                Spacer()
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private func answerButton(title: String,
                              icon: KeyPath<CompoundIcons, Image>,
                              background: Color,
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                CompoundIcon(icon, size: .medium, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(background, in: Circle())
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

struct NativeCallIncomingScreen_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        NativeCallIncomingScreen(callerDisplayName: "Marta Illienko",
                                 isVoiceCall: false,
                                 agentPreflightText: "Your assistant will join · EN · UK") { _ in }
            .previewDisplayName("Incoming video")

        NativeCallIncomingScreen(callerDisplayName: "Marta Illienko",
                                 isVoiceCall: true,
                                 agentPreflightText: nil) { _ in }
            .previewDisplayName("Incoming voice")
    }
}
