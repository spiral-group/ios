//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import Foundation
import SwiftUI

// AGENT-PLATFORM (Brief 0083): the recording is drawn in the composer's field, with its stop button inside the
// field's trailing end as the microphone was. It was a grey box beside a separate stop button.
struct VoiceMessageRecordingComposer<Trailing: View>: View {
    @ObservedObject var recorderState: AudioRecorderState
    let trailing: Trailing
    
    var body: some View {
        VoiceMessageRecordingView(recorderState: recorderState)
            .padding(.leading, CompoundDesignTokens.space2X)
            .messageComposerStyle(trailing: trailing, insetsContent: false)
    }
}

// MARK: - Previews

struct VoiceMessageRecordingComposer_Previews: PreviewProvider, TestablePreview {
    static let recorderState = AudioRecorderState()
    
    static var previews: some View {
        VoiceMessageRecordingComposer(recorderState: recorderState, trailing: VoiceMessageRecordingButton(mode: .recording)) // AGENT-PLATFORM (Brief 0083)
            .fixedSize(horizontal: false, vertical: true)
    }
}
