//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 148): invitations — Create account and invitation
// links, no stale welcome (G4; 1.0.3: no invitation screen in the app); the owner's own
// link, a person who registers through it and what the owner then sees
// (G5). They run after E3: G4 starts on the start screen S17 leaves, and its
// used-up code is the one-seat campaign S1 registered through.
//

import XCTest

final class E4InviteTests: DevE2ETestCase {
    private var owner: DevE2EFixture.Person {
        fixture.owner
    }

    private var peer: DevE2EFixture.Person {
        fixture.peer
    }

    private var newcomer: DevE2EFixture.Person {
        fixture.newcomer
    }

    // `Untranslated.strings`, en.
    private let campaignBannerText = "You were invited to Spiral"
    private let signedInToastText = "That is an invitation to join Spiral" // «… — you already have.»

    private var banner: XCUIElement {
        element(A11yIdentifiers.authenticationStartScreen.invitedBanner)
    }

    // MARK: G4

    /// No invitation pending: Create account goes straight to the system
    /// sign-in sheet (1.0.3: no invitation screen in the app — the web
    /// registration's first step asks, covered by identity-login's tests). A
    /// valid link leaves the banner, a dead one takes it away. Signed in, a
    /// person's link opens their profile and a campaign's shows the toast.
    /// Nothing takes a seat.
    func testG04CreateAccountAndInvitationLinks() async throws {
        let unknownCode = "E2ENOSUCH\(fixture.runID)"
        let once = try await seats(of: fixture.onceInviteCode)
        guard once["live"] == "1" else {
            throw DevE2EError.flow("the one-seat campaign is not used up (live=\(once["live"] ?? "?")): S01 registers through it first")
        }
        let campaignBefore = try await seats(of: fixture.inviteCode)
        let unknownRows = try await helper.check("invite_seats", ["token": unknownCode])
        XCTAssertTrue(unknownRows.isEmpty, "the unknown code is no invitation on the backend")

        try await ensureSignedOut()
        XCTAssertFalse(banner.waitForExistence(timeout: 3), "no invitation outlives the last session")

        try tap(element(A11yIdentifiers.authenticationStartScreen.createAccount), "Create account")
        // Straight on to the sign-in sheet; stop there.
        try tap(springboard.buttons["Cancel"].firstMatch, timeout: 30, "the system sign-in sheet's Cancel")

        try await openLink("spiral://join/\(fixture.inviteCode)")
        try require(banner, timeout: 20, "the invitation banner after a valid link")
        XCTAssertTrue(banner.label.contains(campaignBannerText), "a campaign names nobody: '\(banner.label)'")

        try await openLink("spiral://join/\(unknownCode)")
        XCTAssertTrue(waitUntil(30) { !banner.exists }, "a dead link leaves no banner")

        // A person's link opened signed out, then a sign-in to an account it didn't register: no welcome — the
        // platform decides it (GET /me/invite/welcome), not the link the app holds.
        let peerInvite = try await personalInvite(of: peer)
        try await openLink("spiral://join/\(peerInvite.token)")
        try require(banner, timeout: 20, "the peer's invitation banner")

        let onceAfter = try await seats(of: fixture.onceInviteCode)
        let campaignAfter = try await seats(of: fixture.inviteCode)
        record("one-seat campaign: live \(onceAfter["live"] ?? "?"), rows \(onceAfter["redemptions"] ?? "?"); "
            + "\(fixture.inviteCode): rows \(campaignBefore["redemptions"] ?? "?") → \(campaignAfter["redemptions"] ?? "?")")
        XCTAssertEqual(onceAfter["redemptions"], once["redemptions"], "nothing took a seat of the one-seat campaign")
        XCTAssertEqual(campaignAfter["redemptions"], campaignBefore["redemptions"], "a link takes a seat only at registration")
        let unknownAfter = try await helper.check("invite_seats", ["token": unknownCode])
        XCTAssertTrue(unknownAfter.isEmpty, "a dead link leaves no invitation behind")

        // Signed in: the link is a way to the inviter, never a seat.
        try await signInWithPassword(owner)
        try completeOnboarding(allowAI: true)
        let welcome = element(A11yIdentifiers.inviteWelcomeScreen.text)
        XCTAssertFalse(welcome.waitForExistence(timeout: 10), "a sign-in to an account the link didn't register gets no welcome")
        let toast = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", signedInToastText)).firstMatch
        let toastShown = try await openLink("spiral://join/\(fixture.inviteCode)", thenWaitFor: toast, timeout: 45)
        XCTAssertTrue(toastShown, "a campaign link while signed in shows the toast")

        try await openLink("spiral://join/\(peerInvite.token)")
        try requireProfile(of: peer, "the peer's profile from their invitation link")

        let peerSeats = try await seats(of: peerInvite.token)
        let campaignSignedIn = try await seats(of: fixture.inviteCode)
        record("peer's invite: rows \(peerSeats["redemptions"] ?? "?"); \(fixture.inviteCode): rows \(campaignSignedIn["redemptions"] ?? "?")")
        XCTAssertEqual(peerSeats["redemptions"], "0", "opening a person's link while signed in takes no seat")
        XCTAssertEqual(campaignSignedIn["redemptions"], campaignBefore["redemptions"], "nor does a campaign link")
    }

