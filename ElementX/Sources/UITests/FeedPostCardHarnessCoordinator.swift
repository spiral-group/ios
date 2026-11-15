//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). One feed card in a scroll view, as Latest
// lays it out, with everything its taps did written under it: the UI test taps
// the card's text and its link and reads what each one did, and only that.
//

import SwiftUI

class FeedPostCardHarnessCoordinator: CoordinatorProtocol {
    func toPresentable() -> AnyView {
        AnyView(FeedPostCardHarness())
    }
}

private struct FeedPostCardHarness: View {
    static let post = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000001",
                                           author: FeedPreviewData.ann,
                                           minutesAgo: 5,
                                           text: "https://example.org/garden\nFirst frost this morning. The tomatoes did not make it, but the kale is fine, "
                                               + "and the leeks look as if nothing happened. Next year the tomatoes go in the greenhouse.")

    @State private var actions: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                FeedPostCard(model: FeedPostCardModel(post: Self.post), isRevealed: false, mediaProvider: nil) { action in
                    actions.append("\(action)")
                }
                Divider()
                Text(actions.isEmpty ? "none" : actions.joined(separator: ", "))
                    .accessibilityIdentifier("feed_card_harness-actions")
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            actions.append("link \(url.absoluteString)")
            return .handled
        })
    }
}
