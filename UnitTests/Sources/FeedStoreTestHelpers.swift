//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (decision 289). The session's store and engagement
// controller as the feed suites build them.
//

import Foundation
@testable import Spiral

extension FeedEngagementController {
    /// A fresh store over `service`, for the person `@me:spiral.md`.
    static func make(_ service: FeedServiceProtocol,
                     userIndicatorController: UserIndicatorControllerProtocol = UserIndicatorControllerMock(),
                     currentUserID: String = "@me:spiral.md") -> FeedEngagementController {
        FeedEngagementController(store: FeedStore(feedService: service, currentUserID: currentUserID),
                                 userIndicatorController: userIndicatorController)
    }
}

extension FeedStore {
    /// Waits until no re-read runs, those a re-read started included.
    func settle() async {
        while let task = rereadTasks.values.first {
            await task.value
            // Let the finished task take itself out before looking again.
            await Task.yield()
        }
    }
}
