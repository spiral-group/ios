//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRustSDK

extension KeychainControllerMock {
    struct Configuration {
        var restorationTokens: [KeychainCredentials] = []
    }
    
    convenience init(_ configuration: Configuration) {
        self.init()
        
        restorationTokensReturnValue = configuration.restorationTokens
    }
}

/// Adds the missing methods for conformance to the protocol.
extension KeychainControllerMock {
    // AGENT-PLATFORM: a mock that traps took the test runner down with it; a missing session is the honest answer.
    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        throw ClientError.Generic(msg: "KeychainControllerMock holds no sessions.", details: nil)
    }
    
    func saveSessionInKeychain(session: Session) { }
}
