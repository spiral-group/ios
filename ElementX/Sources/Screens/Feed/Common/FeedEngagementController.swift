//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Like and hide as every feed screen does
// them (lane I3), on the session's one `FeedStore` (decision 289): one like or
// unlike per post is in flight in the whole session, so answers never arrive
// out of order; a like shows at once on every screen that holds the post and
// is rolled back on all of them when the server refuses it. A hide is said
// only once the server has made it.
//

import Foundation

final class FeedEngagementController {
    let store: FeedStore
    private let userIndicatorController: UserIndicatorControllerProtocol

    var feedService: FeedServiceProtocol {
        store.feedService
    }

    init(store: FeedStore, userIndicatorController: UserIndicatorControllerProtocol) {
        self.store = store
        self.userIndicatorController = userIndicatorController
    }

    /// Likes or unlikes the post as the store holds it; every screen follows.
    func toggleLike(_ post: FeedPost) async {
        let post = store.post(post.id) ?? post
        guard post.state == .visible, store.beginLike(postID: post.id) else { return }

        let before = FeedLikes(likes: post.counts.likes, liked: post.viewer.liked)
        store.setLikes(FeedLikes(likes: max(0, before.likes + (before.liked ? -1 : 1)), liked: !before.liked), postID: post.id)

        switch await feedService.setLiked(!before.liked, postID: post.id) {
        case .success(let likes):
            store.endLike(postID: post.id, .answered(likes))
        case .failure(let error):
            MXLog.error("Failed to \(before.liked ? "unlike" : "like") feed post \(post.id): \(error)")
            store.endLike(postID: post.id, .refused(rollback: before))
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: Self.likeFailure(error, wasLiked: before.liked), icon: \.close))
        }
    }

    /// Hides `postID` from the person's lists; `true` once the server has.
    func hide(postID: String) async -> Bool {
        let indicatorID = UUID().uuidString
        userIndicatorController.submitIndicator(UserIndicator(id: indicatorID,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: .milliseconds(200))
        let result = await feedService.setHidden(true, postID: postID)
        userIndicatorController.retractIndicatorWithId(indicatorID)

        switch result {
        case .success:
            store.setHidden(true, postID: postID)
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: UntranslatedL10n.screenFeedHidden, icon: \.visibilityOff))
            return true
        case .failure(let error):
            MXLog.error("Failed to hide feed post \(postID): \(error)")
            let title = error == .notFound ? UntranslatedL10n.screenFeedPostNotAvailableTitle : UntranslatedL10n.screenFeedHideFailed
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: title, icon: \.close))
            return false
        }
    }

    static func likeFailure(_ error: FeedError, wasLiked: Bool) -> String {
        switch error {
        case .rateLimited: UntranslatedL10n.screenFeedLikeRateLimited
        case .notFound: UntranslatedL10n.screenFeedPostNotAvailableTitle
        default: wasLiked ? UntranslatedL10n.screenFeedUnlikeFailed : UntranslatedL10n.screenFeedLikeFailed
        }
    }
}
