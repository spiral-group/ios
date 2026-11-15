//
// Copyright 2025 Element Creations Ltd.
// Copyright 2021-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound // AGENT-PLATFORM (Brief 0083)
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct CompletionSuggestionView: View {
    let mediaProvider: MediaProviderProtocol?
    let items: [SuggestionItem]
    var showBackgroundShadow = true
    let onTap: (SuggestionItem) -> Void
    
    private enum Constants {
        static let topPadding: CGFloat = 8.0
        static let listItemPadding: CGFloat = 6.0
        static let leadingPadding: CGFloat = 16.0
        /// To make the scrolling more apparent we show a factional amount
        static let maxVisibleRows: CGFloat = 4.5
    }
    
    // MARK: Public
    
    @State private var prototypeListItemFrame: CGRect = .zero
    
    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ZStack {
                // AGENT-PLATFORM (question 357): a row with both its lines. With only an ID it measured one line and cut off the last row.
                MentionSuggestionItemView(mediaProvider: nil, item: .init(suggestionType: .user(.init(id: "@user:example.com", displayName: "User", avatarURL: nil)), range: .init(), rawSuggestionText: ""))
                    .readFrame($prototypeListItemFrame)
                    .hidden()
                if showBackgroundShadow {
                    BackgroundView {
                        list()
                    }
                } else {
                    list()
                }
            }
            // AGENT-PLATFORM (question 357): the bar's own top padding is the gap above the glass field; before it, the gap clears the bar's hairline.
            .padding(.bottom, showBackgroundShadow && Compound.supportsGlass ? 0 : Constants.listItemPadding)
        }
    }
    
    private func list() -> some View {
        List(items) { item in
            Button {
                onTap(item)
            } label: {
                MentionSuggestionItemView(mediaProvider: mediaProvider, item: item)
            }
            .modifier(ListItemPaddingModifier(isFirst: items.first?.id == item.id))
            .listRowInsets(.init(top: 0, leading: Constants.leadingPadding, bottom: 0, trailing: 0))
            .listRowSeparator(items.last?.id == item.id ? .hidden : .automatic, edges: .bottom) // AGENT-PLATFORM (question 357): it would sit on the card's edge
            .listRowBackground(Color.clear) // AGENT-PLATFORM (question 357): out of the bar a list paints its own background, black on a dark timeline
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .frame(height: contentHeightForRowCount(min(CGFloat(items.count), Constants.maxVisibleRows)))
        // AGENT-PLATFORM (Brief 0083): the floating card is the raised canvas, so it shows over a dark timeline.
        .background(showBackgroundShadow ? Color.compound.bgCanvasDefaultLevel1 : Color.compound.bgCanvasDefault)
    }
    
    private func contentHeightForRowCount(_ count: CGFloat) -> CGFloat {
        (prototypeListItemFrame.height + Constants.listItemPadding * 2) * count + Constants.topPadding - Constants.listItemPadding
    }
    
    private struct ListItemPaddingModifier: ViewModifier {
        private let isFirst: Bool
        
        init(isFirst: Bool) {
            self.isFirst = isFirst
        }
        
        func body(content: Content) -> some View {
            let topPadding: CGFloat = isFirst ? Constants.topPadding : Constants.listItemPadding
            let bottomPadding: CGFloat = Constants.listItemPadding
            
            return content
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
        }
    }
}

// AGENT-PLATFORM (Brief 0083): a card floating above the field, inset from the screen's edges and rounded all round
// as iOS rounds a popover. It was a sheet across the screen with only its top corners rounded.
private struct BackgroundView<Content: View>: View {
    @ViewBuilder var content: () -> Content
    
    private var cornerRadius: CGFloat {
        Compound.supportsGlass ? SpiralRadius.listCard : SpiralRadius.block
    }
    
    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 16.0, x: 0.0, y: 4.0)
            .padding(.horizontal, CompoundDesignTokens.space3X)
    }
}

// MARK: - Previews

struct CompletionSuggestion_Previews: PreviewProvider, TestablePreview {
    static let multipleItems: [SuggestionItem] = (0...10).map { index in
        .init(suggestionType: .user(.init(id: "\(index)", displayName: "\(index)", avatarURL: nil)), range: .init(), rawSuggestionText: "")
    }
    
    static var previews: some View {
        // Putting them is VStack allows the preview to work properly in tests
        VStack(spacing: 8) {
            CompletionSuggestionView(mediaProvider: MediaProviderMock(.init()),
                                     items: [
                                         .init(suggestionType: .user(.init(id: "@user_mention_1:matrix.org",
                                                                           displayName: "User 1",
                                                                           avatarURL: nil)),
                                               range: .init(),
                                               rawSuggestionText: ""),
                                         .init(suggestionType: .user(.init(id: "@user_mention_2:matrix.org",
                                                                           displayName: "User 2",
                                                                           avatarURL: .mockMXCUserAvatar,
                                                                           status: .mockCall)),
                                               range: .init(),
                                               rawSuggestionText: "")
                                     ]) { _ in }
        }
        
        VStack(spacing: 8) {
            CompletionSuggestionView(mediaProvider: MediaProviderMock(.init()),
                                     items: multipleItems) { _ in }
        }
    }
}
