//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (question 412 concept G): the catalogue is light. Stills only,
// on the chat's Mist, with search and sections; nothing runs here. A card opens
// the post's page, where it is tried before it is sent. What you made yourself
// is behind «Yours», for someone with an agent. The first visit starts with an
// introduction.
//

import Compound
import SFSafeSymbols
import SpiralComponents
import SpiralTokens
import SwiftUI

struct InteractivePostCatalogScreen: View {
    @Bindable var context: InteractivePostCatalogScreenViewModel.Context

    @Environment(\.openURL) private var openURL

    /// Whether the header's title has scrolled under the bar, which then names the screen.
    @State private var isTitleUnderBar = false

    var body: some View {
        Group {
            if context.viewState.hasSeenIntroduction {
                catalogue
            } else {
                InteractivePostCatalogIntroduction(context: context)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: context.viewState.hasSeenIntroduction)
        .chatBackground()
        // The catalogue's title is its header's, not the bar's large title, which truncated (question 412); the bar
        // names the screen once the header has scrolled under it. The introduction names itself under its fan.
        .navigationTitle(context.viewState.hasSeenIntroduction ? UntranslatedL10n.screenInteractiveCatalogTitle : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onAppear { context.send(viewAction: .screenAppeared(.catalogue)) }
        .onDisappear { context.send(viewAction: .screenDisappeared(.catalogue)) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // Not there at all until the header's title is under the bar: a title at opacity 0 still reached the
            // accessibility audit (and UI automation) through the bar, `accessibilityHidden` or not.
            ZStack {
                if isTitleUnderBar, context.viewState.hasSeenIntroduction {
                    Text(UntranslatedL10n.screenInteractiveCatalogTitle)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isTitleUnderBar)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button { context.send(viewAction: .cancel) } label: {
                CompoundIcon(\.close)
            }
            .accessibilityLabel(L10n.actionClose)
            .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.cancel)
        }
        if context.viewState.hasYours, context.viewState.hasSeenIntroduction {
            ToolbarItem(placement: .primaryAction) {
                // An HStack, not a Label: the bar draws a label's icon alone.
                Button { context.send(viewAction: .showYours) } label: {
                    HStack(spacing: 6) {
                        CompoundIcon(\.history, size: .small, relativeTo: .compound.bodyLGSemibold)
                        Text(UntranslatedL10n.screenInteractiveCatalogMine)
                            .font(.compound.bodyLGSemibold)
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.yours)
            }
        }
    }

    private var catalogue: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            InteractivePostCatalogTitle(text: UntranslatedL10n.screenInteractiveCatalogTitle)
                                .font(.compound.headingXLBold)
                                .foregroundStyle(.compound.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                            Text(UntranslatedL10n.screenInteractiveCatalogExplanation)
                                .font(.compound.bodyMD)
                                .foregroundStyle(.spiral.chatBackgroundTextSecondary)
                        }
                        .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
                        // 14, not 8: the Peek's head over the field reached 3 pt into the line above's frame (step 5's audit).
                        InteractivePostCatalogSearchField(query: $context.searchQuery)
                            .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
                            .padding(.top, 14)
                        content(width: geometry.size.width) {
                            withAnimation { proxy.scrollTo(Self.chipsID, anchor: .top) }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > Self.titleScrollDistance
                } action: { _, isUnder in
                    isTitleUnderBar = isUnder
                }
            }
        }
    }

    private static let chipsID = "chips"
    /// How far the content scrolls before the header's title is under the bar.
    private static let titleScrollDistance: CGFloat = 40

