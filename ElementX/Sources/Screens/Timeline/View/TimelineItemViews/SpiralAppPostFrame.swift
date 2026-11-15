//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066): the ONE way an Interactive Post is drawn —
// in a room, and as a draft's preview in the studio thread.
//
// The frame is decided from `aspect` before anything loads, capped like a
// media row; the app's surface sits in it; the quiet card covers it until
// the app has drawn; a small control opens the same running app in a
// sheet over the chat. A draft's preview goes through exactly this, so what
// the owner sees before Publish is what the room sees after — same box,
// same cap, same card, same expand.
//

import Compound
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

struct SpiralAppPostFrame<Surface: View, Expanded: View>: View {
    /// Width : height, from the manifest.
    let aspectRatio: CGFloat
    /// Whether the app has drawn; until then the card covers the surface.
    let isReady: Bool
    /// Whether it is on its way (the card shows a spinner after a moment).
    let isLoading: Bool
    /// What the card says: the newest summary line, or the title.
    let cardTitle: String
    /// The line under it: the body, or "not running".
    let cardSubtitle: String
    /// The moment the post's newest summary counts down to (§ 5.79): the
    /// card counts down to it by itself, and stops saying it once it passes.
    var cardCountdown: Date?
    let accessibilityLabel: String
    /// The app as it last looked: stands in for it, in place of the card.
    var standIn: UIImage?
    /// A draft waits as a card of the chat's, on its bubble. A post keeps its own quiet card (question 359).
    var isChatCard = false
    /// Called as the viewer is asked for, before it shows.
    var onExpanded: () -> Void = { }
    /// Called as the viewer starts to close, so the row can take
    /// its app back while the viewer slides away.
    var onExpandedClosing: () -> Void = { }
    /// Called when the viewer has closed, so a row can reclaim.
    var onExpandedDismissed: () -> Void = { }
    /// Bumped by whoever is listening when the app itself asks for the whole
    /// screen (`ui.expand`). Any value; only the change matters.
    var expandRequests = 0
    @ViewBuilder let surface: () -> Surface
    /// The same app, in the viewer sheet.
    @ViewBuilder let expanded: () -> Expanded

    /// Upper bound on a post's height, matching the one media rows use.
    ///
    /// A post is a message in a conversation, not a page: a 9:16 artifact
    /// that took the whole screen would turn scrolling past it into work.
    static var maxHeight: CGFloat {
        300
    }

    /// How long a post may take to start before the row admits it is working.
    private var beforeSayingItIsWorking: Duration {
        .milliseconds(300)
    }

    @State private var showsProgress = false
    @State private var showsViewer = false

    var body: some View {
        sizedContent
            // Width first: a post takes the bubble's width and its height
            // follows from `aspect` — a square post is as wide as a text
            // bubble, not narrower (operator, 2026-09-17). The 300-point cap
            // applies only to TALL shapes (3:4, 9:16), where height-first is
            // what keeps a post from being a page.
            .frame(maxHeight: aspectRatio < 1 ? Self.maxHeight : .infinity)
            // The post's surface, drawn NATIVELY and identically whether an
            // app is running or not — so starting one changes what is on
            // the row, never the shape of the row.
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background(surfaceColor)
            .spiralAppViewer(isPresented: $showsViewer,
                             isReady: isReady,
                             expandRequests: expandRequests,
                             onExpanded: onExpanded,
                             onClosing: onExpandedClosing,
                             onDismissed: onExpandedDismissed,
                             viewer: expanded)
    }

