//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I2's identifiers, for the E2E
// scenarios FD4 (held, author only) and FD8.
//

extension A11yIdentifiers {
    static let feedComposerScreen = FeedComposerScreen()

    struct FeedComposerScreen {
        let compose = "feed_composer-compose"
        let ownPosts = "feed_composer-own_posts"
        let textField = "feed_composer-text_field"
        let post = "feed_composer-post"
        let cancel = "feed_composer-cancel"
        let counter = "feed_composer-counter"
        let standingNotice = "feed_composer-standing_notice"
        let rulesAgree = "feed_composer-rules_agree"
        let rulesAcceptFailed = "feed_composer-rules_accept_failed"
        let deletePost = "feed_composer-delete_post"
        let heldNotice = "feed_composer-held_notice"
    }
}