    @ViewBuilder
    private func content(width: CGFloat, scrollToChips: @escaping () -> Void) -> some View {
        switch context.viewState.catalogLoad {
        case .loading:
            InteractivePostCatalogLoading(width: width, side: InteractivePostCatalogCardMetrics.shelfSide(in: width))
        case .loaded:
            InteractivePostCatalogChips(context: context)
                .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
                .id(Self.chipsID)
            loaded(width: width, scrollToChips: scrollToChips)
                .padding(.top, 8)
        case .failed:
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.screenInteractiveCatalogErrorTitle,
                             message: UntranslatedL10n.screenInteractiveCatalogErrorHint,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retryCatalog) },
                             isOnChatBackground: true)
                .padding(.top, 40)
        case .needsNewerApp:
            // Decision 96: a newer catalogue asks for the update, and the button goes where the update is.
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.spiralAppNeedsUpdate,
                             action: .init(UntranslatedL10n.screenInteractiveCatalogUpdateAction) { openURL(AppSettings.appStoreURL) },
                             isOnChatBackground: true)
                .padding(.top, 40)
        }
    }

    @ViewBuilder
    private func loaded(width: CGFloat, scrollToChips: @escaping () -> Void) -> some View {
        switch context.viewState.content {
        case .shelves(let sections):
            // Eager, so the page's back finds every shelf where it was; each row of cards is lazy.
            VStack(alignment: .leading, spacing: 24) {
                let newTemplates = context.viewState.newCardTemplates
                if !newTemplates.isEmpty {
                    InteractivePostCatalogNewSlider(templates: newTemplates, stills: context.viewState.catalogueStills) { templateID in
                        context.send(viewAction: .openPost(templateID: templateID))
                    }
                }
                ForEach(sections) { section in
                    InteractivePostCatalogShelf(context: context,
                                                section: section,
                                                side: InteractivePostCatalogCardMetrics.shelfSide(in: width),
                                                showAll: scrollToChips)
                }
            }
        case .grid(let templates):
            InteractivePostCatalogGrid(context: context, templates: templates, side: InteractivePostCatalogCardMetrics.gridSide(in: width))
        case .noResults(let query):
            InteractivePostCatalogNoResults(context: context, query: query)
        }
    }
}

// MARK: - Titles

/// A title that never truncates (question 412): it shrinks a little to stay on one line, and past that wraps onto
/// lines balanced at a space, keeping its weight. Only a word too long for a line on its own shrinks further.
/// The font and colour are the caller's.
struct InteractivePostCatalogTitle: View {
    let text: String

    /// How far a title may shrink before it wraps instead.
    private static let shrink: CGFloat = 0.8
    /// How far a lone word that can't wrap may shrink.
    private static let lastResortShrink: CGFloat = 0.5

    var body: some View {
        let balanced = Self.balanced(text)
        ViewThatFits(in: .horizontal) {
            InteractivePostCatalogShrunkIdealWidth(scale: Self.shrink) {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.shrink)
            }
            Text(balanced)
                .fixedSize(horizontal: false, vertical: true)
            Text(balanced)
                .lineLimit(balanced.contains("\n") ? 2 : 1)
                .minimumScaleFactor(Self.lastResortShrink)
        }
        .accessibilityLabel(text)
    }

    /// The text broken at the space nearest its middle, so two lines are about as long; one word stays as it is.
    static func balanced(_ text: String) -> String {
        let middle = text.count / 2
        let spaces = text.enumerated().filter { $0.element == " " }.map(\.offset)
        guard let split = spaces.min(by: { abs($0 - middle) < abs($1 - middle) }) else { return text }
        var characters = Array(text)
        characters[split] = "\n"
        return String(characters)
    }
}

/// Says its content's ideal width is `scale` of what it is, so `ViewThatFits` takes a text that fits once shrunk;
/// offered a width, it lays the content out in it, where `minimumScaleFactor` does the shrinking.
private struct InteractivePostCatalogShrunkIdealWidth: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        guard let width = proposal.width else {
            let ideal = content.sizeThatFits(.init(width: nil, height: proposal.height))
            return CGSize(width: (ideal.width * scale).rounded(.up), height: ideal.height)
        }
        return content.sizeThatFits(.init(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: .init(bounds.size))
    }
}

// MARK: - Search

