//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0083, batch P4-C, decision 338). A list's posts
// are full width between hairlines, as Threads and X draw a feed on iOS.
//

import Compound
import SpiralTokens
import SwiftUI

/// One post in a list, with what belongs above it (an own post's state), and the hairline under it.
struct FeedPostListCell<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
        }
    }
}

/// A line above a post that says where it stands: one of the person's own posts under review or removed.
/// Its glyph sits in the avatar's column, as X marks a pinned post.
struct FeedPostMarker: View {
    let title: String
    let icon: KeyPath<CompoundIcons, Image>

    var body: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            CompoundIcon(icon, size: .xSmall, relativeTo: .compound.bodySMSemibold)
                .frame(minWidth: SpiralAvatarSize.small, alignment: .trailing)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(.compound.bodySMSemibold)
        .foregroundStyle(.compound.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.top, CompoundDesignTokens.space3X)
        .accessibilityElement(children: .combine)
    }
}
