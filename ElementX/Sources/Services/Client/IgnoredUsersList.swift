//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the account's ignore list (`m.ignored_user_list`) behind
// `ClientProxy.ignoredUsersPublisher`.
//
// `subscribeToIgnoredUsers` first hands over the SDK's in-memory list, which a
// launch never restores from the store: it stays `[]` until a sync *changes*
// the list (a restored sync position doesn't resend it, and the SDK fires only
// on a difference from the stored copy). Taken as the list, that `[]` hid
// Settings › Privacy › Blocked users, put blocked people back in the feed and
// had `OwnerBlocksSync` tell the platform the owner blocks nobody.
//
// So the first value is skipped: the list is unknown (`nil`) until `refresh`
// read it, and every later value (a sync's change) is taken as it comes.
//
// The contract: `ClientProxy.setupSubscriptions` must run before the first
// sync starts. It does: the proxy's `init` awaits it before anything, such as
// `resumeServices`, starts the sync service. So the first value is always the
// SDK's start, never a sync's change. Moved after a sync, the subscription's
// first value could be a real change, and skipping it would lose that change
// until `refresh`.
//

import Combine
import Foundation

final class IgnoredUsersList {
    private let subject = CurrentValueSubject<[String]?, Never>(nil)
    /// The SDK subscription's first value, its unrestored in-memory list, was seen.
    private var hasSeenSubscriptionStart = false
    /// Bumped by every change a sync delivered, so a read in flight before one
    /// never replaces it.
    private var syncChanges = 0
    private var isRefreshing = false

    var publisher: CurrentValuePublisher<[String]?, Never> {
        subject.asCurrentValuePublisher()
    }

    /// Whether the list has been read or changed since launch.
    var isKnown: Bool {
        subject.value != nil
    }

    /// A value from the SDK's ignored-users subscription.
    func subscriptionDelivered(_ userIDs: [String]) {
        guard hasSeenSubscriptionStart else {
            hasSeenSubscriptionStart = true
            return
        }
        syncChanges += 1
        subject.send(userIDs)
    }

    /// Waits between the tries of `load`.
    static let retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)]

    /// Reads the list until it is known: a failed read is tried again after each
    /// of `retryDelays`, and a sync's change meanwhile ends the tries. While it is
    /// unknown, Blocked users is hidden and the feed can't hide blocked people.
    func load(retryDelays: [Duration] = IgnoredUsersList.retryDelays, _ read: () async throws -> [String]) async {
        for delay in [Duration.zero] + retryDelays {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !isKnown, !Task.isCancelled else { return }
            do {
                try await refresh(read)
                // A refresh already in flight returns without reading; try again if it didn't land.
                if isKnown { return }
            } catch {
                MXLog.error("Failed fetching ignored users with error: \(error)")
            }
        }
    }

    /// Reads the list with `read` (the server's copy) and takes it, unless a
    /// sync changed the list meanwhile.
    /// A refresh already in flight makes this one a no-op.
    func refresh(_ read: () async throws -> [String]) async throws {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let changes = syncChanges
        let userIDs = try await read()
        guard syncChanges == changes else { return }
        subject.send(userIDs)
    }
}