    /// The post in the shape the row decided, before anything loaded.
    ///
    /// `Color.clear` has NO ideal size, so it takes whatever shape it is
    /// offered — which is what makes the height come from `aspect` rather
    /// than from whatever happens to be drawn. The ratio is applied twice,
    /// once here and once outside `maxHeight`, copying `timelineMediaFrame`.
    private var sizedContent: some View {
        ZStack {
            Color.clear
            content
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private var content: some View {
        ZStack {
            surface()

            // The way out of the box: the app at the size of the screen.
            if isReady {
                SpiralAppExpandButton { showsViewer = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            // COVERS the app rather than replacing it. The web view has to be
            // in the hierarchy to paint at all, so it goes in early and waits
            // behind this until it has something to show.
            //
            // Fades out and never in. A cover going on means the app has gone
            // from under it, and a fade would show the empty row meanwhile.
            if !isReady {
                cover
                    .background(surfaceColor)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isReady)
    }

    private var surfaceColor: Color {
        isChatCard ? .clear : .compound.bgSubtleSecondary
    }
    
    @ViewBuilder
    private var cover: some View {
        if let standIn {
            picture(standIn)
        } else {
            placeholder
        }
    }

    /// Fills the shape the row decided and takes no part in deciding it: an
    /// overlay on `Color.clear` has no say in the row's height.
    private func picture(_ image: UIImage) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .overlay(alignment: .bottom) {
                progress
            }
            .workingAfterAMoment(isLoading: isLoading, showsProgress: $showsProgress, delay: beforeSayingItIsWorking)
    }

    @ViewBuilder
    private var progress: some View {
        if showsProgress {
            ProgressView()
                .padding(16)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if isChatCard {
            ChatCardRow(icon: \.extensions, title: cardTitle) {
                Text(cardSubtitle)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
            .padding(.top, 8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 8) {
            CompoundIcon(\.extensions, size: .medium, relativeTo: .compound.bodyMDSemibold)
                .foregroundStyle(.compound.iconSecondary)

            Text(cardTitle)
                .font(.compound.bodyMDSemibold)
                .foregroundStyle(.compound.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if let cardCountdown {
                // A new moment is a new countdown, with nothing carried over.
                SpiralAppCardCountdown(moment: cardCountdown)
                    .id(cardCountdown)
            }

            Text(cardSubtitle)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            progress
        }
        .workingAfterAMoment(isLoading: isLoading, showsProgress: $showsProgress, delay: beforeSayingItIsWorking)
    }
}

private extension View {
    /// Only once it has taken long enough to be worth saying. On a warm cache
    /// the whole start is about 50ms, and a spinner shown for 50ms is not
    /// information, it is a flicker.
    func workingAfterAMoment(isLoading: Bool, showsProgress: Binding<Bool>, delay: Duration) -> some View {
        task(id: isLoading) {
            showsProgress.wrappedValue = false
            guard isLoading else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            showsProgress.wrappedValue = true
        }
    }
}

// MARK: - The viewer's way in

extension View {
    /// A post's viewer, a system sheet over whatever shows the post (question 412): opened by the post's expand disc,
    /// or by the post itself (`ui.expand`) once it has drawn. The one way in for a room's post, a draft, and a
    /// catalogue post tried on its page. Swiping the viewer down is its way out, as on every sheet.
    func spiralAppViewer<Viewer: View>(isPresented: Binding<Bool>,
                                       isReady: Bool,
                                       expandRequests: Int,
                                       onExpanded: @escaping () -> Void = { },
                                       onClosing: @escaping () -> Void = { },
                                       onDismissed: @escaping () -> Void = { },
                                       @ViewBuilder viewer: @escaping () -> Viewer) -> some View {
        modifier(SpiralAppViewerPresenter(isPresented: isPresented,
                                          isReady: isReady,
                                          expandRequests: expandRequests,
                                          onExpanded: onExpanded,
                                          onClosing: onClosing,
                                          onDismissed: onDismissed,
                                          viewer: viewer))
    }
}

private struct SpiralAppViewerPresenter<Viewer: View>: ViewModifier {
    @Binding var isPresented: Bool
    let isReady: Bool
    /// Bumped when the app asks for the whole screen. Any value; only the change matters.
    let expandRequests: Int
    /// Called as the viewer is asked for, before it shows.
    let onExpanded: () -> Void
    /// Called as the viewer starts to close, so the post's box can take its app back while the viewer slides away.
    let onClosing: () -> Void
    /// Called when the viewer has closed.
    let onDismissed: () -> Void
    @ViewBuilder let viewer: () -> Viewer

    /// Whether this viewer's closing was told. A swipe calls `onDismiss` as the dismissal commits, BEFORE the flag
    /// clears (measured on Stage-A), and the box must still hear "closing" first.
    @State private var hasReportedClosing = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: viewerDidDismiss) {
                viewer()
            }
            // AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): a post played full screen is above the call
            // screen: it closes as a call comes up, by the swipe's own path, unanimated so a ring can present.
            .onReceive(NotificationCenter.default.publisher(for: .callScreenWillCoverTheApp)) { _ in
                guard isPresented else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isPresented = false }
            }
            .onChange(of: isPresented) { _, isShown in
                SpiralAppReturnTrace.note("viewer \(isShown ? "asked for (expand)" : "flag cleared (dismiss started)") — isReady=\(isReady)")
                if isShown {
                    hasReportedClosing = false
                    onExpanded()
                } else {
                    reportClosing()
                }
            }
            // The app asking, rather than the reader. Ignored until it has
            // drawn: a card that grows to full screen before there is
            // anything in it is a black rectangle.
            .onChange(of: expandRequests) { _, _ in
                guard isReady else { return }
                isPresented = true
            }
    }

    private func reportClosing() {
        guard !hasReportedClosing else { return }
        hasReportedClosing = true
        onClosing()
    }

    private func viewerDidDismiss() {
        reportClosing()
        onDismissed()
    }
}

/// The disc in a post's top corner that opens its viewer. It sits on whatever the app drew. On iOS 26 it is Liquid
/// Glass (operator, question 412): the glass and its glyph turn light or dark with the app behind them. Before 26 it
/// brings its own opaque disc and outline: a material over an app's colours read as a grey circle with no glyph
/// (question 343). The disc is 32 pt, inset 6 pt in a 44 pt target.
struct SpiralAppExpandButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .padding(6)
                .contentShape(.rect)
        }
        .accessibilityLabel(UntranslatedL10n.spiralAppOpenFullScreen)
    }

    @ViewBuilder
    private var glyph: some View {
        let glyph = CompoundIcon(\.expand, size: .xSmall, relativeTo: .compound.bodySM)
            .frame(width: 32, height: 32)
        if #available(iOS 26, *), !ProcessInfo.isRunningUnitTests {
            glyph
                .foregroundStyle(.primary)
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            glyph
                .foregroundStyle(.compound.iconPrimary)
                .background(.compound.bgCanvasDefault, in: Circle())
                .overlay {
                    Circle().stroke(.compound.borderInteractiveSecondary)
                }
        }
    }
}

/// «Try it — nothing is sent» (question 412): over a post tried before it is sent, on the catalogue's page and in its
/// viewer. A chip of the chat's on the room's background, else a quiet capsule.
struct SpiralAppTryBanner: View {
    @Environment(\.isChatBackgroundDrawn) private var isChatBackgroundDrawn
    /// Half the text's x-height: how far the baseline lies under the middle of a lower-case letter.
    @ScaledMetric(relativeTo: .footnote) private var dotDrop: CGFloat = 3.5

