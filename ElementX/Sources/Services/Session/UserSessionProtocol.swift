//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

enum UserSessionCallback {
    case didReceiveAuthError(isSoftLogout: Bool)
}

struct SessionSecurityState: Equatable {
    let verificationState: SessionVerificationState
    let recoveryState: SecureBackupRecoveryState
}

// sourcery: AutoMockable
protocol UserSessionProtocol: Sendable {
    var clientProxy: ClientProxyProtocol { get }
    var userSettings: UserSettings { get }
    var userHooks: UserHooks { get }
    
    var mediaProvider: MediaProviderProtocol { get }
    var voiceMessageMediaManager: VoiceMessageMediaManagerProtocol { get }
    var liveLocationService: LiveLocationServiceProtocol { get }
    /// Scans media content, `nil` when no content scanner is configured for the server.
    var contentScannerService: ContentScannerServiceProtocol? { get }
    var notificationService: NotificationServiceProtocol { get }
    
    var sessionSecurityStatePublisher: CurrentValuePublisher<SessionSecurityState, Never> { get }
    
    var callbacks: PassthroughSubject<UserSessionCallback, Never> { get }

    // AGENT-PLATFORM: typed REST client for `/api/v1/*` on the
    // Agent Platform backend (`spiral.md`). Constructed in
    // `UserSessionStore::buildUserSessionWithClient` alongside
    // the rest of the session-scoped services; bearer-token
    // resolution flows through `MatrixSDKAuthBridge` which
    // reads the MAS session token from the keychain.
    //
    // Optional because (a) the bridge can fail to build if the
    // backend base URL is malformed in `AppSettings`, in which
    // case we'd rather degrade gracefully than block login; and
    // (b) it keeps the surface backward-compatible for the
    // UI-tests app coordinator + the existing mock generator.
    var agentPlatformService: AgentPlatformServiceProtocol? { get }

    // AGENT-PLATFORM: platform sync (decision 289): the Agents tab's store,
    // one per session, fed by the session's sync stream. `nil` with
    // `agentPlatformService`.
    var agentsStore: AgentsStore? { get }

    // AGENT-PLATFORM: platform sync (decision 289): the feed's store and the
    // session's one stream feeding both stores, started and stopped by the
    // session flow. `nil` with `agentPlatformService`.
    var feedStore: FeedStore? { get }
    var platformSync: PlatformSync? { get }
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083): who is online, for the DM
    // header and the room list. Session-scoped so two screens share one
    // cache and one poll. Optional for the mocks and the UI-tests session.
    var presenceObserverService: PresenceObserverServiceProtocol? { get }
}
