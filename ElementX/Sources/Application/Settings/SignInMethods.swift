//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3, operator 2026-11-20): how the account signs in —
// a sign-in phrase, Sign in with Apple, or both (`GET /me/sign-in-methods`).
// It lives with the settings because `AccountSettings` keeps the last answer and
// the extensions compile it; the wire mapping is in `AgentPlatformService+SignInMethods`.
//

import Foundation

/// The account's sign-in methods. A field the server did not send is
/// unknown (`nil`), and the screens keep their usual wording for it: an older
/// server without the route reads the same as one that failed to answer.
nonisolated struct SignInMethods: Equatable, Codable {
    /// The account has a sign-in phrase; `nil` when unknown.
    let phrase: Bool?
    /// Sign in with Apple is linked; `nil` when unknown.
    let apple: Bool?
    /// The server offers Sign in with Apple. Missing means it does not.
    let appleAvailable: Bool

    /// Nothing is known: the read failed or the server has no such route.
    static let unknown = SignInMethods(phrase: nil, apple: nil, appleAvailable: false)

    /// This answer, with any field it left unknown taken from `known`: a partial answer
    /// never erases a good one. `appleAvailable` can't say it is unknown, so a partial
    /// answer keeps the known value of it too.
    func filling(from known: SignInMethods) -> SignInMethods {
        guard phrase == nil || apple == nil else { return self }
        return SignInMethods(phrase: phrase ?? known.phrase,
                             apple: apple ?? known.apple,
                             appleAvailable: known.appleAvailable)
    }

    /// Only an account known to have no phrase gets «Add sign-in phrase».
    var addsFirstPhrase: Bool {
        phrase == false
    }

    /// The Apple row: hidden unless the server answered about it.
    var appleRow: AppleRow? {
        switch apple {
        case .some(true): .linked
        case .some(false) where appleAvailable: .add
        default: nil
        }
    }

    enum AppleRow: Equatable, Codable {
        /// «Sign in with Apple · Connected», not tappable.
        case linked
        /// «Add Sign in with Apple».
        case add
    }
}