/// The glass field the catalogue filters by as it is typed, with the Peek looking over its edge.
struct InteractivePostCatalogSearchField: View {
    @Binding var query: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            CompoundIcon(\.search, size: .small, relativeTo: .compound.bodyLG)
                .foregroundStyle(.compound.iconSecondary)
                .accessibilityHidden(true)
            TextField(text: $query, prompt: Text(UntranslatedL10n.screenInteractiveCatalogSearchPlaceholder)) {
                Text(UntranslatedL10n.screenInteractiveCatalogSearchPlaceholder)
            }
            .font(.compound.bodyLG)
            .foregroundStyle(.compound.textPrimary)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .focused($isFocused)
            .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemSymbol: .xmarkCircleFill)
                        .foregroundStyle(.compound.iconTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.actionClear)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(.capsule)
        .onTapGesture { isFocused = true }
        .spiralGlass(in: Capsule(), isInteractive: true)
        .background(alignment: .topTrailing) {
            // Behind the field: only its head shows over the top edge. The Agents tab's layered Peek, drawn as the tab
            // draws it: hierarchical, the back layer lighter (operator, 2026-11-15).
            Image(asset: Asset.spiralPeekLayers)
                .symbolRenderingMode(.hierarchical)
                .font(.compound.headingXLBold)
                .foregroundStyle(.compound.iconAccentPrimary)
                .offset(x: -28, y: -30)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Sections

/// The section chips, wrapping, «All» first; the chosen one is the screen's one blue.
private struct InteractivePostCatalogChips: View {
    let context: InteractivePostCatalogScreenViewModel.Context

    var body: some View {
        InteractivePostCatalogWrappingLayout(spacing: 8) {
            chip(UntranslatedL10n.screenInteractiveCatalogAllSections, sectionID: nil)
            ForEach(context.viewState.shelves) { section in
                chip(section.localizedTitle, sectionID: section.id)
            }
        }
    }

    private func chip(_ title: String, sectionID: String?) -> some View {
        let isSelected = context.viewState.bindings.sectionID == sectionID
        return Button { context.send(viewAction: .selectSection(sectionID)) } label: {
            SpiralWrappingChip(wrappedCornerRadius: 18) { shape, cornerRadius in
                Text(title)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(isSelected ? .compound.textOnSolidPrimary : .compound.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, cornerRadius == nil ? 0 : 6)
                    .frame(minHeight: 36)
                    .background(isSelected ? Color.compound.bgAccentRest : Color.spiral.chatBackgroundSurface, in: shape)
                    .chatElevation(cornerRadius: cornerRadius)
                    .contentShape(shape)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.section(sectionID ?? "all"))
    }
}

/// Lays its views out in rows, starting a new row when the next doesn't fit. A view wider than the row gets a row
/// of its own at the row's width, where its words wrap (AX3–AX5 on a 375 pt phone; question 412).
struct InteractivePostCatalogWrappingLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .init(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].size(fittingWidth: width)
            let last = rows.count - 1
            if !rows[last].indices.isEmpty, rows[last].width + spacing + size.width > width {
                rows.append(Row())
            }
            let row = rows.count - 1
            rows[row].width += (rows[row].indices.isEmpty ? 0 : spacing) + size.width
            rows[row].height = max(rows[row].height, size.height)
            rows[row].indices.append(index)
            rows[row].sizes.append(size)
        }
        return rows
    }
}

nonisolated extension LayoutSubview {
    /// The view's ideal size while it fits `width`; past that, its size at `width`, where its words wrap.
    func size(fittingWidth width: CGFloat) -> CGSize {
        let ideal = sizeThatFits(.unspecified)
        guard ideal.width > width else { return ideal }
        let fitted = sizeThatFits(.init(width: width, height: nil))
        return CGSize(width: min(fitted.width, width), height: fitted.height)
    }
}

/// A chip on one line in a capsule; when its words don't fit the width it's given (AX sizes, a narrow phone) they
/// wrap in a rounded rectangle instead, as a capsule's round ends would cut into a second line (question 412).
/// `content` draws the chip in the shape it's handed, with `cornerRadius` nil for the capsule (`chatElevation`'s).
struct SpiralWrappingChip<Content: View>: View {
    let wrappedCornerRadius: CGFloat
    @ViewBuilder let content: (_ shape: AnyShape, _ cornerRadius: CGFloat?) -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(AnyShape(Capsule()), nil)
                .fixedSize(horizontal: true, vertical: false)
            content(AnyShape(RoundedRectangle(cornerRadius: wrappedCornerRadius, style: .continuous)), wrappedCornerRadius)
        }
    }
}

// MARK: - Shelves and grid

