//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 412 concept G): a post's own page. The post runs at
// the screen's width, playable, as a rehearsal in memory: nothing is sent until
// Send (`SpiralAppPreviewSession`). A sideways swipe moves to the section's next
// post; only the post on screen runs, its neighbours show their stills, so there
// is one web view on screen. Under it, concept A1: the post's one line, its
// facts as chips, and one row of actions — Send, or changing it with the agent
// first; for a post the agent fills in, the agent's path or the way to an agent.
//

import Compound
import SFSafeSymbols
import SpiralTokens
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

struct InteractivePostCatalogPostScreen: View {
    let context: InteractivePostCatalogScreenViewModel.Context

    /// Where the pager opens: on the page's post, by id.
    @State private var position: ScrollPosition
    @State private var hold = InteractivePostCatalogPagerHold()
    /// The post waiting to become the page's once the pager settles; one at a time, and none once the page has gone.
    @State private var settling: Task<Void, Never>?

    init(context: InteractivePostCatalogScreenViewModel.Context) {
        self.context = context
        _position = State(initialValue: context.viewState.page.map { ScrollPosition(id: $0.currentID, anchor: .center) } ?? ScrollPosition(idType: String.self))
    }

    var body: some View {
        GeometryReader { geometry in
            if let page = context.viewState.page {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(context.viewState.templates(of: page.section)) { template in
                                InteractivePostCatalogPostPage(context: context,
                                                               template: template,
                                                               height: geometry.size.height + geometry.safeAreaInsets.bottom,
                                                               bottomInset: geometry.safeAreaInsets.bottom)
                                    .containerRelativeFrame(.horizontal)
                                    .id(template.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    // The first layout already on the page's post: on iOS 18 the scroll position by id lands a layout
                    // later, so a page laid out once (a snapshot) showed the section's first post under the page's
                    // pill. The pages are all as wide as the pager, so the post's share of the scroll is its index's.
                    .defaultScrollAnchor(Self.openingAnchor(of: page.currentID, in: context.viewState.templates(of: page.section).map(\.id)),
                                         for: .initialOffset)
                    .scrollPosition($position)
                    .scrollIndicators(.hidden)
                    // The bar's hard edge drew a band across the Mist; nothing scrolls under the bar here.
                    .backportScrollEdgeEffectHidden()
                    .ignoresSafeArea(.container, edges: .bottom)
                    .onScrollPhaseChange { _, phase in
                        hold.scrollPhaseChanged(to: phase)
                    }
                    .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { templateIDs in
                        switch hold.postsOnScreen(templateIDs, pagePost: page.currentID) {
                        case .none:
                            break
                        case .show(let templateID):
                            context.send(viewAction: .showPage(templateID: templateID))
                        case .showOnceSettled(let templateID):
                            showOnceSettled(templateID, over: page.currentID)
                        case .scrollBack:
                            proxy.scrollTo(page.currentID, anchor: .center)
                        }
                    }
                }
            }
        }
        .chatBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let page = context.viewState.page {
                    InteractivePostCatalogPagerPill(page: page)
                }
            }
        }
        .onAppear { context.send(viewAction: .screenAppeared(.post)) }
        .onDisappear {
            settling?.cancel()
            context.send(viewAction: .screenDisappeared(.post))
        }
    }

    /// Where the pager's first layout puts it: on `postID`, as a share of the scroll across `postIDs`.
    static func openingAnchor(of postID: String, in postIDs: [String]) -> UnitPoint {
        guard postIDs.count > 1, let index = postIDs.firstIndex(of: postID) else { return .leading }
        return UnitPoint(x: CGFloat(index) / CGFloat(postIDs.count - 1), y: 0.5)
    }

    /// A post the pager showed with no scroll moving it becomes the page's only if it is still there a moment later:
    /// on iOS 18 the pager jumped to the section's first post for one layout and came back, and the page took the
    /// jump for a swipe (the snapshot gate, 2026-11-22).
    private func showOnceSettled(_ templateID: String, over pagePost: String) {
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: InteractivePostCatalogPagerHold.settling)
            guard !Task.isCancelled, hold.stillShows(templateID, over: pagePost), context.viewState.page?.currentID == pagePost else { return }
            context.send(viewAction: .showPage(templateID: templateID))
        }
    }
}

