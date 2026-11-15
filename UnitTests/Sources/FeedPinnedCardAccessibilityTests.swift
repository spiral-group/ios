//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import SwiftUI
import Testing

/// The pinned card is one element: VoiceOver reads the whole text the card cuts, so it has no "Read more" to offer, and
/// activating it opens the post.
@MainActor
@Suite(AccessibilityTree())
struct FeedPinnedCardAccessibilityTests {
    @Test
    func aCutPinnedPostReadsWholeAndOffersNoReadMore() async throws {
        var actions: [FeedPostCardAction] = []
        let host = try await Self.host(FeedPreviewData.welcomePost) { actions.append($0) }

        let card = try #require(Self.card(in: host.view))
        #expect(card.accessibilityLabel?.contains("Glad you're here!") == true)
        #expect(card.accessibilityCustomActions?.contains { $0.name == UntranslatedL10n.screenFeedReadMore } != true)

        #expect(card.accessibilityActivate())
        #expect(actions == [.openPost])
    }

    private static func host(_ post: FeedPost, action: @escaping (FeedPostCardAction) -> Void) async throws -> UIViewController {
        let view = FeedPostCard(model: FeedPostCardModel(post: post), isRevealed: false, mediaProvider: nil, style: .pinned, action: action)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100)) // The tree is built on the next pass of the run loop.
        return host
    }

    /// The card's element, the only one whose label says it is pinned.
    private static func card(in object: NSObject) -> NSObject? {
        if object.accessibilityLabel?.hasPrefix(UntranslatedL10n.screenFeedPinnedLabel) == true {
            return object
        }
        let count = object.accessibilityElementCount()
        let elements = count == NSNotFound ? [] : (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        let views = (object as? UIView)?.subviews ?? []
        return (elements + views).lazy.compactMap(card).first
    }
}
