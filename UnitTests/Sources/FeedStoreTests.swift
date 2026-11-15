//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (decision 289, contract § 5 Feed and § 7). The
// session's store: each kind of the sync stream either sets a value or marks
// a post or a list stale; what is stale and shown is read again once,
// coalesced, and what is off screen when it shows again; a like on its way
// keeps what the app shows; and what the person sends shows at once.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedStoreTests {
    private let service = FeedServiceMock()
    private let store: FeedStore
    private let owner = NSObject()
    private let post = FeedPreviewData.textPost
    private let mine = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000701", author: FeedPreviewData.ann, minutesAgo: 2,
                                            text: "Mine", isAuthor: true)

    init() {
        store = FeedStore(feedService: service, currentUserID: "@me:spiral.md")
        service.activityCursorLimitReturnValue = .success(FeedActivityPage(items: [], nextCursor: nil, unread: 0))
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        service.draftReturnValue = nil
        store.upsert([post, mine])
        store.setList(.latest, FeedStoreList(ids: [post.id, mine.id], nextCursor: nil))
        store.setList(.author(userID: post.author.userID), FeedStoreList(ids: [post.id], nextCursor: nil))
        store.setList(.ownPosts, FeedStoreList(ids: [mine.id], nextCursor: nil))
    }

    // MARK: - Values

    @Test
    func countsAreSetAndALikeOnItsWayKeepsWhatTheAppShows() {
        store.apply([.counts(postID: post.id, counts: FeedCounts(likes: 4, comments: 2, shares: 1))])
        #expect(store.post(post.id)?.counts == FeedCounts(likes: 4, comments: 2, shares: 1))

        #expect(store.beginLike(postID: post.id))
        #expect(!store.beginLike(postID: post.id), "One like per post on its way")
        store.setLikes(FeedLikes(likes: 5, liked: true), postID: post.id)
        store.apply([.counts(postID: post.id, counts: FeedCounts(likes: 4, comments: 3, shares: 1)),
                     .viewerLike(postID: post.id, liked: false)])
        #expect(store.post(post.id)?.counts == FeedCounts(likes: 5, comments: 3, shares: 1))
        #expect(store.post(post.id)?.viewer.liked == true)
        store.endLike(postID: post.id, .refused(rollback: FeedLikes(likes: 4, liked: false)))

        store.apply([.viewerLike(postID: post.id, liked: true)])
        #expect(store.post(post.id)?.viewer.liked == true, "The person's like from another device")
    }

    /// A read answering while a like is on its way does not undo what the app shows.
    @Test
    func aReadDuringALikeKeepsTheLike() {
        _ = store.beginLike(postID: post.id)
        store.setLikes(FeedLikes(likes: 1, liked: true), postID: post.id)
        store.upsert([post.withCounts(comments: 9)])

        #expect(store.post(post.id)?.viewer.liked == true)
        #expect(store.post(post.id)?.counts.likes == 1)
        #expect(store.post(post.id)?.counts.comments == 9)
    }

    /// Liked here, then unliked on another device: both frames land before
    /// the like's answer, which is older than them and does not undo them.
    @Test
    func aLikesAnswerDoesNotUndoWhatTheStreamSaidMeanwhile() async {
        store.upsert([post.settingLike(false, likes: 2)])
        service.setLikedPostIDClosure = { [store, post] _, _ in
            await MainActor.run {
                store.apply([.viewerLike(postID: post.id, liked: true), .counts(postID: post.id, counts: FeedCounts(likes: 3, comments: 0, shares: 0)),
                             .viewerLike(postID: post.id, liked: false), .counts(postID: post.id, counts: FeedCounts(likes: 2, comments: 0, shares: 0))])
            }
            return .success(FeedLikes(likes: 3, liked: true))
        }

        await engagement().toggleLike(post)
        #expect(store.post(post.id)?.viewer.liked == false)
        #expect(store.post(post.id)?.counts.likes == 2)

        // A page asked for before the frames keeps neither the answer nor its own copy.
        store.upsert([post.settingLike(true, likes: 3)])
        #expect(store.post(post.id)?.viewer.liked == false)
        #expect(store.post(post.id)?.counts.likes == 2)
    }

    /// Opus M1: a read of the post alone answering during the like ends the
    /// record but not what the stream said of the like since it began.
    @Test
    func aSingleReadDuringALikeKeepsWhatTheStreamSaidOfIt() async {
        store.upsert([post.settingLike(false, likes: 2)])
        store.show(postID: post.id, by: owner)
        service.postIdReturnValue = .success(post.settingLike(false, likes: 2).withCounts(comments: 5))
        service.setLikedPostIDClosure = { [store, post] _, _ in
            await MainActor.run {
                store.apply([.viewerLike(postID: post.id, liked: true), .counts(postID: post.id, counts: FeedCounts(likes: 3, comments: 0, shares: 0)),
                             .viewerLike(postID: post.id, liked: false), .counts(postID: post.id, counts: FeedCounts(likes: 2, comments: 0, shares: 0)),
                             .postUpdated(postID: post.id)])
            }
            await store.settle()
            return .success(FeedLikes(likes: 3, liked: true))
        }

        await engagement().toggleLike(post)
        #expect(store.post(post.id)?.viewer.liked == false)
        #expect(store.post(post.id)?.counts.likes == 2)
        #expect(store.post(post.id)?.counts.comments == 5, "The rest is the read's")

        store.upsert([post.settingLike(true, likes: 3)])
        #expect(store.post(post.id)?.viewer.liked == false)
        #expect(store.post(post.id)?.counts.likes == 2)
    }

    /// Opus L4: a like that timed out after the server made it; its frames
    /// came during the like and show, and the rollback records nothing.
    @Test
    func aRefusedLikeShowsWhatTheStreamSaidMeanwhile() async {
        store.upsert([post.settingLike(false, likes: 2)])
        service.setLikedPostIDClosure = { [store, post] _, _ in
            await MainActor.run {
                store.apply([.viewerLike(postID: post.id, liked: true), .counts(postID: post.id, counts: FeedCounts(likes: 3, comments: 0, shares: 0))])
            }
            return .failure(.transport)
        }

        await engagement().toggleLike(post)

        #expect(store.post(post.id)?.viewer.liked == true)
        #expect(store.post(post.id)?.counts.likes == 3)
    }

    /// With nothing newer from the stream, the answer is the word: a page read in flight does not undo it.
    @Test
    func aLikesAnswerOutlivesAPageReadInFlight() async {
        store.upsert([post.settingLike(false, likes: 2)])
        store.apply([.counts(postID: post.id, counts: FeedCounts(likes: 2, comments: 0, shares: 0))])
        service.setLikedPostIDReturnValue = .success(FeedLikes(likes: 3, liked: true))

        await engagement().toggleLike(post)
        store.upsert([post.settingLike(false, likes: 2)])

        #expect(store.post(post.id)?.viewer.liked == true)
        #expect(store.post(post.id)?.counts.likes == 3)
    }

    /// A refused like rolls back what the app guessed and records nothing: a later read is the word.
    @Test
    func aRefusedLikeRecordsNothing() async {
        store.upsert([post.settingLike(false, likes: 2)])
        service.setLikedPostIDReturnValue = .failure(.transport)

        await engagement().toggleLike(post)
        #expect(store.post(post.id)?.viewer.liked == false)
        #expect(store.post(post.id)?.counts.likes == 2)

        // Liked on another device; the read after it shows it.
        store.upsert([post.settingLike(true, likes: 3)])
        #expect(store.post(post.id)?.viewer.liked == true)
        #expect(store.post(post.id)?.counts.likes == 3)
    }

    /// Fable H1: a page asked for before the stream's change answers with the
    /// older copy; the change wins. A post gone, or hidden on another device,
    /// does not come back, and counts do not go backwards.
    @Test
    func aPageReadBeforeAStreamChangeDoesNotUndoIt() {
        let other = FeedPreviewData.posts(1, startingAt: 7)[0]
        store.upsert([other])
        store.apply([.postState(postID: post.id, state: .other("gone")),
                     .hidden(postID: other.id),
                     .counts(postID: mine.id, counts: FeedCounts(likes: 5, comments: 4, shares: 3))])

        // The page that was in flight: every post as it was before.
        store.upsert([post, other, mine.withCounts(likes: 1, comments: 1, shares: 0)])
        store.setList(.latest, FeedStoreList(ids: [post.id, other.id, mine.id], nextCursor: nil))
        store.setList(.ownPosts, FeedStoreList(ids: [mine.id, post.id], nextCursor: nil))

        #expect(store.list(.latest)?.ids == [mine.id])
        #expect(store.list(.ownPosts)?.ids == [mine.id])
        #expect(store.post(post.id)?.state == .other("gone"))
        #expect(store.post(other.id)?.viewer.hidden == true)
        #expect(store.post(mine.id)?.counts == FeedCounts(likes: 5, comments: 4, shares: 3))
    }

    /// A read of the post alone, asked after the change, is newer than the stream's word; so is anything after a gap.
    @Test
    func aTargetedReadOrAGapEndsWhatTheStreamSaid() async {
        store.apply([.counts(postID: post.id, counts: FeedCounts(likes: 5, comments: 0, shares: 0))])
        service.postIdReturnValue = .success(post.withCounts(likes: 6))
        store.show(postID: post.id, by: owner)
        store.apply([.postUpdated(postID: post.id)])
        await store.settle()
        #expect(store.post(post.id)?.counts.likes == 6)
        store.upsert([post.withCounts(likes: 7)])
        #expect(store.post(post.id)?.counts.likes == 7)

        store.apply([.counts(postID: mine.id, counts: FeedCounts(likes: 9, comments: 0, shares: 0))])
        store.markEverythingStale()
        store.upsert([mine.withCounts(likes: 2)])
        #expect(store.post(mine.id)?.counts.likes == 2)
    }

    /// A read of the post alone that started before a later change ends only what was said before it (Opus H-1).
    @Test(arguments: [true, false])
    func aSingleReadInFlightKeepsALaterChange(isGone: Bool) async {
        store.show(postID: post.id, by: owner)
        service.postIdClosure = { [store, post] _ in
            // The next frame lands while the read is on its way; the read answers with the copy from before it.
            await MainActor.run {
                store.apply([isGone ? .postState(postID: post.id, state: .other("gone"))
                        : .counts(postID: post.id, counts: FeedCounts(likes: 6, comments: 0, shares: 0))])
            }
            return .success(post.withCounts(likes: 5))
        }
        store.apply([.postUpdated(postID: post.id)])
        await store.settle()

        if isGone {
            #expect(store.post(post.id)?.state == .other("gone"))
        } else {
            #expect(store.post(post.id)?.counts.likes == 6)
        }
        store.upsert([post.withCounts(likes: 5)])
        store.setList(.latest, FeedStoreList(ids: [post.id, mine.id], nextCursor: nil))
        #expect(isGone ? store.list(.latest)?.ids == [mine.id] : store.post(post.id)?.counts.likes == 6)
    }

    /// The person's own comment moves the count at once, but the stream's counts stay the word (Opus M-1).
    @Test
    func anOwnCommentDoesNotPinTheCount() async {
        store.apply([.counts(postID: post.id, counts: FeedCounts(likes: 0, comments: 3, shares: 0))])
        let made = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000702", author: FeedPreviewData.ann, minutesAgo: 0, text: "Hi", isAuthor: true)
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .success(made)

        // The server's count for this comment (3) came first; the answer then adds one locally.
        await store.sendComment(postID: post.id, text: "Hi", replyTo: nil, author: FeedPreviewData.ann)
        #expect(store.post(post.id)?.counts.comments == 4)

        store.upsert([post.withCounts(comments: 2)])
        #expect(store.post(post.id)?.counts.comments == 3, "The stream's word, not the local guess pinned over it")
    }

    /// A read's 404 (a block) is not the stream's word: lifted later, the post comes back with the next read (Opus M-2).
    @Test
    func aPostNotFoundByAReadComesBackWhenReadAgain() async {
        store.show(postID: post.id, by: owner)
        service.postIdReturnValue = .failure(.notFound)
        store.apply([.postUpdated(postID: post.id)])
        await store.settle()
        #expect(store.list(.latest)?.ids == [mine.id])

        store.upsert([post])
        store.setList(.latest, FeedStoreList(ids: [post.id, mine.id], nextCursor: nil))
        #expect(store.post(post.id)?.state == .visible)
        #expect(store.list(.latest)?.ids == [post.id, mine.id])
    }

    /// The person's like from another device is not turned back by a page read in flight.
    @Test
    func aViewerLikeIsNotUndoneByAPageInFlight() {
        store.apply([.viewerLike(postID: post.id, liked: true)])
        store.upsert([post])
        #expect(store.post(post.id)?.viewer.liked == true)
    }

    /// Someone else sees `visible` or `gone` (§ 4): gone leaves every list and is "not available" where it is open.
    @Test
    func aPostGoneLeavesEveryList() throws {
        store.apply([.postState(postID: post.id, state: .other("gone"))])

        #expect(store.list(.latest)?.ids == [mine.id])
        #expect(store.list(.author(userID: post.author.userID))?.ids == [])
        #expect(try FeedPostScreenViewModel.loadState(for: #require(store.post(post.id))) == .notAvailable)
    }

    /// The author sees the real state: held leaves Latest but stays in their own list, read again for its reason.
    @Test
    func theAuthorsHeldPostStaysInTheirOwnList() async {
        service.postIdReturnValue = .success(mine)
        store.show(postID: mine.id, by: owner)
        store.apply([.postState(postID: mine.id, state: .held)])
        await store.settle()

        #expect(store.list(.latest)?.ids == [post.id])
        #expect(store.list(.ownPosts)?.ids == [mine.id])
        #expect(service.postIdReceivedId == mine.id)
    }

    /// Review I6 L4: the author's held post released goes back where Latest
    /// and the author's list hold it, not only after a pull; one older than the pages read waits for its page.
    @Test
    func theAuthorsReleasedPostGoesBackInPlace() {
        let newer = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000900", author: FeedPreviewData.ann, minutesAgo: 1, text: "Newer")
        let older = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000100", author: FeedPreviewData.ann, minutesAgo: 9, text: "Older")
        store.upsert([newer, older])
        store.setList(.latest, FeedStoreList(ids: [newer.id, mine.id, older.id], nextCursor: "next"))

        store.apply([.postState(postID: mine.id, state: .held)])
        #expect(store.list(.latest)?.ids == [newer.id, older.id])
        #expect(store.list(.author(userID: post.author.userID))?.ids == [post.id])

        store.apply([.postState(postID: mine.id, state: .visible)])
        #expect(store.list(.latest)?.ids == [newer.id, mine.id, older.id])
        #expect(store.list(.author(userID: post.author.userID))?.ids == [mine.id, post.id])

        store.setList(.latest, FeedStoreList(ids: [newer.id], nextCursor: "next"))
        store.apply([.postState(postID: older.id, state: .held), .postState(postID: older.id, state: .visible)])
        #expect(store.list(.latest)?.ids == [newer.id], "older than the pages read: it comes with its page")
    }

    @Test
    func hiddenLeavesTheListsAndUnhiddenReadsThemAgain() async {
        let reads = Counter()
        store.show(.latest, by: owner) {
            reads.count += 1
            return true
        }
        store.apply([.hidden(postID: post.id)])
        #expect(store.post(post.id)?.viewer.hidden == true)
        #expect(store.list(.latest)?.ids == [mine.id])
        #expect(store.list(.author(userID: post.author.userID))?.ids == [])

        store.apply([.unhidden(postID: post.id)])
        await store.settle()
        #expect(store.post(post.id)?.viewer.hidden == false)
        #expect(reads.count == 1)
        #expect(store.isStale(.author(userID: post.author.userID)), "Off screen: read when it shows")
    }

    // MARK: - Stale

    /// `post_updated` re-reads a post that is shown, once however many changes come while it is read.
    @Test
    func aChangedPostShownIsReadAgainOnceCoalesced() async {
        service.postIdClosure = { [post] _ in
            .success(post.withCommentsEnabled(false))
        }
        store.apply([.postUpdated(postID: post.id)])
        await store.settle()
        #expect(service.postIdCallsCount == 0, "Not shown: nothing is read")

        store.show(.latest, by: owner) { true }
        await store.settle()
        store.apply([.postUpdated(postID: post.id), .postUpdated(postID: post.id), .postUpdated(postID: post.id)])
        await store.settle()

        #expect(service.postIdCallsCount == 2, "One read, and one more for the changes that came while it ran")
        #expect(store.post(post.id)?.commentsEnabled == false)
    }

    /// A failure is not an answer: what is shown stays, and the post stays stale for its next show.
    @Test
    func aFailedReadAgainKeepsThePost() async {
        service.postIdReturnValue = .failure(.transport)
        store.show(postID: post.id, by: owner)
        store.apply([.postUpdated(postID: post.id)])
        await store.settle()

        #expect(store.post(post.id) == post)
    }

    @Test
    func commentsAndLikersAreMarkedStaleByTheirKinds() {
        store.setList(.comments(postID: post.id), FeedStoreList(ids: [], nextCursor: nil))
        store.setList(.likers(postID: post.id), FeedStoreList(ids: [], nextCursor: nil))

        store.apply([.commentAdded(postID: post.id, commentID: "c")])
        #expect(store.isStale(.comments(postID: post.id)))
        #expect(!store.isStale(.likers(postID: post.id)))

        store.apply([.counts(postID: post.id, counts: FeedCounts(likes: 3, comments: 0, shares: 0))])
        #expect(store.isStale(.likers(postID: post.id)))
    }

    /// A list nobody read is not stale: it is read when it opens anyway.
    @Test
    func aListNobodyReadIsNotMarked() {
        store.apply([.postPublished(postID: "n1", authorID: "@olena:spiral.md")])
        #expect(!store.isStale(.author(userID: "@olena:spiral.md")))
        #expect(store.newPostsCount == 1)
    }

    @Test
    func theBlocksMarkEveryListStale() {
        store.apply([.blocks])
        #expect(store.isStale(.latest))
        #expect(store.isStale(.ownPosts))
        #expect(store.isStale(.author(userID: post.author.userID)))
    }

    /// Review I6 M4: a stream that never gets ready reads the badges on its
    /// wait; a failed read is tried on the next wait, a done one is not again.
    @Test
    func aWaitingStreamReadsTheBadgesUntilTheyAreRead() async {
        service.activityCursorLimitReturnValue = .failure(.server(status: 503))

        store.connectionState = .waiting(attempt: 1, isOffline: false)
        await store.settle()
        #expect(service.activityCursorLimitCallsCount == 1)
        #expect(service.noticesCursorLimitLanguageCallsCount == 1)
        #expect(service.noticesCursorLimitLanguageReceivedArguments?.limit == 1)

        service.activityCursorLimitReturnValue = .success(FeedActivityPage(items: [], nextCursor: nil, unread: 3))
        store.connectionState = .connecting
        store.connectionState = .waiting(attempt: 2, isOffline: false)
        await store.settle()
        #expect(service.activityCursorLimitCallsCount == 2, "the failed one is read again")
        #expect(service.noticesCursorLimitLanguageCallsCount == 1, "the one read is not")

        store.connectionState = .waiting(attempt: 3, isOffline: true)
        await store.settle()
        #expect(service.activityCursorLimitCallsCount == 2)
        #expect(service.noticesCursorLimitLanguageCallsCount == 1)
    }

    /// `ready.fresh` and `limited`: what is shown is read now, the rest when it shows, and the badges are read.
    @Test
    func everythingStaleReadsOnlyWhatIsShown() async {
        let latestReads = Counter()
        store.show(.latest, by: owner) {
            latestReads.count += 1
            return true
        }
        service.postIdReturnValue = .success(mine)
        store.show(postID: mine.id, by: owner)
        store.show(postID: "01933f2a-0000-7000-8000-000000000799", by: owner)

        store.markEverythingStale()
        await store.settle()

        #expect(latestReads.count == 1)
        #expect(service.postIdCallsCount == 0, "Its post is read with the list; one the store never held is the screen's to read")
        #expect(store.isStale(.ownPosts))
        #expect(service.activityCursorLimitReceivedArguments?.limit == 1)
        #expect(service.noticesCursorLimitLanguageReceivedArguments?.limit == 1)

        let ownReads = Counter()
        store.show(.ownPosts, by: owner) {
            ownReads.count += 1
            return true
        }
        await store.settle()
        #expect(ownReads.count == 1)
    }

    /// While the catch-up runs the screens say "Updating…".
    @Test
    func theCatchUpShowsAsUpdating() async {
        let gate = Gate()
        store.connectionState = .live
        store.show(.latest, by: owner) {
            await gate.wait()
            return true
        }
        #expect(store.syncStatus == nil)

        store.markEverythingStale()
        #expect(store.syncStatus == .updating)
        gate.open()
        await store.settle()
        #expect(store.syncStatus == nil)
    }

    // MARK: - Local echo: posts

    @Test
    func aPostIsSendingThenTheServersCopyAtTheTop() async {
        let key = UUID()
        service.draftReturnValue = FeedDraft(text: "New", idempotencyKey: key)
        let made = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000702", author: FeedPreviewData.ann, minutesAgo: 0, text: "New", isAuthor: true)
        var during: [FeedPendingPost] = []
        service.createPostTextIdempotencyKeyClosure = { [store] _, _ in
            during = store.pendingPosts
            return .success(made)
        }

        let result = await store.publishPost(text: "New", idempotencyKey: key)

        #expect(result == .success(made))
        #expect(during.map(\.key) == [key])
        #expect(during.first?.delivery == .sending)
        #expect(store.pendingPosts.isEmpty)
        #expect(store.list(.latest)?.ids.first == made.id)
        #expect(store.list(.ownPosts)?.ids.first == made.id)
        #expect(service.deleteDraftCallsCount == 1)
    }

    @Test
    func aRefusedPostStaysAndARetrySendsTheSameKey() async {
        let key = UUID()
        service.createPostTextIdempotencyKeyReturnValue = .failure(.duplicate)
        await store.publishPost(text: "Again", idempotencyKey: key)
        #expect(store.pendingPosts.first?.delivery == .failed(.duplicate))
        #expect(service.deleteDraftCallsCount == 0)

        service.createPostTextIdempotencyKeyReturnValue = .failure(.transport)
        await store.retryPost(key)
        #expect(service.createPostTextIdempotencyKeyReceivedInvocations.map(\.idempotencyKey) == [key, key])
        #expect(store.pendingPosts.count == 1)

        store.discardPost(key)
        #expect(store.pendingPosts.isEmpty)
    }

    // MARK: - Local echo: comments

    @Test
    func aCommentIsSendingThenTheServersCopyCountedOnThePost() async {
        store.setList(.comments(postID: post.id), FeedStoreList(ids: [], nextCursor: nil))
        let made = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000701", author: FeedPreviewData.ann, minutesAgo: 0, text: "Hi", isAuthor: true)
        var during: [FeedPendingComment] = []
        service.createCommentPostIDTextReplyToIdempotencyKeyClosure = { [store, post] _, _, _, _ in
            during = store.pendingComments(on: post.id)
            return .success(made)
        }

        await store.sendComment(postID: post.id, text: "Hi", replyTo: nil, author: FeedPreviewData.ann)

        #expect(during.map(\.text) == ["Hi"])
        #expect(during.first?.comment.isAuthor == true)
        #expect(store.pendingComments.isEmpty)
        #expect(store.list(.comments(postID: post.id))?.ids == [made.id])
        #expect(store.post(post.id)?.counts.comments == post.counts.comments + 1)
    }

    @Test
    func aFailedCommentStaysAndRetriesWithItsKey() async {
        let key = UUID()
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .failure(.transport)
        await store.sendComment(postID: post.id, text: "Hi", replyTo: nil, author: FeedPreviewData.ann, idempotencyKey: key)
        #expect(store.pendingComments.first?.delivery == .failed(.transport))
        #expect(store.post(post.id)?.counts.comments == post.counts.comments)

        await store.retryComment(key)
        #expect(service.createCommentPostIDTextReplyToIdempotencyKeyReceivedInvocations.map(\.idempotencyKey) == [key, key])

        store.discardComment(key)
        #expect(store.pendingComments.isEmpty)
    }

    // MARK: - Helpers

    private func engagement() -> FeedEngagementController {
        FeedEngagementController(store: store, userIndicatorController: UserIndicatorControllerMock())
    }

    private final class Counter {
        var count = 0
    }

    /// Holds a re-read until the test opens it.
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }
}
