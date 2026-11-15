//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (decision 289, contract § 7). The session's one copy
// of the feed: posts and comments by id, the person's lists as ids, and what
// the person sent that the server has not answered yet (keyed by the
// idempotency key). Every feed screen renders from here and holds only ids and
// its own UI state. A sync change either sets a value (counts, a state, the
// person's like) or marks a post or a list stale; a stale thing on screen is
// read again once, coalesced, and one off screen is read when it shows again.
// A failed read again leaves what was shown. Only the first page of Latest is
// kept on disk, by the service; nothing here is.
//

import Foundation
import Observation

/// A list the person can have on screen.
nonisolated enum FeedListID: Hashable {
    case latest
    case author(userID: String)
    /// The person's own posts in every state (`/feed/me/posts`).
    case ownPosts
    case comments(postID: String)
    /// Activity, who liked a post and the notices: their rows are not shared
    /// by any other screen, so they stay on theirs; the store holds their ids
    /// and marks them stale.
    case activity
    case likers(postID: String)
    case notices
}

nonisolated struct FeedStoreList: Equatable {
    var ids: [String]
    /// Where the next page starts; `nil` at the end.
    var nextCursor: String?
}

/// Something the person sent that the server has not taken yet.
nonisolated enum FeedDelivery: Equatable {
    case sending
    /// Stays on screen with Retry.
    case failed(FeedError)
}

/// A post on its way, shown at once at the top of the person's lists.
nonisolated struct FeedPendingPost: Identifiable, Equatable {
    let key: UUID
    let text: String
    let createdAt: Date
    var delivery: FeedDelivery

    var id: UUID {
        key
    }
}

/// A comment on its way, shown at once under the post.
nonisolated struct FeedPendingComment: Identifiable, Equatable {
    let key: UUID
    let postID: String
    let text: String
    let replyTo: FeedCommentReply?
    let author: FeedAuthor
    let createdAt: Date
    var delivery: FeedDelivery

    var id: UUID {
        key
    }

    /// The row the comment will be, until the server's copy replaces it.
    var comment: FeedComment {
        FeedComment(id: "pending-\(key.uuidString.lowercased())", postID: postID, author: author, text: text, replyTo: replyTo,
                    createdAt: createdAt, state: .visible, heldReason: nil, isAuthor: true, canDelete: false, isSensitive: false)
    }
}

/// What the sync stream (or the person's own action) said of a post last: a
/// page read that started before it must not undo it (a post gone coming
/// back, a hide undone, counts going backwards).
nonisolated struct FeedPostFacts: Equatable {
    var state: FeedPostState?
    var counts: FeedCounts? {
        didSet { countsVersion = version }
    }

    var hidden: Bool?
    var liked: Bool? {
        didSet { likedVersion = version }
    }

    /// Bumped on every write, so a read that started before the last one does not end the record.
    var version = 0
    /// The writes that last said the counts and the person's like, so a like
    /// knows whether the stream spoke of them while it was on its way.
    private(set) var countsVersion = 0
    private(set) var likedVersion = 0

    /// The person's like and the likes count as the record has said them after `clock`, over `likes`.
    func likes(saidSince clock: Int, over likes: FeedLikes) -> FeedLikes {
        FeedLikes(likes: countsVersion > clock ? counts?.likes ?? likes.likes : likes.likes,
                  liked: likedVersion > clock ? liked ?? likes.liked : likes.liked)
    }

    /// The like and the likes count only, with when they were said; the rest is `counts`, a read's.
    func keepingLike(over counts: FeedCounts) -> FeedPostFacts {
        var kept = FeedPostFacts()
        kept.version = version
        kept.liked = liked
        kept.counts = self.counts.map { FeedCounts(likes: $0.likes, comments: counts.comments, shares: counts.shares) }
        // After the writes above, which stamp them with `version`.
        kept.likedVersion = likedVersion
        kept.countsVersion = countsVersion
        return kept
    }

    func applied(to post: FeedPost) -> FeedPost {
        var post = post
        if let state {
            post.state = state
        }
        if let counts {
            post.counts = counts
        }
        if let hidden {
            post.viewer.hidden = hidden
        }
        if let liked {
            post.viewer.liked = liked
        }
        return post
    }
}

/// How a like ended.
nonisolated enum FeedLikeOutcome: Equatable {
    /// The server's answer.
    case answered(FeedLikes)
    /// Refused: the app's guess goes back to what was shown before it.
    case refused(rollback: FeedLikes)
}

