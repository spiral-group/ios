//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct JoinCallButton: View {
    let isVoiceCall: Bool
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26, *) {
            glassButton
        } else {
            customButton
        }
    }
    
    var glassButton: some View {
        Button(action: action) {
            // AGENT-PLATFORM (Brief 0083, decision 344): the icon alone, in the call button's place. The word beside the
            // centred capsule left a long name three letters in ru («Присоединиться»). VoiceOver still says it.
            CompoundIcon(isVoiceCall ? \.voiceCallSolid : \.videoCallSolid)
                .foregroundStyle(.compound.textOnSolidPrimary)
        }
        .tint(.compound.bgActionPrimaryRest)
        .backportButtonStyleGlassProminent()
        .accessibilityLabel(L10n.a11yJoinCall)
    }
    
    var customButton: some View {
        Button(action: action) {
            CompoundIcon(isVoiceCall ? \.voiceCallSolid : \.videoCallSolid) // AGENT-PLATFORM (Brief 0083, decision 344)
        }
        .buttonStyle(CustomStyle())
        .accessibilityLabel(L10n.a11yJoinCall)
    }
    
    struct CustomStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.horizontal, 16.0)
                .padding(.vertical, 4.0)
                // AGENT-PLATFORM (Brief 0083, decision 306): white on the filled blue, 4.81:1 in both themes.
                // It was the canvas colour on the icon blue: black on #0A84FF in dark.
                .foregroundColor(.compound.textOnSolidPrimary)
                .background(Color.compound.bgActionPrimaryRest)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Previews

struct JoinCallButton_Previews: PreviewProvider {
    static var previews: some View {
        ElementNavigationStack {
            Color.clear
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        JoinCallButton(isVoiceCall: false) { }
                    }
                }
        }
        .previewDisplayName("Join Video Call")
        
        ElementNavigationStack {
            Color.clear
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        JoinCallButton(isVoiceCall: true) { }
                    }
                }
        }
        .previewDisplayName("Join Audio Call")
    }
}
