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
    var mediaProvider: MediaProviderProtocol { get }
    var voiceMessageMediaManager: VoiceMessageMediaManagerProtocol { get }
    var liveLocationManager: LiveLocationManagerProtocol { get }
    
    /// Scans media content, `nil` when no content scanner is configured for the server.
    var contentScannerService: ContentScannerServiceProtocol? { get }
    
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

    // AGENT-PLATFORM: long-lived SSE subscription to
    // `/api/v1/approvals/stream`. UserSession-scope per
    // DECISIONS.md ("ApprovalsStreamService lives at UserSession
    // scope"). Same optionality contract as `agentPlatformService`
    // — nil if the bridge couldn't build. Lifecycle managed by
    // `AppCoordinator` foreground/background hooks (S151+).
    var approvalsStreamService: ApprovalsStreamServiceProtocol? { get }
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083): who is online, for the DM
    // header and the room list. Session-scoped so two screens share one
    // cache and one poll. Optional for the mocks and the UI-tests session.
    var presenceObserverService: PresenceObserverServiceProtocol? { get }
}
