//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066): the ONE way an Interactive Post is drawn —
// in a room, and as a draft's preview in the studio thread.
//
// The frame is decided from `aspect` before anything loads, capped like a
// media row; the app's surface sits in it; the quiet card covers it until
// the app has drawn; a small control opens the same running app at the
// size of the screen. A draft's preview goes through exactly this, so what
// the owner sees before Publish is what the room sees after — same box,
// same cap, same card, same expand.
//

import Compound
import SwiftUI

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
    /// Called when the full-screen viewer closes, so a row can reclaim.
    var onExpandedDismissed: () -> Void = { }
    /// Bumped by whoever is listening when the app itself asks for the whole
    /// screen (`ui.expand`). Any value; only the change matters.
    var expandRequests = 0
    @ViewBuilder let surface: () -> Surface
    /// The same app, at the size of the screen.
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
    @State private var showsFullScreen = false

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
            .background(Color.compound.bgSubtleSecondary)
            .fullScreenCover(isPresented: $showsFullScreen, onDismiss: onExpandedDismissed) {
                expanded()
            }
            // The app asking, rather than the reader. Ignored until it has
            // drawn: a card that grows to full screen before there is
            // anything in it is a black rectangle.
            .onChange(of: expandRequests) { _, _ in
                guard isReady else { return }
                showsFullScreen = true
            }
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
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showsFullScreen = true
                        } label: {
                            CompoundIcon(\.expand, size: .xSmall, relativeTo: .compound.bodySM)
                                .foregroundStyle(.compound.iconSecondary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(6)
                        .accessibilityLabel(UntranslatedL10n.spiralAppOpenFullScreen)
                    }
                    Spacer()
                }
            }

            // COVERS the app rather than replacing it. The web view has to be
            // in the hierarchy to paint at all, so it goes in early and waits
            // behind this until it has something to show.
            if !isReady {
                card
                    .background(Color.compound.bgSubtleSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isReady)
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
            if showsProgress {
                ProgressView()
                    .padding(16)
            }
        }
        // Only once it has taken long enough to be worth saying. On a warm
        // cache the whole start is about 50ms, and a spinner shown for 50ms
        // is not information, it is a flicker.
        .task(id: isLoading) {
            showsProgress = false
            guard isLoading else { return }
            try? await Task.sleep(for: beforeSayingItIsWorking)
            guard !Task.isCancelled else { return }
            showsProgress = true
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

/// The full-screen viewer's chrome: a title, Done, and the whole area for
/// whatever surface is handed in.
struct SpiralAppExpandedView<Surface: View>: View {
    let title: String
    @ViewBuilder let surface: () -> Surface

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ElementNavigationStack {
            GeometryReader { geometry in
                // The whole area, not the row's aspect: the app is written to
                // fill 100% × 100% and this is where that pays.
                surface()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.compound.bgSubtleSecondary)
            }
            // The app stops ABOVE the home indicator.
            //
            // It used to ignore the bottom safe area so the app's own
            // background reached the screen edge, and the cost was the last
            // line of every post: measured on a simulator, the web view was
            // 402 × 758 at y = 116 — bottom edge 874, the screen's own — and
            // the final line of a drawing post sat at y = 842, inside the
            // indicator's 34 points. Reported from use as "no bottom padding,
            // the text disappears" (2026-09-21).
            //
            // The frame is what the app is told it has, so it may not include
            // room the reader cannot see.
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionDone) { dismiss() }
                }
            }
        }
    }
}
