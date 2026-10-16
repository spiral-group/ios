//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import LocalAuthentication

/// AGENT-PLATFORM (Brief 0075, 0078): Face ID / Touch ID with the passcode as
/// fallback before an account-level change (a new sign-in phrase, deleting the
/// account). A device with no passcode reports `.passcodeRequired`, and the
/// caller decides: a new phrase is refused, a deletion is confirmed with the
/// typed handle instead (decision 112).
enum DeviceOwnerCheck: Equatable {
    case authenticated
    case cancelled
    case passcodeRequired
}

// sourcery: AutoMockable
protocol DeviceOwnerAuthenticatorProtocol {
    func authenticate(reason: String) async -> DeviceOwnerCheck
}

struct DeviceOwnerAuthenticator: DeviceOwnerAuthenticatorProtocol {
    var makeContext: () -> LAContext = { LAContext() }
    
    func authenticate(reason: String) async -> DeviceOwnerCheck {
        let context = makeContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            MXLog.info("Device owner authentication unavailable (\(error?.code ?? 0))")
            return error?.code == LAError.passcodeNotSet.rawValue ? .passcodeRequired : .cancelled
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .authenticated : .cancelled
        } catch {
            MXLog.info("Device owner authentication failed: \((error as NSError).code)")
            return .cancelled
        }
    }
}
