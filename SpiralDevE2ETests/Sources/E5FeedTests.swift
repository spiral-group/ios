//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082, plan § 8). The public feed's scenarios
// FD1–FD15 in one class; lane I1 owns FD1 and FD6, lane I2 FD4 and FD8, lane
// I3 FD3, FD5 and FD7, lane I5 FD10 (Activity), FD11 (who liked) and FD12
// (a live count), lane I6 FD13–FD15 (the sync stream, decision 289: a live
// comment, the new-posts pill, resume after the background) (FD2, images,
// is lane I4's, v1.1). The peer posts over
// the platform API (accepting the feed rules first), the owner reads, posts,
// likes, comments, reports, shares and deletes in the app; FD3, FD5 and FD7
// open the post as a person does, with a tap on the card's text. FD5's
// moderator removes the post through the admin API with an `urn:mas:admin`
// token the helper signs in for. FD6 unblocks the peer in its teardown, so
// the scenarios after it see the peer's posts again.
//

import XCTest

final class E5FeedTests: DevE2ETestCase {
    private var owner: DevE2EFixture.Person {
        fixture.owner
    }

    private var peer: DevE2EFixture.Person {
        fixture.peer
    }

    private var moderator: DevE2EFixture.Person {
        fixture.moderator
    }

    // MARK: FD1

    /// A post the peer publishes appears in the owner's Latest.
    func testFD1PeerPostAppearsInLatest() async throws {
        try await ensureSignedIn(owner)
        let text = "FD1 feed post \(fixture.runID)"
        let postID = try await publish(text, as: peer)

        try openFeedTab()
        let card = try requireCard(containing: text)
        XCTAssertTrue(card.label.contains(peer.displayName), "the card names its author")
        record("POST /feed/posts as \(peer.mxid): \(postID); the owner's Latest shows it")
    }

    // MARK: FD3

