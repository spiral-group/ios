//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
@testable import Spiral
import SwiftUI
import Testing

/// The pinned post's text (concept A): cut to four lines, with "Read more" under it only when something was cut, at
/// every text size, and sized in the one pass that draws it.
@MainActor
struct FeedClampedTextTests {
    private static let width = 345.0
    private static let lineLimit = FeedPostCard.pinnedLineLimit
    private static let shortText = AttributedString("Welcome to the Spiral feed.")
    private static let longText = AttributedString(FeedPreviewData.welcomePost.content.text)

    @Test(arguments: [DynamicTypeSize.large, .accessibility3])
    func aShortTextShowsWholeWithoutTheLink(dynamicTypeSize: DynamicTypeSize) {
        let clamped = height(of: FeedClampedText(text: Self.shortText, lineLimit: Self.lineLimit), dynamicTypeSize: dynamicTypeSize)
        let whole = height(of: FeedCardText(text: Self.shortText), dynamicTypeSize: dynamicTypeSize)

        #expect(abs(clamped - whole) < 1, "clamped \(clamped), whole \(whole)")
    }

    @Test(arguments: [DynamicTypeSize.large, .accessibility3])
    func aLongTextIsCutAndGetsTheLink(dynamicTypeSize: DynamicTypeSize) {
        let clamped = height(of: FeedClampedText(text: Self.longText, lineLimit: Self.lineLimit), dynamicTypeSize: dynamicTypeSize)
        let cut = height(of: FeedCardText(text: Self.longText).lineLimit(Self.lineLimit), dynamicTypeSize: dynamicTypeSize)
        let whole = height(of: FeedCardText(text: Self.longText), dynamicTypeSize: dynamicTypeSize)
        let link = height(of: Text(UntranslatedL10n.screenFeedReadMore).font(.compound.bodyLGSemibold), dynamicTypeSize: dynamicTypeSize)

        #expect(cut < whole)
        #expect(clamped < whole, "clamped \(clamped), whole \(whole)")
        #expect(abs(clamped - (cut + CompoundDesignTokens.space1X + link)) < 1, "clamped \(clamped), cut \(cut), link \(link)")
    }

    @Test
    func aRoundingErrorIsNotACut() {
        #expect(!FeedClampLayout.isCut(wholeHeight: 88.3, cutHeight: 88))
        #expect(FeedClampLayout.isCut(wholeHeight: 110, cutHeight: 88))
    }

    private func height(of view: some View, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let sized = view.environment(\.dynamicTypeSize, dynamicTypeSize)
        return UIHostingController(rootView: sized).sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude)).height
    }
}
