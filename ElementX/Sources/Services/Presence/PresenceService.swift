//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import UIKit

final class PresenceService {
    private let clientProxy: ClientProxyProtocol
    private let userSettings: UserSettings
    private let notificationCenter: NotificationCenter
    
    private var isForegroundActive: Bool
    private var lastSentPresence: ClientProxyPresence?
    private var pendingPresence: ClientProxyPresence?
    private var sendTask: Task<Void, Never>?
    /// AGENT-PLATFORM (1.0.3): set when the session ends; a stopped service sends nothing again.
    private var isStopped = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init(clientProxy: ClientProxyProtocol,
         userSettings: UserSettings,
         notificationCenter: NotificationCenter = .default,
         initialApplicationState: UIApplication.State = UIApplication.shared.applicationState) {
        self.clientProxy = clientProxy
        self.userSettings = userSettings
        self.notificationCenter = notificationCenter
        isForegroundActive = initialApplicationState != .background // AGENT-PLATFORM: inactive is on screen (e.g. Face ID at launch)
        
        observeApplicationState()
        observeSharePresence()
        reportCurrentState()
    }
    
    isolated deinit {
        sendTask?.cancel()
        cancellables.forEach { $0.cancel() }
    }

    /// AGENT-PLATFORM (1.0.3): ends the service with its session. The flow
    /// that owns it can outlive the session (the soft-logout screen keeps it;
    /// leaked screens may too), and every foreground would otherwise send a
    /// presence PUT with the ended session's token.
    func stop() {
        isStopped = true
        pendingPresence = nil
        sendTask?.cancel()
        sendTask = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    private var desiredPresence: ClientProxyPresence {
        switch (isForegroundActive, userSettings.account.sharePresence) {
        case (true, true):
            .online
        case (true, false):
            .offline
        case (false, true):
            .unavailable
        case (false, false):
            .offline
        }
    }
    
    private func observeApplicationState() {
        // AGENT-PLATFORM: away on entering the background, not on resigning active — a Notification Centre pull
        // resigned and re-activated, two presence PUTs Synapse rate-limits (docs/project/DECISIONS.md, 2026-11-18).
        notificationCenter.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.apply(applicationState: .background)
            }
            .store(in: &cancellables)
        
        notificationCenter.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.apply(applicationState: .active)
            }
            .store(in: &cancellables)
    }
    
    private func observeSharePresence() {
        userSettings.account.sharePresencePublisher
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reportCurrentState()
            }
            .store(in: &cancellables)
    }
    
    private func apply(applicationState: UIApplication.State) {
        isForegroundActive = applicationState == .active
        reportCurrentState()
    }
    
    private func reportCurrentState() {
        guard !isStopped else { return } // AGENT-PLATFORM (1.0.3)
        let presence = desiredPresence
        guard sendTask != nil || presence != lastSentPresence,
              pendingPresence != presence else {
            return
        }
        
        pendingPresence = presence
        startSendTaskIfNeeded()
    }
    
    private func startSendTaskIfNeeded() {
        guard sendTask == nil else {
            return
        }
        
        sendTask = Task { [weak self, clientProxy] in
            while !Task.isCancelled {
                guard let presence = self?.nextPendingPresence() else {
                    break
                }
                
                _ = await clientProxy.configurePresence(presence, sendImmediately: true)
                
                guard !Task.isCancelled else {
                    break
                }
                
                self?.finishSending(presence)
            }
            
            self?.finishSendTask()
        }
    }
    
    private func nextPendingPresence() -> ClientProxyPresence? {
        guard let pendingPresence else {
            return nil
        }
        
        self.pendingPresence = nil
        return pendingPresence
    }
    
    private func finishSending(_ presence: ClientProxyPresence) {
        lastSentPresence = presence
        
        if pendingPresence == presence {
            pendingPresence = nil
        }
    }
    
    private func finishSendTask() {
        sendTask = nil
        
        if pendingPresence != nil {
            startSendTaskIfNeeded()
        }
    }
}
