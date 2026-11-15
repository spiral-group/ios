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
            if let oldValue {
                registry?.surfaceWillLeaveWindow(self, eventID: oldValue)
            }
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
    ///
    /// A hidden row shows nothing, wherever it is: see `isHiddenInWindow`.
    var visibleFraction: CGFloat {
        isHiddenInWindow ? 0 : fractionInsideWindow
    }

    /// How much of this surface lies inside its window, shown or not.
    private var fractionInsideWindow: CGFloat {
        guard let window, bounds.height > 0 else { return 0 }
        let frame = convert(bounds, to: window)
        let visible = frame.intersection(window.bounds)
        guard !visible.isNull else { return 0 }
        return visible.height / frame.height
    }

    /// Whether this surface, or a view it sits in, is hidden.
    ///
    /// A table keeps the cells it may reuse as HIDDEN subviews, still in the
    /// window and at the frame they last had, still holding the post they last
    /// showed. Such a row asked for its post's app at every rest of the table
    /// (`reclaim`), and the last surface to ask wins: on Dev-B a finished
    /// tug-of-war went into a hidden cell lying under its visible row, the page
    /// laid out and drew, and the row the reader saw stayed an empty grey frame
    /// until the viewer took the app and gave it back (question 411, 2026-11-13).
    var isHiddenInWindow: Bool {
        var view: UIView? = self
        while let current = view, current !== window {
            if current.isHidden { return true }
            view = current.superview
        }
        return false
    }

    /// The last moment the app's web view is in a window, which is what a
    /// picture of it needs.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, let eventID {
            registry?.surfaceWillLeaveWindow(self, eventID: eventID)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            register()
            watchEnclosingScroll()
        } else {
            registry?.scrollWatch.forget(self)
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
    /// has, or clears — so `SpiralAppScrollWatch` has every surface ask again
    /// once a scroll settles. It makes "who shows the app" answerable from
    /// what is on screen rather than from what was remembered.
    private func watchEnclosingScroll() {
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) {
            ancestor = view.superview
        }
        guard let scrollView = ancestor as? UIScrollView else { return }
        registry?.scrollWatch.watch(scrollView, for: self)
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
        still?.removeFromSuperview()
        container.removeFromSuperview()
        container.frame = bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(container)
        // The web view takes the new size now, not at the next layout pass:
        // the page can only start laying itself out once it has it.
        container.layoutIfNeeded()
        presentedContainer = container
    }

    /// A picture of the app, where the app was: what a closing viewer shows
    /// while it slides away, once the app has gone back to its row.
    func showStill(_ image: UIImage) {
        still?.removeFromSuperview()
        let view = UIImageView(image: image)
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        addSubview(view)
        still = view
    }

    private weak var still: UIView?

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
        still?.removeFromSuperview()
    }

    // MARK: - Private

    /// A hidden row never asks: it would take the app from the row the reader
    /// sees. Once it is shown again, the table's next rest or the registry's
    /// watch (`adoptRowsInSight`) has it ask.
    private func register() {
        guard let eventID, let post else { return }
        guard !isHiddenInWindow else {
            #if DEBUG || SPIRAL_STAGING
            if fractionInsideWindow > 0 || registry?.remembers(eventID) == false {
                SpiralAppReturnTrace.step(eventID, "a hidden row (\(String(format: "%.2f", fractionInsideWindow)) inside the window, "
                    + "post known=\(registry?.remembers(eventID) ?? false)) asked for the app — not given")
            }
            #endif
            return
        }
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

/// Whether the timeline's table is moving, and who to tell when it stops.
///
/// One per registry, and one observation of the table's offset: each surface
/// used to hold its own, and allocate a work item, on every scrolled frame.
@MainActor
final class SpiralAppScrollWatch {
    /// How long the offset must hold before the table counts as still. A finger
    /// resting on it counts: a reader who stopped to look is looking.
    private static let stillAfter = Duration.milliseconds(120)
    private static let checkEvery = Duration.milliseconds(40)
    /// A frame, for the one wait that ends while the table still drifts.
    private static let checkCalmEvery = Duration.milliseconds(16)

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var lastMoved: ContinuousClock.Instant?
    private var pace = SpiralAppScrollPace()
    private var settling: Task<Void, Never>?
    private let surfaces = NSHashTable<SpiralAppSurface>.weakObjects()
    #if DEBUG || SPIRAL_STAGING
    private var frames: SpiralAppFrameProbe?
    #endif
    /// Called each time the table has stopped, once the surfaces have asked again.
    var onSettled: (() -> Void)?

    /// Covers a programmatic scroll too, which is the table moving with no
    /// finger on it and no deceleration.
    var isMoving: Bool {
        if scrollView?.isDecelerating == true { return true }
        guard let lastMoved else { return false }
        return lastMoved.duration(to: .now) < Self.stillAfter
    }

    /// Still, or drifting slower than a reader can follow a post by. A flick
    /// decelerates for about three seconds, and most of the last one and a half
    /// is a few points a frame (Stage-A, 2026-11-12).
    var isCalm: Bool {
        !isMoving || pace.isCalm(at: .now)
    }

    /// How fast the table moved at its last sample, in points per second.
    var speed: CGFloat {
        isMoving ? pace.speed : 0
    }

    func watch(_ scrollView: UIScrollView, for surface: SpiralAppSurface) {
        surfaces.add(surface)
        guard scrollView !== self.scrollView else { return }
        self.scrollView = scrollView
        // KVO's handler is nonisolated, but UIKit only moves contentOffset on the main thread.
        observation = scrollView.observe(\.contentOffset, options: []) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.noteMovement()
            }
        }
    }

    func forget(_ surface: SpiralAppSurface) {
        surfaces.remove(surface)
    }

    /// Every surface in the table's window, hidden ones included.
    var watchedSurfaces: [SpiralAppSurface] {
        surfaces.allObjects
    }

    /// Returns once the table is still, or at once if the caller is cancelled.
    func untilStill() async {
        while isMoving, !Task.isCancelled {
            try? await Task.sleep(for: Self.checkEvery)
        }
    }

    /// Returns once the table is calm (see `isCalm`), or at once if the caller is cancelled.
    func untilCalm() async {
        while !isCalm, !Task.isCancelled {
            try? await Task.sleep(for: Self.checkCalmEvery)
        }
    }

    func stop() {
        #if DEBUG || SPIRAL_STAGING
        _ = frames?.finish()
        frames = nil
        #endif
        observation = nil
        onSettled = nil
        settling?.cancel()
        settling = nil
    }

    private func noteMovement() {
        lastMoved = .now
        if let offset = scrollView?.contentOffset.y {
            pace.note(offset: offset, at: .now)
        }
        guard settling == nil else { return }
        #if DEBUG || SPIRAL_STAGING
        let began = ContinuousClock.now
        frames = SpiralAppFrameProbe()
        #endif
        // The main queue is served in every run loop mode, so this runs under
        // a finger too.
        settling = Task { [weak self] in
            await self?.untilStill()
            guard !Task.isCancelled, let self else { return }
            #if DEBUG || SPIRAL_STAGING
            let hitches = frames?.finish() ?? "-"
            frames = nil
            SpiralAppReturnTrace.note("table still after \(SpiralAppReturnTrace.milliseconds(began.duration(to: .now)))ms of movement — frames \(hitches)")
            #endif
            settling = nil
            pace.reset()
            for surface in surfaces.allObjects {
                surface.reclaim()
            }
            onSettled?()
        }
    }
}

