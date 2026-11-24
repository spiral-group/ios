//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import KeychainAccess
import MatrixRustSDK
@testable import Spiral
import Testing

struct KeychainControllerTests {
    var keychain: KeychainController
    
    init() {
        keychain = KeychainController(service: .tests,
                                      accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier)
        keychain.removeAllRestorationTokens()
        keychain.resetSecrets()
    }
    
    @Test
    func addRestorationToken() {
        // Given an empty keychain.
        #expect(keychain.restorationTokens().isEmpty, "The keychain should be empty to begin with.")
        
        // When adding an restoration token.
        let username = "@test:example.com"
        let restorationToken = RestorationToken(session: .init(accessToken: "accessToken",
                                                               refreshToken: "refreshToken",
                                                               userId: "userId",
                                                               deviceId: "deviceId",
                                                               homeserverUrl: "homeserverUrl",
                                                               oauthData: "oauthData",
                                                               slidingSyncVersion: .native),
                                                sessionDirectories: .init(),
                                                passphrase: RestorationTokenFixtures.passphrase,
                                                pusherNotificationClientIdentifier: "pusherClientID")
        keychain.setRestorationToken(restorationToken, forUsername: username)
        
        // Then the restoration token should be stored in the keychain.
        #expect(keychain.restorationTokenForUsername(username) == restorationToken, "The retrieved restoration token should match the value that was stored.")
    }
    
    @Test
    func removingRestorationToken() {
        // Given a keychain with a stored restoration token.
        let username = "@test:example.com"
        let restorationToken = RestorationToken(session: .init(accessToken: "accessToken",
                                                               refreshToken: "refreshToken",
                                                               userId: "userId",
                                                               deviceId: "deviceId",
                                                               homeserverUrl: "homeserverUrl",
                                                               oauthData: "oauthData",
                                                               slidingSyncVersion: .native),
                                                sessionDirectories: .init(),
                                                passphrase: RestorationTokenFixtures.passphrase,
                                                pusherNotificationClientIdentifier: "pusherClientID")
        keychain.setRestorationToken(restorationToken, forUsername: username)
        #expect(keychain.restorationTokens().count == 1, "The keychain should have 1 restoration token.")
        #expect(keychain.restorationTokenForUsername(username) == restorationToken, "The initial restoration token should match the value that was stored.")
        
        // When deleting the restoration token.
        keychain.removeRestorationTokenForUsername(username)
        
        // Then the keychain should be empty.
        #expect(keychain.restorationTokens().isEmpty, "The keychain should be empty after deleting the token.")
        #expect(keychain.restorationTokenForUsername(username) == nil, "There restoration token should not be returned after removal.")
    }
    
    @Test
    func removingAllRestorationTokens() {
        // Given a keychain with 5 stored restoration tokens.
        for index in 0..<5 {
            let restorationToken = RestorationToken(session: .init(accessToken: "accessToken",
                                                                   refreshToken: "refreshToken",
                                                                   userId: "userId",
                                                                   deviceId: "deviceId",
                                                                   homeserverUrl: "homeserverUrl",
                                                                   oauthData: "oauthData",
                                                                   slidingSyncVersion: .native),
                                                    sessionDirectories: .init(),
                                                    passphrase: RestorationTokenFixtures.passphrase,
                                                    pusherNotificationClientIdentifier: "pusherClientID")
            keychain.setRestorationToken(restorationToken, forUsername: "@test\(index):example.com")
        }
        #expect(keychain.restorationTokens().count == 5, "The keychain should have 5 restoration tokens.")
        
        // When deleting all of the restoration tokens.
        keychain.removeAllRestorationTokens()
        
        // Then the keychain should be empty.
        #expect(keychain.restorationTokens().isEmpty, "The keychain should be empty after deleting the token.")
    }
    
