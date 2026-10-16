//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

class UserSession: UserSessionProtocol {
    private var cancellables = Set<AnyCancellable>()
    
    private var authErrorCancellable: AnyCancellable?
    
    let clientProxy: ClientProxyProtocol
    let mediaProvider: MediaProviderProtocol
    
    let voiceMessageMediaManager: VoiceMessageMediaManagerProtocol
    let liveLocationManager: LiveLocationManagerProtocol

    // AGENT-PLATFORM: typed REST client for our `/api/v1/*` surface.
    // Built in `UserSessionStore::buildUserSessionWithClient`;
    // optional so a misconfigured backend URL or constructor failure
    // degrades gracefully rather than blocking login.
    let agentPlatformService: AgentPlatformServiceProtocol?

    // AGENT-PLATFORM: live approvals SSE service (S151). Same
    // optionality contract as `agentPlatformService`. Connects
    // automatically when AppCoordinator detects foreground; the
    // initial connect happens after the AgentSpacesScreen
    // first appears so we don't burn a socket for users who
    // never tap the Agents tab.
    let approvalsStreamService: ApprovalsStreamServiceProtocol?
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083)
    let presenceObserverService: PresenceObserverServiceProtocol?
    // AGENT-PLATFORM (Brief 0072, ADR-0084): keeps «Share presence» and the
    // account data the server's privacy rule reads in step. Held, not exposed.
    private let sharePresenceSettingSync: SharePresenceSettingSync?
    // AGENT-PLATFORM (decision 98): the owner's messenger blocks reach their
    // agents. Held, not exposed: the service asks it for a resync.
    private let ownerBlocksSync: OwnerBlocksSync?

    /// Scans media content, `nil` when no content scanner is configured for the server.
    let contentScannerService: ContentScannerServiceProtocol?
    
    let callbacks = PassthroughSubject<UserSessionCallback, Never>()
    
    let sessionSecurityStateSubject = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
    var sessionSecurityStatePublisher: CurrentValuePublisher<SessionSecurityState, Never> {
        sessionSecurityStateSubject.asCurrentValuePublisher()
    }
    
    init(clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         voiceMessageMediaManager: VoiceMessageMediaManagerProtocol,
         liveLocationManager: LiveLocationManagerProtocol,
         agentPlatformService: AgentPlatformServiceProtocol? = nil,
         approvalsStreamService: ApprovalsStreamServiceProtocol? = nil,
         presenceObserverService: PresenceObserverServiceProtocol? = nil,
         sharePresenceSettingSync: SharePresenceSettingSync? = nil,
         ownerBlocksSync: OwnerBlocksSync? = nil) {
        self.clientProxy = clientProxy
        self.mediaProvider = mediaProvider
        self.voiceMessageMediaManager = voiceMessageMediaManager
        self.liveLocationManager = liveLocationManager
        self.agentPlatformService = agentPlatformService
        self.approvalsStreamService = approvalsStreamService
        self.presenceObserverService = presenceObserverService
        self.sharePresenceSettingSync = sharePresenceSettingSync
        self.ownerBlocksSync = ownerBlocksSync
        contentScannerService = clientProxy.contentScanner.map(ContentScannerService.init)
        
        authErrorCancellable = clientProxy.actionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] callback in
                guard let self else { return }
                switch callback {
                case .receivedAuthError(let isSoftLogout):
                    callbacks.send(.didReceiveAuthError(isSoftLogout: isSoftLogout))
                    authErrorCancellable = nil
                default:
                    break
                }
            }
        
        Publishers.CombineLatest(clientProxy.verificationStatePublisher, clientProxy.secureBackupController.recoveryState)
            .map {
                MXLog.info("Session security state changed, verificationState: \($0), recoveryState: \($1)")
                return SessionSecurityState(verificationState: $0, recoveryState: $1)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sessionSecurityStateSubject.send(value)
            }
            .store(in: &cancellables)
    }
}