private struct InteractivePostCatalogShelf: View {
    let context: InteractivePostCatalogScreenViewModel.Context
    let section: SpiralAppCatalog.Section
    let side: CGFloat
    let showAll: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: InteractivePostCatalogCardMetrics.spacing) {
                    ForEach(context.viewState.templates(of: section)) { template in
                        InteractivePostCatalogTemplateCell(template: template, side: side, still: context.viewState.catalogueStills[template.id],
                                                          isNew: context.viewState.isNew(template.id)) {
                            context.send(viewAction: .openPost(templateID: template.id))
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled() // The cards' shadow reaches past the row.
        }
    }

    /// At accessibility sizes the «All N ›» link goes on its own line under the section's name: beside it, the
    /// link that never shrinks left a name like «Wszystkie 12 ›»'s section about 40 pt (DEBT § 412 catalogue G).
    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            InteractivePostCatalogTitle(text: section.localizedTitle)
                .font(.compound.headingMDBold)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            Button {
                context.send(viewAction: .selectSection(section.id))
                showAll()
            } label: {
                HStack(spacing: 2) {
                    Text(UntranslatedL10n.screenInteractiveCatalogAllCount(section.items.count))
                    CompoundIcon(\.chevronRight, size: .xSmall, relativeTo: .compound.bodyMD)
                        .flipsForRightToLeftLayoutDirection(true)
                }
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textActionAccent)
                // On the section chips' surface: straight on the Mist the blue fell to 2.3:1 (question 412).
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.spiral.chatBackgroundSurface, in: .capsule)
                .chatElevation()
                .frame(minHeight: 44) // The chip's height is the section chips'; the touch area stays 44.
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .fixedSize() // The section's name gives way, by shrinking and then wrapping, never the link.
            .accessibilityLabel(UntranslatedL10n.a11yInteractiveCatalogAll(section.items.count, section.localizedTitle))
        }
        .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
    }
}

/// One section, or what a search found, two to a row.
private struct InteractivePostCatalogGrid: View {
    let context: InteractivePostCatalogScreenViewModel.Context
    let templates: [SpiralAppTemplate]
    let side: CGFloat

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(side), spacing: InteractivePostCatalogCardMetrics.spacing, alignment: .top), count: 2)
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(templates) { template in
                InteractivePostCatalogTemplateCell(template: template, side: side, still: context.viewState.catalogueStills[template.id],
                                                          isNew: context.viewState.isNew(template.id)) {
                    context.send(viewAction: .openPost(templateID: template.id))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A search that found nothing is not a dead end: the agent makes what was asked for.
private struct InteractivePostCatalogNoResults: View {
    let context: InteractivePostCatalogScreenViewModel.Context
    let query: String

    var body: some View {
        SpiralEmptyState(symbol: .magnifyingglass,
                         title: UntranslatedL10n.screenInteractiveCatalogNoResultsTitle,
                         message: context.viewState.hasYours ? nil : UntranslatedL10n.screenInteractiveCatalogNoResultsHint,
                         action: context.viewState.hasYours ? .init(UntranslatedL10n.screenInteractiveCatalogAgentMakes(query)) {
                             context.send(viewAction: .startNew(description: query))
                         } : nil,
                         isOnChatBackground: true)
            .padding(.top, 24)
            .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
            .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.noResults)
    }
}

/// The chips and shelves before the catalogue arrives, in the shape they will have.
private struct InteractivePostCatalogLoading: View {
    /// The screen's width, which a shelf's row of cards is cut to.
    let width: CGFloat
    let side: CGFloat

    var body: some View {
        SpiralPreloader(label: L10n.commonLoading) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 8) {
                    chip
                    chip
                    chip
                }
                .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
                shelf
                shelf
            }
        }
    }

    private var chip: some View {
        Text(verbatim: "Section")
            .font(.compound.bodyMDSemibold)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Section name")
                .font(.compound.headingMDBold)
                .frame(minHeight: 44)
                .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
            HStack(alignment: .top, spacing: InteractivePostCatalogCardMetrics.spacing) {
                card
                card
                card
            }
            .padding(.leading, InteractivePostCatalogCardMetrics.screenMargin)
            // The screen's width exactly: the cards run past its edge, and a frame of `maxWidth: .infinity` still
            // took their width, which widened the header and the search field off the screen (the critic, 2026-11-14).
            .frame(width: width, alignment: .leading)
            .clipped()
        }
    }

    /// A card's bubble, its still and its two lines of each, at the size the real one will have.
    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.compound.bgSubtleSecondary
                .frame(width: side - 2 * InteractivePostCatalogCardMetrics.stillInset,
                       height: side - 2 * InteractivePostCatalogCardMetrics.stillInset)
                .clipShape(RoundedRectangle(cornerRadius: InteractivePostCatalogCardMetrics.stillRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Post name")
                    .font(.compound.bodyMDSemibold)
                    .lineLimit(2, reservesSpace: true)
                Text(verbatim: "One line about it")
                    .font(.compound.bodySM)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 6)
        }
        .padding(InteractivePostCatalogCardMetrics.stillInset)
        .padding(.bottom, 4)
        .frame(width: side, alignment: .leading)
        .background(Color.spiral.chatBackgroundSurface, in: RoundedRectangle(cornerRadius: SpiralRadius.bubble, style: .continuous))
    }
}

