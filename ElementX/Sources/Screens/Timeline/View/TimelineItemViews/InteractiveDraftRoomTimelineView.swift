//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, step 6): a generated Interactive Post the
// owner has not published, as a row in their DM thread with the agent.
//
// Three things, in a bubble: a LIVE preview of the code (the same runtime
// the post will run in, on a preview session with nothing behind it — § 7.7
// exists for exactly this), the source to read, and "Send". Send
// posts `com.spiral.app` into THIS room as the owner; forwarding takes it
// anywhere else, which is the flow the operator chose (notebook § 5.35).
//
// The preview is not shared and not pooled: one host per draft row, built
// when the row appears and torn down when it goes. Drafts are few and live
// in one thread, so the pool's economy does not apply, and a preview that
// shared a host with a real post would be a post that could not run.
//

import Compound
import MatrixRustSDK
import SwiftUI

struct InteractiveDraftRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    @Environment(\.timelineRowContext) private var rowContext // AGENT-PLATFORM (Brief 0083, question 359)
    let timelineItem: InteractiveDraftRoomTimelineItem

    @StateObject private var preview = DraftPreview()
    /// Bumped when the full-screen viewer closes: the row's box adopts the
    /// container again. The viewer's box took it; the row's never left the
    /// window, so nothing else would ask (6.11 A1).
    @State private var reclaimCount = 0

    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            // A poll's layout: the content, then ONE primary action across
            // the bubble ("End poll"). The post is drawn by the very view
            // the room uses, so what the owner sees is what the room will
            // show after Publish. Everything else — the code, the version —
            // is secondary and lives in the item menu and under the bubble,
            // not beside the primary action (HIG: one primary per object).
            VStack(spacing: 8) {
                SpiralAppPostFrame(aspectRatio: timelineItem.draft.displayAspectRatio,
                                   isReady: preview.isReady,
                                   isLoading: preview.instance != nil && !preview.isReady,
                                   cardTitle: timelineItem.draft.title,
                                   cardSubtitle: UntranslatedL10n.screenRoomInteractiveDraftVersion(Int(timelineItem.draft.version)),
                                   accessibilityLabel: UntranslatedL10n.a11ySpiralAppPost(timelineItem.draft.title),
                                   isChatCard: true,
                                   onExpandedDismissed: {
                                       preview.setViewport(.row)
                                       reclaimCount += 1
                                   },
                                   expandRequests: preview.expandRequests) {
                    previewSurface { context?.send(viewAction: .displayTimelineItemMenu(itemID: timelineItem.id)) }
                } expanded: {
                    SpiralAppExpandedView(title: timelineItem.draft.title,
                                          author: SpiralAppViewerAuthor(timelineItem.sender),
                                          mediaProvider: context?.mediaProvider) {
                        previewSurface()
                            .onAppear { preview.setViewport(.expanded) }
                    }
                }

                publishButton
                    .padding(.horizontal, 8)
                    .padding(.bottom, rowContext.updatesLivePost ? 0 : 8)
                
                // A thread whose post is out there updates it; starting over
                // is the second choice, and says so (§ 5.55).
                if rowContext.updatesLivePost {
                    Button(UntranslatedL10n.screenRoomInteractivePostPublishNew) {
                        context?.send(viewAction: .publishInteractiveDraftAsNew(itemID: timelineItem.id))
                    }
                    .font(.compound.bodyMDSemibold)
                    .foregroundColor(.compound.textActionPrimary)
                    .disabled(timelineItem.draft.artifact == nil)
                    .padding(.bottom, 8)
                }
            }
        }
        // The version, as quiet text where reactions hang; a refused digest
        // says so here, in red.
        .environment(\.timelineItemAccessory, AnyView(versionLine))
        .onAppear { startPreview() }
        // A preview that failed to come up is tried again — a bounded number
        // of times, not for ever (§ 5.80).
        .onChange(of: preview.failures) { _, failures in
            if failures <= DraftPreview.retries { startPreview() }
        }
        .onDisappear { preview.stop() }
    }

    private func startPreview() {
        let draft = timelineItem.draft
        let resolver = context?.viewState.spiralMembersResolver
        // The people of the room this draft will actually land in: the live
        // post's, the catalogue's «here», or the one it was made for.
        let landsIn = context?.viewState.spiralUpdatableLivePost?.roomID
            ?? context?.viewState.spiralPublishRoom?.id
            ?? draft.targetRoomID
        preview.start(draft, viewerID: context?.viewState.ownUserID ?? "") {
            await resolver?(landsIn) ?? ["members": []]
        }
    }

    /// Send — the poll's "End poll": a capsule across the bubble. In a
    /// thread whose post is live, it updates that post instead.
    private var publishButton: some View {
        Button {
            context?.send(viewAction: .publishInteractiveDraft(itemID: timelineItem.id))
        } label: {
            Label(publishTitle, icon: \.send)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .font(.compound.bodyLGSemibold)
                .foregroundColor(.compound.textOnSolidPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background {
                    Capsule()
                        .foregroundColor(.compound.bgActionPrimaryRest)
                }
        }
        .disabled(timelineItem.draft.artifact == nil)
        .opacity(timelineItem.draft.artifact == nil ? 0.5 : 1)
        .accessibilityLabel(publishAccessibilityLabel)
    }

    /// «Update the post» in a live post's thread, else «Send», as short as the catalogue's (question 412, A1): the
    /// chat it goes to is VoiceOver's to say.
    private var publishTitle: String {
        rowContext.updatesLivePost ? UntranslatedL10n.screenRoomInteractivePostUpdate : L10n.actionSend
    }

    private var publishAccessibilityLabel: String {
        guard !rowContext.updatesLivePost, let publishRoomName = rowContext.publishRoomName else { return publishTitle }
        return UntranslatedL10n.a11yInteractivePostSendToChat(publishRoomName)
    }

    private var versionLine: some View {
        Text(timelineItem.draft.artifact == nil
            ? UntranslatedL10n.screenRoomInteractiveDraftBadDigest
            : UntranslatedL10n.screenRoomInteractiveDraftVersion(Int(timelineItem.draft.version)))
            .font(.compound.bodyXS)
            .foregroundColor(timelineItem.draft.artifact == nil ? .compound.textCriticalPrimary : .compound.textSecondary)
            .chatBackgroundChip() // AGENT-PLATFORM (Brief 0083, question 359): 2.49:1 in red and 3.91:1 in grey on the picture without it
            .padding(.top, 6)
    }

    /// `onLongPress` is the row's menu; nil in the full-screen viewer, which has none.
    @ViewBuilder
    private func previewSurface(onLongPress: (() -> Void)? = nil) -> some View {
        if let instance = preview.instance {
            DraftPreviewSurface(container: instance.containerView, reclaimCount: reclaimCount, onLongPress: onLongPress)
        } else {
            Color.clear
        }
    }
}

