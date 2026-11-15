//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

enum VoiceMessageRecordingButtonMode {
    case idle
    case recording
}

struct VoiceMessageRecordingButton: View {
    @Environment(\.isEnabled) private var isEnabled
    
    let mode: VoiceMessageRecordingButtonMode
    var startRecording: (() -> Void)?
    var stopRecording: (() -> Void)?
    
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()
    
    private var recordIconColour: Color {
        guard isEnabled else { return .compound.textDisabled } // AGENT-PLATFORM: Spiral's iconDisabled is #E5E5EA in light mode
        // AGENT-PLATFORM (Brief 0083): grey inside the field, as Messages draws it, and on glass what the placeholder is:
        // the picture's blue leaves the icon's grey at 2.87:1.
        return Compound.supportsGlass ? SpiralComposerMetrics.chatPlaceholder : .compound.iconSecondary
    }
    
    var body: some View {
        Button {
            impactFeedbackGenerator.impactOccurred()
            switch mode {
            case .idle:
                startRecording?()
            case .recording:
                stopRecording?()
            }
        } label: {
            switch mode {
            // AGENT-PLATFORM (Brief 0083): the field's action, inside its trailing end. The microphone is a glyph without
            // a disc, and stop a white square on red as a recording's control is in iOS. They were 44 pt glass discs.
            case .idle:
                CompoundIcon(\.micOn,
                             size: Compound.supportsGlass ? .medium : .small,
                             relativeTo: .compound.headingLG)
                    .foregroundColor(recordIconColour)
                    .spiralComposerAction()
            case .recording:
                CompoundIcon(\.stopSolid,
                             size: .small,
                             relativeTo: .compound.headingLG)
                    .foregroundColor(.compound.iconOnSolidPrimary)
                    .spiralComposerAction()
                    .background(.compound.bgCriticalPrimary, in: .circle)
                    .compositingGroup()
            }
        }
        .buttonStyle(VoiceMessageRecordingButtonStyle())
        .accessibilityLabel(mode == .idle ? L10n.a11yVoiceMessageRecord : L10n.a11yVoiceMessageStopRecording)
    }
}

// AGENT-PLATFORM (Brief 0083): the field's glass is the button's surface, so it has none of its own.
private struct VoiceMessageRecordingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct VoiceMessageRecordingButton_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        HStack(spacing: 12) {
            VoiceMessageRecordingButton(mode: .idle)
                .disabled(true)
            VoiceMessageRecordingButton(mode: .idle)
            VoiceMessageRecordingButton(mode: .recording)
        }
    }
}
