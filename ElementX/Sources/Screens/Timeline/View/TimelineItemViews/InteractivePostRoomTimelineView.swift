//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.5): where an Interactive Post is
// drawn.
//
// The row is sized from the event's `aspect` BEFORE anything loads, the way
// `timelineMediaFrame` sizes an image from its declared dimensions. A row
// that grew when the app finished starting would shove the conversation
// around under the reader's thumb — and in a flipped table that means the
// message they were reading walks off the screen.
//
// The card below is what the post looks like when nothing is running: its
// title, or the newest action's summary once there is one. Step 7.3 puts a
// live web view inside this same frame; the frame is deliberately decided
// here, once, so the two can never disagree about the row's height.
//

import Compound
import MatrixRustSDK
import SwiftUI

struct InteractivePostRoomTimelineView: View {
    @Environment(\.timelineContext) private var context
    /// Set from "hide media in the timeline". A post is not a picture, but it
    /// IS somebody else's code fetched over the network and run without being
    /// asked for — so the reader who turned media off meant this too, more than
    /// they meant photographs.
    @Environment(\.shouldAutomaticallyLoadImages) private var mayRunAutomatically
    let timelineItem: InteractivePostRoomTimelineItem
    /// What tells this row an app has started. The registry mounts long after
    /// the row is first drawn, so without something observable the row would
    /// keep its quiet card for ever.
    @ObservedObject var slot: SpiralAppSlot

    /// Bumped when the full-screen viewer closes, so the row's surface asks
    /// for the container back (`SpiralAppSurface.reclaim`).
    @State private var reclaimCount = 0

    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            // Corners are the styler's, as they are for a photo.
            //
            // No `onAppear`/`onDisappear` here, on purpose. Visibility is
            // reported by the surface below from `didMoveToWindow` — a
            // UIKit fact — because SwiftUI's hints drifted from the screen
            // and cost two days of blank rows (§5.28, §5.30).
            SpiralAppPostFrame(aspectRatio: timelineItem.post.displayAspectRatio,
                               isReady: slot.phase == .ready,
                               isLoading: slot.phase == .loading,
                               cardTitle: slot.summaryLine ?? timelineItem.body,
                               // Named so a reader can tell "this app has not
                               // started" from "this app has nothing to say" —
                               // or from "this app needs a newer app" (§ 5.70).
                               cardSubtitle: !timelineItem.post.isRuntimeSupported || slot.needsNewerApp ? UntranslatedL10n.spiralAppNeedsUpdate
                                   : slot.couldNotStart ? L10n.errorUnknown
                                   : slot.summaryLine == nil ? UntranslatedL10n.spiralAppNotRunning
                                   : Self.lineAttribution(writer: slot.summaryWriter, author: timelineItem.sender.id) ?? timelineItem.body,
                               cardCountdown: slot.summaryCountdown,
                               accessibilityLabel: accessibilityLabel,
                               // A reader who hid media hid this too.
                               standIn: mayRunAutomatically ? slot.standIn : nil,
                               onExpandedClosing: {
                                   if let eventID = timelineItem.id.eventID {
                                       registry?.viewerWillClose(eventID: eventID)
                                   }
                               },
                               onExpandedDismissed: {
                                   reclaimCount += 1
                                   // Re-opening needs a new touch, not one
                                   // from inside the viewer just closed.
                                   if let eventID = timelineItem.id.eventID {
                                       registry?.viewerDismissed(eventID: eventID)
                                   }
                               },
                               expandRequests: slot.expandRequests) {
                // Always here, app or not: this is the row's surface, and its
                // presence in a window is what tells the registry the post is
                // on screen. The registry puts the app's container inside it.
                //
                // No accessibility modifiers here on purpose: the row is
                // already a CONTAINER, and anything added here would collapse
                // the app's controls back into a single element.
                // A post from a runtime this build does not carry keeps its
                // card and never mounts: no surface, no registry, no boot.
                if timelineItem.post.isRuntimeSupported {
                    SpiralAppSurfaceView(eventID: timelineItem.id.eventID,
                                         post: timelineItem.post,
                                         registry: registry,
                                         mayRunAutomatically: mayRunAutomatically,
                                         reclaimCount: reclaimCount,
                                         onLongPress: { context?.send(viewAction: .displayTimelineItemMenu(itemID: timelineItem.id)) })
                } else {
                    Color.clear
                }
            } expanded: {
                SpiralAppExpandedView(title: timelineItem.body,
                                      author: SpiralAppViewerAuthor(timelineItem.sender),
                                      mediaProvider: context?.mediaProvider) {
                    SpiralAppSurfaceView(eventID: timelineItem.id.eventID,
                                         post: timelineItem.post,
                                         registry: registry,
                                         mayRunAutomatically: true,
                                         viewportMode: .expanded)
                }
            }
        }
    }

    private var registry: SpiralAppHostRegistry? {
        context?.viewState.spiralAppHosts
    }

    /// «From X» when the card's line is not the author's (L1): any
    /// member's action can write it, and the card is the post's face.
    static func lineAttribution(writer: (id: String, name: String)?, author: String) -> String? {
        guard let writer, writer.id != author else { return nil }
        return UntranslatedL10n.spiralAppCardLineBy(writer.name)
    }

    /// What the post is, then what it says.
    ///
    /// Named as interactive first, the way a sticker row names itself before
    /// its body: "Interactive" is the part a reader cannot see. The line an app
    /// published is preferred over the title because it is the newer truth, and
    /// it is exactly what `summary.line` exists to be read as.
    private var accessibilityLabel: String {
        let line = slot.summaryLine ?? timelineItem.body
        // The countdown the card shows, as words — «in 3 days» — while it
        // still counts (§ 5.79).
        guard let moment = slot.summaryCountdown, moment > .now else {
            return UntranslatedL10n.a11ySpiralAppPost(line)
        }
        let relative = RelativeDateTimeFormatter().localizedString(for: moment, relativeTo: .now)
        return UntranslatedL10n.a11ySpiralAppPost("\(line), \(relative)")
    }
}

