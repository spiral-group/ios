//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0075, 0078): how LocalAuthentication's answers map to `DeviceOwnerCheck`. Account deletion
// confirms with the typed handle only on `.passcodeRequired`, so no other error may ever map to it.
//

import LocalAuthentication
@testable import Spiral
import Testing

struct DeviceOwnerAuthenticatorTests {
    @Test
    func aDeviceWithoutAPasscodeRequiresOne() async {
        let check = await authenticate(canEvaluateError: .passcodeNotSet)
        #expect(check == .passcodeRequired)
    }
    
    /// A lockout must not become `.passcodeRequired`: that would let a locked-out device delete the account with the
    /// handle alone.
    @Test
    func aLockoutIsACancelNotAMissingPasscode() async {
        #expect(await authenticate(canEvaluateError: .biometryLockout) == .cancelled)
        #expect(await authenticate(evaluateError: .biometryLockout) == .cancelled)
    }
    
    @Test
    func otherUnavailableReasonsAreACancel() async {
        #expect(await authenticate(canEvaluateError: .biometryNotAvailable) == .cancelled)
        #expect(await authenticate(canEvaluateError: .biometryNotEnrolled) == .cancelled)
    }
    
    @Test
    func aFailedEvaluationIsNeverAMissingPasscode() async {
        #expect(await authenticate(evaluateError: .userCancel) == .cancelled)
        #expect(await authenticate(evaluateError: .authenticationFailed) == .cancelled)
        #expect(await authenticate(evaluateError: .passcodeNotSet) == .cancelled)
    }
    
    @Test
    func theOwnerIsAuthenticated() async {
        #expect(await authenticate() == .authenticated)
    }
    
    // MARK: - Helpers
    
    private func authenticate(canEvaluateError: LAError.Code? = nil, evaluateError: LAError.Code? = nil) async -> DeviceOwnerCheck {
        let authenticator = DeviceOwnerAuthenticator {
            StubContext(canEvaluateError: canEvaluateError, evaluateError: evaluateError)
        }
        return await authenticator.authenticate(reason: "Test")
    }
}

/// Answers `canEvaluatePolicy` and `evaluatePolicy` without a device owner.
private nonisolated final class StubContext: LAContext, @unchecked Sendable {
    private let canEvaluateError: LAError.Code?
    private let evaluateError: LAError.Code?
    
    init(canEvaluateError: LAError.Code?, evaluateError: LAError.Code?) {
        self.canEvaluateError = canEvaluateError
        self.evaluateError = evaluateError
        super.init()
    }
    
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        guard let canEvaluateError else { return true }
        error?.pointee = NSError(domain: LAErrorDomain, code: canEvaluateError.rawValue)
        return false
    }
    
    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, (any Error)?) -> Void) {
        if let evaluateError {
            reply(false, NSError(domain: LAErrorDomain, code: evaluateError.rawValue))
        } else {
            reply(true, nil)
        }
    }
}