// MARK: - Previews

/// A small catalogue in the shape of the real one. A preview runs no web view.
enum InteractivePostCatalogPreviewFixture {
    static let catalog = SpiralAppCatalog(runtime: "1",
                                          sections: [.init(id: "decide", title: "Decide", titles: nil, items: ["wheel", "dice", "invite", "list", "poll"]),
                                                     .init(id: "two", title: "For two", titles: nil, items: ["chess", "sea-battle", "tic-tac-toe"])],
                                          items: [template("wheel", "Who's-it wheel", "Stops on one for everyone", traits: [.names, .sameForAll]),
                                                  template("dice", "Dice", "Everyone rolls, the last one shows", traits: [.sameForAll, .shown]),
                                                  template("invite", "Event invite", "Who's coming, who isn't, and the date", ask: "When and where are you meeting?"),
                                                  template("list", "Shared list", "Shopping or chores together"),
                                                  template("poll", "Poll", "One question, shares and names", ask: "What's the question?"),
                                                  template("chess", "Chess", "Full rules, a log of moves", players: .two, traits: [.turns]),
                                                  template("sea-battle", "Sea battle", "Fleets stay hidden", players: .two, traits: [.secret, .turns]),
                                                  template("tic-tac-toe", "Tic-tac-toe", "Three in a row", players: .two, traits: [.turns])],
                                          newIDs: ["sea-battle", "dice"])

    /// Four new posts, for the «New» slider with its dots.
    static let severalNewIDs = ["sea-battle", "dice", "poll", "chess"]

