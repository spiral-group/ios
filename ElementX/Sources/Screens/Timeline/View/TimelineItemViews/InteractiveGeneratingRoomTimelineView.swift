//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, § 5.71; Brief 0083, question 359): the card that
// stands where the draft will land while the agent's model writes it — a row of
// the chat's cards, a band of the accent colour crossing it, the agent's own line
// and «usually under a minute». The draft takes 25–65 s; the card is the difference
// between «it is working» and «it said “done” and nothing came».
//
// It is never dismissed by hand: the controller drops the marker the moment
// anything from the agent follows it (the draft, or the sentence that it
// failed). A marker older than five minutes with nothing after it is a
// generation the orchestrator lost, and the card says so.
//

import Compound
import SwiftUI

struct InteractiveGeneratingRoomTimelineView: View {
    let timelineItem: InteractiveGeneratingRoomTimelineItem

    @State private var isStale = false
    @State private var bandOffset: CGFloat = -1

    var body: some View {
        TimelineStyler(timelineItem: timelineItem) {
            ChatCardRow(icon: isStale ? \.error : \.extensions,
                        isCritical: isStale,
                        title: isStale ? UntranslatedL10n.screenRoomInteractiveGeneratingFailed : timelineItem.body) {
                Text(isStale ? UntranslatedL10n.screenRoomInteractiveGeneratingFailedHint : UntranslatedL10n.screenRoomInteractiveGeneratingHint)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
            }
            .padding(.top, 8)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                if !isStale {
                    // Under the time too, which sits below this: the bubble's shape is what clips the band.
                    band.padding(.bottom, -32)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .task(id: timelineItem.timestamp) {
            isStale = staleNow
            guard !isStale else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false).disabledDuringTests()) {
                bandOffset = 2
            }
            let remaining = InteractiveGeneratingRoomTimelineItem.staleAfter - Date().timeIntervalSince(timelineItem.timestamp)
            try? await Task.sleep(for: .seconds(max(remaining, 0)))
            guard !Task.isCancelled else { return }
            isStale = true
        }
    }

    private var staleNow: Bool {
        Date().timeIntervalSince(timelineItem.timestamp) > InteractiveGeneratingRoomTimelineItem.staleAfter
    }

    /// The accent colour, faint, in a slanted band that crosses the card
    /// left to right — the same motion the app's own shimmer makes.
    private var band: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            LinearGradient(colors: [.clear, Color.compound.iconAccentPrimary.opacity(0.15), .clear],
                           startPoint: .leading,
                           endPoint: .trailing)
                .frame(width: width * 0.4, height: geometry.size.height * 3)
                .rotationEffect(.degrees(18))
                .offset(x: bandOffset * width, y: -geometry.size.height)
        }
    }
}

struct InteractiveGeneratingRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock

    static var previews: some View {
        VStack(spacing: 20) {
            InteractiveGeneratingRoomTimelineView(timelineItem: makeItem(body: "Створюю чернетку v2…", isFresh: true))
            InteractiveGeneratingRoomTimelineView(timelineItem: makeItem(body: "Creating draft v1…", isFresh: false))
        }
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
    }

    /// Dated off the clock, or the snapshot's time label changes by the hour:
    /// the fresh card is dated 9:41 on a day still to come, so it is never
    /// stale; the stale one at `.mock`.
    private static func makeItem(body: String, isFresh: Bool) -> InteractiveGeneratingRoomTimelineItem {
        let timestamp = isFresh ? DateComponents(calendar: .current, year: 2100, month: 1, day: 9, hour: 9, minute: 41).date ?? .mock : .mock
        return InteractiveGeneratingRoomTimelineItem(id: .randomEvent,
                                                     body: body,
                                                     timestamp: timestamp,
                                                     isOutgoing: false,
                                                     isEditable: false,
                                                     canBeRepliedTo: false,
                                                     sender: .init(id: "@assistant-x:spiral.md"))
    }
}
