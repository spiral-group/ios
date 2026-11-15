//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks

extension ClientFactoryMock {
    struct Configuration {
        var homeserverClients = [
            "matrix.org": ClientSDKMock(.init()),
            "https://matrix-client.matrix.org": ClientSDKMock(.init()),
            "example.com": ClientSDKMock(.init(serverName: "example.com",
                                               homeserverURL: "https://matrix.example.com",
                                               slidingSyncVersion: .native,
                                               oAuthLoginURL: nil,
                                               supportsOAuthCreatePrompt: false,
                                               supportsPasswordLogin: true)),
            "company.com": ClientSDKMock(.init(serverName: "company.com",
                                               homeserverURL: "https://matrix.company.com",
                                               slidingSyncVersion: .native,
                                               oAuthLoginURL: "https://auth.company.com/login",
                                               supportsOAuthCreatePrompt: false,
                                               supportsPasswordLogin: false)),
            "server.net": ClientSDKMock(.init(serverName: "server.net",
                                              homeserverURL: "https://matrix.server.net",
                                              slidingSyncVersion: .native,
                                              oAuthLoginURL: nil,
                                              supportsOAuthCreatePrompt: false,
                                              supportsPasswordLogin: false))
            // AGENT-PLATFORM (Brief 0083 L1b): no secure.gov, the Element Pro server.
        ]
    }
    
    convenience init(_ configuration: Configuration) {
        self.init()
        
        makeAuthenticationClientServerNameOrBaseURLSessionDirectoriesPassphraseClientSessionDelegateAppSettingsAppHooksClosure = { address, _, _, _, _, _ in
            guard let client = configuration.homeserverClients[address] else {
                throw ClientBuildError.ServerUnreachable(message: "Not a known homeserver.")
            }
            return client
        }
        
        // AGENT-PLATFORM (Brief 0083 L1b): no makeInMemoryClient.
        
        makeAppClientCredentialsClientSessionDelegateAppSettingsAppHooksClosure = { credentials, _, _, _ in
            ClientSDKMock(.init(userID: credentials.userID))
        }
        
        makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderClosure = { credentials, _, _, _, _, _ in
            ClientSDKMock(.init(userID: credentials.userID))
        }
    }
}
