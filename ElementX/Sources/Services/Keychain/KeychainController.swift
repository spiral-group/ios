//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
@preconcurrency import KeychainAccess
import MatrixRustSDK
import Security // AGENT-PLATFORM: `SecItemUpdate` for the save path

nonisolated enum KeychainControllerService: String {
    case sessions
    case tests
    
    var restorationTokenID: String {
        InfoPlistReader.main.baseBundleIdentifier + "." + rawValue
    }
    
    var mainID: String {
        InfoPlistReader.main.baseBundleIdentifier + ".keychain.\(rawValue)"
    }
}

/// The SDK calls the `ClientSessionDelegate` methods from arbitrary threads and the
/// underlying `Keychain` is thread-safe, so the controller doesn't need an actor.
final nonisolated class KeychainController: KeychainControllerProtocol {
    /// The keychain responsible for storing account restoration tokens (keyed by userID).
    private let restorationTokenKeychain: Keychain
    /// The keychain responsible for storing all other secrets in the app (keyed by `Key`s).
    private let mainKeychain: Keychain
    
    private enum Key: String {
        case appLockPINCode
        case appLockBiometricState
    }
    
    /// AGENT-PLATFORM: what a read of the stored restoration token found. A keychain or decode error is not "signed out".
    enum StoredRestorationToken {
        case found(RestorationToken)
        case notFound
        /// The keychain refused the read; it may work a moment later.
        case unreadable(Error)
        /// The stored data doesn't decode; reading it again won't change that.
        case undecodable(Error)
    }
    
    /// AGENT-PLATFORM: the save path reads the stored token through this, so tests can fail a read or sign out mid-save.
    private let readStoredTokenData: @Sendable (_ username: String) throws -> Data?
    /// AGENT-PLATFORM: pauses before a failed read of the stored token is tried again on the save path.
    private let unreadableTokenRetryDelays: [TimeInterval]
    
    /// - Parameter readStoredTokenData: for tests; it is given the keychain and the username to read.
    init(service: KeychainControllerService,
         accessGroup: String,
         unreadableTokenRetryDelays: [TimeInterval] = [0.05, 0.2],
         readStoredTokenData: (@Sendable (Keychain, String) throws -> Data?)? = nil) {
        let restorationTokenKeychain = Keychain(service: service.restorationTokenID, accessGroup: accessGroup)
        self.restorationTokenKeychain = restorationTokenKeychain
        mainKeychain = Keychain(service: service.mainID, accessGroup: accessGroup)
        self.unreadableTokenRetryDelays = unreadableTokenRetryDelays
        let read = readStoredTokenData ?? { keychain, username in try keychain.getData(username) }
        self.readStoredTokenData = { try read(restorationTokenKeychain, $0) }
    }
    
    // MARK: - Restoration Tokens
    
    func setRestorationToken(_ restorationToken: RestorationToken, forUsername username: String) {
        do {
            let tokenData = try JSONEncoder().encode(restorationToken)
            try restorationTokenKeychain.set(tokenData, key: username)
        } catch {
            MXLog.error("Failed storing user restore token with error: \(error)")
        }
    }
    
    func restorationTokenForUsername(_ username: String) -> RestorationToken? {
        switch storedRestorationToken(forUsername: username, read: { try restorationTokenKeychain.getData($0) }) {
        case .found(let restorationToken):
            return restorationToken
        case .notFound:
            return nil
        case .unreadable(let error), .undecodable(let error):
            MXLog.error("Failed retrieving user restore token: \(error)")
            return nil
        }
    }
    
    private func storedRestorationToken(forUsername username: String, read: (String) throws -> Data?) -> StoredRestorationToken {
        let tokenData: Data
        do {
            // KeychainAccess returns nil for `errSecItemNotFound` and throws on every other status.
            guard let data = try read(username) else {
                return .notFound
            }
            tokenData = data
        } catch {
            return .unreadable(error)
        }
        
        do {
            return try .found(JSONDecoder().decode(RestorationToken.self, from: tokenData))
        } catch RestorationTokenError.slidingSyncProxyNotSupported {
            MXLog.error("Unsupported user restore token (contains sliding sync proxy). Deleting token.")
            removeRestorationTokenForUsername(username)
            return .notFound
        } catch {
            return .undecodable(error)
        }
    }
    
    func restorationTokens() -> [KeychainCredentials] {
        restorationTokenKeychain.allKeys().compactMap { username in
            guard let restorationToken = restorationTokenForUsername(username) else {
                return nil
            }
            
            return KeychainCredentials(userID: username, restorationToken: restorationToken)
        }
    }
    
    func removeRestorationTokenForUsername(_ username: String) {
        MXLog.warning("Removing restoration token for user: \(username).")
        
        do {
            try restorationTokenKeychain.remove(username)
        } catch {
            MXLog.error("Failed removing restore token with error: \(error)")
        }
    }
    
    func removeAllRestorationTokens() {
        MXLog.warning("Removing all user restoration tokens.")
        
        do {
            try restorationTokenKeychain.removeAll()
        } catch {
            MXLog.error("Failed removing all tokens")
        }
    }
    
    // MARK: - ClientSessionDelegate
    
    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        MXLog.info("Retrieving an updated Session from the keychain.")
        guard let session = restorationTokenForUsername(userId)?.session else {
            throw ClientError.Generic(msg: "Failed to find RestorationToken in the Keychain.", details: nil)
        }
        return session
    }
    
    func saveSessionInKeychain(session: Session) {
        // AGENT-PLATFORM: the SDK saves a refreshed token from whichever process
        // refreshed it, so a sign-out in the app can remove the token while the
        // NSE (or the app's own client) is mid-refresh. Upstream trapped here and
        // the push was lost. The session is gone: skip the save rather than write
        // a token for it, and never overwrite a newer login's token for the same user.
        // With refresh-token rotation the old pair is dead once the SDK holds the
        // new one, so a read error must not pass for a sign-out: it is read again.
        let oldToken: RestorationToken
        switch storedRestorationTokenRetryingUnreadable(forUsername: session.userId) {
        case .found(let token):
            oldToken = token
        case .notFound:
            MXLog.info("No restoration token for the refreshed session, it was signed out. Not saving it.")
            return
        case .unreadable(let error), .undecodable(let error):
            MXLog.error("Couldn't read the stored restoration token, the refreshed session isn't saved: \(error)")
            return
        }
        guard oldToken.session.deviceId == session.deviceId else {
            MXLog.error("The stored restoration token belongs to another device. Not saving the refreshed session.")
            return
        }
        
        MXLog.info("Saving session changes in the keychain.")
        let restorationToken = RestorationToken(session: session,
                                                sessionDirectories: oldToken.sessionDirectories,
                                                passphrase: oldToken.passphrase,
                                                pusherNotificationClientIdentifier: oldToken.pusherNotificationClientIdentifier)
        updateExistingRestorationToken(restorationToken, forUsername: session.userId)
    }
    
    private func storedRestorationTokenRetryingUnreadable(forUsername username: String) -> StoredRestorationToken {
        var stored = storedRestorationToken(forUsername: username, read: readStoredTokenData)
        for delay in unreadableTokenRetryDelays {
            guard case .unreadable(let error) = stored else { break }
            MXLog.error("Failed reading the stored restoration token, trying again: \(error)")
            // The SDK calls this synchronously on its own thread, not the main one.
            Thread.sleep(forTimeInterval: delay)
            stored = storedRestorationToken(forUsername: username, read: readStoredTokenData)
        }
        return stored
    }
    
    /// Replaces the stored token only if it is still there. A sign-out in another process between the read above and
    /// this write removes the item, and `SecItemUpdate` then finds nothing instead of writing the token back, which
    /// KeychainAccess's check-then-add `set` would do.
    private func updateExistingRestorationToken(_ restorationToken: RestorationToken, forUsername username: String) {
        let tokenData: Data
        do {
            tokenData = try JSONEncoder().encode(restorationToken)
        } catch {
            MXLog.error("Failed encoding the refreshed restoration token: \(error)")
            return
        }
        
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: restorationTokenKeychain.service,
                                    kSecAttrAccount as String: username,
                                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny]
        if let accessGroup = restorationTokenKeychain.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: tokenData] as CFDictionary)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            MXLog.info("The restoration token was removed while saving, it was signed out. Not saving it.")
        default:
            MXLog.error("Failed storing the refreshed restoration token: \(status)")
        }
    }
    
    // MARK: - App Secrets
    
    func resetSecrets() {
        MXLog.warning("Resetting main keychain.")
        
        do {
            try mainKeychain.removeAll()
        } catch {
            MXLog.error("Failed resetting the main keychain.")
        }
    }
    
    func containsPINCode() throws -> Bool {
        try mainKeychain.contains(Key.appLockPINCode.rawValue)
    }
    
    func setPINCode(_ pinCode: String) throws {
        try mainKeychain.set(pinCode, key: Key.appLockPINCode.rawValue)
    }
    
    func pinCode() -> String? {
        do {
            return try mainKeychain.getString(Key.appLockPINCode.rawValue)
        } catch {
            MXLog.error("Failed retrieving the PIN code.")
            return nil
        }
    }
    
    func removePINCode() {
        do {
            try mainKeychain.remove(Key.appLockPINCode.rawValue)
        } catch {
            MXLog.error("Failed removing the PIN code.")
        }
    }
    
    func containsPINCodeBiometricState() -> Bool {
        do {
            return try mainKeychain.contains(Key.appLockBiometricState.rawValue)
        } catch {
            MXLog.error("Failed checking for biometric state.")
            return false // No need to re-throw the error, we can fall back to the PIN code.
        }
    }
    
    func setPINCodeBiometricState(_ state: Data) throws {
        try mainKeychain.set(state, key: Key.appLockBiometricState.rawValue)
    }
    
    func pinCodeBiometricState() -> Data? {
        do {
            return try mainKeychain.getData(Key.appLockBiometricState.rawValue)
        } catch {
            MXLog.error("Failed setting the PIN code biometric state.")
            return nil
        }
    }
    
    func removePINCodeBiometricState() {
        do {
            try mainKeychain.remove(Key.appLockBiometricState.rawValue)
        } catch {
            MXLog.error("Failed removing the PIN code biometric state.")
        }
    }
}