@Observable
final class FeedStore {
    /// The "N new posts" pill counts at most this many ("99+").
    static let newPostsCap = 99

    @ObservationIgnored let feedService: FeedServiceProtocol
    @ObservationIgnored let currentUserID: String

    private(set) var posts: [String: FeedPost] = [:]
    private(set) var comments: [String: FeedComment] = [:]
    private(set) var lists: [FeedListID: FeedStoreList] = [:]
    /// Newest first.
    private(set) var pendingPosts: [FeedPendingPost] = []
    /// Oldest first.
    private(set) var pendingComments: [FeedPendingComment] = []
    /// Posts published after Latest was read, for the pill (`feed.post_published`).
    private(set) var newPostIDs: Set<String> = []
    /// Set by `PlatformSync`.
    var connectionState: PlatformSyncConnectionState = .idle {
        didSet {
            // A stream that never gets ready (a 429, the server away) leaves the bell
            // unread otherwise: its first wait reads it, as `ready` would have.
            if case .waiting = connectionState {
                for badge in [FeedListID.activity, .notices] where !badgesRead.contains(badge) && !isShown(badge) {
                    rereadBadge(badge)
                }
            }
        }
    }

    /// Re-reads started by `ready.fresh` or `limited` that have not finished.
    private(set) var catchUpCount = 0

    /// The record's clock when each like on its way began.
    @ObservationIgnored private var likesInFlight: [String: Int] = [:]
    /// Kept over a page's copy until a read of that post alone, started after them, answers.
    @ObservationIgnored private var postFacts: [String: FeedPostFacts] = [:]
    @ObservationIgnored private var postFactsClock = 0
    @ObservationIgnored private var staleLists: Set<FeedListID> = []
    @ObservationIgnored private var stalePosts: Set<String> = []
    @ObservationIgnored private var shownLists: [FeedListID: [ObjectIdentifier: @MainActor @Sendable () async -> Bool]] = [:]
    @ObservationIgnored private var shownPosts: [String: Set<ObjectIdentifier>] = [:]
    @ObservationIgnored private var listRereadsInFlight: Set<FeedListID> = []
    @ObservationIgnored private var listsToRereadAgain: Set<FeedListID> = []
    @ObservationIgnored private var postRereadsInFlight: Set<String> = []
    @ObservationIgnored private var postsToRereadAgain: Set<String> = []
    @ObservationIgnored private var badgeRereadsInFlight: Set<FeedListID> = []
    /// The badges read since launch; until then each wait of the stream tries again.
    @ObservationIgnored private var badgesRead: Set<FeedListID> = []
    /// The re-reads running now, for tests to wait on.
    @ObservationIgnored private(set) var rereadTasks: [UUID: Task<Void, Never>] = [:]

    init(feedService: FeedServiceProtocol, currentUserID: String) {
        self.feedService = feedService
        self.currentUserID = currentUserID
    }

    var newPostsCount: Int {
        min(newPostIDs.count, Self.newPostsCap)
    }

    var syncStatus: PlatformSyncStatus? {
        connectionState.status(isCatchingUp: catchUpCount > 0)
    }

    /// Reads everything a screen renders, so `withObservationTracking` follows it all.
    func trackRenderedState() {
        _ = posts
        _ = comments
        _ = lists
        _ = pendingPosts
        _ = pendingComments
        _ = newPostIDs
        _ = connectionState
        _ = catchUpCount
    }