/// What the post page's pager does with the posts it reports on screen. Its first frame was on the section's first
/// post — reported before the page's — and the page took that for a swipe or stayed there: a card opened its shelf's
/// first post (operator, 2026-11-15). So until the page's post has been on screen once, another post is scrolled
/// back from; after that, or once a finger moves the pager, the post on screen is the page's post, however it got
/// there (a swipe, VoiceOver, Full Keyboard Access or Switch Control). One that got there with no scroll is the
/// page's only once it stays: on iOS 18 the pager could jump to the first post for one layout and come back.
struct InteractivePostCatalogPagerHold {
    enum Response: Equatable {
        case none
        /// The post on screen becomes the page's post.
        case show(String)
        /// The post on screen becomes the page's post if it is still on screen after `settling`.
        case showOnceSettled(String)
        /// The pager goes back to the page's post.
        case scrollBack
    }

    /// Long enough for a pager that jumped for one layout to come back.
    static let settling = Duration.milliseconds(150)

    private(set) var hasShownPage = false
    /// A swipe, its deceleration, or an animated scroll (VoiceOver's among them) is moving the pager.
    private(set) var isScrolling = false
    /// The posts the pager reported last.
    private(set) var lastReported: [String] = []

    mutating func postsOnScreen(_ templateIDs: [String], pagePost: String) -> Response {
        lastReported = templateIDs
        if templateIDs.contains(pagePost) {
            hasShownPage = true
            return .none
        }
        guard let templateID = templateIDs.first else { return .none }
        guard hasShownPage else { return .scrollBack }
        return isScrolling ? .show(templateID) : .showOnceSettled(templateID)
    }

    /// A finger always wins, even on a page whose post never showed.
    mutating func scrollPhaseChanged(to phase: ScrollPhase) {
        if phase == .interacting {
            hasShownPage = true
        }
        isScrolling = phase.isScrolling
    }

    /// Whether the pager still shows `templateID`, and nothing of the page's post.
    func stillShows(_ templateID: String, over pagePost: String) -> Bool {
        lastReported.first == templateID && !lastReported.contains(pagePost)
    }
}

/// «For two · 2 of 10»: which section the swipe goes through, and where in it. The position is quieter by weight, not
/// grey: the glass takes the Mist's blue, and grey read 2.56:1 on it in dark (question 412).
private struct InteractivePostCatalogPagerPill: View {
    let page: InteractivePostCatalogPage

    var body: some View {
        HStack(spacing: 6) {
            // In the bar there is no second line: a long section name shrinks a little first.
            Text(page.section.localizedTitle)
                .font(.compound.bodyMDSemibold)
                .foregroundStyle(.compound.textPrimary)
                .minimumScaleFactor(0.8)
            Text(UntranslatedL10n.screenInteractiveCatalogPagePosition(page.position, page.section.items.count))
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .spiralGlass(in: Capsule())
        // A bar's title: it stops growing at AX1, as the system's do, and a long press shows it large.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityShowsLargeContentViewer()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.pagePosition)
    }
}

/// One post of the section, with what it is and what to do with it (question 412, concept A1): the post, its
/// line and facts under it, the actions at the bottom — all on the first screen, the post sized to what is left.
private struct InteractivePostCatalogPostPage: View {
    let context: InteractivePostCatalogScreenViewModel.Context
    let template: SpiralAppTemplate
    /// The page's height to the bottom edge, under the home indicator too.
    let height: CGFloat
    let bottomInset: CGFloat

    /// The page holding the running post, the one swiped away too until its picture is taken: falling back to
    /// the catalogue's still in between flashed another language's picture.
    private var isLive: Bool {
        context.viewState.runningTemplateID == template.id
    }

    /// The page on screen. Its neighbours in the pager are laid out too, so only this one carries the identifiers
    /// a test finds by `.firstMatch`; a neighbour's would be read or tapped off screen (question 412).
    private var isCurrent: Bool {
        context.viewState.page?.currentID == template.id
    }