/// One live preview: a host of its own, a session with nothing behind it.
@MainActor
final class DraftPreview: ObservableObject {
    @Published private(set) var instance: SpiralAppInstance?
    @Published private(set) var isReady = false
    /// How many times this preview has failed to come up — a start that did
    /// not start, or a content process the system killed. The preview then
    /// lets go of the instance and counts, so a caller that still wants it can
    /// start it again, a bounded number of times (§ 5.80). It used to keep
    /// the dead instance, which made `start` a no-op: the card stayed a
    /// picture until the screen was left.
    @Published private(set) var failures = 0
    /// Bumped when the running app asks for the whole screen (`ui.expand`): whoever shows the preview opens its viewer.
    @Published private(set) var expandRequests = 0
    /// How many failures a caller should start again after.
    static let retries = 2
    /// A pool of one, so the preview's host is its own and goes with it.
    private let pool: SpiralAppHostPool
    private var running: Task<Void, Never>?

    init(makeHost: @escaping @MainActor () -> SpiralAppHostProtocol = { SpiralAppWebViewHost() }) {
        pool = SpiralAppHostPool(makeHost: makeHost)
    }

    func start(_ draft: SpiralAppDraft, viewerID: String, members: (() async -> [String: Any])? = nil) {
        guard let artifact = draft.artifact else { return }
        start(artifact, viewerID: viewerID, members: members)
    }

    /// The same preview over any verified artifact — the layout lab mounts
    /// the gallery and clipboard source through here.
    func start(_ artifact: SpiralAppArtifact, viewerID: String, members: (() async -> [String: Any])? = nil) {
        guard instance == nil else { return }

        let session = SpiralAppPreviewSession(userID: viewerID,
                                              loadMembers: members ?? { ["members": []] })
        let instance = SpiralAppInstance(session: session, pool: pool)
        self.instance = instance
        instance.onExpandRequested = { [weak self] in
            self?.expandRequests += 1
        }
        // The system reclaims web views nobody is looking at; a preview whose
        // process died is a blank box, not a preview.
        instance.onContentProcessDied = { [weak self, weak instance] in
            guard let instance else { return }
            MXLog.info("[SpiralApp] a preview lost its content process")
            self?.fail(instance)
        }

        running = Task { [weak self] in
            let started = await instance.start(artifact, instanceID: "draft-preview") == .started
            // A process that died during the start has already failed this instance.
            guard !Task.isCancelled, self?.instance === instance else { return }
            if started {
                self?.isReady = true
            } else {
                MXLog.error("[SpiralApp] the draft preview refused to start")
                self?.fail(instance)
            }
        }
    }

