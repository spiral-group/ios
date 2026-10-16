//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated enum TimelineEventContent: Hashable {
    case message(EventBasedMessageTimelineItemContentType)
    case poll(question: String)
    case liveLocation
    case redacted
    /// AGENT-PLATFORM (Brief 0066): a post quoted somewhere else — a reply, a
    /// thread summary, a search result.
    ///
    /// It was `.message(.text(title))` until this existed, which made a post
    /// indistinguishable from somebody typing its name. A poll gets its own
    /// case for the same reason, and so does a shared location: what a message
    /// IS matters most exactly where you cannot see it.
    case interactivePost(title: String)
}
