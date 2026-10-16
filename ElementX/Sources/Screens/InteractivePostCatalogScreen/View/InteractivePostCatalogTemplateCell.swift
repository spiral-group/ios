//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (§ 5.61, § 5.63, § 5.80): a catalogue card IS the template,
// running.
//
// Not a picture of it. A picture is one language and one roster, and a
// catalogue of twelve would need thirty-six of them; the template itself,
// in the row's box, speaks the viewer's language and shows the people of
// the room it would go to, and the wheel spins right here. Its state is a
// rehearsal in memory (`SpiralAppPreviewSession`); nothing leaves the phone.
//
// Each running template is a WebContent process (§ 5.25), so only the card
// the carousel rests on and its two neighbours run; every other card shows
// its quiet face and holds nothing (§ 5.80).
//

import Compound
import SwiftUI

struct InteractivePostCatalogTemplateCell: View {
    let template: SpiralAppTemplate
    /// The template packed as the room would receive it; nil while loading.
    let artifact: SpiralAppArtifact?
    let viewerID: String
    let loadMembers: @MainActor () async -> [String: Any]
    /// How many cards away from the one the carousel rests on: 0 is the one
    /// shown, 1 a neighbour at the edge, more is out of sight.
    let distance: Int

    @StateObject private var live = DraftPreview()
    @State private var reclaimCount = 0
    @State private var isOnScreen = false

    /// The row's width in a conversation on this phone (§ 5.45); the card is
    /// square so every shape rests in the same box and the carousel does not
    /// change height as it turns.
    static let side: CGFloat = 322

    /// The card shown and its neighbours run; the rest do not.
    ///
    /// It used to be a budget of three taken first-come: `LazyHStack` builds
    /// cards ahead of the scroll and `onAppear` fires for them off screen, so
    /// the three slots went to whichever cards were BUILT first — a card out
    /// of sight held one for six minutes while the card in the middle stayed
    /// a picture (sim, 2026-09-30). Where a card stands is the only fair
    /// question, so it is the one asked.
    static let liveReach = 1

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            frame
            Spacer(minLength: 0)
        }
        .frame(width: Self.side, height: Self.side)
        .background(Color.compound.bgCanvasDefault)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { isOnScreen = true }
        .onDisappear {
            isOnScreen = false
            stop()
        }
        // Started after a pause, so a card the carousel only passes on its way
        // does not start at all; stopped at once when it is no longer wanted.
        // A failure changes the key, and a card still wanted tries again.
        .task(id: RunKey(wanted: wanted, delay: startDelay, failures: live.failures)) {
            guard wanted else {
                stop()
                return
            }
            try? await Task.sleep(for: startDelay)
            guard !Task.isCancelled, let artifact, live.instance == nil else { return }
            MXLog.info("[SpiralApp] catalogue: start \(template.id) (\(distance == 0 ? "shown" : "neighbour"))")
            live.start(artifact, viewerID: viewerID, members: loadMembers)
        }
    }

    // MARK: - Private

    private struct RunKey: Equatable {
        let wanted: Bool
        let delay: Duration
        let failures: Int
    }

    private var wanted: Bool {
        isOnScreen && distance <= Self.liveReach && artifact != nil && live.failures <= DraftPreview.retries
    }

    /// The card in the middle first; its neighbours once the carousel has
    /// plainly stopped there.
    private var startDelay: Duration {
        distance == 0 ? .milliseconds(100) : .milliseconds(300)
    }

    private var frame: some View {
        SpiralAppPostFrame(aspectRatio: template.displayAspectRatio,
                           isReady: live.isReady,
                           isLoading: artifact == nil || (live.instance != nil && !live.isReady),
                           cardTitle: template.localizedTitle,
                           cardSubtitle: template.localizedDescription,
                           accessibilityLabel: UntranslatedL10n.a11ySpiralAppPost(template.localizedTitle),
                           onExpandedDismissed: {
                               live.setViewport(.row)
                               reclaimCount += 1
                           }) {
            surface
        } expanded: {
            SpiralAppExpandedView(title: template.localizedTitle) {
                surface
                    .onAppear { live.setViewport(.expanded) }
            }
        }
    }

    @ViewBuilder
    private var surface: some View {
        if let instance = live.instance {
            DraftPreviewSurface(container: instance.containerView, reclaimCount: reclaimCount)
        } else {
            Color.clear
        }
    }

    private func stop() {
        guard live.instance != nil else { return }
        MXLog.info("[SpiralApp] catalogue: stop \(template.id)")
        live.stop()
    }
}

extension SpiralAppTemplate {
    /// `aspect` as a ratio, clamped as a post's row clamps it.
    var displayAspectRatio: CGFloat {
        let parts = aspect.split(separator: ":")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else {
            return 4 / 3
        }
        return min(max(CGFloat(w / h), SpiralAppPost.narrowestAspectRatio), SpiralAppPost.widestAspectRatio)
    }
}