    var body: some View {
        // One line in a capsule; at AX sizes on a narrow phone the words wrap inside the width (question 412).
        // Wrapped, the dot keeps to the first line.
        SpiralWrappingChip(wrappedCornerRadius: 14) { shape, cornerRadius in
            HStack(alignment: cornerRadius == nil ? .center : .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(.compound.iconSuccessPrimary)
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dotDrop }
                Text(UntranslatedL10n.screenInteractiveCatalogPreviewTry)
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isChatBackgroundDrawn ? Color.spiral.chatBackgroundSurface : Color.compound.bgSubtleSecondary, in: shape)
            .chatElevation(cornerRadius: cornerRadius)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SpiralAppPostFrame_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    /// What an app left behind, drawn for the preview: any picture will do.
    private static var picture: UIImage? {
        let renderer = ImageRenderer(content: VStack(spacing: 12) {
            CompoundIcon(\.chart, size: .medium, relativeTo: .compound.headingMD)
            Text("3 of 5 have voted")
                .font(.compound.headingMD)
        }
        .foregroundStyle(.compound.textOnSolidPrimary)
        .frame(width: 300, height: 225)
        .background(.compound.bgAccentHovered))
        renderer.scale = 2
        return renderer.uiImage
    }

    static var previews: some View {
        VStack(spacing: 16) {
            frame(standIn: nil, isLoading: false)
            frame(standIn: picture, isLoading: false)
        }
        .padding(16)
        .previewDisplayName("Never seen, and away")
    }

    private static func frame(standIn: UIImage?, isLoading: Bool) -> some View {
        SpiralAppPostFrame(aspectRatio: 4 / 3,
                           isReady: false,
                           isLoading: isLoading,
                           cardTitle: "Where do we eat?",
                           cardSubtitle: "Interactive",
                           accessibilityLabel: "Where do we eat?",
                           standIn: standIn) {
            Color.clear
        } expanded: {
            EmptyView()
        }
    }
}

/// A card's countdown (§ 5.79): `Text(_:style: .relative)` ticks by itself
/// and is localised by the system; the view takes itself away when the
/// moment comes, since a post whose event has happened says nothing about a
/// countdown.
///
/// Not a `TimelineView(.explicit([moment]))`: its first render is dated at
/// the schedule's first entry even when that is in the future (measured), so
/// a countdown gated on `context.date < moment` never showed at all.
struct SpiralAppCardCountdown: View {
    let moment: Date
    @State private var hasPassed = false