    var body: some View {
        // A scroll view only for text sizes where even the smallest post leaves too little room.
        ScrollView {
            InteractivePostCatalogPageLayout(height: height,
                                             bottomInset: bottomInset,
                                             aspectRatio: Self.aspectRatio(of: template),
                                             margin: InteractivePostCatalogCardMetrics.screenMargin) {
                SpiralAppTryBanner()
                post
                InteractivePostCatalogPostDetails(template: template, isCurrent: isCurrent)
                InteractivePostCatalogPostActions(context: context, template: template, isCurrent: isCurrent)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .backportScrollEdgeEffectHidden()
    }

    /// The post names itself; the page doesn't repeat its title (A1).
    private var post: some View {
        ZStack {
            if isLive {
                InteractivePostCatalogLivePost(preview: context.viewState.livePreview,
                                               still: context.viewState.still(of: template.id),
                                               title: template.localizedTitle)
                    .background(InteractivePostCatalogTouchGuard())
            } else {
                InteractivePostCatalogStill(image: context.viewState.still(of: template.id))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: SpiralRadius.listCard, style: .continuous))
        .chatElevation(cornerRadius: SpiralRadius.listCard)
        .accessibilityElement(children: isLive ? .contain : .ignore)
        .accessibilityLabel(UntranslatedL10n.a11ySpiralAppPost(template.localizedTitle))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.currentTitle, isEnabled: isCurrent)
    }

    /// The manifest's shape, held to what a conversation would give it.
    static func aspectRatio(of template: SpiralAppTemplate) -> CGFloat {
        let parts = template.aspect.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return 1 }
        return min(max(CGFloat(parts[0] / parts[1]), SpiralAppPost.narrowestAspectRatio), SpiralAppPost.widestAspectRatio)
    }
}

/// The page in one pass: the pill, the post, its line and facts, and the actions held to the bottom. The post takes
/// what the rest leaves, at its own shape — narrower than the screen if it must — so Send never drops below the
/// fold (question 412: a square post and three facts did that). Below a smallest post the page grows and scrolls.
private struct InteractivePostCatalogPageLayout: Layout {
    /// The page's height, under the home indicator too.
    let height: CGFloat
    let bottomInset: CGFloat
    let aspectRatio: CGFloat
    let margin: CGFloat
    private let top: CGFloat = 8
    private let pillGap: CGFloat = 12
    private let detailsGap: CGFloat = 16
    private let actionsGap: CGFloat = 16
    /// Under this a post stops shrinking: a post the eye can't read is worse than a scroll.
    private let smallestPostHeight: CGFloat = 200

    private var bottom: CGFloat {
        max(bottomInset, 16)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: frames(in: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(in: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames.rects) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .init(frame.size))
        }
    }

    private func frames(in width: CGFloat, subviews: Subviews) -> (rects: [CGRect], height: CGFloat) {
        guard subviews.count == 4 else { return ([], height) }
        let inner = max(width - 2 * margin, 0)
        // The try banner at its own width while it fits; past that it wraps within the margins (AX sizes).
        let pill = subviews[0].size(fittingWidth: inner)
        let details = subviews[2].sizeThatFits(.init(width: inner, height: nil))
        let actions = subviews[3].sizeThatFits(.init(width: inner, height: nil))

        let fixed = top + pill.height + pillGap + detailsGap + details.height + actionsGap + actions.height + bottom
        let fullHeight = inner / aspectRatio
        let postHeight = min(fullHeight, max(height - fixed, min(smallestPostHeight, fullHeight)))
        let postWidth = postHeight < fullHeight ? postHeight * aspectRatio : inner
        let pageHeight = max(height, fixed + postHeight)

        let pillRect = CGRect(x: (width - pill.width) / 2, y: top, width: pill.width, height: pill.height)
        let postRect = CGRect(x: (width - postWidth) / 2, y: pillRect.maxY + pillGap, width: postWidth, height: postHeight)
        let detailsRect = CGRect(x: margin, y: postRect.maxY + detailsGap, width: inner, height: details.height)
        let actionsRect = CGRect(x: margin, y: pageHeight - bottom - actions.height, width: inner, height: actions.height)
        return ([pillRect, postRect, detailsRect, actionsRect], pageHeight)
    }
}

/// The running post. Its own view, so only it redraws as the post starts; the
/// still stays until the post has drawn, so it never passes through an empty box.
/// It opens full screen as a post in a chat does (question 412): the same expand
/// disc, the post's own `ui.expand`, the same viewer — still a rehearsal there,
/// with no author or room, and its ✕ back to this page.
private struct InteractivePostCatalogLivePost: View {
    @ObservedObject var preview: DraftPreview
    let still: UIImage?
    let title: String

