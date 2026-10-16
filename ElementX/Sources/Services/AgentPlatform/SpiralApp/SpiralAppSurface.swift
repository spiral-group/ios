//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.30): where a post's app is shown,
// and the one honest answer to "is this post on screen".
//
// The row used to tell the registry about visibility through SwiftUI's
// `onAppear`/`onDisappear`, and receive the app's view back through an
// observed slot. Three independent clocks — SwiftUI's diff, the registry's
// state, WebKit's paint — with nothing tying them to what was actually in the
// window. `onAppear` overshoots, is not paired across cell recycling, and can
// fire for a new row of a post before the old row's `onDisappear` — so the
// registry's idea of "visible" drifted from the screen, evicted apps the
// reader was looking at, and handed containers to rows that had already gone.
//
// A UIView knows whether it is in a window. That is not a hint, it is the
// fact. So the row now holds one of these for its whole life, and this view
// does two things: it tells the registry when it enters and leaves the window,
// and it is the thing the registry puts the app's container INTO. One channel,
// one truth, and the registry never depends on SwiftUI's timing again.
//
// The shape is `MediaPlayerProvider`'s: attach and detach, keyed by event id.
//

import UIKit

@MainActor
final class SpiralAppSurface: UIView {
    /// Which post this surface shows. Changes exactly once, when a local echo
    /// gets its event id — and the surface re-registers when it does.
    var eventID: String? {
        didSet {
            guard eventID != oldValue else { return }
            // A recycled cell means THIS view now shows a different post.
            // Whatever the previous post left inside must go first, or the new
            // post's row shows the old post's app — grey, because the old app
            // was told to stop painting when its own row went. The registry
            // will present the new post's app if it has one.
            clear()
            // ALWAYS give up the old post, window or not. A surface out of a
            // window that is handed a new post still holds the old post's
            // registration, and the registry reads "is this post visible" from
            // the surface it was given — so when this view came back on screen
            // showing the new post, the OLD one looked visible for ever. It
            // was therefore never evictable, the pool stayed full of posts
            // nobody could see, and every post actually on screen kept its
            // card with no way to get a turn.
            unregister(oldValue)
            if window != nil {
                register()
            }
        }
    }

    /// A long press anywhere on the post (§ 7 #18, § 5.66).
    ///
    /// The web view takes every touch, so the row's own long press — the one
    /// every other message answers — never began on a post; the menu opened
    /// only from the timestamp. This recogniser sits on the surface, UNDER
    /// the web view's container, and recognises simultaneously with WebKit's
    /// own, so the app keeps its taps and drags (a press that moves more than
    /// ten points is a drag, not a press) and a held finger opens the menu.
    var onLongPress: (() -> Void)? {
        didSet {
            if onLongPress != nil, longPress == nil {
                let recogniser = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
                recogniser.minimumPressDuration = 0.5
                recogniser.allowableMovement = 10
                recogniser.cancelsTouchesInView = false
                recogniser.delegate = self
                addGestureRecognizer(recogniser)
                longPress = recogniser
            }
        }
    }

    private var longPress: UILongPressGestureRecognizer?

    @objc private func handleLongPress(_ recogniser: UILongPressGestureRecognizer) {
        guard recogniser.state == .began else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onLongPress?()
    }