    @Test
    func removingSingleRestorationTokens() {
        // Given a keychain with 5 stored restoration tokens.
        for index in 0..<5 {
            let restorationToken = RestorationToken(session: .init(accessToken: "accessToken",
                                                                   refreshToken: "refreshToken",
                                                                   userId: "userId",
                                                                   deviceId: "deviceId",
                                                                   homeserverUrl: "homeserverUrl",
                                                                   oauthData: "oauthData",
                                                                   slidingSyncVersion: .native),
                                                    sessionDirectories: .init(),
                                                    passphrase: RestorationTokenFixtures.passphrase,
                                                    pusherNotificationClientIdentifier: "pusherClientID")
            keychain.setRestorationToken(restorationToken, forUsername: "@test\(index):example.com")
        }
        #expect(keychain.restorationTokens().count == 5, "The keychain should have 5 restoration tokens.")
        
        // When deleting one of the restoration tokens.
        keychain.removeRestorationTokenForUsername("@test2:example.com")
        
        // Then the other 4 items should remain untouched.
        #expect(keychain.restorationTokens().count == 4, "The keychain have 4 remaining restoration tokens.")
        #expect(keychain.restorationTokenForUsername("@test0:example.com") != nil, "The restoration token should not have been deleted.")
        #expect(keychain.restorationTokenForUsername("@test1:example.com") != nil, "The restoration token should not have been deleted.")
        #expect(keychain.restorationTokenForUsername("@test2:example.com") == nil, "The restoration token should have been deleted.")
        #expect(keychain.restorationTokenForUsername("@test3:example.com") != nil, "The restoration token should not have been deleted.")
        #expect(keychain.restorationTokenForUsername("@test4:example.com") != nil, "The restoration token should not have been deleted.")
    }
    
    @Test
    func unsupportedRestorationToken() throws {
        // Given a keychain with an unsupported restoration token with a sliding sync proxy URL value.
        let underlyingKeychain = Keychain(service: KeychainControllerService.tests.restorationTokenID,
                                          accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier)
        // Note: We assert with this underlying keychain's keys as keychain.restorationTokens() triggers the deletion that we're testing.
        #expect(underlyingKeychain.allKeys().isEmpty, "The keychain should be empty to begin with.")
        
        let unsupportedToken = RestorationTokenV4(session: SessionV1(accessToken: "1234",
                                                                     refreshToken: nil,
                                                                     userId: "@test:example.com",
                                                                     deviceId: "D3V1C3",
                                                                     homeserverUrl: "https://matrix.example.com",
                                                                     oidcData: nil,
                                                                     slidingSyncVersion: .proxy(url: "https://sync.example.com")),
                                                  sessionDirectory: .sessionsBaseDirectory.appending(component: UUID().uuidString),
                                                  passphrase: RestorationTokenFixtures.base64Passphrase,
                                                  pusherNotificationClientIdentifier: "pusherClientID")
        let tokenData = try JSONEncoder().encode(unsupportedToken)
        try underlyingKeychain.set(tokenData, key: "@test:example.com")
        #expect(underlyingKeychain.allKeys().count == 1)
        
        // When attempting to retrieve the unsupported token.
        let retrievedToken = keychain.restorationTokenForUsername("@test:example.com")
        
        // Then nothing should be returned and the restoration token should be automatically removed.
        #expect(retrievedToken == nil, "The token should not be decoded.")
        #expect(underlyingKeychain.allKeys().isEmpty, "The keychain should be empty again.")
    }
    
    // AGENT-PLATFORM: a refresh that lands after a sign-out removed the token.
    @Test
    func savingSessionWithoutRestorationTokenWritesNothing() {
        // Given an empty keychain (the user signed out).
        #expect(keychain.restorationTokens().isEmpty, "The keychain should be empty to begin with.")

        // When the SDK saves a refreshed session for that user.
        keychain.saveSessionInKeychain(session: makeSession(accessToken: "refreshed", deviceId: "deviceId"))

        // Then nothing traps and nothing is written.
        #expect(keychain.restorationTokens().isEmpty, "A signed-out session must not be written back.")
        #expect(keychain.restorationTokenForUsername("@test:example.com") == nil)
    }

    // AGENT-PLATFORM: a late refresh from a signed-out device after the same user signed in again.
    @Test
    func savingSessionFromAnotherDeviceKeepsTheStoredToken() {
        // Given a keychain holding a newer login for the same user.
        let stored = makeRestorationToken(session: makeSession(accessToken: "current", deviceId: "newDevice"))
        keychain.setRestorationToken(stored, forUsername: "@test:example.com")

        // When the old device's session is saved.
        keychain.saveSessionInKeychain(session: makeSession(accessToken: "stale", deviceId: "oldDevice"))

        // Then the newer login is untouched.
        #expect(keychain.restorationTokenForUsername("@test:example.com") == stored)
    }

