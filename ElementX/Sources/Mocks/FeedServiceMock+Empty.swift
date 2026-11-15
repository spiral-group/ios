//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082).
//

import Combine
import Foundation

extension FeedServiceMock {
    /// A feed with nothing in it, for flows that bring up the Feed tab without testing it.
    static func empty() -> FeedServiceMock {
        let mock = FeedServiceMock()
        mock.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        mock.postIdReturnValue = .failure(.notFound)
        mock.authorPostsUserIDCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        mock.cachedFirstPageReturnValue = nil
        mock.ownPostsCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        mock.draftReturnValue = nil
        mock.standingReturnValue = .failure(.unavailable)
        mock.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [], nextCursor: nil))
        mock.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
        mock.noticesUnreadPublisher = Empty().eraseToAnyPublisher()
        mock.notificationSettingsReturnValue = .failure(.unavailable)
        // Lane I5: no activity and nobody liked.
        mock.activityCursorLimitReturnValue = .success(FeedActivityPage(items: [], nextCursor: nil, unread: 0))
        mock.markActivitySeenUpToReturnValue = .success(0)
        mock.activityUnreadPublisher = Empty().eraseToAnyPublisher()
        mock.likersPostIDCursorLimitReturnValue = .success(FeedLikersPage(items: [], nextCursor: nil))
        return mock
    }
}

extension PlatformSyncServiceMock {
    /// No sync on this backend: the stream stays closed.
    static func unavailable() -> PlatformSyncServiceMock {
        let mock = PlatformSyncServiceMock()
        mock.openSinceReturnValue = .failure(.unavailable)
        return mock
    }
}
