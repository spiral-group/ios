//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, backend ADR-0094 A.1): "my language" rides each person's MatrixRTC call membership as
// `com.matrixagent.language`. The memberships are already on the phone, so every participant's language is read from
// them, and one's own is published with the join and republished when it changes (`update_language`).

import Foundation

/// Every participant's published language, and one's own, through the call's memberships.
@MainActor
protocol NativeCallMembershipLanguagesProtocol: AnyObject {
    /// Each person's published language by MXID. Nil when the memberships couldn't be read; a person with no language
    /// is simply absent.
    func languages() async -> [String: String]?
    /// Publishes `language` with this device's membership. False when it didn't land.
    func publish(_ language: String) async -> Bool
}

extension NativeCallSession: NativeCallMembershipLanguagesProtocol {
    func languages() async -> [String: String]? {
        membershipLanguages
    }

    func publish(_ language: String) async -> Bool {
        await setLanguage(language)
    }
}