    @Test
    func savingSessionUpdatesTheStoredToken() {
        // Given a keychain with a stored restoration token.
        let stored = makeRestorationToken(session: makeSession(accessToken: "old", deviceId: "deviceId"))
        keychain.setRestorationToken(stored, forUsername: "@test:example.com")

        // When the SDK saves a refreshed session.
        let refreshed = makeSession(accessToken: "refreshed", deviceId: "deviceId")
        keychain.saveSessionInKeychain(session: refreshed)

        // Then the session is replaced and everything else is kept.
        let saved = keychain.restorationTokenForUsername("@test:example.com")
        #expect(saved?.session == refreshed)
        #expect(saved?.sessionDirectories == stored.sessionDirectories)
        #expect(saved?.passphrase == stored.passphrase)
        #expect(saved?.pusherNotificationClientIdentifier == stored.pusherNotificationClientIdentifier)
    }

    /// AGENT-PLATFORM (1.0.3, NSE keychain review finding 1): with refresh-token rotation the stored pair is dead once
    /// the SDK holds the new one, so a read that fails is tried again rather than taken for a sign-out.
    @Test
    func aReadThatFailsOnceIsTriedAgainAndTheSessionSaved() {
        let failures = FailureBudget(count: 1)
        let keychain = KeychainController(service: .tests,
                                          accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier,
                                          unreadableTokenRetryDelays: [0]) { keychain, username in
            if failures.spend() { throw Status.interactionNotAllowed }
            return try keychain.getData(username)
        }
        let stored = makeRestorationToken(session: makeSession(accessToken: "old", deviceId: "deviceId"))
        keychain.setRestorationToken(stored, forUsername: "@test:example.com")
        
        let refreshed = makeSession(accessToken: "refreshed", deviceId: "deviceId")
        keychain.saveSessionInKeychain(session: refreshed)
        
        #expect(keychain.restorationTokenForUsername("@test:example.com")?.session == refreshed)
    }
    
    @Test
    func aReadThatKeepsFailingLeavesTheStoredTokenAlone() {
        let keychain = KeychainController(service: .tests,
                                          accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier,
                                          unreadableTokenRetryDelays: [0, 0]) { _, _ in throw Status.interactionNotAllowed }
        let stored = makeRestorationToken(session: makeSession(accessToken: "old", deviceId: "deviceId"))
        keychain.setRestorationToken(stored, forUsername: "@test:example.com")
        
        keychain.saveSessionInKeychain(session: makeSession(accessToken: "refreshed", deviceId: "deviceId"))
        
        #expect(keychain.restorationTokenForUsername("@test:example.com") == stored)
    }
    
    /// Fable L2: data that doesn't decode is read once; only a keychain error is worth another read.
    @Test
    func undecodableDataIsNotReadAgain() {
        let reads = FailureBudget(count: Int.max)
        let keychain = KeychainController(service: .tests,
                                          accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier,
                                          unreadableTokenRetryDelays: [0, 0]) { _, _ in
            _ = reads.spend()
            return Data("not a token".utf8)
        }
        
        keychain.saveSessionInKeychain(session: makeSession(accessToken: "refreshed", deviceId: "deviceId"))
        
        #expect(reads.spent == 1)
    }
    
    /// AGENT-PLATFORM (1.0.3, NSE keychain review finding 2): a sign-out in another process between the read and the
    /// write must not get the signed-out token written back.
    @Test
    func aSignOutBetweenTheReadAndTheWriteIsNotUndone() {
        let keychain = KeychainController(service: .tests,
                                          accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier) { keychain, username in
            let data = try keychain.getData(username)
            try keychain.remove(username) // The app signs out right after the NSE's read.
            return data
        }
        keychain.setRestorationToken(makeRestorationToken(session: makeSession(accessToken: "old", deviceId: "deviceId")),
                                     forUsername: "@test:example.com")
        
        keychain.saveSessionInKeychain(session: makeSession(accessToken: "refreshed", deviceId: "deviceId"))
        
        #expect(keychain.restorationTokenForUsername("@test:example.com") == nil)
        #expect(keychain.restorationTokens().isEmpty)
    }

    private func makeSession(accessToken: String, deviceId: String) -> Session {
        Session(accessToken: accessToken,
                refreshToken: "refreshToken",
                userId: "@test:example.com",
                deviceId: deviceId,
                homeserverUrl: "homeserverUrl",
                oauthData: "oauthData",
                slidingSyncVersion: .native)
    }

    private func makeRestorationToken(session: Session) -> RestorationToken {
        RestorationToken(session: session,
                         sessionDirectories: .init(),
                         passphrase: RestorationTokenFixtures.passphrase,
                         pusherNotificationClientIdentifier: "pusherClientID")
    }

