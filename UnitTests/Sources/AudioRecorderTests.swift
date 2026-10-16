//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import Testing

@MainActor
struct AudioRecorderTests {
    private var audioRecorder: AudioRecorder!
    private var audioSessionMock: AudioSessionMock!
    
    init() async {
        audioSessionMock = AudioSessionMock()
        audioSessionMock.requestRecordPermissionClosure = { completion in
            completion(true)
        }
        audioRecorder = AudioRecorder(audioSession: audioSessionMock)
    }
    
    /// AGENT-PLATFORM (Brief 0063): the call screen minimises, so the composer
    /// and its mic button stay reachable for the whole call. Recording used to
    /// take `.playAndRecord, mode: .default` — dropping the call's `.voiceChat`
    /// and with it the echo cancellation and receiver routing — and then
    /// deactivate the session on release, which ended the call's audio for
    /// good with no way back short of hanging up.
    @Test
    mutating func recordingIsRefusedWhileACallOwnsTheAudioSession() async throws {
        NativeCallAudioSession.setHeldByCall(true)
        defer { NativeCallAudioSession.setHeldByCall(false) }

        let deferred = deferFulfillment(audioRecorder.actions) { action in
            switch action {
            case .didFailWithError(.audioSessionFailure):
                return true
            default:
                return false
            }
        }
        let url = URL.temporaryDirectory.appendingPathComponent("test-voice-message").appendingPathExtension("m4a")
        await audioRecorder.record(audioFileURL: url)
        try await deferred.fulfill()

        #expect(!audioRecorder.isRecording)
        #expect(!audioSessionMock.setCategoryModeOptionsCalled,
                "the call's category must be left exactly as it is")
        #expect(!audioSessionMock.setActiveOptionsCalled,
                "and its session must never be deactivated")
    }

    @Test
    mutating func recordWithoutPermission() async throws {
        audioSessionMock.requestRecordPermissionClosure = { completion in
            completion(false)
        }
        
        let deferred = deferFulfillment(audioRecorder.actions) { action in
            switch action {
            case .didFailWithError(.recordPermissionNotGranted):
                return true
            default:
                return false
            }
        }
        let url = URL.temporaryDirectory.appendingPathComponent("test-voice-message").appendingPathExtension("m4a")
        await audioRecorder.record(audioFileURL: url)
        try await deferred.fulfill()
        #expect(!audioRecorder.isRecording)
    }
}