    /// A preview's stand-in for a template's still.
    static let still = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
        UIColor.compound.bgAccentRest.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
    }

    static func viewModel(roomName: String = "Stage A",
                          assistant: InteractivePostCatalogAssistant = .available,
                          hasSeenIntroduction: Bool = true,
                          peopleInRoom: Int? = nil,
                          catalogLoad: InteractivePostCatalogLoad = .loaded,
                          query: String = "",
                          sectionID: String? = nil,
                          page: String? = nil,
                          threads: [InteractivePostThreadItem] = [],
                          threadsLoad: InteractivePostCatalogLoad = .loaded,
                          newIDs: [String]? = nil) -> InteractivePostCatalogScreenViewModel {
        var state = InteractivePostCatalogScreenViewState(roomName: roomName,
                                                          catalogURL: "https://spiral.md/catalog/",
                                                          ownUserID: "@alice:spiral.md",
                                                          assistant: assistant,
                                                          livePreview: DraftPreview())
        state.hasSeenIntroduction = hasSeenIntroduction
        state.catalogLoad = catalogLoad
        if catalogLoad == .loaded {
            let catalog = newIDs.map { SpiralAppCatalog(runtime: catalog.runtime, sections: catalog.sections, items: catalog.items, newIDs: $0) } ?? catalog
            state.catalog = catalog
            state.shelves = InteractivePostCatalogScreenViewState.shelves(of: catalog, peopleInRoom: peopleInRoom)
            state.catalogueStills = Dictionary(uniqueKeysWithValues: catalog.items.map { ($0.id, still) })
            state.artifacts = page.flatMap(artifact).map { [page ?? "": $0] } ?? [:]
        }
        state.bindings.searchQuery = query
        state.bindings.sectionID = sectionID
        if let page, let section = state.homeSection(of: page) {
            state.page = InteractivePostCatalogPage(section: section, currentID: page)
        }
        state.threads = threads
        state.threadsLoad = threadsLoad
        return InteractivePostCatalogScreenViewModel(previewState: state)
    }

    static let threads = [thread("1", title: "Class quiz", room: "Group", minutes: 44),
                          thread("2", title: "Pizza vote", room: "Stage A", minutes: 1440),
                          thread("3", title: nil, room: "Family", minutes: 2880, lastMessage: "Here's a new version"),
                          thread("4", title: "Office raffle", room: "Work", minutes: 4320),
                          thread("5", title: "Birthday card for mum", room: "Family", minutes: 10080)]

    /// Enough of a post for Send to wake up. Nothing runs it.
    private static func artifact(_ id: String) -> SpiralAppArtifact? {
        let manifest = #"{"app_id":"tpl-\#(id)","runtime":"1","entry":"app.jsx","aspect":"1:1","state_channel":"matrix","capabilities":[],"limits":{"max_state_bytes":16384}}"#
        let packed = SpiralAppContainer.pack(manifestJSON: manifest, entry: "app.jsx", source: "")
        return SpiralAppArtifact.verified(packed: packed, claimedDigest: SpiralAppArtifact.digest(of: packed))
    }

    private static func template(_ id: String, _ title: String, _ description: String, ask: String? = nil,
                                 players: SpiralAppTemplate.Players? = .group, traits: [SpiralAppTemplate.Trait] = []) -> SpiralAppTemplate {
        SpiralAppTemplate(id: id, title: title, titles: nil, description: description, descriptions: nil,
                          aspect: "1:1", source: "\(id).jsx", manifest: "\(id)/manifest.json", row: nil,
                          asks: ask.map { [SpiralAppCatalog.baseLanguage: $0] }, runtime: nil,
                          players: players, traits: ask == nil ? traits : [.agentFills] + traits)
    }

    private static func thread(_ id: String, title: String?, room: String, minutes: Double, lastMessage: String? = nil) -> InteractivePostThreadItem {
        InteractivePostThreadItem(id: id, dmRoomID: "!dm", madeForRoomName: room,
                                  lastActivity: .now.addingTimeInterval(-minutes * 60),
                                  title: title, lastMessage: lastMessage, replies: 3)
    }
}

struct InteractivePostCatalogScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    private static let fixture = InteractivePostCatalogPreviewFixture.self

    static let group = fixture.viewModel(peopleInRoom: 5, newIDs: fixture.severalNewIDs)
    static let oneNew = fixture.viewModel(peopleInRoom: 5, newIDs: ["sea-battle"])
    static let twoPeople = fixture.viewModel(peopleInRoom: 2)
    static let section = fixture.viewModel(sectionID: "decide")
    static let search = fixture.viewModel(query: "es")
    static let noResults = fixture.viewModel(query: "Karaoke")
    static let noResultsNoAgent = fixture.viewModel(assistant: .none, query: "Karaoke")
    static let noAgent = fixture.viewModel(assistant: .none, peopleInRoom: 5)
    static let introduction = fixture.viewModel(hasSeenIntroduction: false)
    static let loading = fixture.viewModel(catalogLoad: .loading)
    static let failed = fixture.viewModel(catalogLoad: .failed)
    static let needsNewerApp = fixture.viewModel(catalogLoad: .needsNewerApp)

    static var previews: some View {
        screen(group, "Catalogue in a group")
        screen(twoPeople, "Catalogue in a room of two")
        screen(section, "One section")
        screen(search, "Search")
        screen(noResults, "Search found nothing")
        screen(noResultsNoAgent, "Search found nothing, no agent")
        screen(noAgent, "No agent")
        screen(introduction, "Introduction")
        screen(loading, "Loading")
        screen(failed, "Failure")
        screen(needsNewerApp, "Needs a newer app")
        screen(oneNew, "One new post")
    }

    private static func screen(_ viewModel: InteractivePostCatalogScreenViewModel, _ name: String) -> some View {
        ElementNavigationStack {
            InteractivePostCatalogScreen(context: viewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName(name)
    }
}