    @Test
    func addPINCode() throws {
        // Given a keychain without a PIN code set.
        #expect(try !keychain.containsPINCode(), "A new keychain shouldn't contain a PIN code.")
        #expect(keychain.pinCode() == nil, "A new keychain shouldn't return a PIN code.")
        
        // When setting a PIN code.
        try keychain.setPINCode("0000")
        
        // Then the PIN code should be stored.
        #expect(try keychain.containsPINCode(), "The keychain should contain the PIN code.")
        #expect(keychain.pinCode() == "0000", "The stored PIN code should match what was set.")
    }
    
    @Test
    func updatePINCode() throws {
        // Given a keychain with a PIN code already set.
        try keychain.setPINCode("0000")
        #expect(try keychain.containsPINCode(), "The keychain should contain the PIN code.")
        #expect(keychain.pinCode() == "0000", "The stored PIN code should match what was set.")
        
        // When setting a different PIN code.
        try keychain.setPINCode("1234")
        
        // Then the PIN code should be updated.
        #expect(try keychain.containsPINCode(), "The keychain should still contain the PIN code.")
        #expect(keychain.pinCode() == "1234", "The stored PIN code should match the new value.")
    }
    
    @Test
    func removePINCode() throws {
        // Given a keychain with a PIN code already set.
        try keychain.setPINCode("0000")
        #expect(try keychain.containsPINCode(), "The keychain should contain the PIN code.")
        #expect(keychain.pinCode() == "0000", "The stored PIN code should match what was set.")
        
        // When removing the PIN code.
        keychain.removePINCode()
        
        // Then the PIN code should no longer be stored.
        #expect(try !keychain.containsPINCode(), "The keychain should no longer contain the PIN code.")
        #expect(keychain.pinCode() == nil, "There shouldn't be a stored PIN code after removing it.")
    }
    
    @Test
    func addPINCodeBiometricState() throws {
        // Given a keychain without any biometric state.
        #expect(!keychain.containsPINCodeBiometricState(), "A new keychain shouldn't contain biometric state.")
        #expect(keychain.pinCodeBiometricState() == nil, "A new keychain shouldn't return biometric state.")
        
        // When setting the state.
        let data = Data("Face ID".utf8)
        try keychain.setPINCodeBiometricState(data)
        
        // Then the state should be stored.
        #expect(keychain.containsPINCodeBiometricState(), "The keychain should contain the biometric state.")
        #expect(keychain.pinCodeBiometricState() == data, "The stored biometric state should match what was set.")
    }
    
    @Test
    func updatePINCodeBiometricState() throws {
        // Given a keychain that contains PIN code biometric state.
        let data = Data("😃".utf8)
        try keychain.setPINCodeBiometricState(data)
        #expect(keychain.containsPINCodeBiometricState(), "The keychain should contain the biometric state.")
        #expect(keychain.pinCodeBiometricState() == data, "The stored biometric state should match what was set.")
        
        // When setting different state.
        let newData = Data("😎".utf8)
        try keychain.setPINCodeBiometricState(newData)
        
        // Then the state should be updated.
        #expect(keychain.containsPINCodeBiometricState(), "The keychain should still contain biometric state.")
        #expect(keychain.pinCodeBiometricState() != data, "The stored biometric state shouldn't match the old value.")
        #expect(keychain.pinCodeBiometricState() == newData, "The stored biometric state should match the new value.")
    }
    
    @Test
    func removePINCodeBiometricState() throws {
        // Given a keychain that contains PIN code biometric state.
        let data = Data("Face ID".utf8)
        try keychain.setPINCodeBiometricState(data)
        #expect(keychain.containsPINCodeBiometricState(), "The keychain should contain the biometric state.")
        #expect(keychain.pinCodeBiometricState() == data, "The stored biometric state should match what was set.")
        
        // When removing the state.
        keychain.removePINCodeBiometricState()
        
        // Then the state should no longer be stored.
        #expect(!keychain.containsPINCodeBiometricState(), "The keychain should no longer contain the biometric state.")
        #expect(keychain.pinCodeBiometricState() == nil, "There shouldn't be any stored biometric state after removing it.")
    }
}

/// Fails the first `count` reads, and counts them, from whichever thread the keychain is read on.
private nonisolated final class FailureBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int
    private var spentCount = 0
    
    var spent: Int {
        lock.withLock { spentCount }
    }
    
    init(count: Int) {
        self.count = count
    }
    
    func spend() -> Bool {
        lock.withLock {
            guard count > 0 else { return false }
            count -= 1
            spentCount += 1
            return true
        }
    }
}
