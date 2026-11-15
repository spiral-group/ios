//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Posts for the feed's previews and tests.
//

import Foundation

enum FeedPreviewData {
    static let ann = FeedAuthor(userID: "@ann:spiral.md", name: "Ann", avatarURL: nil, bio: "Gardener, hiker, bad at chess.", isOfficial: false, isNameWithheld: false)
    static let bob = FeedAuthor(userID: "@bob:spiral.md", name: nil, avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false)
    static let spiral = FeedAuthor(userID: "@spiral:spiral.md", name: "Spiral", avatarURL: nil, bio: "The official Spiral account.", isOfficial: true, isNameWithheld: false)
    /// Their name breaks the rules (lane B4): "Spiral member", no MXID, no bio.
    static let withheld = FeedAuthor(userID: "@withheld:spiral.md", name: nil, avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: true)

    static let textPost = post(id: "01933f2a-0000-7000-8000-000000000001",
                               author: ann,
                               minutesAgo: 5,
                               text: "First frost this morning. The tomatoes did not make it, but the kale is fine. Notes on https://example.org/garden")

    static let officialPost = post(id: "01933f2a-0000-7000-8000-000000000002",
                                   author: spiral,
                                   minutesAgo: 60 * 24,
                                   text: "Welcome to the Spiral feed. Be kind, post your own photos, and report anything that breaks the rules.")

    /// The pinned rules post as Spiral publishes it (the starter posts' `welcome`, shortened): longer than its card shows.
    static let welcomePost = post(id: "01933f2a-0000-7000-8000-000000000006",
                                  author: spiral,
                                  minutesAgo: 34,
                                  text: "👋 Hi! This is the Spiral feed: the place where everyone on Spiral shares thoughts, news and the things that "
                                      + "make them smile. The newest is on top.\n\nTo keep it good for everyone, a few simple things:\n"
                                      + "• be kind: no hate, harassment or threats;\n• no sexual content, spam or scams.\n\n"
                                      + "All the rules: https://spiral.md/brand/terms (section 6). Glad you're here!")

    static let sensitivePost = post(id: "01933f2a-0000-7000-8000-000000000003",
                                    author: bob,
                                    minutesAgo: 30,
                                    text: "A photo from the field hospital.",
                                    mediaCount: 1,
                                    isSensitive: true)

    static let unsupportedPost = post(id: "01933f2a-0000-7000-8000-000000000004",
                                      author: bob,
                                      minutesAgo: 90,
                                      kind: .other("poll"),
                                      text: "From a newer server")

    /// Its author is deactivated: a list shows "not available" in its place.
    static let notAvailablePost = post(id: "01933f2a-0000-7000-8000-000000000005",
                                       author: bob,
                                       minutesAgo: 120,
                                       text: "Never shown",
                                       state: .hiddenAuthor)

    // MARK: Lane I3

    /// Liked by the person, with comments and a share.
    static let engagedPost = textPost.settingLike(true, likes: 12).withCounts(comments: 3, shares: 1)

    /// Hidden by the person: still readable by id.
    static let hiddenPost: FeedPost = {
        var post = textPost
        post.viewer.hidden = true
        return post
    }()

    static let commentPage = FeedCommentPage(items: [comment(id: "01933f2b-0000-7000-8000-000000000001", author: bob, minutesAgo: 4,
                                                             text: "Same here, the kale always survives."),
                                                     comment(id: "01933f2b-0000-7000-8000-000000000002", author: ann, minutesAgo: 3,
                                                             text: "It does! Notes at https://example.org/kale",
                                                             replyTo: FeedCommentReply(id: "01933f2b-0000-7000-8000-000000000001", author: bob),
                                                             isAuthor: true),
                                                     comment(id: "01933f2b-0000-7000-8000-000000000003", author: spiral, minutesAgo: 2,
                                                             text: "Hidden until shown", isSensitive: true),
                                                     comment(id: "01933f2b-0000-7000-8000-000000000004", author: ann, minutesAgo: 1,
                                                             text: "Waiting for a moderator", state: .held, isAuthor: true)],
                                             nextCursor: "next")

    // MARK: Lane I3, reports and notices

    static let fixedDate = Date(timeIntervalSince1970: 1_793_116_800) // 27 Oct 2026, 00:00 UTC.

