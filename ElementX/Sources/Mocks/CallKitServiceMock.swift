//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

struct CallKitServiceMockConfiguration {
    var ongoingCallRoomID: String?
}

extension CallKitServiceMock {
    convenience init(_ configuration: CallKitServiceMockConfiguration) {
        self.init()
        
        actions = PassthroughSubject().eraseToAnyPublisher()
        ongoingCallRoomIDPublisher = .init(.init(configuration.ongoingCallRoomID))
        heldCallPublisher = .init(.init(nil))
        // CallKit does not carry the change unless a test says so — the
        // screen applies it directly, the simulator's own behaviour.
        requestAudioEnabledRoomIDReturnValue = false
    }
}