    @State private var showsViewer = false
    /// Bumped when the viewer closes: this box takes the post back from the viewer's.
    @State private var reclaimCount = 0

    var body: some View {
        ZStack {
            if let instance = preview.instance {
                DraftPreviewSurface(container: instance.containerView, reclaimCount: reclaimCount)
            }
            if preview.isReady {
                SpiralAppExpandButton { showsViewer = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            } else {
                InteractivePostCatalogStill(image: still)
                    .allowsHitTesting(false)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: preview.isReady)
        .spiralAppViewer(isPresented: $showsViewer,
                         isReady: preview.isReady,
                         expandRequests: preview.expandRequests,
                         onDismissed: {
                             preview.setViewport(.row)
                             reclaimCount += 1
                         },
                         viewer: viewer)
    }

    private func viewer() -> some View {
        SpiralAppExpandedView(title: title, isRehearsal: true) {
            if let instance = preview.instance {
                DraftPreviewSurface(container: instance.containerView)
                    .onAppear { preview.setViewport(.expanded) }
            }
        }
    }
}

/// Under the post: its one line, and up to three facts as chips that wrap.
private struct InteractivePostCatalogPostDetails: View {
    let template: SpiralAppTemplate
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(template.localizedDescription)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            InteractivePostCatalogFacts(facts: InteractivePostCatalogFact.facts(of: template), isCurrent: isCurrent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The page's one row of actions (A1). A plain post: the Peek in a glass circle to change it with the agent first,
/// and a wide Send that doesn't name the chat — VoiceOver does. A post the agent fills in: one wide «Fill it in with
/// the agent», or the way to an agent, with what happens next in quiet text under it.
private struct InteractivePostCatalogPostActions: View {
    let context: InteractivePostCatalogScreenViewModel.Context
    let template: SpiralAppTemplate
    let isCurrent: Bool

    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 54
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At accessibility sizes a label may take more lines than one, rather than end in «…» (DEBT § 412 catalogue tails).
    private var labelLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 3 : 1
    }

    var body: some View {
        switch context.viewState.choiceAction(for: template) {
        case .publish(let canChange):
            // At accessibility sizes the Peek's circle grows past 100 pt, and Send beside it was cut to «Наді…»:
            // it goes under the circle there, at the page's width.
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                if canChange {
                    changeWithAgent
                }
                send
            }
        case .fillIn(let ask):
            withCaption(UntranslatedL10n.screenInteractiveCatalogPreviewAsks(ask), isNote: false) {
                fillIn
            }
        case .createAgent:
            withCaption(UntranslatedL10n.screenInteractiveCatalogAgentFillsHint) {
                createAgent(isSettingUp: false)
            }
        case .agentSettingUp:
            withCaption(UntranslatedL10n.screenInteractiveCatalogAgentSettingUp) {
                createAgent(isSettingUp: true)
            }
        case .agentUnknown:
            // The agents couldn't be read: not "create one" (decision 129), and not a dead button — read them again.
            withCaption(UntranslatedL10n.screenInteractiveCatalogAgentUnknown) {
                retryAgents
            }
        }
    }

    private var send: some View {
        Button { context.send(viewAction: .publishTemplate(template)) } label: {
            Label(L10n.actionSend, icon: \.send)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.75 : 1) // One word: it can't wrap.
                .frame(minHeight: 24)
        }
        .buttonStyle(.compound(.primary))
        .disabled(context.viewState.artifacts[template.id] == nil)
        .accessibilityLabel(context.viewState.sendAccessibilityLabel)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.publish, isEnabled: isCurrent)
    }

    /// The Peek in glass. Its name is VoiceOver's, and a long press's.
    private var changeWithAgent: some View {
        Button { context.send(viewAction: .changeTemplate(template)) } label: {
            // The button's only content (WCAG 1.4.11): the action accent read ~2.9:1 on this glass in dark, so it takes
            // the chips' link accent, as «Create an agent» does.
            Image(asset: Asset.spiralPeekFill)
                .font(.compound.headingMDBold)
                .foregroundStyle(.compound.textLinkExternal)
                .frame(width: circle, height: circle)
                .spiralGlass(in: Circle(), isInteractive: true)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(UntranslatedL10n.screenInteractiveCatalogChangeWithAgent)
        .contextMenu {
            Button { context.send(viewAction: .changeTemplate(template)) } label: {
                Label { Text(UntranslatedL10n.screenInteractiveCatalogChangeWithAgent) } icon: { Image(asset: Asset.spiralPeekFill) }
            }
        }
        .accessibilityLabel(UntranslatedL10n.screenInteractiveCatalogChangeWithAgent)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.changeFirst, isEnabled: isCurrent)
    }

