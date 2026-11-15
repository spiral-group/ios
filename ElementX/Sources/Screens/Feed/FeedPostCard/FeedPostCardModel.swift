//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). What a feed card renders, prepared once
// per post so a scroll never re-runs link detection. Room-free: no timeline
// item, no room proxy, no pills.
//

import Foundation

struct FeedPostCardModel: Identifiable, Equatable {
    struct Media: Equatable {
        let source: MediaSourceProxy?
        let mimeType: String
        let width: Int
        let height: Int
        let blurhash: String?
        let altText: String?
    }

    enum Body: Equatable {
        case content(text: AttributedString?, media: [Media])
        /// A kind newer than this build: "Update Spiral to see this post".
        case unsupported
        /// Author-hidden, or a state newer than this build: "This post isn't
        /// available", with nothing of the post in it (decision 96).
        case notAvailable
    }

    /// The row under a visible post (lane I3): like, comments, share, hide, report.
    struct Engagement: Equatable {
        let likes: Int
        let isLiked: Bool
        let comments: Int
        let shares: Int
        let commentsEnabled: Bool
        /// Everyone but the author may hide a post from their own lists.
        let canHide: Bool
        /// Everyone but the author may report it (lane I3 on B4).
        let canReport: Bool

        /// "12 likes, 3 comments, 1 share" for VoiceOver, leaving out the counts at zero.
        var accessibilitySummary: String? {
            let parts = [likes > 0 ? UntranslatedL10n.a11yFeedLikes(likes) : nil,
                         comments > 0 ? UntranslatedL10n.a11yFeedComments(comments) : nil,
                         shares > 0 ? UntranslatedL10n.a11yFeedShares(shares) : nil].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

    let id: String
    let authorID: String
    let authorName: String
    let authorAvatarURL: URL?
    let isOfficial: Bool
    let createdAt: Date
    let body: Body
    let isSensitive: Bool
    /// The http(s) links in the text, for VoiceOver.
    let links: [URL]
    /// Only a visible post is liked, commented on and shared; the server refuses the rest.
    let engagement: Engagement?

    init(post: FeedPost) {
        id = post.id
        authorID = post.author.userID
        authorName = post.author.displayName
        authorAvatarURL = post.author.avatarURL
        isOfficial = post.author.isOfficial
        createdAt = post.createdAt

        switch post.state {
        case .visible:
            engagement = Engagement(likes: post.counts.likes,
                                    isLiked: post.viewer.liked,
                                    comments: post.counts.comments,
                                    shares: post.counts.shares,
                                    commentsEnabled: post.commentsEnabled,
                                    canHide: !post.viewer.isAuthor,
                                    canReport: !post.viewer.isAuthor)
        case .held, .removed:
            engagement = nil
        case .hiddenAuthor, .other:
            engagement = nil
            isSensitive = false
            body = .notAvailable
            links = []
            return
        }

        isSensitive = post.content.isSensitive
        switch post.content.kind {
        case .text, .textImages:
            let text = post.content.text.isEmpty ? nil : FeedTextBuilder.attributedString(from: post.content.text)
            let media = post.content.media.prefix(4).map { ref in
                Media(source: ref.mxcURL.flatMap { try? MediaSourceProxy(url: $0, mimeType: ref.mimeType) },
                      mimeType: ref.mimeType,
                      width: ref.width,
                      height: ref.height,
                      blurhash: ref.blurhash,
                      altText: ref.altText)
            }
            body = .content(text: text, media: Array(media))
            links = text.map(FeedTextBuilder.links(in:)) ?? []
        case .other:
            body = .unsupported
            links = []
        }
    }

    var isAvailable: Bool {
        body != .notAvailable
    }

    /// A visible post is shared; a sensitive one only once the person chose
    /// "Show" (decision 267), so what they send is what they saw.
    func canShare(isRevealed: Bool) -> Bool {
        engagement != nil && (!isSensitive || isRevealed)
    }

    var media: [Media] {
        if case .content(_, let media) = body { media } else { [] }
    }

    /// The card as one VoiceOver element: who, when, and what, never the
    /// hidden text of a sensitive post.
    func accessibilityLabel(isRevealed: Bool, now: Date = .now) -> String {
        guard isAvailable else { return UntranslatedL10n.screenFeedPostNotAvailableTitle }

        var parts = [authorName]
        if isOfficial {
            parts.append(UntranslatedL10n.screenFeedOfficialLabel)
        }
        parts.append(createdAt.formatted(.relative(presentation: .named, unitsStyle: .wide)))

        if isSensitive, !isRevealed {
            parts.append(UntranslatedL10n.screenFeedSensitiveTitle)
            if let summary = engagement?.accessibilitySummary {
                parts.append(summary)
            }
            return parts.joined(separator: ", ")
        }

        switch body {
        case .content(let text, let media):
            if let text {
                parts.append(String(text.characters))
            }
            if !media.isEmpty {
                parts.append(UntranslatedL10n.a11yFeedImages(media.count))
            }
        case .unsupported:
            parts.append(UntranslatedL10n.screenFeedPostUnsupported)
        case .notAvailable:
            break
        }
        if let engagement {
            if engagement.isLiked {
                parts.append(UntranslatedL10n.a11yFeedLikedByYou)
            }
            if let summary = engagement.accessibilitySummary {
                parts.append(summary)
            }
        }
        return parts.joined(separator: ", ")
    }
}