    // MARK: G5

    /// Settings › Invite to Spiral: the link (copied), «N of M»; the owner
    /// signs out and a new person registers through that link, sees who
    /// invited them; the owner, back, has one seat less, the newcomer on the
    /// joined list (and in `GET /me/invite/joined`), whose row opens their
    /// profile; the seat is a completed `invite_redemptions` row of the
    /// owner's invite, the referral notice an executed `agent_action_log` row
    /// whose event the assistant sent in the owner DM. The card itself is not
    /// read here: on one simulator the owner's device that existed when it was
    /// sent is gone, and this second session cannot decrypt it (E2EE history,
    /// no key backup) — PRERELEASE_WALK G5 walks it on two simulators.
    func testG05InvitePeopleAndReferral() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant() // the referral notice is its message

        try openInvitePeople()
        let before = try seatsOnScreen()
        let link = element(A11yIdentifiers.invitePeopleScreen.link)
        try require(link, timeout: 30, "the invitation link")
        guard let url = URL(string: link.label), url.pathComponents.count == 3, url.pathComponents[1] == "join" else {
            throw DevE2EError.flow("the link is not a join link: '\(link.label)'")
        }
        let token = url.lastPathComponent
        let apiBefore = try await personalInvite(of: owner)
        XCTAssertEqual(apiBefore.token, token, "the screen shows the link GET /me/invite gives")
        XCTAssertEqual(before.left, apiBefore.maxUses - apiBefore.used, "«N of M» is the API's seats left")
        XCTAssertEqual(before.max, apiBefore.maxUses)
        XCTAssertFalse(element(A11yIdentifiers.invitePeopleScreen.joinedUser(newcomer.mxid)).exists)

        try tap(element(A11yIdentifiers.invitePeopleScreen.copy), "Copy link")
        XCTAssertTrue(app.staticTexts["Copied to clipboard"].firstMatch.waitForExistence(timeout: 10), "the copy is confirmed")
        record("seats \(before.left) of \(before.max); link copied")

        // The newcomer, on this simulator after the owner signs out.
        try await ensureSignedOut()
        try await registerWithSeedPhrase(newcomer, inviteCode: token, inviter: owner.displayName, checkTermsRefusal: false)
        try passInviteWelcome(naming: owner.displayName)
        try completeOnboarding(allowAI: true)
        XCTAssertEqual(try currentAccount(), newcomer.mxid)

        let redemption = try await eventually("the newcomer's seat completed", timeout: 120) {
            try await helper.check("invite_redemption", ["localpart": newcomer.localpart]).first { $0["completed"] == "t" }
        }
        record("invite_redemptions: kind=\(redemption["kind"] ?? "?") owner=\(redemption["owner"] ?? "?") status=\(redemption["status"] ?? "?")")
        XCTAssertEqual(redemption["kind"], "personal")
        XCTAssertEqual(redemption["owner"], owner.mxid, "the seat is the owner's invite's")
        let joined = try await eventually("the newcomer in GET /me/invite/joined") { () -> [String: Any]? in
            let reply = try await helper.peer("api", owner.localpart, "GET", "/api/v1/me/invite/joined")
            let entries = (reply.first?["body"] as? [String: Any])?["joined"] as? [[String: Any]] ?? []
            return entries.first { $0["user_id"] as? String == newcomer.mxid }
        }
        record("GET /me/invite/joined: \(joined["user_id"] ?? "?") at \(joined["joined_at"] ?? "?")")
        let apiAfter = try await personalInvite(of: owner)
        XCTAssertEqual(apiAfter.used, apiBefore.used + 1, "one seat more is used")

        // The owner again.
        try signOut()
        try await signInWithPassword(owner)
        try completeOnboarding(allowAI: true)

        try openInvitePeople()
        let after = try seatsOnScreen()
        record("seats \(before.left) → \(after.left) of \(after.max)")
        XCTAssertEqual(after.left, before.left - 1, "«N of M» dropped by one")
        let row = element(A11yIdentifiers.invitePeopleScreen.joinedUser(newcomer.mxid))
        try require(row, timeout: 30, "the newcomer on the joined list")