struct InteractivePostRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock

    static var previews: some View {
        VStack(spacing: 20) {
            InteractivePostRoomTimelineView(timelineItem: makeItem(title: "Куди їдемо?", aspect: "4:3"),
                                            slot: SpiralAppSlot())
            InteractivePostRoomTimelineView(timelineItem: makeItem(title: "Split the bill", aspect: "1:1"),
                                            slot: SpiralAppSlot())
            InteractivePostRoomTimelineView(timelineItem: makeItem(title: "A checklist with a title long enough to wrap onto more than one line",
                                                                   aspect: "16:9"),
                                            slot: SpiralAppSlot())
        }
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
    }

    private static func makeItem(title: String, aspect: String) -> InteractivePostRoomTimelineItem {
        InteractivePostRoomTimelineItem(id: .randomEvent,
                                        body: title,
                                        timestamp: .mock,
                                        isOutgoing: false,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: "@a:spiral.md"),
                                        post: SpiralAppPost(InteractivePostContent(body: title,
                                                                                   appId: "poll",
                                                                                   runtime: "1",
                                                                                   title: title,
                                                                                   aspect: aspect,
                                                                                   stateChannel: "matrix",
                                                                                   sha256: String(repeating: "a", count: 64),
                                                                                   url: "mxc://spiral.md/abc",
                                                                                   fileJson: nil)))
    }
}

/// Lends the registry's host view to whichever row is currently on screen.
///
/// `makeUIView` is documented to CREATE the view it returns, and is called once
/// per representable. This one honours that: it returns a fresh, empty box each
/// time and lends the shared host into it. Returning the shared host itself —
/// which this did until it was measured — tells SwiftUI it owns something that
/// three rows are using, and SwiftUI then takes it away from the row that is on
/// screen to tidy up a row that is not.
///
/// The loan has both halves, because half a protocol is how the bug survived:
///
///   * `SpiralAppRowView` takes the host when it gains a window, and only then.
///     A row being torn down never gains one, so it can never take anything.
///   * `dismantleUIView` gives the host back when SwiftUI is finished with a
///     row. It is the documented place to clean up, and using it is what makes
///     "who holds the host" always answerable rather than left to timing.
///
/// Every hand-over is guarded by identity, so the order the two rows are
/// serviced in stops mattering: a departing row returns the host only if it is
/// still the one holding it.
struct SpiralAppSurfaceView: UIViewRepresentable {
    let eventID: String?
    let post: SpiralAppPost
    let registry: SpiralAppHostRegistry?
    let mayRunAutomatically: Bool
    /// Changes when the surface should ask for the app back (see
    /// `SpiralAppSurface.reclaim`). Any value; only the change matters.
    var reclaimCount = 0
    var viewportMode: SpiralAppViewportMode = .row
    /// The row's menu, from a held finger on the post itself (§ 5.66); nil
    /// where there is no menu (the full-screen viewer).
    var onLongPress: (() -> Void)?

    func makeUIView(context: Context) -> SpiralAppSurface {
        let surface = SpiralAppSurface()
        surface.backgroundColor = .clear
        configure(surface)
        return surface
    }

    /// The event id arrives here for a local echo — the row is not rebuilt
    /// when it does (the timeline keeps one `UniqueID` across the echo), so
    /// this update is the moment a just-sent post can start.
    func updateUIView(_ uiView: SpiralAppSurface, context: Context) {
        configure(uiView)
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

    private func configure(_ surface: SpiralAppSurface) {
        surface.registry = registry
        surface.post = post
        surface.mayRunAutomatically = mayRunAutomatically
        surface.viewportMode = viewportMode
        surface.onLongPress = onLongPress
        surface.eventID = eventID
    }

    /// Take exactly the frame the row decided from `aspect`.
    ///
    /// Without this the web view is asked for an intrinsic size, has none, and
    /// draws itself into a corner of the card. The row's frame is the one
    /// decided before anything loaded, which is the whole point of `aspect`.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SpiralAppSurface, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}