    var body: some View {
        if !hasPassed, moment > .now {
            Label {
                Text(moment, style: .relative)
                    .monospacedDigit()
            } icon: {
                CompoundIcon(\.time, size: .xSmall, relativeTo: .compound.bodySMSemibold)
            }
            .font(.compound.bodySMSemibold)
            .foregroundStyle(.compound.textPrimary)
            .task {
                try? await Task.sleep(for: .seconds(moment.timeIntervalSinceNow))
                guard !Task.isCancelled else { return }
                hasPassed = true
            }
        }
    }
}

/// Who sent the post a viewer shows: what its header needs, nothing more.
struct SpiralAppViewerAuthor: Equatable {
    let id: String
    let displayName: String
    let avatarURL: URL?

    init(id: String, displayName: String, avatarURL: URL?) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    init(_ sender: TimelineItemSender) {
        self.init(id: sender.id,
                  displayName: sender.disambiguatedDisplayName ?? sender.id,
                  avatarURL: sender.avatarURL)
    }
}

/// The words of the viewer's chrome (M2): a post somebody sent is named by them, never by itself, and a line
/// under it warns never to type a password there; the header already says whose code it is (question 412).
/// Our own catalogue's templates keep their title and have no line; tried from their page, they keep the page's banner.
struct SpiralAppViewerChrome: Equatable {
    let title: String
    let subtitle: String?
    let safetyLine: String?
    /// A template tried before it is sent, from the catalogue's page: the page's «nothing is sent» stays under it.
    let isRehearsal: Bool

    init(title: String, author: SpiralAppViewerAuthor?, isRehearsal: Bool = false) {
        if let author {
            self.title = author.displayName
            subtitle = UntranslatedL10n.spiralAppViewerSubtitle
            safetyLine = UntranslatedL10n.spiralAppViewerBanner
            self.isRehearsal = false
        } else {
            self.title = title
            subtitle = nil
            safetyLine = nil
            self.isRehearsal = isRehearsal
        }
    }
}

/// The viewer of a post, a system sheet over the chat (question 412, concept C): the author and a glass ✕ in the
/// sheet's own header, the post in the whole area between it and a quiet safety line, which stays while the post
/// is open (M2) — a post that draws a sign-in page in here is still plainly a post from them.
struct SpiralAppExpandedView<Surface: View>: View {
    let chrome: SpiralAppViewerChrome
    var author: SpiralAppViewerAuthor?
    var mediaProvider: MediaProviderProtocol?
    @ViewBuilder let surface: () -> Surface

    @Environment(\.dismiss) private var dismiss

    /// The board's 34 pt: a little larger than a timeline sender's, beside a two-line name.
    private var avatarSize: CGFloat {
        34
    }