    private var fillIn: some View {
        Button { context.send(viewAction: .changeTemplate(template)) } label: {
            HStack(spacing: 8) {
                Image(asset: Asset.spiralPeekFill)
                    .accessibilityHidden(true)
                Text(UntranslatedL10n.screenInteractiveCatalogFillIn)
                    .lineLimit(labelLineLimit)
                    .multilineTextAlignment(.center)
            }
            .frame(minHeight: 24)
        }
        .buttonStyle(.compound(.primary))
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.fillIn, isEnabled: isCurrent)
    }

    /// While the agents are read again it spins, as «setting up» does, and can't be pressed.
    private var retryAgents: some View {
        Button { context.send(viewAction: .retryAgents) } label: {
            Group {
                if context.viewState.isReadingAgents {
                    Label { Text(L10n.actionRetry) } icon: {
                        // The restart icon, hidden, holds the slot so the button keeps its width as the icon swaps.
                        // The spinner takes the Mist's quiet ink as «setting up»'s does: the plain grey all but
                        // vanished on the disabled fill.
                        CompoundIcon(\.restart)
                            .hidden()
                            .overlay { ProgressView().tint(.spiral.chatBackgroundTextSecondary) }
                    }
                } else {
                    Label(L10n.actionRetry, icon: \.restart)
                }
            }
            .labelStyle(.titleAndIcon)
            .lineLimit(labelLineLimit)
            .frame(minHeight: 24)
        }
        .buttonStyle(.compound(.primary))
        .disabled(context.viewState.isReadingAgents)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.retryAgents, isEnabled: isCurrent)
    }

    /// A step aside, not a send: glass, not blue. Waiting for an agent being set up, it spins, says so and can't be
    /// pressed.
    private func createAgent(isSettingUp: Bool) -> some View {
        Button { context.send(viewAction: .showAgents) } label: {
            HStack(spacing: 8) {
                if isSettingUp {
                    ProgressView()
                } else {
                    Image(asset: Asset.spiralPeekFill)
                        .accessibilityHidden(true)
                }
                Text(isSettingUp ? UntranslatedL10n.screenInteractiveCatalogAgentSettingUpAction : UntranslatedL10n.screenInteractiveCatalogCreateAgent)
                    .lineLimit(labelLineLimit)
                    .multilineTextAlignment(.center)
            }
            .font(.compound.bodyLGSemibold)
            // The accent one step deeper in light and lighter in dark: on glass over the Mist the action accent read
            // 3.95:1 (light) and 2.9:1 (dark); this is 4.8:1 in both (step 5's audit). Setting up, it takes the Mist's
            // quiet ink, as the caption under it: the disabled grey all but vanished on light glass.
            .foregroundStyle(isSettingUp ? .spiral.chatBackgroundTextSecondary : .compound.textLinkExternal)
            .tint(.spiral.chatBackgroundTextSecondary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: circle)
            .spiralGlass(in: Capsule(), isInteractive: !isSettingUp)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(isSettingUp)
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.createAgent, isEnabled: isCurrent)
    }

    /// `isNote`: the caption says why the agent's path isn't open, rather than what it will ask.
    private func withCaption(_ caption: String, isNote: Bool = true, @ViewBuilder button: () -> some View) -> some View {
        VStack(spacing: 10) {
            button()
            Text(caption)
                .font(.compound.bodySM)
                .foregroundStyle(.spiral.chatBackgroundTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.assistantNote, isEnabled: isNote && isCurrent)
        }
    }
}

/// Up to three facts on who a post is for and how it plays, as glass chips that wrap.
private struct InteractivePostCatalogFacts: View {
    let facts: [InteractivePostCatalogFact]
    let isCurrent: Bool