    /// The post, for the registry to fetch when this surface arms a mount.
    ///
    /// An edit keeps the event id and replaces the artifact (§ 5.55), so a
    /// new digest is reported like a new sighting: the registry stops the old
    /// version and mounts this one. After the current view update, because
    /// the registry publishes the row's phase and this is set from inside one.
    var post: SpiralAppPost? {
        didSet {
            guard let post, let oldValue, post.digest != oldValue.digest else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, window != nil, self.post?.digest == post.digest else { return }
                register()
            }
        }
    }

    /// What this surface is: a row (default) or the full-screen viewer. The
    /// registry tells the app when it hands the container over.
    var viewportMode: SpiralAppViewportMode = .row

    /// Whether the reader allows apps to start without a tap. Off means the
    /// surface still reports itself, so the registry can keep the card current,
    /// but nothing is armed.
    var mayRunAutomatically = true

    /// Set by the row. Weak, because the registry outlives no row and owns no
    /// row; the surface is the registry's client, not its dependant.
    weak var registry: SpiralAppHostRegistry?

    /// The app's container, while this surface is showing one.
    ///
    /// Derived from the hierarchy, not remembered: a container can be TAKEN
    /// from this surface by a newer one for the same post (cell recycling),
    /// and a remembered reference would then name a view that is somebody
    /// else's. The hierarchy cannot be wrong about that.
    var presented: UIView? {
        subviews.first { $0 === presentedContainer }
    }

    private weak var presentedContainer: UIView?

    /// Whether the reader can actually see this row.
    ///
    /// Being in a window is NOT that. A timeline keeps rows in the hierarchy
    /// beyond the viewport — visibility overshoots (§5.15) — and with `window
    /// != nil` as the test, six posts reported themselves on screen at once
    /// with a cap of four: none could be evicted, so nothing on screen could
    /// get a turn, and every row that arrived kept its card. Geometry is the
    /// question being asked, so geometry is what answers it.
    var isOnScreen: Bool {
        visibleFraction > 0
    }

    /// How much of this row the reader can actually see, from 0 to 1.
    ///
    /// Asking only whether the row INTERSECTS the window makes a one-pixel
    /// sliver at the edge count for as much as the post under the reader's
    /// eye. Measured 2026-09-16, in an 874pt window with 235pt posts: five to
    /// six rows intersected at any moment, of which three or four were really
    /// visible and two or three were slivers. With a cap of four and a rule
    /// that never evicts what is "on screen", the slivers held hosts that the
    /// posts being read could not get — so a post the reader was looking at
    /// kept its card, and which sliver held a host changed with every scrolled
    /// pixel, which is where the eviction storms came from.
    ///
    /// The cap of four turned out to be right for that viewport. What was
    /// wrong was the question it was answering.
    var visibleFraction: CGFloat {
        guard let window, bounds.height > 0 else { return 0 }
        let frame = convert(bounds, to: window)
        let visible = frame.intersection(window.bounds)
        guard !visible.isNull else { return 0 }
        return visible.height / frame.height
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            register()
            watchEnclosingScroll()
        } else {
            scrollObservation = nil
            unregister(eventID)
        }
    }

    // MARK: - Re-asserting after a scroll

    /// A timeline recycles cells, and the surface the registry remembers for
    /// a post is not always the one on screen showing it: the row that was
    /// scrolled in kept its `eventID`, so `didSet` never re-registered, and
    /// the registry read "unseen" off a surface that had moved on — the post
    /// sat on screen as a grey rectangle with a running app it could not be
    /// handed (2026-09-17, six posts in view, 4 hosts). Registering is
    /// idempotent — the registry takes the newest asker and presents what it
    /// has, or clears — so the surface simply asks again once each scroll
    /// settles. Cheap, and it makes "who shows the app" answerable from what
    /// is on screen rather than from what was remembered.
    private var scrollObservation: NSKeyValueObservation?
    private var reassertWork: DispatchWorkItem?

    private func watchEnclosingScroll() {
        scrollObservation = nil
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) {
            ancestor = view.superview
        }
        guard let scrollView = ancestor as? UIScrollView else { return }
        scrollObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.scheduleReassert()
        }
    }

    private func scheduleReassert() {
        reassertWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, window != nil else { return }
            register()
        }
        reassertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
    }

    /// Layout MOVES NOTHING. It only sizes what is already here.
    ///
    /// An earlier version asked the registry for its app from here, to heal
    /// any ordering of appear/disappear/recycle that had left the surface
    /// empty. It froze the app: `present` adds a subview, adding a subview
    /// re-enters layout, layout asked again, and the stack in `sample` was
    /// `layoutSubviews → surfaceNeedsApp → present → _addSubview →
    /// _didMoveFromWindow → layoutSubviews`, at 115% CPU. Mutating the view
    /// hierarchy during layout is the oldest UIKit mistake there is, and no
    /// amount of guarding the re-entry makes it right — the fix belongs at the
    /// events that change what should be shown, which is where it now lives.
    override func layoutSubviews() {
        super.layoutSubviews()
        presented?.frame = bounds
    }

    // MARK: - Registry side

    /// Show this container. Idempotent: the same container twice is a no-op,
    /// and a container that is somewhere else is taken from there — exactly
    /// one surface may be showing an app at a time, and it is the one that
    /// asked most recently.
    func present(_ container: UIView) {
        guard presented !== container else { return }
        presented?.removeFromSuperview()
        container.removeFromSuperview()
        container.frame = bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(container)
        presentedContainer = container
    }

    /// Ask for the app again while still in a window.
    ///
    /// A full-screen viewer registers a second surface for the same post and
    /// is handed the container; when it closes, its surface leaves the window
    /// and the registry keeps the app but shows it nowhere. The row's surface
    /// never left, so nothing re-registered it — this does.
    func reclaim() {
        guard window != nil else { return }
        register()
    }

    /// Stop showing whatever this surface shows. Safe to call when it shows
    /// nothing, and safe when the container has already been taken by
    /// another surface — only what is actually HERE is removed.
    func clear() {
        presented?.removeFromSuperview()
        presentedContainer = nil
    }

    // MARK: - Private

    private func register() {
        guard let eventID, let post else { return }
        registry?.surfaceDidEnterWindow(self, eventID: eventID, post: post)
    }

    private func unregister(_ eventID: String?) {
        guard let eventID else { return }
        registry?.surfaceDidLeaveWindow(self, eventID: eventID)
    }
}

extension SpiralAppSurface: UIGestureRecognizerDelegate {
    /// Alongside WebKit's, never instead of it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
