//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, § 5.82): where a tap on a game's ping goes.
//

import UserNotifications

extension UNNotificationContent {
    /// The room, opened on the post the ping came from — the road a link to a
    /// message takes, and the pinned bar. A move is a hidden event, so the
    /// event the notification names cannot be scrolled to; its post can.
    var spiralPostRoute: AppRoute? {
        guard let roomID, let spiralPostEventID else { return nil }
        return .event(eventID: spiralPostEventID, roomID: roomID, via: [])
    }
}