/// How fast the table is moving, from its offsets over time, and whether it
/// has been slow for long enough to count as calm. Its own clock, so the rule
/// can be tested without a table.
struct SpiralAppScrollPace {
    /// Points per second. A row drifting slower than this has a reader who can
    /// see it, and a kept app may come back to it.
    static let calmSpeed: CGFloat = 300
    /// How long the table must stay under `calmSpeed`: one slow frame in a
    /// fling is not the end of the fling.
    static let calmFor = Duration.milliseconds(100)
    /// KVO reports several offsets a frame; closer than this they say nothing about speed.
    static let sampleSpacing = Duration.milliseconds(8)
    /// Further apart than this, the table rested in between: a new movement, speed unknown.
    static let restGap = Duration.milliseconds(100)

    private(set) var speed: CGFloat = 0
    private var anchor: (offset: CGFloat, at: ContinuousClock.Instant)?
    private var calmSince: ContinuousClock.Instant?

    mutating func note(offset: CGFloat, at now: ContinuousClock.Instant) {
        guard let anchor else {
            self.anchor = (offset, now)
            return
        }
        let elapsed = anchor.at.duration(to: now)
        guard elapsed >= Self.sampleSpacing else { return }
        guard elapsed <= Self.restGap else {
            reset()
            self.anchor = (offset, now)
            return
        }

        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        speed = abs(offset - anchor.offset) / CGFloat(seconds)
        self.anchor = (offset, now)
        if speed < Self.calmSpeed {
            calmSince = calmSince ?? now
        } else {
            calmSince = nil
        }
    }

    func isCalm(at now: ContinuousClock.Instant) -> Bool {
        guard let calmSince else { return false }
        return calmSince.duration(to: now) >= Self.calmFor
    }

    mutating func reset() {
        speed = 0
        anchor = nil
        calmSince = nil
    }
}
