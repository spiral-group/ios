//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation
import MatrixRustSDK

// AGENT-PLATFORM (Brief 0063): wraps the Rust MatrixRTC session so nothing
// above this layer sees SDK types.

class MatrixRTCSessionProxy: MatrixRTCSessionProtocol {
    private let session: MatrixRtcSessionProtocol
    private let updatesSubject = PassthroughSubject<MatrixRTCSessionUpdate, Never>()
    private var subscriptionHandle: TaskHandle?
    
    let ownIdentity: String
    
    var updates: AnyPublisher<MatrixRTCSessionUpdate, Never> {
        updatesSubject.eraseToAnyPublisher()
    }
    
    /// The membership lifetime published to the room. This is the value
    /// Element Call uses; the Rust session refreshes it while the call runs.
    private static let membershipExpiry: Duration = .seconds(4 * 60 * 60)
    
    init(session: MatrixRtcSessionProtocol) {
        self.session = session
        ownIdentity = session.ownIdentity()
        
        // The SDK emits updates in order and `onMainActor` preserves that
        // order, which matters because a key must never be applied before the
        // participant list that explains it.
        let listener: MatrixRtcSessionListener = SDKListener.onMainActor { [weak self] update in
            self?.handle(update)
        }
        
        subscriptionHandle = session.subscribe(listener: listener)
    }
    
    deinit {
        subscriptionHandle?.cancel()
    }
    
    func join(encryptMedia: Bool, notification: NativeCallNotification?, media: NativeCallMedia) async -> Result<Void, MatrixRTCSessionError> {
        do {
            let expiry = UInt64(Self.membershipExpiry.components.seconds * 1000)
            try await session.join(configuration: .init(membershipExpiryMs: expiry,
                                                        encryptMedia: encryptMedia,
                                                        notificationType: notification?.rustValue,
                                                        callIntent: media.rustValue))
            return .success(())
        } catch {
            MXLog.error("Failed joining the MatrixRTC session: \(error)")
            return .failure(.sdkError(error))
        }
    }

    func setMedia(_ media: NativeCallMedia) async -> Result<Void, MatrixRTCSessionError> {
        do {
            try await session.updateCallIntent(callIntent: media.rustValue)
            return .success(())
        } catch {
            MXLog.error("Failed updating the MatrixRTC call intent: \(error)")
            return .failure(.sdkError(error))
        }
    }
    
    func rtcNotificationEventID() async -> String? {
        await session.rtcNotificationEventId()
    }
    
    func leave() async -> Result<Void, MatrixRTCSessionError> {
        do {
            try await session.leave()
            return .success(())
        } catch {
            // Audit wave 8 — reported rather than swallowed. The old comment
            // claimed the staged leave event and the expiry both remove us
            // anyway; the first is only true when one was staged, and the
            // fork's own fallback (no delay id, so publish directly) can fail
            // on a 403, a rate limit or an expired token. That left the caller
            // believing the hang-up had landed while peers kept seeing this
            // device in the call for the full membership expiry.
            MXLog.error("Failed leaving the MatrixRTC session: \(error)")
            return .failure(.sdkError(error))
        }
    }
    
    func transportCredentials() async -> Result<MatrixRTCTransportCredentials, MatrixRTCSessionError> {
        do {
            let credentials = try await session.transportCredentials()
            
            guard let url = URL(string: credentials.url) else {
                MXLog.error("The MatrixRTC transport returned an unusable URL")
                return .failure(.roomInvalid)
            }
            
            return .success(.init(url: url, token: credentials.token, identity: credentials.identity))
        } catch {
            MXLog.error("Failed authorizing against the MatrixRTC transport: \(error)")
            return .failure(.sdkError(error))
        }
    }
    
    func memberships() async -> Result<[MatrixRTCParticipant], MatrixRTCSessionError> {
        do {
            return try await .success(session.memberships().map(MatrixRTCParticipant.init(rustValue:)))
        } catch {
            MXLog.error("Failed reading the MatrixRTC memberships: \(error)")
            return .failure(.sdkError(error))
        }
    }
    
    // MARK: - Private
    
    private func handle(_ update: MatrixRtcSessionUpdate) {
        switch update {
        case .membershipsChanged(let memberships):
            updatesSubject.send(.participantsChanged(memberships.map(MatrixRTCParticipant.init(rustValue:))))
        case .ownEncryptionKeyChanged(let key):
            updatesSubject.send(.ownEncryptionKeyChanged(.init(rustValue: key)))
        case .encryptionKeyReceived(let key):
            updatesSubject.send(.encryptionKeyReceived(.init(rustValue: key)))
        case .ended:
            updatesSubject.send(.ended)
        }
    }
}

private extension NativeCallMedia {
    var rustValue: MatrixRtcCallIntent {
        switch self {
        case .audio: .audio
        case .video: .video
        }
    }
}

private extension MatrixRTCParticipant {
    init(rustValue: MatrixRtcMembership) {
        self.init(userID: rustValue.userId, deviceID: rustValue.deviceId, identity: rustValue.identity)
    }
}

private extension MatrixRTCEncryptionKey {
    init(rustValue: MatrixRtcEncryptionKey) {
        self.init(participantIdentity: rustValue.participantIdentity,
                  index: Int32(rustValue.index),
                  key: Data(rustValue.key))
    }
}

private extension NativeCallNotification {
    var rustValue: MatrixRtcNotificationType {
        switch self {
        case .ring: .ring
        case .notification: .notification
        }
    }
}
