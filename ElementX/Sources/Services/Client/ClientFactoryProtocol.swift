//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

// sourcery: AutoMockable
nonisolated protocol ClientFactoryProtocol {
    // MARK: Authentication
    
    #if IS_MAIN_APP
    func makeAuthenticationClient(serverNameOrBaseURL: String,
                                  sessionDirectories: SessionDirectories,
                                  passphrase: Data,
                                  clientSessionDelegate: ClientSessionDelegate,
                                  appSettings: AppSettings,
                                  appHooks: AppHooks) async throws -> ClientProtocol
    
    // AGENT-PLATFORM (Brief 0083 L1b): no makeInMemoryClient, only Element Classic's account check used it.
    
    // MARK: Restoration
    
    func makeAppClient(credentials: KeychainCredentials,
                       clientSessionDelegate: ClientSessionDelegate,
                       appSettings: AppSettings,
                       appHooks: AppHooks) async throws -> ClientProtocol
    #endif
    
    func makeNSEClient(credentials: KeychainCredentials,
                       roomID: String,
                       clientSessionDelegate: ClientSessionDelegate,
                       userSettings: UserSettings,
                       appHooks: AppHooks,
                       lockHolder: NSEClientLockHolder) async throws -> ClientProtocol // AGENT-PLATFORM: feed (Brief 0082)
}

// AGENT-PLATFORM: feed (Brief 0082). The SDK's cross-process lease is shared by
// every client that names the same holder, even two in one process: both would
// refresh at once and exchange the same refresh token, which MAS answers by
// revoking a pair. The feed's refresher names its own holder, so its refresh
// waits for a Matrix push's refresh and then finds the new token in the store.
nonisolated enum NSEClientLockHolder: Equatable {
    /// A Matrix push's client.
    case notification
    /// The feed push's token refresher.
    case feedTokenRefresh

    func name(bundleIdentifier: String = InfoPlistReader.main.bundleIdentifier) -> String {
        switch self {
        case .notification: bundleIdentifier
        case .feedTokenRefresh: "\(bundleIdentifier).feed"
        }
    }
}
