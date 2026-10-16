//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 146): a person who joins by invitation in the
// app — the seed-phrase registration with the Terms (S1) — and deletes the
// account in the app with Face ID (S17). They run last: the registration
// needs the start screen, so the owner is signed out first.
//

import XCTest

final class E3RegistrantTests: DevE2ETestCase {
    private var registrant: DevE2EFixture.Person {
        fixture.registrant
    }
    
    // MARK: S1
    
    /// The invitation link, Create account, identity-login refusing to go on
    /// without the Terms, the phrase read and confirmed, then the backend's
    /// terms_acceptances row and the redeemed invitation.
    func testS01RegistrationWithTerms() async throws {
        try await ensureSignedOut()
        // The run's one-seat campaign: this registration uses it up for G4.
        try await registerWithSeedPhrase(registrant, inviteCode: fixture.onceInviteCode, checkTermsRefusal: true)
        try passInviteWelcome()
        try completeOnboarding(allowAI: true)
        XCTAssertEqual(try currentAccount(), registrant.mxid)
        
        let terms = try await eventually("the registrant's identity row") {
            try await helper.check("terms_acceptance", ["localpart": registrant.localpart]).first
        }
        record("identity: invited=\(terms["invited"] ?? "?") terms_version=\(terms["terms_version"] ?? "?") recent=\(terms["recent"] ?? "?")")
        XCTAssertEqual(terms["invited"], "t", "the identity carries its invitation")
        XCTAssertFalse(terms["terms_version"]?.isEmpty ?? true, "a terms_acceptances row names the accepted version")
        XCTAssertEqual(terms["recent"], "t", "the acceptance is from this registration")
        
        let seats = try await eventually("the one-seat campaign") {
            try await helper.check("invite_seats", ["token": fixture.onceInviteCode]).first
        }
        record("one-seat campaign: live=\(seats["live"] ?? "?") of \(seats["max_uses"] ?? "?")")
        XCTAssertEqual(seats["live"], "1", "the registration took the campaign's only seat")
    }
    
    // MARK: S17
    
    /// Settings › Delete account › Delete › Face ID: back on the start
    /// screen, and every store of the person erased.
    func testS17AccountDeletion() async throws {
        let signedIn = try await launchToKnownState(allowAI: true)
        let signedInAsRegistrant = try signedIn && currentAccount() == registrant.mxid
        if !signedInAsRegistrant {
            if signedIn { try signOut() }
            try await registerWithSeedPhrase(registrant, inviteCode: fixture.inviteCode, checkTermsRefusal: false)
            try passInviteWelcome()
            try completeOnboarding(allowAI: true)
        }
        
        try openSettings()
        try scrollAndTap(element(A11yIdentifiers.settingsScreen.deleteAccount), "Settings › Delete account")
        try tap(element(A11yIdentifiers.deactivateAccountScreen.delete), timeout: 20, "the red Delete account")
        try tap(app.alerts.buttons[A11yIdentifiers.alertInfo.primaryButton].firstMatch, "the alert's Delete")
        var signedOut = false
        for _ in 0..<3 where !signedOut {
            settle(2)
            try await helper.sim("faceid-match")
            signedOut = startSignIn.waitForExistence(timeout: 30)
        }
        XCTAssertTrue(signedOut, "the deletion ends on the start screen")
        
        let state = try await eventually("the erased account", timeout: 60) { () -> [String: String]? in
            let rows = try await helper.check("account_state", ["mxid": registrant.mxid])
            let values = Dictionary(rows.map { ($0["key"] ?? "", $0["value"] ?? "") }) { $1 }
            return values["tenant rows"] == "0" ? values : nil
        }
        record(state.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
        XCTAssertEqual(state["assistant"], "-", "the assistant is gone")
        XCTAssertEqual(state["ai consent rows"], "0", "the consent decisions are erased")
        XCTAssertEqual(state["identity rows"], "0", "the identity and its terms_acceptances are erased")
        XCTAssertEqual(state["mas upstream links"], "0")
        XCTAssertEqual(state["synapse deactivated"], "1")
        XCTAssertFalse(state["mas user"]?.contains("deactivated_at=null") ?? true, "MAS deactivates the user")
        XCTAssertGreaterThanOrEqual(Int(state["gdpr audit rows"] ?? "0") ?? 0, 1, "the purge leaves its receipt")
    }
    
    /// «Welcome to Spiral» after an invitation: Later, when it shows.
    private func passInviteWelcome() throws {
        let later = element(A11yIdentifiers.inviteWelcomeScreen.later)
        if later.waitForExistence(timeout: 20) { later.tap() }
    }
}