    /// Calls `onChange` after changes to what screens render, coalesced per
    /// turn of the main actor, for as long as it answers `true` (its owner lives).
    func observe(_ onChange: @escaping @MainActor @Sendable () -> Bool) {
        withObservationTracking {
            trackRenderedState()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, onChange() else { return }
                observe(onChange)
            }
        }
    }

    // MARK: - Reads

    func post(_ id: String) -> FeedPost? {
        posts[id]
    }

    func list(_ id: FeedListID) -> FeedStoreList? {
        lists[id]
    }

    func comment(_ id: String) -> FeedComment? {
        comments[id]
    }

    /// The posts of a list in order, those the store holds.
    func posts(in list: FeedListID) -> [FeedPost] {
        (lists[list]?.ids ?? []).compactMap { posts[$0] }
    }

    func comments(in list: FeedListID) -> [FeedComment] {
        (lists[list]?.ids ?? []).compactMap { comments[$0] }
    }

    func pendingComments(on postID: String) -> [FeedPendingComment] {
        pendingComments.filter { $0.postID == postID }
    }

    func isLikeInFlight(postID: String) -> Bool {
        likesInFlight[postID] != nil
    }

    // MARK: - Writes from reads

    /// Posts as a read gave them. What the stream said since (a state, counts,
    /// a hide) wins over the read's copy, which may have started before it;
    /// a like on its way keeps what the app shows for it.
    func upsert(_ newPosts: [FeedPost]) {
        guard !newPosts.isEmpty else { return }
        var updated = posts
        for var post in newPosts {
            if let facts = postFacts[post.id] {
                post = facts.applied(to: post)
            }
            if likesInFlight[post.id] != nil, let shown = updated[post.id] {
                post.viewer.liked = shown.viewer.liked
                post.counts.likes = shown.counts.likes
            }
            stalePosts.remove(post.id)
            if updated[post.id] != post {
                updated[post.id] = post
            }
        }
        if updated != posts {
            posts = updated
        }
    }

    func upsert(_ newComments: [FeedComment]) {
        guard !newComments.isEmpty else { return }
        var updated = comments
        for comment in newComments {
            updated[comment.id] = comment
        }
        if updated != comments {
            comments = updated
        }
    }

    /// A page's ids, without a post the stream took out of the list since the page was asked for.
    func setList(_ id: FeedListID, _ list: FeedStoreList) {
        var list = list
        list.ids = list.ids.filter { isListable($0, in: id) }
        staleLists.remove(id)
        if id == .latest {
            // What the person sees now is read: the pill counts from here.
            newPostIDs.subtract(list.ids)
        }
        if lists[id] != list {
            lists[id] = list
        }
    }

    /// Read above the top of Latest without moving what the person sees: the pill shows them.
    func addNewPosts(_ postIDs: some Sequence<String>) {
        let added = Set(postIDs).subtracting(lists[.latest]?.ids ?? [])
        if !added.isSubset(of: newPostIDs) {
            newPostIDs.formUnion(added)
        }
    }

    /// The pill was tapped, or Latest was read from its top again.
    func clearNewPosts() {
        if !newPostIDs.isEmpty {
            newPostIDs = []
        }
    }

    // MARK: - What is shown

    /// `owner` shows `list`; `reread` reads it again (`true` once read). A list
    /// that went stale while nobody showed it is read again now.
    func show(_ list: FeedListID, by owner: AnyObject, reread: @escaping @MainActor @Sendable () async -> Bool) {
        shownLists[list, default: [:]][ObjectIdentifier(owner)] = reread
        rereadIfShown(list)
    }

    func stopShowing(_ list: FeedListID, by owner: AnyObject) {
        shownLists[list]?[ObjectIdentifier(owner)] = nil
        if shownLists[list]?.isEmpty == true {
            shownLists[list] = nil
        }
    }

    /// `owner` shows the post on its own (the post screen).
    func show(postID: String, by owner: AnyObject) {
        shownPosts[postID, default: []].insert(ObjectIdentifier(owner))
        rereadIfShown(postID: postID)
    }

    func stopShowing(postID: String, by owner: AnyObject) {
        shownPosts[postID]?.remove(ObjectIdentifier(owner))
        if shownPosts[postID]?.isEmpty == true {
            shownPosts[postID] = nil
        }
    }

    private func recordFact(_ postID: String, _ write: (inout FeedPostFacts) -> Void) {
        postFactsClock += 1
        var facts = postFacts[postID] ?? FeedPostFacts()
        // First, so the fields written below are stamped with this write.
        facts.version = postFactsClock
        write(&facts)
        postFacts[postID] = facts
    }

    /// Latest and an author's posts hold visible posts the person has not hidden; their own list every state they can see.
    private func isListable(_ postID: String, in list: FeedListID) -> Bool {
        guard let post = posts[postID] else { return true }
        switch list {
        case .latest, .author:
            return post.state == .visible && !post.viewer.hidden
        case .ownPosts:
            return post.state != .other("gone")
        case .comments, .activity, .likers, .notices:
            return true
        }
    }

    func isShown(_ list: FeedListID) -> Bool {
        shownLists[list] != nil
    }

    func isStale(_ list: FeedListID) -> Bool {
        staleLists.contains(list)
    }

    private func isShown(postID: String) -> Bool {
        shownPosts[postID] != nil || shownLists.keys.contains { lists[$0]?.ids.contains(postID) == true }
    }

    // MARK: - The sync stream

    /// `ready.fresh` or `limited`: anything may have changed. What is shown is
    /// read again now; the rest when it shows. The badges are read again too.
    func markEverythingStale() {
        // Changes were missed: what the stream said before is no newer than the reads that follow.
        postFacts = [:]
        staleLists.formUnion(lists.keys)
        staleLists.formUnion(shownLists.keys)
        stalePosts.formUnion(posts.keys)

        for list in shownLists.keys {
            rereadIfShown(list, isCatchUp: true)
        }
        // Posts in a list being read come with it; the rest on their own.
        let readWithLists = Set(shownLists.keys.flatMap { lists[$0]?.ids ?? [] })
        for postID in shownPosts.keys where !readWithLists.contains(postID) {
            rereadIfShown(postID: postID, isCatchUp: true)
        }
        for badge in [FeedListID.activity, .notices] where !isShown(badge) {
            rereadBadge(badge)
        }
    }

    func apply(_ changes: [FeedSyncChange]) {
        for change in changes {
            apply(change)
        }
    }

    private func apply(_ change: FeedSyncChange) {
        switch change {
        case .postPublished(let postID, let authorID):
            if authorID != currentUserID, lists[.latest]?.ids.contains(postID) != true, posts[postID]?.viewer.isAuthor != true {
                newPostIDs.insert(postID)
            }
            markStale(.author(userID: authorID))
            if authorID == currentUserID {
                markStale(.ownPosts)
            }
        case .postState(let postID, let newState):
            if newState != .visible {
                newPostIDs.remove(postID)
            }
            recordFact(postID) { $0.state = newState }
            guard var post = posts[postID] else { return }
            let wasVisible = post.state == .visible
            post.state = newState
            posts[postID] = post
            if newState != .visible {
                removeFromLists(postID, keepingOwn: post.viewer.isAuthor)
            } else if !wasVisible, !post.viewer.hidden {
                // Released (the author's held post): back where it was, not only after a pull.
                insertInPlace(postID, of: .latest)
                insertInPlace(postID, of: .author(userID: post.author.userID))
            }
            if post.viewer.isAuthor, newState == .held || newState == .removed {
                // The author's banner names why: that comes with the post.
                markStale(postID: postID)
            }
        case .postUpdated(let postID):
            markStale(postID: postID)
        case .counts(let postID, let counts):
            recordFact(postID) { $0.counts = counts }
            guard var post = posts[postID] else { return }
            let likesMoved = post.counts.likes != counts.likes
            post.counts.comments = counts.comments
            post.counts.shares = counts.shares
            if likesInFlight[postID] == nil {
                // A like on its way shows the app's count until the server's answer.
                post.counts.likes = counts.likes
            }
            if posts[postID] != post {
                posts[postID] = post
            }
            if likesMoved {
                markStale(.likers(postID: postID))
            }
        case .commentAdded(let postID, _), .commentRemoved(let postID, _):
            markStale(.comments(postID: postID))
        case .viewerLike(let postID, let liked):
            recordFact(postID) { $0.liked = liked }
            guard likesInFlight[postID] == nil, var post = posts[postID], post.viewer.liked != liked else { return }
            post.viewer.liked = liked
            posts[postID] = post
        case .hidden(let postID):
            setHidden(true, postID: postID)
        case .unhidden(let postID):
            setHidden(false, postID: postID)
        case .blocks:
            for list in Set(lists.keys).union(shownLists.keys) where list != .notices {
                markStale(list)
            }
        case .activity:
            markStale(.activity)
        case .notice:
            markStale(.notices)
        }
    }

    /// A list nobody read is not stale: it is read when it opens.
    private func markStale(_ list: FeedListID) {
        guard lists[list] != nil || isShown(list) else {
            if list == .activity || list == .notices {
                rereadBadge(list)
            }
            return
        }
        staleLists.insert(list)
        if isShown(list) {
            rereadIfShown(list)
        } else if list == .activity || list == .notices {
            rereadBadge(list)
        }
    }

    private func markStale(postID: String) {
        guard posts[postID] != nil else { return }
        stalePosts.insert(postID)
        rereadIfShown(postID: postID)
    }

    private func rereadIfShown(_ list: FeedListID, isCatchUp: Bool = false) {
        guard staleLists.contains(list), let reread = shownLists[list]?.values.first else { return }
        guard !listRereadsInFlight.contains(list) else {
            listsToRereadAgain.insert(list)
            return
        }
        staleLists.remove(list)
        listRereadsInFlight.insert(list)
        if isCatchUp {
            catchUpCount += 1
        }
        track { [weak self] in
            let isRead = await reread()
            guard let self else { return }
            listRereadsInFlight.remove(list)
            if isCatchUp {
                catchUpCount -= 1
            }
            if !isRead {
                // Read when it next shows; what is shown stays.
                staleLists.insert(list)
            }
            if listsToRereadAgain.remove(list) != nil {
                staleLists.insert(list)
                rereadIfShown(list)
            }
        }
    }

    private func rereadIfShown(postID: String, isCatchUp: Bool = false) {
        guard stalePosts.contains(postID), isShown(postID: postID) else { return }
        guard !postRereadsInFlight.contains(postID) else {
            postsToRereadAgain.insert(postID)
            return
        }
        postRereadsInFlight.insert(postID)
        if isCatchUp {
            catchUpCount += 1
        }
        let versionAtStart = postFacts[postID]?.version
        track { [weak self, feedService] in
            let result = await FeedReadWindow.retryingOnce { await feedService.post(id: postID) }
            guard let self else { return }
            postRereadsInFlight.remove(postID)
            if isCatchUp {
                catchUpCount -= 1
            }
            switch result {
            case .success(let post):
                // Newer than what the stream said before the read started; not than what it said since.
                if let facts = postFacts[postID], facts.version == versionAtStart {
                    // A like on its way needs what the stream said of it since it began; the read gives it no answer.
                    postFacts[postID] = likesInFlight[postID] != nil ? facts.keepingLike(over: post.counts) : nil
                }
                upsert([post])
            case .failure(.notFound):
                markGone(postID)
            case .failure(let error):
                // What is shown stays; it is read again when it next shows.
                MXLog.info("Could not read feed post \(postID) again: \(error)")
            }
            if postsToRereadAgain.remove(postID) != nil {
                stalePosts.insert(postID)
                rereadIfShown(postID: postID)
            }
        }
    }

    /// The bell's counts: read again by the list when it shows, else on their own.
    private func rereadBadge(_ badge: FeedListID) {
        guard badgeRereadsInFlight.insert(badge).inserted else { return }
        track { [weak self, feedService] in
            let isRead: Bool
            switch badge {
            case .activity:
                let result = await FeedReadWindow.retryingOnce { await feedService.activity(cursor: nil, limit: 1) }
                if case .failure(let error) = result {
                    MXLog.info("Could not read the feed activity's unread count: \(error)")
                }
                isRead = (try? result.get()) != nil
            default:
                let result = await FeedReadWindow.retryingOnce { await feedService.notices(cursor: nil, limit: 1, language: nil) }
                if case .failure(let error) = result {
                    MXLog.info("Could not read the feed notices' unread count: \(error)")
                }
                isRead = (try? result.get()) != nil
            }
            guard let self else { return }
            badgeRereadsInFlight.remove(badge)
            if isRead {
                badgesRead.insert(badge)
            }
        }
    }

    /// Each re-read is kept until it ends, for tests to wait on.
    private func track(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        let id = UUID()
        rereadTasks[id] = Task { [weak self] in
            await operation()
            self?.rereadTasks[id] = nil
        }
    }

    // MARK: - The person's own changes

    /// `false` when a like of the post is already on its way.
    func beginLike(postID: String) -> Bool {
        guard likesInFlight[postID] == nil else { return false }
        likesInFlight[postID] = postFactsClock
        return true
    }

    /// The like or unlike as the app shows it before the server's answer.
    func setLikes(_ likes: FeedLikes, postID: String) {
        guard var post = posts[postID] else { return }
        post.viewer.liked = likes.liked
        post.counts.likes = likes.likes
        if posts[postID] != post {
            posts[postID] = post
        }
    }

    /// The server's answer is recorded, so a page read in flight does not undo
    /// it; a refusal is not. What the stream said of the like or the count
    /// after the like began is newer than either (the person may have unliked
    /// on another device meanwhile): it stays in the record and shows.
    func endLike(postID: String, _ outcome: FeedLikeOutcome) {
        guard let began = likesInFlight.removeValue(forKey: postID) else { return }
        let likes: FeedLikes
        switch outcome {
        case .answered(let answer):
            recordFact(postID) { facts in
                if facts.likedVersion <= began {
                    facts.liked = answer.liked
                }
                if facts.countsVersion <= began, facts.counts != nil {
                    facts.counts?.likes = answer.likes
                }
            }
            likes = answer
        case .refused(let rollback):
            likes = rollback
        }
        setLikes(postFacts[postID]?.likes(saidSince: began, over: likes) ?? likes, postID: postID)
    }

    /// Out of Latest and the authors' lists; still readable by id. Shown again,
    /// it is where the server puts it, which may be any page: those lists are read again.
    func setHidden(_ hidden: Bool, postID: String) {
        recordFact(postID) { $0.hidden = hidden }
        if var post = posts[postID], post.viewer.hidden != hidden {
            post.viewer.hidden = hidden
            posts[postID] = post
        }
        if hidden {
            removeFromLists(postID, keepingOwn: true)
        } else {
            markStale(.latest)
            if let authorID = posts[postID]?.author.userID {
                markStale(.author(userID: authorID))
            }
        }
    }

    /// The author deleted it.
    func removePost(_ postID: String) {
        recordFact(postID) { $0.state = .other("gone") }
        removeFromLists(postID, keepingOwn: false)
        posts[postID] = nil
        newPostIDs.remove(postID)
    }

    /// Not there for the person any more: out of every list, "not available" where it is open.
    /// No record: a read's 404 may be a block that the person lifts later, with no stream change to say so.
    private func markGone(_ postID: String) {
        guard var post = posts[postID] else { return }
        post.state = .other("gone")
        posts[postID] = post
        removeFromLists(postID, keepingOwn: false)
    }

    private func removeFromLists(_ postID: String, keepingOwn: Bool) {
        var updated = lists
        for (id, list) in lists {
            switch id {
            case .latest, .author:
                break
            case .ownPosts where !keepingOwn:
                break
            default:
                continue
            }
            guard list.ids.contains(postID) else { continue }
            updated[id]?.ids.removeAll { $0 == postID }
        }
        if updated != lists {
            lists = updated
        }
    }

    // MARK: - Posting (local echo)

    /// Shows the post at once as sending, then as the server made it. The key
    /// is the composer's: a retry, and a draft restored after the app closed,
    /// send the same one, so the server answers the post it already made.
    @discardableResult
    func publishPost(text: String, idempotencyKey: UUID) async -> Result<FeedPost, FeedError> {
        if let index = pendingPosts.firstIndex(where: { $0.key == idempotencyKey }) {
            pendingPosts[index].delivery = .sending
        } else {
            pendingPosts.insert(FeedPendingPost(key: idempotencyKey, text: text, createdAt: .now, delivery: .sending), at: 0)
        }

        let result = await feedService.createPost(text: text, idempotencyKey: idempotencyKey)
        switch result {
        case .success(let post):
            pendingPosts.removeAll { $0.key == idempotencyKey }
            deleteDraft(withKey: idempotencyKey)
            upsert([post])
            insertAtTop(post.id, of: .ownPosts)
            if post.state == .visible {
                insertAtTop(post.id, of: .latest)
            }
        case .failure(.idempotencyKeyReused):
            // An earlier text was made with the key: it is read in, and this text needs a key of its own.
            markStale(.latest)
            markStale(.ownPosts)
            let newKey = UUID()
            replacePendingPost(idempotencyKey, with: newKey, delivery: .failed(.idempotencyKeyReused))
            feedService.saveDraft(FeedDraft(text: text, idempotencyKey: newKey))
        case .failure(let error):
            MXLog.error("Failed to publish a feed post: \(error)")
            updatePendingPost(idempotencyKey) { $0.delivery = .failed(error) }
        }
        return result
    }

    @discardableResult
    func retryPost(_ key: UUID) async -> Result<FeedPost, FeedError>? {
        guard let pending = pendingPosts.first(where: { $0.key == key }), pending.delivery != .sending else { return nil }
        return await publishPost(text: pending.text, idempotencyKey: key)
    }

    /// The person gave up on it: the draft goes with it.
    func discardPost(_ key: UUID) {
        guard pendingPosts.contains(where: { $0.key == key && $0.delivery != .sending }) else { return }
        pendingPosts.removeAll { $0.key == key }
        deleteDraft(withKey: key)
    }

    private func updatePendingPost(_ key: UUID, _ update: (inout FeedPendingPost) -> Void) {
        guard let index = pendingPosts.firstIndex(where: { $0.key == key }) else { return }
        update(&pendingPosts[index])
    }

    private func replacePendingPost(_ key: UUID, with newKey: UUID, delivery: FeedDelivery) {
        guard let index = pendingPosts.firstIndex(where: { $0.key == key }) else { return }
        let pending = pendingPosts[index]
        pendingPosts[index] = FeedPendingPost(key: newKey, text: pending.text, createdAt: pending.createdAt, delivery: delivery)
    }

    private func deleteDraft(withKey key: UUID) {
        if feedService.draft()?.idempotencyKey == key {
            feedService.deleteDraft()
        }
    }

    /// Where the server lists it (newest id first), when that is within the pages read.
    private func insertInPlace(_ postID: String, of list: FeedListID) {
        guard var entry = lists[list], !entry.ids.contains(postID) else { return }
        if let index = entry.ids.firstIndex(where: { $0 < postID }) {
            entry.ids.insert(postID, at: index)
        } else if entry.nextCursor == nil {
            entry.ids.append(postID)
        } else {
            // Older than every post read: it comes with the next page.
            return
        }
        lists[list] = entry
    }

    private func insertAtTop(_ postID: String, of list: FeedListID) {
        guard var entry = lists[list], !entry.ids.contains(postID) else { return }
        entry.ids.insert(postID, at: 0)
        lists[list] = entry
    }

    // MARK: - Comments (local echo)

    /// Shows the comment at once as sending, then as the server made it. One
    /// key per comment: a retry sends the same text with the same key.
    @discardableResult
    func sendComment(postID: String, text: String, replyTo: FeedCommentReply?, author: FeedAuthor,
                     idempotencyKey: UUID = UUID()) async -> Result<FeedComment, FeedError> {
        if let index = pendingComments.firstIndex(where: { $0.key == idempotencyKey }) {
            pendingComments[index].delivery = .sending
        } else {
            pendingComments.append(FeedPendingComment(key: idempotencyKey, postID: postID, text: text, replyTo: replyTo,
                                                      author: author, createdAt: .now, delivery: .sending))
        }

        let result = await feedService.createComment(postID: postID, text: text, replyTo: replyTo?.id, idempotencyKey: idempotencyKey)
        switch result {
        case .success(let comment):
            pendingComments.removeAll { $0.key == idempotencyKey }
            addComment(comment, postID: postID)
        case .failure(let error):
            MXLog.error("Failed to send a comment on feed post \(postID): \(error)")
            if let index = pendingComments.firstIndex(where: { $0.key == idempotencyKey }) {
                pendingComments[index].delivery = .failed(error)
            }
        }
        return result
    }

    @discardableResult
    func retryComment(_ key: UUID) async -> Result<FeedComment, FeedError>? {
        guard let pending = pendingComments.first(where: { $0.key == key }), pending.delivery != .sending else { return nil }
        return await sendComment(postID: pending.postID, text: pending.text, replyTo: pending.replyTo, author: pending.author, idempotencyKey: key)
    }

    func discardComment(_ key: UUID) {
        pendingComments.removeAll { $0.key == key && $0.delivery != .sending }
    }

    /// The server's copy, in time order (UUIDv7 ids sort by time); a visible one counts on the post.
    private func addComment(_ comment: FeedComment, postID: String) {
        let isNew = comments[comment.id] == nil
        comments[comment.id] = comment
        let listID = FeedListID.comments(postID: postID)
        if var list = lists[listID], !list.ids.contains(comment.id) {
            list.ids.append(comment.id)
            list.ids.sort()
            lists[listID] = list
        }
        if isNew, comment.state == .visible, var post = posts[postID] {
            post.counts.comments += 1
            posts[postID] = post
        }
    }

    /// Deleted by the person; replies to it lose their "replying to", as on the server.
    func removeComment(_ commentID: String, postID: String) {
        let removed = comments[commentID]
        let listID = FeedListID.comments(postID: postID)
        if var list = lists[listID], list.ids.contains(commentID) {
            list.ids.removeAll { $0 == commentID }
            lists[listID] = list
        }
        var updated = comments
        updated[commentID] = nil
        for (id, comment) in updated where comment.replyTo?.id == commentID {
            updated[id] = comment.withoutReply
        }
        comments = updated
        if removed?.state == .visible, var post = posts[postID] {
            post.counts.comments = max(0, post.counts.comments - 1)
            posts[postID] = post
        }
    }
}