    /// One of each: an author's statement of reasons, a limiting, a suspension, a held comment, the filter's mark at publish,
    /// a reporter's two, and a kind newer than this build.
    static let notices: [FeedNotice] = [
        notice(id: "01933f2d-0000-7000-8000-000000000001", kind: .removed, isRead: false, postID: textPost.id,
               statement: statement(restriction: .removed, trigger: .report, rule: "hate", ruleTitle: "Hate",
                                    ruleExplanation: "Attacking people for who they are: their origin, religion, gender, sexuality or disability.",
                                    moderatorComment: "The second paragraph targets a group of people.",
                                    legalGround: "DSA Art. 16", appealContact: "support@spiral.md")),
        notice(id: "01933f2d-0000-7000-8000-000000000002", kind: .limited, isRead: false,
               statement: statement(restriction: .limited, tier: 0, trigger: .moderator, rule: "spam", ruleTitle: "Spam",
                                    ruleExplanation: "Posting the same thing again and again, or advertising.", appealContact: "support@spiral.md")),
        notice(id: "01933f2d-0000-7000-8000-000000000003", kind: .suspended, isRead: true,
               statement: statement(restriction: .suspended, until: fixedDate.addingTimeInterval(7 * 86400), trigger: .moderator,
                                    rule: "harassment", ruleTitle: "Harassment", ruleExplanation: "Targeting a person again and again.",
                                    appealContact: "support@spiral.md")),
        notice(id: "01933f2d-0000-7000-8000-000000000004", kind: .held, isRead: true, postID: textPost.id, commentID: "01933f2b-0000-7000-8000-000000000004",
               statement: statement(restriction: .held, trigger: .sla, isAutomated: true, appealContact: "support@spiral.md")),
        // Decision 278: the filter's notice at publish.
        notice(id: "01933f2d-0000-7000-8000-000000000008", kind: .sensitive, isRead: true, postID: sensitivePost.id,
               statement: statement(restriction: .sensitive, trigger: .filter, isAutomated: true, isDetectedByAutomatedMeans: true,
                                    rule: "sexual_content", ruleTitle: "Sexual content",
                                    ruleExplanation: "Pornography and sexually explicit content.", appealContact: "support@spiral.md")),
        notice(id: "01933f2d-0000-7000-8000-000000000005", kind: .reportReceived, isRead: true, postID: textPost.id, reportID: "01933f2c-0000-7000-8000-000000000001",
               statement: statement(targetKind: .post, deadline: fixedDate.addingTimeInterval(86400))),
        notice(id: "01933f2d-0000-7000-8000-000000000006", kind: .reportDecided, isRead: true, reportID: "01933f2c-0000-7000-8000-000000000002",
               statement: statement(targetKind: .author, outcome: .noAction)),
        notice(id: "01933f2d-0000-7000-8000-000000000007", kind: .other("appeal_decided"), isRead: true, statement: statement())
    ]

    // MARK: Lane I5, activity and who liked

    static let taras = FeedAuthor(userID: "@taras:spiral.md", name: "Taras", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false)
    static let olena = FeedAuthor(userID: "@olena:spiral.md", name: "Olena", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false)

    /// A like group, a comment, a reply, a sensitive comment and a single like.
    static let activity: [FeedActivityEntry] = [
        activityEntry(id: "like:\(textPost.id):2026-10-30", kind: .like, minutesAgo: 2, actors: [taras, olena, bob], total: 4, isUnread: true),
        activityEntry(id: "reply:01933f2b-0000-7000-8000-000000000011", kind: .reply, minutesAgo: 10, actors: [olena], total: 1,
                      commentID: "01933f2b-0000-7000-8000-000000000011", preview: "So true!", isUnread: true),
        activityEntry(id: "comment:01933f2b-0000-7000-8000-000000000012", kind: .comment, minutesAgo: 30, actors: [bob], total: 1,
                      commentID: "01933f2b-0000-7000-8000-000000000012", preview: "The kale always survives."),
        activityEntry(id: "comment:01933f2b-0000-7000-8000-000000000013", kind: .comment, minutesAgo: 45, actors: [withheld], total: 1,
                      commentID: "01933f2b-0000-7000-8000-000000000013", preview: "Something upsetting", isSensitive: true),
        activityEntry(id: "like:\(officialPost.id):2026-10-29", kind: .like, minutesAgo: 60 * 20, actors: [ann], total: 1)
    ]

    static func activityEntry(id: String,
                              kind: FeedActivityKind,
                              minutesAgo: Int,
                              actors: [FeedAuthor],
                              total: Int,
                              commentID: String? = nil,
                              preview: String? = nil,
                              postPreview: String = "First frost this morning. The tomatoes did not make it",
                              isSensitive: Bool = false,
                              isUnread: Bool = false) -> FeedActivityEntry {
        FeedActivityEntry(id: id, kind: kind, at: createdAt(minutesAgo: minutesAgo), postID: textPost.id, commentID: commentID,
                          actors: actors, total: total, preview: preview, postPreview: postPreview, isSensitive: isSensitive, isUnread: isUnread)
    }

    static let likers: [FeedLiker] = [taras, olena, spiral, withheld, bob].enumerated().map { index, author in
        FeedLiker(author: author, likedAt: createdAt(minutesAgo: 2 + index * 7))
    }

    static func notice(id: String,
                       kind: FeedNoticeKind,
                       isRead: Bool,
                       postID: String? = nil,
                       commentID: String? = nil,
                       reportID: String? = nil,
                       statement: FeedNoticeStatement) -> FeedNotice {
        FeedNotice(id: id, kind: kind, createdAt: .now.addingTimeInterval(-3600), isRead: isRead,
                   postID: postID, commentID: commentID, reportID: reportID, statement: statement)
    }

