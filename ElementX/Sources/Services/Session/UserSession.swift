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
    let userSettings: UserSettings
    let userHooks: UserHooks
    
    let mediaProvider: MediaProviderProtocol
    let voiceMessageMediaManager: VoiceMessageMediaManagerProtocol
    let liveLocationService: LiveLocationServiceProtocol

    // AGENT-PLATFORM: typed REST client for our `/api/v1/*` surface.
    // Built in `UserSessionStore::buildUserSessionWithClient`;
    // optional so a misconfigured backend URL or constructor failure
    // degrades gracefully rather than blocking login.
    let agentPlatformService: AgentPlatformServiceProtocol?

    // AGENT-PLATFORM: platform sync (decision 289): the Agents tab's one store,
    // fed by the session's sync stream. There with `agentPlatformService` only.
    let agentsStore: AgentsStore?
    // AGENT-PLATFORM: platform sync (decision 289): the feed's one store and the
    // session's one stream, which feeds both stores. The session flow starts it
    // and stops it on sign-out; no tab owns it.
    let feedStore: FeedStore?
    let platformSync: PlatformSync?
    
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
    let notificationService: NotificationServiceProtocol
    
    let callbacks = PassthroughSubject<UserSessionCallback, Never>()
    
    let sessionSecurityStateSubject = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
    var sessionSecurityStatePublisher: CurrentValuePublisher<SessionSecurityState, Never> {
        sessionSecurityStateSubject.asCurrentValuePublisher()
    }
    
    init(clientProxy: ClientProxyProtocol,
         userSettings: UserSettings,
         userHooks: UserHooks,
         mediaProvider: MediaProviderProtocol,
         voiceMessageMediaManager: VoiceMessageMediaManagerProtocol,
         liveLocationService: LiveLocationServiceProtocol,
         notificationService: NotificationServiceProtocol,
         agentPlatformService: AgentPlatformServiceProtocol? = nil, // AGENT-PLATFORM
         presenceObserverService: PresenceObserverServiceProtocol? = nil,
         sharePresenceSettingSync: SharePresenceSettingSync? = nil,
         ownerBlocksSync: OwnerBlocksSync? = nil) {
        self.clientProxy = clientProxy
        self.userSettings = userSettings
        self.userHooks = userHooks
        
        self.mediaProvider = mediaProvider
        self.voiceMessageMediaManager = voiceMessageMediaManager
        self.liveLocationService = liveLocationService
        self.notificationService = notificationService
        self.agentPlatformService = agentPlatformService
        // AGENT-PLATFORM: platform sync (decision 289)
        let agentsStore = agentPlatformService.map { AgentsStore(service: $0) }
        self.agentsStore = agentsStore
        let feedStore = agentPlatformService.map { FeedStore(feedService: $0.feed, currentUserID: clientProxy.userID) }
        self.feedStore = feedStore
        platformSync = if let agentPlatformService, let feedStore {
            PlatformSync(service: agentPlatformService.sync, feedStore: feedStore, agentsStore: agentsStore)
        } else {
            nil
        }
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
