//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Feed text carries http(s) links and
// nothing else: a pill is what makes `PillAttachmentViewProvider` run, and
// without a room it asserts in Debug (spike C2).
//

import Foundation
@testable import Spiral
import Testing

struct FeedTextBuilderTests {
    static let text = "Ping @room and @alice:localhost, see https://example.com/a?b=1 or https://matrix.to/#/@bob:localhost or example.org, mail alice@example.com, call tel:+3801234567"

    @Test
    func onlyHTTPLinksAreAttributed() throws {
        let rendered = try NSAttributedString(FeedTextBuilder.attributedString(from: Self.text), including: \.elementX) // What MessageText hands to TextKit.

        var attachments = 0
        var mentions = 0
        var links: [String] = []
        rendered.enumerateAttributes(in: NSRange(location: 0, length: rendered.length)) { attributes, _, _ in
            if attributes[.attachment] != nil { attachments += 1 }
            if attributes[.MatrixUserID] != nil || attributes[.MatrixAllUsersMention] != nil || attributes[.MatrixRoomAlias] != nil {
                mentions += 1
            }
            if let url = attributes[.link] as? URL { links.append(url.absoluteString) }
        }

        #expect(attachments == 0, "pill attachments: \(attachments)")
        #expect(mentions == 0, "mention attributes: \(mentions)")
        #expect(links == ["https://example.com/a?b=1", "https://matrix.to/#/@bob:localhost", "https://example.org"])
        #expect(rendered.string == Self.text, "the visible text must not change")
    }

    @Test
    func aMentionAloneStaysPlainText() {
        let result = FeedTextBuilder.attributedString(from: "@room and @alice:spiral.md")
        #expect(result.runs.count == 1)
        #expect(result.runs.first?.link == nil)
        #expect(FeedTextBuilder.links(in: result).isEmpty)
    }

    @Test
    func theCardKeepsTheLinksForVoiceOver() {
        let post = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000001", author: FeedPreviewData.ann, minutesAgo: 1,
                                        text: "See example.org and https://spiral.md/feed/01933f2a-0000-7000-8000-000000000002")
        #expect(FeedPostCardModel(post: post).links.map(\.absoluteString) == ["https://example.org",
                                                                              "https://spiral.md/feed/01933f2a-0000-7000-8000-000000000002"])
    }

    @Test
    func aNewerKindIsAnUpdateNotice() {
        #expect(FeedPostCardModel(post: FeedPreviewData.unsupportedPost).body == .unsupported)
        #expect(FeedPostCardModel(post: FeedPreviewData.unsupportedPost).links.isEmpty)
    }

    /// Decision 96 in a list too: an author-hidden or newer state is "not
    /// available", with nothing of the post in it (text, images, links, author).
    @Test(arguments: [FeedPostState.hiddenAuthor, .other("archived")])
    func aStateAListDoesNotShowIsNotAvailable(state: FeedPostState) {
        let post = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000001", author: FeedPreviewData.ann, minutesAgo: 1,
                                        text: "Secret words https://example.org", mediaCount: 1, state: state)
        let card = FeedPostCardModel(post: post)

        #expect(card.media.isEmpty)
        #expect(card.links.isEmpty)
        #expect(card.accessibilityLabel(isRevealed: true) == UntranslatedL10n.screenFeedPostNotAvailableTitle)
    }

    @Test(arguments: [FeedPostState.visible, .held, .removed])
    func aStateTheAuthorOrEveryoneSeesIsShown(state: FeedPostState) {
        let post = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000001", author: FeedPreviewData.ann, minutesAgo: 1,
                                        text: "Words", mediaCount: 1, state: state)
        let card = FeedPostCardModel(post: post)

        #expect(card.media.count == 1)
        #expect(card.accessibilityLabel(isRevealed: true).contains("Words"))
    }
}
