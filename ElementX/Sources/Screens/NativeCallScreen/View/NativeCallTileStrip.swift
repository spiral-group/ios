//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the group's strip beside the stage, one design for the video filmstrip and
// the audio Spotlight. It keeps inside the margins it is given and only ever shows whole tiles. The tiles come in pages:
// as many as fit at their smallest length (four on a usual phone, fewer at large text), stretched to fill the strip
// exactly, each page the strip's own length. A swipe moves one page and settles on it (`viewAligned`, one target per
// swipe); the next page starts a spacing past the edge, so nothing is ever cut. The dots are the pages: they follow the
// scroll and a tap goes to one. Lazy, so a page scrolled away builds no video view and draws no Aura.

import Compound
import SwiftUI

struct NativeCallTileStrip<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    /// Sideways under a portrait stage, downwards beside a landscape one.
    var axis: Axis = .horizontal
    /// The shortest a tile may get along the strip; scale it with the text size so larger text fits fewer.
    let minimumTileLength: CGFloat
    let spacing: CGFloat
    /// Room across the strip for what a tile draws round itself (an Aura), inside the strip's clip.
    var crossInset: CGFloat = 0
    /// Builds one tile at the length the page gives it.
    @ViewBuilder let tile: (Item, CGFloat) -> Tile

    @State private var length: CGFloat = 0
    @State private var page: Int?

    var body: some View {
        let perPage = Self.tilesPerRow(length: length, minimumTileLength: minimumTileLength, spacing: spacing)
        let tileLength = perPage > 0 ? (length - CGFloat(perPage - 1) * spacing) / CGFloat(perPage) : 0
        let pageCount = Self.pageCount(items: items.count, perPage: perPage)
        let layout = axis == .horizontal
            ? AnyLayout(VStackLayout(spacing: CompoundDesignTokens.space2X))
            : AnyLayout(HStackLayout(spacing: CompoundDesignTokens.space2X))

        layout {
            ScrollView(axis == .horizontal ? .horizontal : .vertical, showsIndicators: false) {
                pages(count: pageCount, perPage: perPage, tileLength: tileLength)
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $page)
            .scrollDisabled(pageCount <= 1)
            // A scroll view takes all it is offered; across the strip it takes only its tiles.
            .fixedSize(horizontal: axis == .vertical, vertical: axis == .horizontal)
            .onGeometryChange(for: CGFloat.self) { axis == .horizontal ? $0.size.width : $0.size.height } action: { length = $0 }

            if pageCount > 1 {
                pageDots(count: pageCount, current: min(page ?? 0, pageCount - 1))
            }
        }
    }

    /// How many whole tiles fit in a page at no less than `minimumTileLength` (at least one).
    static func tilesPerRow(length: CGFloat, minimumTileLength: CGFloat, spacing: CGFloat) -> Int {
        guard length > 0, minimumTileLength > 0 else { return 0 }
        return max(1, Int((length + spacing) / (minimumTileLength + spacing)))
    }

    static func pageCount(items: Int, perPage: Int) -> Int {
        perPage > 0 ? (items + perPage - 1) / perPage : 0
    }

    /// The pages, each exactly the strip's measured length (the length the tiles are sized from, so the snap points
    /// and the tiles agree): whole tiles from its leading edge, a single page centred.
    @ViewBuilder
    private func pages(count: Int, perPage: Int, tileLength: CGFloat) -> some View {
        let alignment: Alignment = count == 1 ? .center : (axis == .horizontal ? .leading : .top)
        if axis == .horizontal {
            LazyHStack(alignment: .top, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(items(onPage: index, perPage: perPage)) { item in
                            tile(item, tileLength).frame(width: tileLength)
                        }
                    }
                    .frame(width: length, alignment: alignment)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, crossInset)
        } else {
            LazyVStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    VStack(spacing: spacing) {
                        ForEach(items(onPage: index, perPage: perPage)) { item in
                            tile(item, tileLength).frame(height: tileLength)
                        }
                    }
                    .frame(height: length, alignment: alignment)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, crossInset)
        }
    }

    private func items(onPage index: Int, perPage: Int) -> [Item] {
        let start = index * perPage
        return Array(items[min(start, items.count)..<min(start + perPage, items.count)])
    }

    /// One dot a page, the current one filled; a tap goes to that page. VoiceOver swipes the strip itself.
    private func pageDots(count: Int, current: Int) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        return layout {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    withAnimation(.snappy) { page = index }
                } label: {
                    Circle()
                        .fill(.primary.opacity(index == current ? 0.75 : 0.25))
                        .frame(width: 6, height: 6)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityHidden(true)
    }
}
