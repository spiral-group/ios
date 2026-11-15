//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct RoomCallControlsToolbar: ToolbarContent {
    let viewState: RoomScreenViewState
    let onCallTap: (_ isVoiceCall: Bool) -> Void
    
    // AGENT-PLATFORM (Brief 0083, decision 344): one quiet call button. It opens a menu in a DM and in a group alike, so
    // a stray tap can't ring anyone. A call on in the room is Join, in its place.
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if viewState.hasOngoingCall {
                JoinCallButton(isVoiceCall: viewState.activeRoomCallIntent == .audio) {
                    onCallTap(viewState.activeRoomCallIntent == .audio)
                }
                .accessibilityIdentifier(A11yIdentifiers.roomScreen.joinCall)
                .disabled(!viewState.canJoinCall)
            } else {
                Menu {
                    // AGENT-PLATFORM (Brief 0063): native group voice call button.
                    if viewState.isDM || viewState.canStartGroupVoiceCall {
                        Button {
                            onCallTap(true)
                        } label: {
                            Label(L10n.actionVoiceCall, icon: \.voiceCallSolid)
                        }
                        .accessibilityIdentifier(A11yIdentifiers.roomScreen.startVoiceCall)
                    }
                    
                    Button {
                        onCallTap(false)
                    } label: {
                        Label(L10n.actionVideoCall, icon: \.videoCallSolid)
                    }
                    .accessibilityIdentifier(A11yIdentifiers.roomScreen.startVideoCall)
                } label: {
                    CompoundIcon(\.voiceCall)
                }
                .accessibilityLabel(L10n.a11yStartCall)
                .disabled(!viewState.canJoinCall)
            }
        }
    }
}

// MARK: - Previews

struct RoomCallControlsToolbar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            ElementNavigationStack {
                Color.clear.toolbar { RoomCallControlsToolbar(viewState: .mock(hasOngoingCall: true)) { _ in } }
            }
            ElementNavigationStack {
                Color.clear.toolbar { RoomCallControlsToolbar(viewState: .mock(hasOngoingCall: false, isDM: true)) { _ in } }
            }
            
            ElementNavigationStack {
                Color.clear.toolbar { RoomCallControlsToolbar(viewState: .mock(hasOngoingCall: false)) { _ in } }
            }
            ElementNavigationStack { // AGENT-PLATFORM (Brief 0063)
                Color.clear.toolbar { RoomCallControlsToolbar(viewState: .mock(hasOngoingCall: false, canStartGroupVoiceCall: true)) { _ in } }
            }
            ElementNavigationStack {
                Color.clear.toolbar { RoomCallControlsToolbar(viewState: .mock(hasOngoingCall: false, canJoinCall: false)) { _ in } }
            }
            ElementNavigationStack {
                Color.clear.toolbar { RoomCallControlsToolbar(viewState: .mock(hasOngoingCall: true, activeRoomCallIntent: .audio)) { _ in } }
            }
        }
        .previewDisplayName("All states")
    }
}

private extension RoomScreenViewState {
    // AGENT-PLATFORM (Brief 0063): `canStartGroupVoiceCall` knob added to the preview mock.
    static func mock(hasOngoingCall: Bool,
                     isDM: Bool = false,
                     canJoinCall: Bool = true,
                     activeRoomCallIntent: CallIntent? = nil,
                     canStartGroupVoiceCall: Bool = false) -> RoomScreenViewState {
        var state = RoomScreenViewState(roomAvatar: .room(id: "mock", name: "Mock Room", avatarURL: nil),
                                        canJoinCall: canJoinCall,
                                        hasOngoingCall: hasOngoingCall,
                                        activeRoomCallIntent: activeRoomCallIntent,
                                        isDM: isDM,
                                        hasSuccessor: false)
        state.canStartGroupVoiceCall = canStartGroupVoiceCall
        return state
    }
}