    /// The owner likes the peer's post on its card, opens the post with a tap
    /// on the card's text and comments there: both counts move on the server,
    /// once each, and on the card.
    func testFD3LikeAndCommentCounts() async throws {
        try await ensureSignedIn(owner)
        let text = "FD3 feed post \(fixture.runID)"
        let postID = try await publish(text, as: peer)

        try openFeedTab()
        let card = try requireCard(containing: text)
        try tap(card.buttons[A11yIdentifiers.feedScreen.like], "the card's Like")
        let liked = try await eventually("the like counted on the server") { () -> [String: Any]? in
            let post = try await helper.peer("api", peer.localpart, "GET", "/api/v1/feed/posts/\(postID)")
            return Self.counts(of: post)["likes"] == 1 ? Self.body(of: post) : nil
        }
        let ownView = try await helper.peer("api", owner.localpart, "GET", "/api/v1/feed/posts/\(postID)")
        XCTAssertEqual((Self.body(of: ownView)?["viewer"] as? [String: Any])?["liked"] as? Bool, true, "the owner's like")
        XCTAssertTrue(waitUntil(10) { card.label.contains("1 like") }, "the card counts the like: '\(card.label)'")

        // A comment, after the rules sheet the first time.
        try openPost(from: card)
        let field = element(A11yIdentifiers.feedScreen.commentField)
        try tap(field, timeout: 30, "the post's comment field")
        settle(1)
        let comment = "FD3 comment \(fixture.runID)"
        field.typeText(comment)
        settle(0.5)
        try tap(element(A11yIdentifiers.feedScreen.sendComment), "the comment's Send")
        let agree = element(A11yIdentifiers.feedComposerScreen.rulesAgree)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                                       A11yIdentifiers.feedScreen.commentRow, comment)).firstMatch
        switch firstAppearing([agree, row], timeout: 30) {
        case 0:
            agree.tap()
            try require(row, timeout: 30, "the comment under the post after Agree")
            record("the first comment showed the rules sheet; Agree sent it")
        case 1:
            record("the rules were agreed already: no sheet")
        default:
            throw DevE2EError.flow("neither the rules sheet nor the comment appeared within 30 s of Send")
        }

        let counted = try await eventually("the comment counted on the server") { () -> [String: Int]? in
            let counts = try await Self.counts(of: helper.peer("api", peer.localpart, "GET", "/api/v1/feed/posts/\(postID)"))
            return counts["comments"] == 1 ? counts : nil
        }
        XCTAssertEqual(counted["likes"], 1, "one like, once")
        let comments = try await helper.peer("api", peer.localpart, "GET", "/api/v1/feed/posts/\(postID)/comments")
        let stored = try XCTUnwrap(Self.items(of: comments).first { $0["text"] as? String == comment }, "the comment, read by the peer")
        XCTAssertEqual((stored["author"] as? [String: Any])?["mxid"] as? String, owner.mxid)
        XCTAssertTrue(waitUntil(10) { card.label.contains("1 comment") }, "the card counts the comment: '\(card.label)'")
        record("\(postID): like → likes \((liked["counts"] as? [String: Any])?["likes"] as? Int ?? -1), comment → comments \(counted["comments"] ?? -1), read back by the peer")
    }

    // MARK: FD4

    /// A post the filter holds is its author's only. The owner posts it from
    /// the composer (a fresh account agrees to the rules first) and lands on
    /// it with the held notice and Delete; the peer reads it nowhere, neither
    /// in Latest, nor on the author's posts, nor by id. Delete takes it down.
    func testFD4HeldPostIsTheAuthorsOnly() async throws {
        try await ensureSignedIn(owner)
        // A card number with a valid Luhn check: the severe list holds it (`held_reason: filter`).
        let text = "FD4 held post \(fixture.runID) card 4111 1111 1111 1111"

        try openFeedTab()
        try tap(element(A11yIdentifiers.feedComposerScreen.compose), "the Feed tab's compose button")
        let field = element(A11yIdentifiers.feedComposerScreen.textField)
        try tap(field, "the composer's text")
        settle(1)
        field.typeText(text)
        settle(0.5)
        try tap(element(A11yIdentifiers.feedComposerScreen.post), "the composer's Post")

        // 409 feed-rules-not-accepted → the rules sheet; Agree posts the same text with the same key.
        let agree = element(A11yIdentifiers.feedComposerScreen.rulesAgree)
        let heldNotice = element(A11yIdentifiers.feedComposerScreen.heldNotice)
        switch firstAppearing([agree, heldNotice], timeout: 30) {
        case 0:
            agree.tap()
            try require(heldNotice, timeout: 30, "the held notice on the author's own post")
            record("the composer's first post showed the rules sheet; Agree posted it")
        case 1:
            record("the rules were agreed already: no sheet")
        default:
            throw DevE2EError.flow("neither the rules sheet nor the held post appeared within 30 s of Post")
        }
        XCTAssertTrue(heldNotice.label.contains("review"), "the notice says the post is under review: '\(heldNotice.label)'")

        let own = try await eventually("the held post among the owner's own posts") { () -> [String: Any]? in
            let lines = try await helper.peer("api", owner.localpart, "GET", "/api/v1/feed/me/posts")
            return Self.items(of: lines).first { $0["content"].flatMap { ($0 as? [String: Any])?["text"] as? String } == text }
        }
        let postID = try XCTUnwrap(own["id"] as? String)
        XCTAssertEqual(own["state"] as? String, "held")
        XCTAssertEqual(own["held_reason"] as? String, "filter")
        let rowsBefore = try await helper.check("feed_post", ["id": postID])
        let row = try XCTUnwrap(rowsBefore.first, "the feed_posts row")
        XCTAssertEqual(row["state"], "held")
        XCTAssertEqual(row["author_mxid"], owner.mxid)

        // Nobody else: by id, in Latest, on the author's posts.
        let byID = try await refusal(as: peer, "GET", "/api/v1/feed/posts/\(postID)")
        XCTAssertEqual(byID.status, 404, "the peer cannot read the held post by id")
        XCTAssertEqual(byID.type, FeedNotFound.type)
        let latest = try await helper.peer("api", peer.localpart, "GET", "/api/v1/feed/latest?limit=50")
        XCTAssertFalse(Self.items(of: latest).contains { $0["id"] as? String == postID }, "the held post is not in the peer's Latest")
        let authorPosts = try await helper.peer("api", peer.localpart, "GET", "/api/v1/feed/authors/\(owner.mxid)/posts")
        XCTAssertFalse(Self.items(of: authorPosts).contains { $0["id"] as? String == postID }, "nor on the author's posts")

        // The author's Delete, from the notice.
        try tap(element(A11yIdentifiers.feedComposerScreen.deletePost), "the held notice's Delete")
        try tap(app.alerts.buttons[A11yIdentifiers.alertInfo.secondaryButton].firstMatch, "the confirmation's Delete")
        XCTAssertTrue(waitUntil(20) { !heldNotice.exists }, "the deleted post's screen closes")
        let gone = try await eventually("the deleted post answering 404 to its author") {
            let answer = try await refusal(as: owner, "GET", "/api/v1/feed/posts/\(postID)")
            return answer.status == 404 ? answer : nil
        }
        XCTAssertEqual(gone.type, FeedNotFound.type)
        let rows = try await helper.check("feed_post", ["id": postID])
        XCTAssertTrue(rows.isEmpty, "Delete removed the feed_posts row")
        record("held \(postID) (\(row["state"] ?? "?"), \(own["held_reason"] as? String ?? "?")): the peer GET \(byID.status) \(byID.type), absent from Latest and the author's posts; Delete → the author GET \(gone.status), row gone")
    }

    // MARK: FD5

    /// The owner opens the peer's post with a tap on the card's text and
    /// reports it from the post's menu: the receipt with its deadline, the
    /// report on the server, and the reporter's notice in the app. The
    /// moderator removes the post through the admin API; the author gets the
    /// removal's notice and the reporter the decision's, read in the app too.
    func testFD5ReportRemoveNotices() async throws {
        try await ensureSignedIn(owner)
        let text = "FD5 feed post \(fixture.runID)"
        let postID = try await publish(text, as: peer)

        try openFeedTab()
        let card = try requireCard(containing: text)
        try openPost(from: card)
        try tap(app.navigationBars.buttons[A11yIdentifiers.feedScreen.postMenu].firstMatch, "the post's menu")
        try tap(app.buttons[A11yIdentifiers.feedScreen.report].firstMatch, "the menu's Report")
        try tap(element(A11yIdentifiers.feedReportScreen.reason("spam")), "the Spam reason")
        try tap(element(A11yIdentifiers.feedReportScreen.send), "the report's Send")
        try require(element(A11yIdentifiers.feedReportScreen.receipt), timeout: 30, "the report's receipt")

        let received = try await eventually("the owner's report_received notice") { () -> [String: Any]? in
            try await notice("report_received", of: owner) { ($0["post_id"] as? String)?.lowercased() == postID.lowercased() }
        }
        let reportID = try XCTUnwrap(received["report_id"] as? String, "the notice names the report")
        let deadline = (received["statement"] as? [String: Any])?["deadline_at"] as? String
        XCTAssertNotNil(deadline, "the receipt's deadline (Art. 16(4))")
        try tap(element(A11yIdentifiers.feedReportScreen.done), "the receipt's Done")

        // The reporter reads it among their notices: the bell's Activity, then "From Spiral".
        try tap(app.navigationBars.buttons.element(boundBy: 0), "back to Latest")
        try tap(app.buttons[A11yIdentifiers.feedNoticesScreen.toolbarButton].firstMatch, timeout: 30, "the Feed's bell")
        try tap(element(A11yIdentifiers.feedActivityScreen.fromSpiral), timeout: 30, "Activity's From Spiral")
        try require(app.staticTexts["We received your report"].firstMatch, timeout: 30, "the report's notice in the app")
        record("reported \(postID) as spam: report \(reportID), deadline \(deadline ?? "-"); the reporter's notice in the app")

        // The moderator removes it (the token lasts 5 minutes: signed in now).
        let login = try await helper.peer("admin-login", moderator.localpart)
        XCTAssertTrue((login.last?["scopes"] as? [String])?.contains("urn:mas:admin") == true, "the moderator's token has urn:mas:admin")
        let decisionBody = try Self.json(["decision": "remove", "rule": "spam"])
        let decision = try await helper.peer("admin-api", moderator.localpart, "POST", "/api/v1/admin/feed/posts/\(postID)/decision", decisionBody)
        XCTAssertEqual(Self.status(of: decision), 200, "the removal")
        XCTAssertEqual(Self.body(of: decision)?["state"] as? String, "removed")
        XCTAssertEqual(Self.body(of: decision)?["reports_closed"] as? Int, 1, "the removal closes the owner's report")

        let removed = try await eventually("the author's removed notice") { () -> [String: Any]? in
            try await notice("removed", of: peer) { ($0["post_id"] as? String)?.lowercased() == postID.lowercased() }
        }
        let decided = try await eventually("the reporter's report_decided notice") { () -> [String: Any]? in
            try await notice("report_decided", of: owner) { ($0["report_id"] as? String) == reportID }
        }
        let gone = try await refusal(as: owner, "GET", "/api/v1/feed/posts/\(postID)")
        XCTAssertEqual(gone.status, 404, "the removed post is gone for the reporter")

        // The notices have no pull (decision 289): the sync's feed.notice reads them again while shown.
        let decidedInApp = app.staticTexts["A moderator decided on your report"].firstMatch
        XCTAssertTrue(decidedInApp.waitForExistence(timeout: 30), "the decision's notice in the reporter's app, live")
        record("removed \(postID) as \(moderator.mxid): the author's notice \(removed["kind"] as? String ?? "?"), the reporter's \(decided["kind"] as? String ?? "?") (in the app too), GET \(gone.status)")
    }

    // MARK: FD6

    /// A block from the author sheet hides the author's posts at once, and
    /// the blocked person gets `404` on the owner's post (blocks hide both ways).
    func testFD6BlockHidesAtOnce() async throws {
        // Whatever happens below, the peer is unblocked for the scenarios after this one.
        let helper: DevE2EHelper = helper, owner = owner, peer = peer
        addTeardownBlock {
            try await helper.peer("unignore", owner.localpart, peer.mxid)
        }
        try await ensureSignedIn(owner)
        let text = "FD6 feed post \(fixture.runID)"
        let peerPostID = try await publish(text, as: peer)
        let ownerPostID = try await publish("FD6 owner post \(fixture.runID)", as: owner)

        try openFeedTab()
        let card = try requireCard(containing: text)
        try tap(card.buttons[A11yIdentifiers.feedScreen.postAuthor], "the card's author")
        try tap(element(A11yIdentifiers.feedAuthorScreen.more), "the author sheet's menu")
        try tap(app.buttons[A11yIdentifiers.feedAuthorScreen.block].firstMatch, "the menu's Block")
        let alert = app.alerts.firstMatch
        try require(alert, "the block confirmation")
        try tap(alert.buttons["Block"].firstMatch, "the confirmation's Block")

        // At once: no refresh, no relaunch.
        XCTAssertTrue(waitUntil(10) { !card.exists }, "the blocked author's post leaves Latest at once")

        let read = try await eventually("the owner's post answering 404 to the blocked peer", timeout: 60) {
            let answer = try await refusal(as: peer, "GET", "/api/v1/feed/posts/\(ownerPostID)")
            return answer.status == 404 ? answer : nil
        }
        XCTAssertEqual(read.type, FeedNotFound.type)
        let commentBody = try Self.json(["text": "FD6 comment \(fixture.runID)", "idempotency_key": UUID().uuidString])
        let comment = try await refusal(as: peer, "POST", "/api/v1/feed/posts/\(ownerPostID)/comments", commentBody)
        XCTAssertEqual(comment.status, 404, "a comment by the blocked person on the owner's post is 404")
        XCTAssertEqual(comment.type, FeedNotFound.type)
        let ownRead = try await refusal(as: owner, "GET", "/api/v1/feed/posts/\(peerPostID)")
        XCTAssertEqual(ownRead.status, 404, "the owner no longer reads the blocked author's post")
        record("blocked \(peer.mxid): the owner's post to the peer GET \(read.status) \(read.type), comment \(comment.status) \(comment.type); the peer's post to the owner GET \(ownRead.status)")
    }

    // MARK: FD7

    /// The owner opens the peer's post with a tap on the card's text and shares
    /// it into their chat: the server builds the message, the peer reads it
    /// there with the post's link, and the share counts.
    func testFD7ShareToChatWithTheLink() async throws {
        try await ensureSignedIn(owner)
        let dm = try await helper.peer("dm", peer.localpart, owner.mxid)
        let roomID = try XCTUnwrap(dm.first?["room_id"] as? String, "the peer's DM with the owner")
        // The server shares only into a room the sharer is in (403 otherwise).
        _ = try await helper.peer("join", owner.localpart, roomID)
        let text = "FD7 feed post \(fixture.runID)"
        let postID = try await publish(text, as: peer)

        try openFeedTab()
        let card = try requireCard(containing: text)
        try openPost(from: card)
        // Latest's card stays behind the post: the post's own Share is the one on screen.
        let share = app.buttons.matching(identifier: A11yIdentifiers.feedScreen.share)
        let onScreen = try XCTUnwrap(waitForOnScreen(share), "the post's Share")
        onScreen.tap()
        try require(app.navigationBars["Share post"].firstMatch, timeout: 20, "the share picker")
        // A picker row is a switch; the card behind the sheet names the peer too.
        let chat = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", peer.displayName)).firstMatch
        try tap(chat, timeout: 60, "the peer's chat in the picker")
        try tap(app.navigationBars.buttons["Send"].firstMatch, "the picker's Send")

        let got = try await helper.peer("wait", peer.localpart, roomID, "/feed/\(postID)", "45", owner.mxid)
        let body = try XCTUnwrap(got.last?["body"] as? String, "the shared message")
        XCTAssertTrue(body.contains(text), "the message carries the post's text")
        XCTAssertTrue(body.contains("/feed/\(postID)"), "and its link")
        let shares = try await eventually("the share counted on the server") { () -> Int? in
            let counts = try await Self.counts(of: helper.peer("api", peer.localpart, "GET", "/api/v1/feed/posts/\(postID)"))
            return counts["shares"] == 1 ? 1 : nil
        }
        record("shared \(postID) into \(roomID): the peer read '\(body.split(separator: "\n").last ?? "")', shares \(shares)")
    }

    // MARK: FD8

    /// Account deletion removes the person's posts (extends S17): the
    /// owner reads the feed author's post, the author's account is deleted
    /// (`DELETE /me`, the purge S17's in-app deletion runs), and the post is
    /// gone from the database, by id and from the owner's Latest.
    func testFD8AccountDeletionRemovesPosts() async throws {
        try await ensureSignedIn(owner)
        let author = fixture.feedAuthor
        let text = "FD8 feed post \(fixture.runID)"
        let postID = try await publish(text, as: author)
        let before = try await helper.check("feed_posts_of", ["mxid": author.mxid])
        XCTAssertEqual(before.first?["posts"], "1", "the author has the one post")

        try openFeedTab()
        let card = try requireCard(containing: text)

        let deletion = try await helper.peer("delete", author.localpart)
        let counts = deletion.last?["counts"].map { "\($0)" } ?? "-"

        let after = try await eventually("the author's posts erased", timeout: 60) { () -> [String: String]? in
            let row = try await helper.check("feed_posts_of", ["mxid": author.mxid]).first
            return row?["posts"] == "0" ? row : nil
        }
        let read = try await refusal(as: owner, "GET", "/api/v1/feed/posts/\(postID)")
        XCTAssertEqual(read.status, 404, "the deleted person's post answers 404")
        XCTAssertEqual(read.type, FeedNotFound.type)

        // Pull to refresh (Latest's own): Latest reads its first page again, without the post.
        for _ in 0..<3 where card.exists {
            pullToRefresh()
            _ = waitUntil(10) { !card.exists }
        }
        XCTAssertFalse(card.exists, "the deleted person's post leaves Latest on refresh")
        record("deleted \(author.mxid) (counts \(counts)): feed_posts of the author \(before.first?["posts"] ?? "?") → \(after["posts"] ?? "?"), GET \(read.status) \(read.type), gone from Latest")
    }

    // MARK: FD9

    /// The bio (decision 284): the owner writes one in Settings › profile, the
    /// backend's author page and the app's author sheet show it, its spaces
    /// normalised; cleared, it is gone from both.
    func testFD9BioFromTheProfileEditor() async throws {
        try await ensureSignedIn(owner)
        let bio = "FD9 bio \(fixture.runID)"
        // The author page carries the bio on its posts, so the owner posts first.
        let text = "FD9 feed post \(fixture.runID)"
        _ = try await publish(text, as: owner)

        // Typed with spaces around and doubled inside; it saves as one trimmed line.
        try editBio(to: "  FD9  bio \(fixture.runID)  ")
        let shown = try await eventually("the bio on the owner's author page", timeout: 60) { try await authorBio(of: owner) }
        XCTAssertEqual(shown, bio, "the backend shows the bio the editor saved, on one line")

        // The owner's own post brings no pill: Latest shows it after a pull if it was read before.
        try openFeedTab()
        let card = try requireCard(containing: text, ownPost: true)
        try tap(card.buttons[A11yIdentifiers.feedScreen.postAuthor], "the card's author")
        let sheetBio = element(A11yIdentifiers.feedAuthorScreen.bio)
        try require(sheetBio, timeout: 20, "the bio on the author sheet")
        XCTAssertEqual(sheetBio.label, bio)

        try tap(app.buttons["Close"].firstMatch, "the author sheet's Close")
        try editBio(to: "")
        let cleared = try await eventually("the bio gone from the owner's author page", timeout: 60) { () -> Bool? in
            try await authorBio(of: owner) == nil ? true : nil
        }
        XCTAssertTrue(cleared)
        record("set '\(bio)' in the profile editor: the author page and the sheet showed it; cleared: gone from the author page")
    }

    /// Settings › the account row › the Bio field, typed over, Save.
    private func editBio(to bio: String) throws {
        // Settings opens from the Chats list's avatar.
        let chats = app.buttons[A11yIdentifiers.homeTabs.chats].firstMatch
        if chats.waitForExistence(timeout: 5) {
            chats.tap()
        }
        try openSettings()
        try tap(element(A11yIdentifiers.settingsScreen.account), "Settings › the account")
        let field = app.textFields.matching(identifier: A11yIdentifiers.feedBioEditor.field).firstMatch
        try tap(field, timeout: 30, "the profile editor's Bio")
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        if !bio.isEmpty {
            field.typeText(bio)
        }
        try tap(app.navigationBars.buttons["Save"].firstMatch, "the profile editor's Save")
        try require(element(A11yIdentifiers.settingsScreen.account), timeout: 30, "Settings after the save")
        try closeSettings()
    }

    /// The bio on `person`'s posts as the peer reads their author page; `nil` without one.
    private func authorBio(of person: DevE2EFixture.Person) async throws -> String? {
        let page = try await helper.peer("api", peer.localpart, "GET", "/api/v1/feed/authors/\(person.mxid)/posts?limit=1")
        guard let author = Self.items(of: page).first?["author"] as? [String: Any] else {
            throw DevE2EError.flow("\(person.mxid)'s author page has no post to read the bio from")
        }
        return author["bio"] as? String
    }

    // MARK: FD10

    /// Lane I5 (decision 287): the peer likes the owner's post and replies to
    /// the owner's comment under it; the owner's bell opens Activity with the
    /// like ("<peer> liked your post") and the reply ("<peer>: <text>"), and
    /// opening it marks them seen on the server.
    func testFD10ActivityShowsALikeAndAReply() async throws {
        try await ensureSignedIn(owner)
        let postID = try await publish("FD10 feed post \(fixture.runID)", as: owner)
        let commentID = try await comment("FD10 owner's comment \(fixture.runID)", on: postID, as: owner)
        let reply = "FD10 reply \(fixture.runID)"
        _ = try await comment(reply, on: postID, replyingTo: commentID, as: peer)
        let like = try await helper.peer("api", peer.localpart, "PUT", "/api/v1/feed/posts/\(postID)/like")
        XCTAssertEqual(Self.status(of: like), 200, "the peer's like")

        let entries = try await eventually("the owner's activity holds the like and the reply") { () -> [[String: Any]]? in
            let items = try await Self.items(of: helper.peer("api", owner.localpart, "GET", "/api/v1/feed/activity?limit=20"))
            let ids = items.compactMap { $0["id"] as? String }
            return ids.contains { $0.hasPrefix("like:\(postID.lowercased()):") } && ids.contains { $0.hasPrefix("reply:") } ? items : nil
        }
        let replyEntry = try XCTUnwrap(entries.first { ($0["id"] as? String)?.hasPrefix("reply:") == true && $0["post_id"] as? String == postID.lowercased() })
        XCTAssertEqual(replyEntry["preview"] as? String, reply)

        try openFeedTab()
        try tap(app.buttons[A11yIdentifiers.feedNoticesScreen.toolbarButton].firstMatch, timeout: 30, "the Feed's bell")
        let likeRow = activityEntry(containing: peer.displayName, and: "liked your post")
        try require(likeRow, timeout: 30, "the like in Activity")
        let replyRow = activityEntry(containing: peer.displayName, and: reply)
        try require(replyRow, timeout: 10, "the reply in Activity")

        let seen = try await eventually("the activity marked seen") { () -> Int? in
            let page = try await helper.peer("api", owner.localpart, "GET", "/api/v1/feed/activity?limit=1")
            return Self.body(of: page)?["unread"] as? Int == 0 ? 0 : nil
        }
        // The reply opens its post, at the comment.
        try tap(replyRow, "the reply's entry")
        try require(element(A11yIdentifiers.feedScreen.commentField), timeout: 30, "the post the reply is under")
        record("\(postID): the peer's like and reply in the owner's Activity; unread after opening \(seen)")
    }

    // MARK: FD11

    /// Lane I5: who liked is open to everyone — the count on the card opens
    /// the people who liked, newest first, and a person opens their author sheet.
    func testFD11WhoLikedFromTheCount() async throws {
        try await ensureSignedIn(owner)
        let text = "FD11 feed post \(fixture.runID)"
        let postID = try await publish(text, as: peer)
        try await acceptRules(as: moderator)
        for person in [moderator, peer] {
            let like = try await helper.peer("api", person.localpart, "PUT", "/api/v1/feed/posts/\(postID)/like")
            XCTAssertEqual(Self.status(of: like), 200, "\(person.mxid)'s like")
        }
        let likers = try await Self.items(of: helper.peer("api", owner.localpart, "GET", "/api/v1/feed/posts/\(postID)/likes"))
        XCTAssertEqual(likers.compactMap { ($0["author"] as? [String: Any])?["mxid"] as? String }, [peer.mxid, moderator.mxid], "newest first")

        try openFeedTab()
        let card = try requireCard(containing: text)
        XCTAssertTrue(waitUntil(30) { card.label.contains("2 likes") }, "the card counts both likes: '\(card.label)'")
        try tap(card.buttons[A11yIdentifiers.feedScreen.likesCount], "the card's likes count")
        let peerRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                                           A11yIdentifiers.feedLikersScreen.liker, peer.displayName)).firstMatch
        try require(peerRow, timeout: 30, "the peer among who liked")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: A11yIdentifiers.feedLikersScreen.liker).count, 2, "two people liked it")
        try tap(peerRow, "the peer in who liked")
        try require(element(A11yIdentifiers.feedAuthorScreen.message), timeout: 30, "the peer's author sheet")
        record("\(postID): the count opened who liked (\(likers.count)), the peer's author sheet from it")
    }

    // MARK: FD12

    /// Lane I5 (decision 287: live counts over SSE): the owner's own post is
    /// on screen; the peer likes it over the API, and the card's count moves
    /// with no refresh — no pull, no pill.
    func testFD12APeersLikeMovesTheCountLive() async throws {
        try await ensureSignedIn(owner)
        let text = "FD12 feed post \(fixture.runID)"
        let postID = try await publish(text, as: owner)

        try openFeedTab()
        let card = try requireCard(containing: text, ownPost: true)
        XCTAssertFalse(card.label.contains("1 like"), "nobody liked it yet: '\(card.label)'")
        // The stream reconnects with the cards on screen a moment after they show.
        settle(3)

        try await acceptRules(as: peer)
        let like = try await helper.peer("api", peer.localpart, "PUT", "/api/v1/feed/posts/\(postID)/like")
        XCTAssertEqual(Self.status(of: like), 200, "the peer's like")
        XCTAssertTrue(waitUntil(20) { card.label.contains("1 like") }, "the card's count moved without a refresh: '\(card.label)'")
        record("\(postID): the peer's like reached the owner's card live")
    }

    // MARK: FD13

    /// Lane I6 (decision 289): the owner has their own post open; the peer
    /// comments on it over the API, and the comment shows under the post
    /// with no refresh (`feed.comment_added`), the post's count with it
    /// (`feed.counts`).
    func testFD13APeersCommentShowsInTheOpenPost() async throws {
        try await ensureSignedIn(owner)
        let text = "FD13 feed post \(fixture.runID)"
        let postID = try await publish(text, as: owner)

        try openFeedTab()
        let card = try requireCard(containing: text, ownPost: true)
        try openPost(from: card)
        let postCards = cards(containing: text)
        XCTAssertFalse(postCards.allElementsBoundByIndex.contains { canTap($0) && $0.label.contains("1 comment") }, "no comment yet")
        // The post screen shows itself to the store a moment after it appears.
        settle(3)

        let comment = "FD13 peer's comment \(fixture.runID)"
        let commentID = try await self.comment(comment, on: postID, as: peer)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                                       A11yIdentifiers.feedScreen.commentRow, comment)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the peer's comment under the open post without a refresh")
        // Latest's card stays behind the post: the count is read off the one on screen.
        XCTAssertTrue(waitUntil(20) { postCards.allElementsBoundByIndex.contains { canTap($0) && $0.label.contains("1 comment") } },
                      "the open post counts the comment without a refresh")
        record("\(postID): the peer's comment \(commentID) showed in the owner's open post, its count with it")
    }

    // MARK: FD14

    /// Lane I6 (decision 289): the owner is on Latest; the peer publishes,
    /// and the "N new posts" pill comes with no pull (`feed.post_published`).
    /// A tap on it shows the post at the top.
    func testFD14APeersPostBringsTheNewPostsPill() async throws {
        try await ensureSignedIn(owner)
        try await acceptRules(as: peer)

        try openFeedTab()
        let anyCard = app.descendants(matching: .any).matching(identifier: A11yIdentifiers.feedScreen.postCard).firstMatch
        guard firstAppearing([anyCard, element(A11yIdentifiers.feedScreen.empty)], timeout: 30) != nil else {
            throw DevE2EError.flow("Latest's first page (posts or empty) did not show within 30 s")
        }
        // The stream is up with Latest on screen a moment after it shows.
        settle(3)

        let text = "FD14 feed post \(fixture.runID)"
        let postID = try await publish(text, as: peer)
        let pill = element(A11yIdentifiers.feedScreen.newPostsPill)
        XCTAssertTrue(pill.waitForExistence(timeout: 20), "the new-posts pill without a pull")
        let card = cards(containing: text).firstMatch
        XCTAssertFalse(card.exists, "the new post waits behind the pill, Latest keeps its place")
        pill.tap()
        try require(card, timeout: 20, "the post '\(text)' in Latest after the pill")
        XCTAssertTrue(waitUntil(10) { topCard()?.label.contains(text) == true }, "the new post is at the top: '\(topCard()?.label ?? "none")'")
        XCTAssertTrue(waitUntil(10) { !pill.exists }, "the pill is gone after the tap")
        record("\(postID): the peer's post brought the pill on the owner's Latest; its tap showed the post at the top")
    }

    // MARK: FD15

    /// Lane I6 (decision 289): the owner's own post is on Latest; the app
    /// goes to the background, the peer likes the post, and back in the
    /// foreground the stream resumes from its position: the card's count
    /// moves with no pull.
    func testFD15ReturnFromTheBackgroundResumes() async throws {
        try await ensureSignedIn(owner)
        let text = "FD15 feed post \(fixture.runID)"
        let postID = try await publish(text, as: owner)
        try await acceptRules(as: peer)

        try openFeedTab()
        let card = try requireCard(containing: text, ownPost: true)
        XCTAssertFalse(card.label.contains("1 like"), "nobody liked it yet: '\(card.label)'")
        settle(3)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(waitUntil(10) { app.state == .runningBackground || app.state == .runningBackgroundSuspended },
                      "the app is in the background (state \(app.state.rawValue))")
        settle(2)
        let like = try await helper.peer("api", peer.localpart, "PUT", "/api/v1/feed/posts/\(postID)/like")
        XCTAssertEqual(Self.status(of: like), 200, "the peer's like")
        settle(2)

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "the app is back in the foreground")
        XCTAssertTrue(waitUntil(20) { card.label.contains("1 like") }, "the card's count moved after the return, no pull: '\(card.label)'")
        record("\(postID): the peer's like while the app was in the background reached the card after the return")
    }

    // MARK: - Steps

    /// Accepts the current feed rules for `person`.
    private func acceptRules(as person: DevE2EFixture.Person) async throws {
        let standing = try await helper.peer("api", person.localpart, "GET", "/api/v1/feed/me/standing")
        guard Self.status(of: standing) == 200, let version = Self.body(of: standing)?["rules_version"] as? String else {
            throw DevE2EError.flow("GET /feed/me/standing as \(person.mxid) answered \(Self.status(of: standing) ?? 0)")
        }
        let acceptBody = try Self.json(["version": version])
        let accept = try await helper.peer("api", person.localpart, "POST", "/api/v1/feed/rules/accept", acceptBody)
        guard Self.status(of: accept) == 200 else {
            throw DevE2EError.flow("accepting the feed rules as \(person.mxid) answered \(Self.status(of: accept) ?? 0)")
        }
    }

    /// `person` comments on `postID` (accepting the rules first); the comment's id.
    private func comment(_ text: String, on postID: String, replyingTo replyTo: String? = nil, as person: DevE2EFixture.Person) async throws -> String {
        try await acceptRules(as: person)
        var payload: [String: Any] = ["text": text, "idempotency_key": UUID().uuidString]
        payload["reply_to"] = replyTo
        let created = try await helper.peer("api", person.localpart, "POST", "/api/v1/feed/posts/\(postID)/comments", Self.json(payload))
        guard Self.status(of: created) == 201, let id = Self.body(of: created)?["id"] as? String else {
            throw DevE2EError.flow("POST …/comments as \(person.mxid) answered \(Self.status(of: created) ?? 0) \(Self.problemType(of: created) ?? "")")
        }
        return id
    }

    /// The Activity entry whose label carries both texts.
    private func activityEntry(containing first: String, and second: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@ AND label CONTAINS %@",
                                                             A11yIdentifiers.feedActivityScreen.entry, first, second)).firstMatch
    }

    /// Accepts the current feed rules for `person` and publishes a text post; its id.
    private func publish(_ text: String, as person: DevE2EFixture.Person) async throws -> String {
        try await acceptRules(as: person)
        let body = try Self.json(["content": ["kind": "text", "text": text, "media_ids": [String]()], "idempotency_key": UUID().uuidString])
        let post = try await helper.peer("api", person.localpart, "POST", "/api/v1/feed/posts", body)
        guard Self.status(of: post) == 201, let postBody = Self.body(of: post), postBody["state"] as? String == "visible",
              let id = postBody["id"] as? String else {
            throw DevE2EError.flow("POST /feed/posts as \(person.mxid) answered \(Self.status(of: post) ?? 0) \(Self.problemType(of: post) ?? "")")
        }
        return id
    }

    private enum FeedNotFound {
        static let type = "/errors/feed-not-found"
    }

    /// A request that must be refused. The peer script fails a non-2xx answer
    /// ("<METHOD> <url> answered <status> <problem type>"), so its error is read;
    /// a request that succeeded comes back as status 200 for the assertions.
    private func refusal(as person: DevE2EFixture.Person, _ method: String, _ path: String, _ body: String? = nil) async throws -> (status: Int, type: String) {
        do {
            let lines = if let body {
                try await helper.peer("api", person.localpart, method, path, body)
            } else {
                try await helper.peer("api", person.localpart, method, path)
            }
            return (Self.status(of: lines) ?? 200, Self.problemType(of: lines) ?? "")
        } catch DevE2EError.helper(let message) {
            guard let match = message.firstMatch(of: /answered (\d{3})(?: (\S+))?/), let status = Int(match.1) else {
                throw DevE2EError.helper(message)
            }
            return (status, match.2.map(String.init) ?? "")
        }
    }

    /// A tap on the card's text, as a person opens a post: the post's screen
    /// (its comment field) follows. The text once took the tap and opened nothing.
    private func openPost(from card: XCUIElement) throws {
        try tap(card.descendants(matching: .any)[A11yIdentifiers.feedScreen.postText].firstMatch, "the card's text")
        try require(element(A11yIdentifiers.feedScreen.commentField), timeout: 30, "the post's screen after a tap on the card's text")
    }

    /// The first of these a tap would land on, within 20 s.
    private func waitForOnScreen(_ query: XCUIElementQuery) -> XCUIElement? {
        var found: XCUIElement?
        _ = waitUntil(20) {
            found = query.allElementsBoundByIndex.first(where: canTap)
            return found != nil
        }
        return found
    }

    /// `person`'s notice of `kind` that `matches`, among their latest 20.
    private func notice(_ kind: String, of person: DevE2EFixture.Person, matching matches: ([String: Any]) -> Bool) async throws -> [String: Any]? {
        let lines = try await helper.peer("api", person.localpart, "GET", "/api/v1/feed/notices?limit=20")
        return Self.items(of: lines).first { $0["kind"] as? String == kind && matches($0) }
    }

    private func openFeedTab() throws {
        try tap(app.buttons[A11yIdentifiers.feedScreen.tab].firstMatch, timeout: 30, "the Feed tab")
    }

    /// The Latest card carrying `text`. The tab may have read its first page
    /// before the post: someone else's then brings "N new posts" (the sync's
    /// `feed.post_published`), and a tap on it reads the first page again.
    /// The person's own post brings no pill (they posted it, here over the
    /// API): Latest shows it after a pull to refresh, the one list that has it.
    private func requireCard(containing text: String, ownPost: Bool = false) throws -> XCUIElement {
        let card = cards(containing: text).firstMatch
        if ownPost {
            guard !card.waitForExistence(timeout: 10) else { return card }
            for _ in 0..<3 where !card.exists {
                pullToRefresh()
                _ = card.waitForExistence(timeout: 10)
            }
            try require(card, timeout: 1, "the owner's own post '\(text)' in Latest after a pull")
            return card
        }
        let pill = element(A11yIdentifiers.feedScreen.newPostsPill)
        switch firstAppearing([card, pill], timeout: 30) {
        case 0:
            return card
        case 1:
            pill.tap()
        default:
            throw DevE2EError.flow("neither the post '\(text)' nor the new-posts pill appeared in Latest within 30 s")
        }
        try require(card, timeout: 20, "the post '\(text)' in Latest after the new-posts pill")
        return card
    }

    /// Every post card carrying `text` (Latest's, and the open post's over it).
    private func cards(containing text: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                                                             A11yIdentifiers.feedScreen.postCard, text))
    }

    /// The topmost card on screen, below the pinned post if there is one.
    private func topCard() -> XCUIElement? {
        let pinned = element(A11yIdentifiers.feedScreen.pinnedPost)
        let pinnedLabel = pinned.exists ? pinned.label : nil
        return app.descendants(matching: .any).matching(identifier: A11yIdentifiers.feedScreen.postCard).allElementsBoundByIndex
            .filter { canTap($0) && $0.label != pinnedLabel }
            .min { $0.frame.minY < $1.frame.minY }
    }

    /// A real pull, past the threshold, on Latest.
    private func pullToRefresh() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
    }

    // MARK: - The peer script's `api` lines

    private static func status(of lines: [[String: Any]]) -> Int? {
        lines.last?["http"] as? Int
    }

    private static func body(of lines: [[String: Any]]) -> [String: Any]? {
        lines.last?["body"] as? [String: Any]
    }

    private static func items(of lines: [[String: Any]]) -> [[String: Any]] {
        body(of: lines)?["items"] as? [[String: Any]] ?? []
    }

    /// A post's `counts`, by name.
    private static func counts(of lines: [[String: Any]]) -> [String: Int] {
        (body(of: lines)?["counts"] as? [String: Any])?.compactMapValues { $0 as? Int } ?? [:]
    }

    private static func problemType(of lines: [[String: Any]]) -> String? {
        body(of: lines)?["type"] as? String
    }

    private static func json(_ object: [String: Any]) throws -> String {
        try String(bytes: JSONSerialization.data(withJSONObject: object), encoding: .utf8) ?? "{}"
    }
}