    init(title: String,
         author: SpiralAppViewerAuthor? = nil,
         isRehearsal: Bool = false,
         mediaProvider: MediaProviderProtocol? = nil,
         @ViewBuilder surface: @escaping () -> Surface) {
        chrome = SpiralAppViewerChrome(title: title, author: author, isRehearsal: isRehearsal)
        self.author = author
        self.mediaProvider = mediaProvider
        self.surface = surface
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                // The whole area, not the row's aspect: the app is written to fill 100% × 100% and this is where
                // that pays.
                surface()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.compound.bgSubtleSecondary)
                    .background(SpiralAppViewerStrokeGuard())
            }
            if let safetyLine = chrome.safetyLine {
                footer(safetyLine)
            } else if chrome.isRehearsal {
                SpiralAppTryBanner()
                    // The footer's margins: wrapped at AX3–AX5 on a 375 pt phone it ran edge to edge (DEBT § 412 catalogue tails).
                    .padding(.horizontal, CompoundDesignTokens.space4X)
                    .padding(.vertical, CompoundDesignTokens.space2X)
            }
        }
        // A sheet of its own, which draws no room background: what is drawn here keeps to the plain canvas.
        .environment(\.isChatBackgroundDrawn, false)
        // The app stops ABOVE the home indicator: the frame is what the app is told it has, so it may not include
        // room the reader cannot see. Ignoring the bottom safe area once cost the last line of every post (the
        // final line of a drawing post sat inside the indicator's 34 points, 2026-09-21).
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            if let author {
                LoadableAvatarImage(url: author.avatarURL,
                                    name: author.displayName,
                                    contentID: author.id,
                                    avatarSize: .custom(avatarSize),
                                    mediaProvider: mediaProvider)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(chrome.title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = chrome.subtitle {
                    Text(subtitle)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            NativeCallSheetRoundButton(systemImage: "xmark", label: L10n.actionClose) {
                SpiralAppReturnTrace.note("viewer ✕ tapped — dismiss starts")
                dismiss()
            }
        }
        .padding(.leading, CompoundDesignTokens.space4X)
        .padding(.trailing, CompoundDesignTokens.space2X)
        // Below the drag indicator, as the other sheets' headers sit.
        .padding(.top, CompoundDesignTokens.space5X)
        .padding(.bottom, CompoundDesignTokens.space2X)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func footer(_ line: String) -> some View {
        Label {
            Text(line)
        } icon: {
            CompoundIcon(\.shield, size: .xSmall, relativeTo: .compound.bodyXS)
        }
        .font(.compound.bodyXS)
        .foregroundStyle(.compound.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space2X)
        .accessibilityElement(children: .combine)
    }
}

/// Keeps the sheet in place while a finger draws in the post (question 412).
///
/// Drawing and board posts take every stroke (`touch-action: none`), and a downward one inside the post dragged the
/// whole sheet away (measured on Stage-A; `presentationContentInteraction(.scrolls)` changed nothing, the web view
/// does not scroll). The sheet's own pan waits for this recogniser to fail, which it never does for a touch that lands
/// on the post, so the system's swipe still works from the header, the drag indicator and the safety line. Nothing
/// here moves the sheet: it is the system's dismissal, only not from inside the post.
private struct SpiralAppViewerStrokeGuard: UIViewRepresentable {
    func makeUIView(context: Context) -> GuardView {
        GuardView()
    }

    func updateUIView(_ uiView: GuardView, context: Context) { }

    /// Sits behind the post with its frame, and takes no touches itself: its recogniser goes on an ancestor of the web
    /// view, which is where a touch on the post is seen.
    final class GuardView: UIView, UIGestureRecognizerDelegate {
        private let recogniser = SpiralAppTouchHold()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            recogniser.delegate = self
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// On the sheet's hosting view, the parent of every view the post is drawn in. The sheet's pan sits above it,
        /// on the presentation's shadow view; below it, each representable has its own one-child wrapper, so the
        /// first ancestor with more than one child is the one (measured on iOS 27: `UIKitPlatformViewHost >
        /// HostingView > _UIDropShadowClippingView > UIDropShadowView[UIPanGestureRecognizer]`).
        override func didMoveToWindow() {
            super.didMoveToWindow()
            recogniser.view?.removeGestureRecognizer(recogniser)
            guard window != nil else { return }
            let host = sequence(first: superview) { $0?.superview }
                .lazy
                .compactMap { $0 }
                .first { $0.subviews.count > 1 }
            host?.addGestureRecognizer(recogniser)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            bounds.contains(touch.location(in: self))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        /// Only the sheet's pan waits: it sits above the sheet's content, where WebKit's recognisers sit below.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard otherGestureRecognizer is UIPanGestureRecognizer,
                  let ownView = gestureRecognizer.view,
                  let otherView = otherGestureRecognizer.view,
                  otherView !== ownView else { return false }
            return ownView.isDescendant(of: otherView)
        }
    }
}

/// Recognises for as long as a finger is down, and never cancels, delays or prevents anything.
private final class SpiralAppTouchHold: UIGestureRecognizer {
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