        let notice = try await eventually("the referral notice's audit row", timeout: 120) {
            try await helper.check("referral_notice", ["agent": assistant.mxid, "owner": owner.mxid, "redemption": redemption["id"] ?? ""]).first
        }
        record("agent_action_log: \(notice["capability_name"] ?? "") \(notice["policy_decision"] ?? "") \(notice["outcome"] ?? "") event=\(notice["outcome_event_id"] ?? "")")
        XCTAssertEqual(notice["outcome"], "executed")
        XCTAssertFalse(notice["outcome_event_id"]?.isEmpty ?? true, "the notice names its event")

        XCTAssertEqual(notice["owner_dm"], "t", "the notice went to the owner's DM with the assistant")
        let event = try await eventually("the notice's event in Synapse") {
            try await helper.check("room_event", ["event": notice["outcome_event_id"] ?? ""]).first
        }
        record("synapse event: \(event["type"] ?? "?") from \(event["sender"] ?? "?")")
        XCTAssertEqual(event["sender"], assistant.mxid)
        XCTAssertEqual(event["room_id"], notice["room_id"])

        try scrollAndTap(row, "the newcomer's row on the joined list")
        try requireProfile(of: newcomer, "the newcomer's profile from the joined list")
    }

    // MARK: - Steps

    private func seats(of token: String) async throws -> [String: String] {
        guard let row = try await helper.check("invite_seats", ["token": token]).first else {
            throw DevE2EError.flow("no invite with the token of this run (\(token.prefix(4))…)")
        }
        return row
    }

    private func personalInvite(of person: DevE2EFixture.Person) async throws -> (token: String, maxUses: Int, used: Int) {
        let reply = try await helper.peer("api", person.localpart, "GET", "/api/v1/me/invite")
        guard reply.first?["http"] as? Int == 200, let body = reply.first?["body"] as? [String: Any],
              let token = body["token"] as? String, let maxUses = body["max_uses"] as? Int, let used = body["used"] as? Int else {
            throw DevE2EError.flow("GET /me/invite for \(person.mxid) answered \(reply.first?["http"] ?? "nothing")")
        }
        return (token, maxUses, used)
    }

    private func openInvitePeople() throws {
        try openSettings()
        try scrollAndTap(element(A11yIdentifiers.settingsScreen.invitePeople), "Settings › Invite to Spiral")
    }

    /// «N of M» from the seats row, once the invite has loaded.
    private func seatsOnScreen() throws -> (left: Int, max: Int) {
        let row = element(A11yIdentifiers.invitePeopleScreen.seats)
        try require(row, timeout: 30, "the seats row")
        // 1.0.3 (concept C): the caller's node reads «Invited N of M»; the seats left are the rest.
        let text = "\(row.label) \(row.value as? String ?? "")"
        guard let match = text.firstMatch(of: /Invited (\d+) of (\d+)/), let used = Int(match.1), let max = Int(match.2) else {
            throw DevE2EError.flow("the seats row reads no «Invited N of M»: '\(text)'")
        }
        return (max - used, max)
    }

    /// «Welcome to Spiral» naming the inviter, after the onboarding prompts
    /// of a first session (it waits for them); Later. Throws when the Chats
    /// list stayed quiet for 10 s with no welcome.
    private func passInviteWelcome(naming inviter: String) throws {
        let text = element(A11yIdentifiers.inviteWelcomeScreen.text)
        let end = Date().addingTimeInterval(120)
        var quietSince: Date?
        while !text.exists, Date() < end {
            if let prompt = onboardingPrompts.first(where: canTap) {
                prompt.tap()
                quietSince = nil
            } else if canTap(homeAvatar) {
                if let quietSince, Date().timeIntervalSince(quietSince) > 10 { break }
                quietSince = quietSince ?? Date()
            }
            settle(0.5)
        }
        guard text.exists else { throw DevE2EError.flow("the invitation welcome did not show after the registration") }
        XCTAssertTrue(waitUntil(20) { text.label.contains(inviter) }, "the welcome names the inviter: '\(text.label)'")
        let message = element(A11yIdentifiers.inviteWelcomeScreen.message)
        XCTAssertTrue(message.label.contains(inviter), "«Message <inviter>»: '\(message.label)'")
        try tap(element(A11yIdentifiers.inviteWelcomeScreen.later), "the welcome's Later")
    }

    /// A user's profile: their MXID under the name, and «Message».
    private func requireProfile(of person: DevE2EFixture.Person, _ what: String) throws {
        try require(app.staticTexts[person.mxid].firstMatch, timeout: 30, what)
        try require(element(A11yIdentifiers.roomMemberDetailsScreen.directChat), timeout: 10, "\(what): «Message»")
    }
}