    /// Let go of an instance that will not show anything, so the next
    /// `start` builds a fresh one.
    private func fail(_ failed: SpiralAppInstance) {
        guard instance === failed else { return }
        instance = nil
        isReady = false
        failures += 1
        let pool = pool
        Task {
            await failed.discard()
            pool.drain()
        }
    }

    /// Tell the app where it is being shown (see `SpiralAppInstance.setViewport`).
    func setViewport(_ mode: SpiralAppViewportMode) {
        instance?.setViewport(mode)
    }

    func stop() {
        running?.cancel()
        let instance = instance
        let pool = pool
        self.instance = nil
        isReady = false
        Task {
            await instance?.stop()
            pool.drain()
        }
    }

    /// `stop`, and only return once the host is back in the pool — for a
    /// caller that mounts the next artifact straight after (the lab). A caller
    /// that is about to take the host again keeps it, shell warm.
    func stopAndWait(keepingHost: Bool = false) async {
        running?.cancel()
        let instance = instance
        self.instance = nil
        isReady = false
        await instance?.stop()
        if !keepingHost {
            pool.drain()
        }
    }

    /// Destroy the host a `stopAndWait(keepingHost: true)` kept, for a caller
    /// that found it has no next artifact after all.
    func dropKeptHost() {
        pool.drain()
    }

    /// A picture of what the app shows now, nil when there is nothing to take.
    func takeSnapshot() async -> UIImage? {
        guard let instance else { return nil }
        return await withCheckedContinuation { continuation in
            instance.takeSnapshot { continuation.resume(returning: $0) }
        }
    }
}

struct DraftPreviewSurface: UIViewRepresentable {
    let container: UIView
    var reclaimCount = 0
    var onLongPress: (() -> Void)?

    func makeUIView(context: Context) -> DraftPreviewBox {
        let box = DraftPreviewBox()
        box.backgroundColor = .clear
        box.container = container
        box.onLongPress = onLongPress
        return box
    }

    func updateUIView(_ uiView: DraftPreviewBox, context: Context) {
        uiView.container = container
        uiView.onLongPress = onLongPress
        if context.coordinator.reclaimCount != reclaimCount {
            context.coordinator.reclaimCount = reclaimCount
            uiView.reclaim()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var reclaimCount = 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DraftPreviewBox, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

/// The view that shows the preview's container — and takes it only once it
/// is itself in a window.
///
/// The timeline sizes a row in a hosting view that is never on screen, so
/// `makeUIView` runs TWICE per row and the second, invisible box would take
/// the container from the first: the app then mounted into a detached view,
/// the host's wait-for-window gave up, and the card stayed blank until the
/// room was re-entered (2026-09-17, the first two drafts). Adopting on
/// `didMoveToWindow` puts it in the box the reader is looking at, whichever
/// order the boxes were made in, and a recycled cell takes it the same way.
final class DraftPreviewBox: UIView {
    var container: UIView? {
        didSet {
            guard container !== oldValue else { return }
            if window != nil { adopt() }
        }
    }

    /// A held finger on the preview opens the row's menu, as on a post (§ 5.66): the web view takes every touch, and
    /// the strip under the draft that used to answer is gone. Beside WebKit's recognisers, never instead of them.
    var onLongPress: (() -> Void)? {
        didSet {
            guard onLongPress != nil, longPress == nil else { return }
            let recogniser = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
            recogniser.minimumPressDuration = 0.5
            recogniser.allowableMovement = 10
            recogniser.cancelsTouchesInView = false
            recogniser.delegate = self
            addGestureRecognizer(recogniser)
            longPress = recogniser
        }
    }

    private var longPress: UILongPressGestureRecognizer?

    @objc private func handleLongPress(_ recogniser: UILongPressGestureRecognizer) {
        guard recogniser.state == .began else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onLongPress?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { adopt() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        container?.frame = bounds
    }

    /// Take the container back while in a window (the full-screen viewer had it).
    func reclaim() {
        if window != nil { adopt() }
    }

    private func adopt() {
        guard let container, container.superview !== self else { return }
        container.removeFromSuperview()
        container.translatesAutoresizingMaskIntoConstraints = true
        container.frame = bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(container)
    }
}

extension DraftPreviewBox: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