    static func statement(restriction: FeedNoticeKind? = nil,
                          until: Date? = nil,
                          tier: Int? = nil,
                          trigger: FeedNoticeTrigger? = nil,
                          isAutomated: Bool = false,
                          isDetectedByAutomatedMeans: Bool = false,
                          rule: String? = nil,
                          ruleTitle: String? = nil,
                          ruleExplanation: String? = nil,
                          moderatorComment: String? = nil,
                          legalGround: String? = nil,
                          appealContact: String? = nil,
                          targetKind: FeedNoticeTargetKind? = nil,
                          deadline: Date? = nil,
                          outcome: FeedReportOutcome? = nil) -> FeedNoticeStatement {
        FeedNoticeStatement(restriction: restriction, until: until, tier: tier, trigger: trigger, isAutomated: isAutomated,
                            isDetectedByAutomatedMeans: isDetectedByAutomatedMeans,
                            rule: rule, ruleTitle: ruleTitle, ruleExplanation: ruleExplanation, moderatorComment: moderatorComment,
                            legalGround: legalGround, appealContact: appealContact, targetKind: targetKind, deadline: deadline, outcome: outcome)
    }

    static func comment(id: String,
                        author: FeedAuthor,
                        minutesAgo: Int,
                        text: String,
                        replyTo: FeedCommentReply? = nil,
                        state: FeedCommentState = .visible,
                        isAuthor: Bool = false,
                        isSensitive: Bool = false) -> FeedComment {
        FeedComment(id: id,
                    postID: textPost.id,
                    author: author,
                    text: text,
                    replyTo: replyTo,
                    createdAt: createdAt(minutesAgo: minutesAgo),
                    state: state,
                    heldReason: state == .held ? .filter : nil,
                    isAuthor: isAuthor,
                    canDelete: isAuthor,
                    isSensitive: isSensitive)
    }

    static func imagePost(count: Int) -> FeedPost {
        post(id: "01933f2a-0000-7000-8000-00000000010\(count)",
             author: ann,
             minutesAgo: 10 * count,
             text: count == 1 ? "" : "\(count) photos from the walk",
             mediaCount: count)
    }

    /// `count` text posts, newest first, a minute apart.
    static func posts(_ count: Int, startingAt start: Int = 0, author: FeedAuthor = ann) -> [FeedPost] {
        (start..<(start + count)).map { index in
            post(id: String(format: "01933f2a-0000-7000-8000-%012d", 1000 + index),
                 author: author,
                 minutesAgo: index + 1,
                 text: "Post number \(index + 1)")
        }
    }

    /// Half a minute short of `minutesAgo`: the static data is made before the
    /// snapshot renders, and "5 minutes ago" must not round to 6 on the way.
    /// Under two minutes it would read in seconds, so a minute stays a minute.
    private static func createdAt(minutesAgo: Int) -> Date {
        .now.addingTimeInterval(-Double(minutesAgo) * 60 + (minutesAgo > 1 ? 30 : 0))
    }

    static func post(id: String,
                     author: FeedAuthor,
                     minutesAgo: Int,
                     kind: FeedContentKind = .text,
                     text: String,
                     mediaCount: Int = 0,
                     isSensitive: Bool = false,
                     state: FeedPostState = .visible,
                     heldReason: FeedHeldReason? = nil,
                     isAuthor: Bool = false) -> FeedPost {
        let media = (0..<mediaCount).map { index in
            FeedMediaRef(id: "0199d0a1-0000-7000-8000-00000000000\(index)",
                         mxcURL: URL(string: "mxc://spiral.md/media\(index)"),
                         mimeType: "image/jpeg",
                         width: index.isMultiple(of: 2) ? 2048 : 1536,
                         height: index.isMultiple(of: 2) ? 1536 : 2048,
                         blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
                         altText: index == 0 ? "A path through a birch wood" : nil)
        }
        return FeedPost(id: id,
                        createdAt: createdAt(minutesAgo: minutesAgo),
                        author: author,
                        content: FeedContent(kind: mediaCount > 0 && kind == .text ? .textImages : kind,
                                             text: text,
                                             media: media,
                                             isSensitive: isSensitive),
                        counts: FeedCounts(likes: 0, comments: 0, shares: 0),
                        viewer: FeedViewer(liked: false, hidden: false, isAuthor: isAuthor),
                        state: state,
                        heldReason: heldReason,
                        commentsEnabled: true)
    }
}

extension FeedPost {
    func settingLike(_ liked: Bool, likes: Int) -> FeedPost {
        var post = self
        post.viewer.liked = liked
        post.counts.likes = likes
        return post
    }

    func withCounts(likes: Int? = nil, comments: Int? = nil, shares: Int? = nil) -> FeedPost {
        var post = self
        post.counts = FeedCounts(likes: likes ?? counts.likes, comments: comments ?? counts.comments, shares: shares ?? counts.shares)
        return post
    }

    func withCommentsEnabled(_ enabled: Bool) -> FeedPost {
        var post = self
        post.commentsEnabled = enabled
        return post
    }
}
