//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083 phase 4, lane room-profile, decision 344): one page for a room's details and a person's
// profile, in the call's language (340): the person's picture as a field behind the top of a grouped list, the hero
// on it, and the screen's own sections under it.

import Compound
import SpiralTokens
import SwiftUI

/// What the page's picture is made of.
enum SpiralProfilePicture {
    case room(RoomAvatar)
    case user(UserProfile)

    var url: URL? {
        switch self {
        case .room(let avatar): avatar.url
        case .user(let profile): profile.avatarURL
        }
    }

    /// The one person the avatar shows, whose Peek decides the field without a photo; `nil` for a room or a group.
    var contentID: String? {
        switch self {
        case .room(let avatar): avatar.heroUserID
        case .user(let profile): profile.id
        }
    }
}

/// The page: a `Form` over the field, which scrolls with it and stretches when pulled. The screen's sections start
/// with a `SpiralProfileHero`. The bar's title stays empty until the hero has scrolled under it, unless the screen
/// keeps its own title in the bar, as Settings does (decision 357).
struct SpiralProfilePage<Content: View>: View {
    let picture: SpiralProfilePicture
    /// What the bar says once the hero has scrolled away. `nil` leaves the bar to the screen's `navigationTitle`.
    var title: String?
    let mediaProvider: MediaProviderProtocol?
    @ViewBuilder let content: () -> Content

    @State private var fieldEdge = CGFloat.zero
    @State private var scrollOffset = CGFloat.zero

    private var isTitleInBar: Bool {
        fieldEdge > 0 && scrollOffset > fieldEdge - CompoundDesignTokens.space16X
    }
    
    /// A title that stays must not have the hero run through it, so the bar comes in as soon as the page scrolls.
    private var isBarShown: Bool {
        title == nil ? scrollOffset > 0 : isTitleInBar
    }

    var body: some View {
        Form {
            content()
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .coordinateSpace(.named(SpiralProfileCoordinateSpace.page))
        .onPreferenceChange(SpiralProfileFieldEdgeKey.self) { edge in
            // The edge is read while the page scrolls: taken back to where it is at rest.
            if edge > 0 { fieldEdge = edge + scrollOffset }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        .background(alignment: .top) { field }
        .spiralGroupedList()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(isBarShown ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
            if let title {
                ToolbarItem(placement: .principal) {
                    // Empty, not transparent: a transparent title stays in the accessibility tree, hidden or not.
                    Text(isTitleInBar ? title : "")
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// The field runs on past the hero and fades out under the first card.
    private var field: some View {
        GeometryReader { proxy in
            NativeCallBackdrop(photoURL: picture.url, contentID: picture.contentID, mediaProvider: mediaProvider, tone: .wash)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 0.7),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top,
                                   endPoint: .bottom)
                }
                .frame(width: proxy.size.width, height: fieldEdge + CompoundDesignTokens.space16X + max(0, -scrollOffset))
                .clipped()
                .offset(y: -proxy.safeAreaInsets.top - max(0, scrollOffset))
        }
    }
}

private enum SpiralProfileCoordinateSpace {
    static let page = "spiralProfilePage"
}

private struct SpiralProfileFieldEdgeKey: PreferenceKey {
    static let defaultValue = CGFloat.zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Marks this view's foot as where the page's field ends.
    func spiralProfileFieldEdge() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: SpiralProfileFieldEdgeKey.self,
                                       value: proxy.frame(in: .named(SpiralProfileCoordinateSpace.page)).maxY)
            }
        }
    }
}
