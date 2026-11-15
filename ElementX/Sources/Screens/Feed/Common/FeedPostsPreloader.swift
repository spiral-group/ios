//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

/// The Feed's posts as placeholders until they load (decision 330): each an author's row and a few
/// lines, the way `FeedPostCard` lays a post out, after `SpiralPreloader`'s short delay.
struct FeedPostsPreloader: View {
    var count = 3
    /// Latest opens on its pinned post: the first stand-in is its card, the size the post comes in at.
    var showsPinned = false

    var body: some View {
        SpiralPreloader(label: L10n.commonLoading) {
            VStack(spacing: 0) {
                if showsPinned {
                    pinned
                }
                ForEach(0..<count, id: \.self) { _ in
                    FeedPostListCell {
                        SpiralPlaceholderRows(count: 1, leading: .avatar(Avatars.Size.user(on: .timeline).value))
                        SpiralPlaceholderLines(count: 3)
                            .padding(.leading, Self.textInset)
                            .padding(.trailing, ListRowPadding.horizontal)
                            .padding(.bottom, CompoundDesignTokens.space4X)
                    }
                }
            }
        }
    }

    /// The pinned card's stand-in: its label, the author, four lines and the link, the actions' row.
    private var pinned: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpiralPlaceholderRows(count: 1, leading: .avatar(Avatars.Size.user(on: .timeline).value))
                // The rows keep a list row's margin; the card's content starts closer to its edge.
                .padding(.horizontal, Self.pinnedInset - ListRowPadding.horizontal)
            SpiralPlaceholderLines(count: FeedPostCard.pinnedLineLimit + 1)
                .padding(.leading, Self.pinnedTextInset)
                .padding(.trailing, Self.pinnedInset)
                .padding(.bottom, CompoundDesignTokens.space11X) // The actions' 44 pt row.
        }
        .padding(.top, CompoundDesignTokens.space6X) // The label's line.
        .feedPinnedCard()
        .padding(CompoundDesignTokens.space2X)
    }

    /// Brief 0083: the lines start where `FeedPostCard`'s text does, in the avatar's column.
    private static let textInset = ListRowPadding.horizontal + SpiralAvatarSize.small + CompoundDesignTokens.space3X
    /// `FeedPostCard`'s margin inside the pinned card.
    private static let pinnedInset = CompoundDesignTokens.space3X
    private static let pinnedTextInset = pinnedInset + SpiralAvatarSize.small + CompoundDesignTokens.space3X
}