    var body: some View {
        if !facts.isEmpty {
            InteractivePostCatalogWrappingLayout(spacing: 8) {
                ForEach(facts) { fact in
                    SpiralWrappingChip(wrappedCornerRadius: 16) { shape, cornerRadius in
                        // Wrapped, the symbol keeps to the first line.
                        HStack(alignment: cornerRadius == nil ? .center : .firstTextBaseline, spacing: 6) {
                            // As «Create an agent»: the accent icon read 3.6:1 (light) and 2.7:1 (dark) on this glass.
                            Image(systemSymbol: fact.symbol)
                                .font(.compound.bodySMSemibold)
                                .foregroundStyle(.compound.textLinkExternal)
                                .accessibilityHidden(true)
                            Text(fact.text)
                                .font(.compound.bodySMSemibold)
                                .foregroundStyle(.compound.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, cornerRadius == nil ? 0 : 6)
                        .frame(minHeight: 32)
                        .spiralGlass(in: shape)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.facts, isEnabled: isCurrent)
        }
    }
}

// MARK: - A finger on the post

/// While a finger is on the running post, the pans around it — the page's
/// swipe, its scroll, the stack's back — wait, so a stroke in a game or a
/// drawing stays the post's. It never cancels or delays a touch. Swipes and
/// scrolls still start anywhere else on the page.
private struct InteractivePostCatalogTouchGuard: UIViewRepresentable {
    func makeUIView(context: Context) -> GuardView {
        GuardView()
    }

    func updateUIView(_ uiView: GuardView, context: Context) { }

    /// Behind the post with its frame, taking no touches itself: its recogniser goes on the nearest scroll view,
    /// an ancestor of the web view, which is where a touch on the post is seen.
    final class GuardView: UIView, UIGestureRecognizerDelegate {
        private let recogniser = InteractivePostCatalogTouchHold()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            recogniser.delegate = self
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recogniser.view?.removeGestureRecognizer(recogniser)
            guard window != nil else { return }
            let ancestors = sequence(first: superview) { $0?.superview }.lazy.compactMap { $0 }
            (ancestors.first { $0 is UIScrollView } ?? superview)?.addGestureRecognizer(recogniser)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            bounds.contains(touch.location(in: self))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        /// Only pans on views that hold the post wait; WebKit's own recognisers sit below it.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard otherGestureRecognizer is UIPanGestureRecognizer, let otherView = otherGestureRecognizer.view else { return false }
            return isDescendant(of: otherView)
        }
    }
}

/// Recognises for as long as a finger is down, and never cancels, delays or prevents anything.
private final class InteractivePostCatalogTouchHold: UIGestureRecognizer {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .began : .changed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

// MARK: - Previews

struct InteractivePostCatalogPostScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    private static let fixture = InteractivePostCatalogPreviewFixture.self

    /// A square post with three facts: everything on the first screen (question 412).
    static let send = fixture.viewModel(page: "dice")
    static let longRoomName = fixture.viewModel(roomName: "Saturday football in the park, with the neighbours and their kids", page: "dice")
    static let noAgent = fixture.viewModel(assistant: .none, page: "dice")
    static let fillIn = fixture.viewModel(page: "invite")
    static let fillInNoAgent = fixture.viewModel(assistant: .none, page: "invite")
    static let fillInSettingUp = fixture.viewModel(assistant: .settingUp, page: "invite")
    static let fillInUnknown = fixture.viewModel(assistant: .unknown, page: "invite")
    /// Retry pressed: the agents are being read again.
    static let fillInReading = {
        let viewModel = fixture.viewModel(assistant: .unknown, page: "invite")
        viewModel.context.send(viewAction: .retryAgents)
        return viewModel
    }()

    static var previews: some View {
        screen(send, "Send")
        screen(longRoomName, "Send to a long room name")
        screen(noAgent, "Send, no agent")
        screen(fillIn, "Filled in with the agent")
        screen(fillInNoAgent, "Filled in, no agent")
        screen(fillInSettingUp, "Filled in, the agent setting up")
        screen(fillInUnknown, "Filled in, the agents unread")
        screen(fillInReading, "Filled in, the agents being read")
    }

    private static func screen(_ viewModel: InteractivePostCatalogScreenViewModel, _ name: String) -> some View {
        ElementNavigationStack {
            InteractivePostCatalogPostScreen(context: viewModel.context)
        }
        .previewDisplayName(name)
    }
}
