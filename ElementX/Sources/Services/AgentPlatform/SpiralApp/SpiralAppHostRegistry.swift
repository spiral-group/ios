//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.15): who owns the web views.
//
// Timeline rows are recycled table cells. A row that owned a `WKWebView` would
// take it down the moment it crossed the screen edge, so the web views are
// owned here and lent to rows — the shape `MediaPlayerProvider` already uses
// for audio, where one player serves many rows through per-row state.
//
// Two measurements decide the policy, both in notebook §5.15:
//
//   · Visibility OVERSHOOTS. An incoming row's `onAppear` precedes the
//     outgoing row's `onDisappear`, so five rows claimed to be visible where
//     three fit on screen. The gate only ever proved four live hosts.
//   · A row can appear and disappear inside one flick.
//
// So visibility ARMS a mount; it does not cause one. A post that leaves before
// the settle never costs a web view, which is what keeps steady-state demand at
// what is really on screen rather than at the overshoot.
//

import Combine
import Foundation
import os
import UIKit

/// What one row watches.
///
/// The registry decides when an app starts, which is long after the row was
/// first drawn — so the row needs something to observe, exactly as a voice
/// message row observes its `AudioPlayerState`. One per post, outliving its
/// host, so a row that scrolls back finds the same object.
@MainActor
final class SpiralAppSlot: ObservableObject {
    /// How far along a post is, so the row can say so.
    ///
    /// The app's view itself no longer travels through here: the registry puts
    /// it straight into the row's `SpiralAppSurface`. What the row still needs
    /// to observe is WHEN to lift the card, and that is this.
    enum Phase {
        /// Nothing is happening. Either nobody has looked at this post yet, or
        /// its app has been taken down to make room for another.
        case waiting
        /// Fetching, verifying, mounting, booting. Can be a moment on a warm
        /// cache and much longer over a network.
        case loading
        /// The app is running, but not in this row yet: it comes back once
        /// the table has stopped. Until then the row covers it, as it covers
        /// an app that has not started.
        case away
        /// The app has drawn something, and the row is showing it.
        case ready
    }

    @Published fileprivate(set) var phase: Phase = .waiting

    /// A picture of the app as it last looked, for the row to show in its
    /// place. In memory only, and gone with the room: it is a picture of what
    /// people wrote, and nothing here is on disk for a purge to find.
    @Published fileprivate(set) var standIn: UIImage?

    /// The post didn't start, and it isn't for want of a host: the card says
    /// so instead of looking as if nothing were wrong.
    @Published fileprivate(set) var couldNotStart = false

    /// The post's code needs a newer app than this one; the card says so,
    /// and it is never started again here.
    @Published fileprivate(set) var needsNewerApp = false

    /// The newest thing the app said about itself, for the card to show when
    /// the app is not running.
    ///
    /// Kept after the app is taken down on purpose: an evicted post saying what
    /// it last said is better than one that has forgotten, and the line was
    /// written precisely to be read where the code is not.
    @Published fileprivate(set) var summaryLine: String?

    /// The moment the newest summary counts down to (`countdown_to`), for the
    /// card to count down to by itself while no code runs (§ 5.79). Kept with
    /// the line, and for the same reason.
    @Published fileprivate(set) var summaryCountdown: Date?

    /// Who wrote `summaryLine`, by id and by name. Any member's action can
    /// write the card, so a row says so when it was not the post's author.
    @Published fileprivate(set) var summaryWriter: (id: String, name: String)?

    /// Bumped whenever the running app asks for the whole screen
    /// (`ui.expand`). The row watches it and opens the viewer; a row that is
    /// not on screen simply never sees the change.
    @Published fileprivate(set) var expandRequests = 0

    fileprivate func requestExpand() {
        expandRequests += 1
    }

    #if DEBUG
    /// Stand in for an app having said something, so a test can check what
    /// survives the app being taken down without running one.
    func reportForTesting(summaryLine: String, countdown: Date? = nil) {
        self.summaryLine = summaryLine
        summaryCountdown = countdown
    }
    #endif
}

@MainActor
final class SpiralAppHostRegistry {
    /// How many apps may be live at once.
    ///
    /// Four is INHERITED, not validated. The gate did run four hosts at once on
    /// an iPhone 15 Pro — but under the opposite lifecycle, where a row leaving
    /// the screen tore its app down, so four was a momentary peak while
    /// scrolling. Apps are kept now (§5.22), so four web views and their four
    /// WebContent processes can sit there for as long as someone stays in the
    /// room. Nothing has measured THAT.
    ///
    /// Two reasons not to guess a smaller number instead: a lower cap shows a
    /// card where an app should be, on hardware that could have run it; and the
    /// same gate saw its own `cpu-burn` figure move 4× on one device between
    /// two sessions, so a number picked from one more run would be no better
    /// founded than this one.
    ///
    /// RAISED FROM FOUR TO SIX (operator, 2026-09-21), on evidence that four
    /// binds in ordinary reading rather than only under stress: scrolling a
    /// room of interactive posts produced 39 mounts and 33 evictions in one
    /// pass, twelve of them taking an app less than a second old, and a post
    /// that lost its host waited a median of 3.4 s for another — all of it
    /// contention for the fourth slot, since a mount itself costs 46 ms
    /// (§ 5.48). Four live apps measured 99 MB of footprint in that run.
    ///
    /// SIX ONLY ON A PHONE WITH THE MEMORY FOR IT. The cost that matters is
    /// not this process's footprint — six live apps measured 124 MB against
    /// four at 99 MB — but six WebContent PROCESSES, and a simulator cannot
    /// price those: its web content runs as macOS processes whose size says
    /// nothing about a phone. That is the measurement ADR-0007 has owed since
    /// the gate, and raising the cap everywhere would have spent it blind.
    ///
    /// So the oldest phones keep the four that were actually proven on an
    /// iPhone 15 Pro, and only a device with memory to spare gets six.
    static let defaultMaxLiveHosts = ProcessInfo.processInfo.physicalMemory >= 6 * 1024 * 1024 * 1024 ? 6 : 4

    /// Settable only so a test can build a crowded timeline without opening
    /// twelve web views to do it.
    let maxLiveHosts: Int

    /// How many posts to remember at all.
    ///
    /// An entry outlives its host on purpose — it is what makes eviction pick
    /// the coldest rather than the newest — so without a bound, scrolling a
    /// long room would accumulate one entry per post seen. Small memory, but
    /// growth keyed by something the room's authors control, which is the same
    /// shape of mistake the artifact cache avoids.
    static let maxRememberedPosts = 64

    /// How long a post must stay visible before it is worth starting.
    ///
    /// Covers a flick past a post without being noticeable when someone stops
    /// to look. Short enough that a reader who lands on a post does not watch
    /// it think about starting.
    static let settleBeforeMount = Duration.milliseconds(250)

    /// How many posts keep their session, and so their actions, with no app
    /// and no row. Each may hold `SpiralAppStateReader.maxKnownActions`.
    static let maxKeptSessions = 16

    /// How many pictures to keep for posts with no row. One is a few megabytes.
    static let maxStandIns = 8

    /// The longest a post waits before trying again after a failure.
    private static let longestBackOff = Duration.seconds(60)

    /// How long a memory warning puts spare web views off: each is a process.
    private static let noSpareHostsAfterMemoryWarning = Duration.seconds(60)

    /// How long a row with a running app waits before taking it back. Moving
    /// a web view into a window isn't free, so never in the frame the row
    /// arrived in; the row's cover makes the wait invisible.
    static let settleBeforeReturn = Duration.milliseconds(50)

    /// How much of a row must be in sight for a picture of its app to be worth
    /// keeping. A web view scrolled out of the window's bounds snapshots blank
    /// (11 of 11 on Stage-A, 2026-11-12), and a cell leaves its window only
    /// after it has scrolled past the viewport.
    static let standInVisibility: CGFloat = 0.5

    /// A row that leaves its window and is back within this keeps its armed
    /// return: the table re-hosts cells mid-scroll in about a millisecond.
    static let rowBounce = Duration.milliseconds(20)

    /// How long after an app is revealed its picture is taken.
    static let pictureAfterReveal = Duration.milliseconds(500)

    /// How long a closing viewer waits for its picture before the app goes
    /// back to its row anyway. Pictures took 1-6 ms on Stage-A.
    static let viewerPictureDeadline = Duration.milliseconds(100)

    /// When a kept app goes back into a row that has come back.
    enum ReturnRule: String {
        /// As soon as the row is in the window, with the cover on until the page has drawn.
        case atOnce
        /// Once the table drifts slower than `SpiralAppScrollPace.calmSpeed`.
        case whenCalm
        /// Once the table has stopped (the rule until 2026-11-12).
        case whenStill
    }

    /// The rule in force. DEBUG and Staging builds take `-SpiralAppReturnRule <rule>`
    /// at launch, so the rules can be compared on one build.
    static let defaultReturnRule: ReturnRule = {
        #if DEBUG || SPIRAL_STAGING
        if let raw = UserDefaults.standard.string(forKey: "SpiralAppReturnRule"), let rule = ReturnRule(rawValue: raw) {
            return rule
        }
        #endif
        return .atOnce
    }()

    var returnRule = SpiralAppHostRegistry.defaultReturnRule

    // A row leaving the screen does NOT take its app down. Only eviction and
    // the timeline going away do. See `postDidDisappear`.

    private struct Entry {
        /// `var`: an edit (`m.replace`) keeps the event id and changes the
        /// artifact, and the entry follows it (§ 5.55).
        var post: SpiralAppPost
        /// The running app: the session bound to a host. Lives and dies with
        /// visibility.
        var instance: SpiralAppInstance?
        let slot: SpiralAppSlot
        /// The row's surface while that row is in a window, nil otherwise.
        /// THIS is what "visible" means here — a UIKit fact reported by the
        /// surface itself on `didMoveToWindow`, not a SwiftUI hint. When the
        /// app is running, its container is inside this surface.
        weak var surface: SpiralAppSurface?
        /// The row while the full-screen viewer holds the app: where the app
        /// goes back to as the viewer starts to close.
        weak var row: SpiralAppSurface?
        /// From the viewer starting to close until it has gone: a viewer
        /// surface arriving meanwhile is one on its way out.
        var isViewerClosing = false
        var arming: Task<Void, Never>?
        /// Bumped whenever this post becomes visible, so the least recently
        /// wanted host is the one to take when the pool is full.
        var lastWantedAt: Date
        /// When this post started loading, so a mount that never answers can
        /// be seen. Nil once it is running or back to a card.
        var loadingSince: Date?
        /// Whether this post has already been given a second chance after the
        /// system killed its content process, since it last started. See
        /// `contentProcessDied`.
        var retriedAfterDeath = false
        /// Has not left when told to, once. Unlike a death this comes after a
        /// good start, so a good start doesn't forgive it.
        var hasWedged = false
        /// Wedged twice (M3). Not mounted again until the app comes back from
        /// the background: each try costs a host and the seconds an eviction
        /// waits for it.
        var isWedged = false
        /// How many times a start was interrupted by something that was not
        /// this app's fault. Bounded so a post cannot reload for ever.
        var startsInterrupted = 0
        /// Failures since the post last started, and when it may try again.
        var failures = 0
        var notBefore: ContinuousClock.Instant?
        /// The post's actions, kept past any one app: a remount starts from
        /// what is known instead of reading it all again. Also what a row that
        /// may not run an app (media hidden) reads its card from (§ 5.79).
        var session: SpiralAppPostSession?
        /// Keeps the card's line current, app or not.
        var sessionCancellable: AnyCancellable?

        /// Whether a failure is still keeping this post from trying.
        var isBackingOff: Bool {
            notBefore.map { $0 > .now } ?? false
        }

        /// A row the reader can see, with an app it may run and doesn't have.
        var wantsHost: Bool {
            guard let surface, surface.isOnScreen, surface.mayRunAutomatically else { return false }
            return instance == nil && !isWedged && !isBackingOff
        }
    }

    private var entries: [String: Entry] = [:]
    private var invariantWatch: Timer?
    /// A warm host on its way for a row that has just arrived.
    private var warming: Task<Void, Never>?
    /// Whether this room has had a post to warm a host for.
    private var hasWarmed = false
    /// After a memory warning, no spare hosts for a while.
    private var noSpareHostsBefore: ContinuousClock.Instant?
    /// The app's own comings and goings.
    private var appObservers = Set<AnyCancellable>()
    /// The timeline's table: nothing starts, and no app moves, while it does.
    let scrollWatch = SpiralAppScrollWatch()
    #if DEBUG
    /// How often the invariant watch has fired, for a test of when it fires.
    private(set) var watchdogTicks = 0
    /// How many returns and mounts have been armed, for the tests of a row bouncing.
    private(set) var armings = 0
    #endif
    private let artifacts: SpiralAppArtifactStore
    /// For the people's avatars a post is handed (§ 5.64).
    private let mediaProvider: MediaProviderProtocol?
    private let roomProxy: JoinedRoomProxyProtocol
    /// One subscription for the whole room, however many posts are mounted.
    private let feed: SpiralAppActionFeed
    /// § 5.87: set by a timeline that can show the resolve sheet.
    var sendRefusals: SpiralAppSendRefusals?
    /// Warm web views, shared by every post in this room. An evicted app's
    /// host goes back here and the next app takes it, so an eviction no longer
    /// costs a WebContent process and a shell load. See `SpiralAppHostPool`.
    let pool: SpiralAppHostPool

    init(artifacts: SpiralAppArtifactStore,
         roomProxy: JoinedRoomProxyProtocol,
         mediaProvider: MediaProviderProtocol? = nil,
         maxLiveHosts: Int = SpiralAppHostRegistry.defaultMaxLiveHosts,
         unmountDeadline: Duration = .seconds(2),
         makeHost: @escaping @MainActor () -> SpiralAppHostProtocol) {
        self.artifacts = artifacts
        self.roomProxy = roomProxy
        self.mediaProvider = mediaProvider
        self.maxLiveHosts = maxLiveHosts
        pool = SpiralAppHostPool(unmountDeadline: unmountDeadline, makeHost: makeHost)
        feed = SpiralAppActionFeed(roomProxy: roomProxy)
        startInvariantWatch()
        observeApp()
        scrollWatch.onSettled = { [weak self] in
            self?.pauseAppsNobodyCanSee()
            self?.captureStandInsInSight()
        }
    }

    /// A backgrounded app's web views are stopped and gone before iOS kills
    /// them: nothing left to die, and nothing to remount a post from a death.
    private func observeApp() {
        let center = NotificationCenter.default
        center.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.captureStandInsOnScreen() }
            .store(in: &appObservers)
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.appDidEnterBackground() }
            .store(in: &appObservers)
        center.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.appWillEnterForeground() }
            .store(in: &appObservers)
        center.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in self?.reclaimMemory() }
            .store(in: &appObservers)
    }

    /// While the app is still active, as a picture needs it to be.
    private func captureStandInsOnScreen() {
        for eventID in entries.keys {
            captureStandIn(eventID)
        }
    }

    private func appDidEnterBackground() {
        updateCover { isInBackground = true }
    }

    /// A fresh start for every post: what failed may well work now, and what
    /// the subscription missed in the background is the read's to find.
    private func appWillEnterForeground() {
        for (eventID, entry) in entries {
            entries[eventID]?.retriedAfterDeath = false
            entries[eventID]?.hasWedged = false
            entries[eventID]?.isWedged = false
            entries[eventID]?.failures = 0
            entries[eventID]?.notBefore = nil
            entry.session?.markStale()
        }
        updateCover { isInBackground = false }
    }

    /// Give back what the reader can't see: the parked hosts, the apps off
    /// screen, their pictures and what their sessions hold. All of it comes
    /// back by itself on the way back to those posts.
    private func reclaimMemory() {
        var stopping: [SpiralAppInstance] = []
        for (eventID, entry) in entries where !isVisible(eventID) {
            entry.slot.standIn = nil
            if let instance = entry.instance {
                entries[eventID]?.instance = nil
                entry.surface?.clear()
                returnToCard(eventID)
                stopping.append(instance)
            }
            entry.session?.stop()
            entries[eventID]?.session = nil
            entries[eventID]?.sessionCancellable = nil
        }
        MXLog.info("[SpiralApp] memory warning — stopping \(stopping.count) — \(ExtensionLogger.formattedMemoryFootprint)")

        noSpareHostsBefore = .now + Self.noSpareHostsAfterMemoryWarning
        pool.drain()
        Task { [pool] in
            for instance in stopping {
                await instance.stop()
            }
            pool.drain()
        }
    }

    /// The invariant: a post whose app is running, whose row is on screen,
    /// shows that app. Anything else is a grey rectangle where the reader
    /// expects something.
    ///
    /// This watches it on a timer rather than trusting the events, because the
    /// events are SwiftUI's and UIKit's together and their orderings defeated
    /// four attempts at reasoning about them. Deliberately NOT in
    /// `layoutSubviews`: presenting adds a subview, adding a subview re-enters
    /// layout, and that spun the app at 115% CPU — `sample` caught it in the
    /// act (§5.30).
    ///
    /// Half a second is slower than a frame and far faster than a reader
    /// notices. It repairs and it SAYS SO, because a silent repair would hide
    /// the path that broke.
    ///
    /// In `.common` modes: a timer in `.default` doesn't fire while a finger
    /// is on the table or the table decelerates, which is when rows change.
    /// What it asks for still waits for the table (`arm`).
    private func startInvariantWatch() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                #if DEBUG
                self?.watchdogTicks += 1
                #endif
                self?.adoptRowsInSight()
                self?.repairSurfacesShowingNothing()
                self?.pauseAppsNobodyCanSee()
                self?.refillPool()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        invariantWatch = timer
    }

    /// The same post, edited: its event id kept, its artifact replaced.
    ///
    /// The row was still running the version it first saw — the entry's post
    /// was fixed at creation and every later sighting ignored — so an update
    /// showed only after leaving the room (§ 5.55). The running app is stopped
    /// and the entry takes the new post; the next sighting mounts it. Its
    /// state is untouched: it lives under the event id, which did not change.
    private func adoptEdit(eventID: String, post: SpiralAppPost) {
        guard var entry = entries[eventID], entry.post.digest != post.digest else { return }
        MXLog.info("[SpiralApp] \(eventID) was edited — \(entry.post.digest.prefix(12)) → \(post.digest.prefix(12))")
        entry.arming?.cancel()
        entry.arming = nil
        entry.surface?.clear()
        // A picture of the version nobody should see any more.
        entry.slot.standIn = nil
        let running = entry.instance
        entry.instance = nil
        entry.post = post
        entries[eventID] = entry
        returnToCard(eventID)
        if let running {
            Task { await running.stop() }
        }
    }

    /// Put a post back to its card. Phase and loading stamp are one fact, so
    /// they are written in one place — a stale stamp would have the watchdog
    /// reporting a hang that had already been resolved.
    private func returnToCard(_ eventID: String) {
        entries[eventID]?.slot.phase = .waiting
        entries[eventID]?.loadingSince = nil
    }

    /// A row the reader can see that this registry isn't serving, while the
    /// surface it is serving for that post can't be seen: the row asks again.
    ///
    /// A hidden row doesn't ask (`SpiralAppSurface.register`), and a table can
    /// show a reused cell again, or hide the one it replaces, without a single
    /// row entering or leaving its window. Until the table next comes to rest
    /// the post would sit in a row nobody sees, and the row in sight would
    /// show only its picture. A viewer keeps what it holds.
    ///
    /// A post this registry has never heard of asks too: its row may have
    /// arrived while the whole table was hidden (the timeline hides it while
    /// the opening rows load) and been shown again with no scroll.
    private func adoptRowsInSight() {
        for surface in scrollWatch.watchedSurfaces where surface.viewportMode == .row && surface.isOnScreen {
            guard let eventID = surface.eventID, !eventID.isEmpty else { continue }
            if let entry = entries[eventID] {
                guard entry.surface !== surface else { continue }
                if let holder = entry.surface {
                    guard !holder.isOnScreen, !(holder.viewportMode == .expanded && holder.window != nil) else { continue }
                }
            }
            SpiralAppReturnTrace.step(eventID, "a row in sight the registry wasn't serving asks again — holder=\(entries[eventID].map { $0.surface.map { "\($0.viewportMode) hidden=\($0.isHiddenInWindow)" } ?? "none" } ?? "no entry")")
            surface.reclaim()
        }
    }

    #if DEBUG || SPIRAL_STAGING
    /// Whether this registry has heard of a post, for a surface's trace.
    func remembers(_ eventID: String) -> Bool {
        entries[eventID] != nil
    }
    #endif

    private func repairSurfacesShowingNothing() {
        for (eventID, entry) in entries {
            // A mount that never answers. The shell settles its promise and
            // the host bounds the wait, so this should be unreachable — which
            // is exactly why it is worth saying out loud if it happens, rather
            // than leaving a post behind its card in silence as it did for a
            // day. 35 of 411 mounts returned nothing at all, and no instrument
            // we had could see it.
            if entry.slot.phase == .loading,
               let since = entry.loadingSince,
               Date().timeIntervalSince(since) > Self.longestReasonableMount {
                MXLog.error("[SpiralApp] \(eventID) has been loading for \(Int(Date().timeIntervalSince(since)))s — its mount never answered")
                entries[eventID]?.loadingSince = nil
            }

            // A post the reader can SEE, with no app and nothing on the way,
            // is the grey rectangle — and every path that leads here is one
            // the events did not cover. A post refused for want of a host
            // used to wait for the next `didMoveToWindow` or for a row to
            // leave; `scheduleReassert` could not save it either, because it
            // is a debounce and a slow continuous scroll cancels it on every
            // frame. Measured: a post that lost its host waited a MEDIAN of
            // 3.4 s to get one back, and the longest waited 129 s, while the
            // mount itself takes 46 ms (Public 0067, 2026-09-21).
            //
            // So the same half-second that repairs a missing container also
            // asks again for a missing app. `makeRoom` still decides whether
            // there is one to give.
            if entry.instance == nil, entry.arming == nil, !entry.isBackingOff,
               let surface = entry.surface, surface.isOnScreen, surface.mayRunAutomatically,
               couldFindAHost {
                arm(eventID)
                continue
            }

            guard entry.instance != nil,
                  entry.arming == nil,
                  let surface = entry.surface,
                  surface.isOnScreen,
                  surface.presented == nil else { continue }

            MXLog.error("[SpiralApp] \(eventID) was on screen with a running app and nothing to show — repaired")
            arm(eventID)
        }
    }

    /// Pause every app whose row is in the window but out of sight.
    ///
    /// WebKit counts a web view in a window as visible however far it has
    /// scrolled, so a row kept past the viewport went on animating for nobody,
    /// and `isHidden` changes nothing (`SpiralAppReparentExperimentTests`). Out
    /// of any window its page stops, which is all the app can do without the
    /// shell's help. The app stays live, and its row takes it back as any row
    /// does. So what runs is at most what is on screen, and `maxLiveHosts`
    /// bounds only what is kept.
    private func pauseAppsNobodyCanSee() {
        guard !scrollWatch.isMoving else { return }

        for (eventID, entry) in entries {
            guard let instance = entry.instance,
                  entry.slot.phase == .ready,
                  let surface = entry.surface,
                  surface.viewportMode == .row,
                  surface.visibleFraction == 0,
                  surface.presented === instance.containerView else { continue }

            SpiralAppReturnTrace.left(eventID, "out of sight in its window — paused")
            captureStandIn(eventID)
            surface.clear()
            entry.slot.phase = .away
            entry.session?.sleep()
        }
    }

    /// Have the next host ready before a post asks for it, so that making one
    /// is off the way to that post's first paint.
    ///
    /// One per tick of the watchdog, and only with nothing else going on: a web
    /// view takes the main thread to make, wherever it is made. Only for a post
    /// that could use it, and never past the cap, so a room of one post keeps
    /// no spare process and the web views stay at `maxLiveHosts` in all.
    private func refillPool() {
        guard hasWarmed, mayMakeSpareHost,
              !scrollWatch.isMoving,
              pool.parkedCount == 0,
              liveHostCount + 1 < maxLiveHosts,
              !entries.values.contains(where: { $0.slot.phase == .loading }),
              entries.values.contains(where: { $0.instance == nil && !$0.isWedged && !$0.isBackingOff }) else { return }
        pool.prewarm()
    }

    private var mayMakeSpareHost: Bool {
        !isCovered && noSpareHostsBefore.map { $0 <= .now } ?? true
    }

    /// Whether asking for a host could possibly succeed: a free slot, or a
    /// live app the reader cannot see.
    ///
    /// Checked BEFORE arming from the watchdog, because a mount fetches the
    /// artifact before it asks `makeRoom`, and a post that can never win
    /// would re-fetch every half second for as long as it stayed on screen.
    private var couldFindAHost: Bool {
        liveHostCount < maxLiveHosts || entries.contains { $0.value.instance != nil && !isVisible($0.key) }
    }

    /// How many interrupted starts a post may be given before it keeps its
    /// card. Two, because interruption means contention and contention passes:
    /// if it has not settled by the third try, retrying is not the answer.
    private static let mostInterruptionsWorthRetrying = 2

    /// Longer than this in `.loading` and something is wrong, not slow. The
    /// host gives a mount 8 s; this is past the point where that has failed.
    private static let longestReasonableMount: TimeInterval = 12

    /// The only way to tell whether a room's apps have actually gone.
    ///
    /// They are held by this, and this is held by the timeline's view model —
    /// so the question "did leaving the room free three web views" has no other
    /// answer from outside. It turned out to be no.
    deinit {
        // The timer holds this only weakly and `releaseAll` invalidates it;
        // a nonisolated deinit may not touch it.
        MXLog.info("[SpiralApp] registry gone")
    }

    /// Number of apps currently live. For tests and for the spike screen.
    var liveHostCount: Int {
        entries.values.count { $0.instance != nil }
    }

    /// Whether one of our sheets covers the room (§ 5.80), or the app is in
    /// the background, which is the same thing to a web view.
    ///
    /// Geometry cannot see a sheet: the rows under it are still in the window
    /// and still "on screen" by every measure this registry has, so the room
    /// kept all six of its apps running under the catalogue — six WebContent
    /// processes nobody could see, while the catalogue ran three more of its
    /// own. Covered, the room runs nothing; uncovered, the posts on screen ask
    /// again and `makeRoom` decides as always.
    var isCovered: Bool {
        isUnderSheet || isInBackground
    }

    /// Two facts, not one: coming back must not uncover a room under a sheet.
    private var isUnderSheet = false
    private var isInBackground = false

    func setCovered(_ covered: Bool) {
        updateCover { isUnderSheet = covered }
    }

    private func updateCover(_ change: () -> Void) {
        let wasCovered = isCovered
        change()
        guard isCovered != wasCovered else { return }

        guard isCovered else {
            MXLog.info("[SpiralApp] uncovered — asking again for the posts on screen")
            for (eventID, entry) in entries {
                guard entry.instance == nil, entry.arming == nil,
                      let surface = entry.surface, surface.isOnScreen, surface.mayRunAutomatically else { continue }
                arm(eventID)
            }
            return
        }

        var stopping: [SpiralAppInstance] = []
        for (eventID, entry) in entries {
            entry.arming?.cancel()
            entries[eventID]?.arming = nil
            guard let instance = entry.instance else { continue }
            captureStandIn(eventID)
            entries[eventID]?.instance = nil
            entry.surface?.clear()
            returnToCard(eventID)
            stopping.append(instance)
        }
        MXLog.info("[SpiralApp] covered — stopping \(stopping.count) — \(ExtensionLogger.formattedMemoryFootprint)")
        // The warm hosts go too: each is a WebContent process of its own, and
        // freeing them is the point. The stops park them first.
        Task { [pool] in
            for instance in stopping {
                await instance.stop()
            }
            pool.drain()
        }
    }

    /// How many posts are holding on to their actions. For tests.
    var keptSessionCount: Int {
        entries.values.count { $0.session != nil }
    }

    /// How many posts the registry is keeping any memory of.
    var rememberedPostCount: Int {
        entries.count
    }

    /// A row's surface entered a window. Arms a mount; does not perform one.
    ///
    /// Called by the surface itself from `didMoveToWindow`, which is the only
    /// statement about visibility this registry believes. SwiftUI's
    /// `onAppear` was tried and is why §5.28 and §5.30 exist: it overshoots,
    /// is unpaired across cell recycling, and can announce a post's new row
    /// before its old row has gone — so "visible" drifted from the screen,
    /// eviction took apps the reader was looking at, and containers went to
    /// rows that no longer existed.
    ///
    /// If the app is already running, the row takes it back as `returnRule`
    /// says — at once by default, moving a web view costing about 3 ms
    /// (Stage-A, 2026-11-12) — and covers it until the page has drawn. A
    /// viewer takes it at once too.
    func surfaceDidEnterWindow(_ surface: SpiralAppSurface, eventID: String, post: SpiralAppPost) {
        #if DEBUG || SPIRAL_STAGING
        if surface.viewportMode == .expanded, let entry = entries[eventID] {
            let row = entry.surface
            SpiralAppReturnTrace.entered(eventID, "VIEWER entered — row phase=\(entry.slot.phase) row presented=\(row?.presented != nil) "
                + "row visible=\(String(format: "%.2f", row?.visibleFraction ?? 0)) standIn=\(SpiralAppReturnTrace.describe(entry.slot.standIn)) moving=\(scrollWatch.isMoving)")
        }
        #endif
        // A viewer closed as fast as it opened never takes the app.
        if surface.viewportMode == .expanded, entries[eventID]?.isViewerClosing == true {
            SpiralAppReturnTrace.step(eventID, "a closing VIEWER entered — the row keeps its app")
            return
        }

        // The row gives its app up to the viewer, and shows this picture of
        // it meanwhile.
        if surface.viewportMode == .expanded, let holder = entries[eventID]?.surface, holder !== surface {
            captureStandIn(eventID)
            if holder.viewportMode == .row {
                entries[eventID]?.row = holder
            }
        }

        // A VIEWER OUTRANKS A ROW. Both surfaces are in a window while the
        // full-screen cover is up — the timeline is simply behind it — and
        // the row re-asserts itself after every scroll (see `scheduleReassert`).
        // Without this the first settle behind the cover pulled the app out of
        // the viewer and the reader was left looking at an empty screen
        // (two simulators, a shared drawing, 2026-09-19).
        if surface.viewportMode == .row,
           let holder = entries[eventID]?.surface,
           holder !== surface,
           holder.viewportMode == .expanded,
           holder.window != nil {
            entries[eventID]?.row = surface
            SpiralAppReturnTrace.step(eventID, "row entered while the VIEWER holds the app — kept for the hand-back; row phase=\(entries[eventID].map { "\($0.slot.phase)" } ?? "-") "
                + "row visible=\(String(format: "%.2f", surface.visibleFraction)) standIn=\(SpiralAppReturnTrace.describe(entries[eventID]?.slot.standIn))")
            return
        }

        adoptEdit(eventID: eventID, post: post)

        if var existing = entries[eventID] {
            existing.surface = surface
            existing.lastWantedAt = .now
            entries[eventID] = existing
            existing.session?.wake()
            if let instance = existing.instance, surface.presented !== instance.containerView {
                SpiralAppReturnTrace.entered(eventID, "phase=\(existing.slot.phase) standIn=\(SpiralAppReturnTrace.describe(existing.slot.standIn)) "
                    + "presented=\(surface.presented === instance.containerView) visible=\(String(format: "%.2f", surface.visibleFraction)) "
                    + "moving=\(scrollWatch.isMoving) arming=\(existing.arming != nil)")
            }
            if let instance = existing.instance {
                show(instance, of: eventID, in: surface)
            } else {
                // Nothing of ours is running for this post, so nothing of
                // ours may be inside this surface — a recycled cell can arrive
                // still holding the previous occupant's container.
                surface.clear()
            }
            // Already live, or already counting down. Either way the row is
            // asking for something in progress.
            guard existing.instance == nil, existing.arming == nil else { return }
        } else {
            surface.clear()
            entries[eventID] = Entry(post: post,
                                     instance: nil,
                                     slot: SpiralAppSlot(),
                                     surface: surface,
                                     arming: nil,
                                     lastWantedAt: .now)
        }

        // A row that may not run its app is still READ: its card owes the
        // reader the newest line and the moment it counts down to.
        guard surface.mayRunAutomatically else {
            read(eventID)
            return
        }
        warmUp()
        arm(eventID)
    }

    /// Give a running app to the surface that asked. Idempotent: a row asks
    /// again after every scroll.
    private func show(_ instance: SpiralAppInstance, of eventID: String, in surface: SpiralAppSurface) {
        guard surface.presented !== instance.containerView else {
            // Two cells for one post (an animated reload): the other one covered this row, and its return found it out
            // of sight. The row still shows the app, so only its cover has to come off.
            if surface.viewportMode == .row, entries[eventID]?.slot.phase == .away, entries[eventID]?.arming == nil {
                SpiralAppReturnTrace.step(eventID, "show — the row already shows the app under its cover, returning")
                returnNow(eventID)
            }
            return
        }

        guard surface.viewportMode == .row else {
            #if DEBUG || SPIRAL_STAGING
            let moveStarted = ContinuousClock.now
            #endif
            surface.present(instance.containerView)
            instance.setViewport(surface.viewportMode)
            // The row has nothing in it now: it covers itself with its picture
            // rather than show an empty frame under the viewer's animation.
            if entries[eventID]?.slot.phase == .ready {
                entries[eventID]?.slot.phase = .away
            }
            #if DEBUG || SPIRAL_STAGING
            SpiralAppReturnTrace.step(eventID, "moved into the VIEWER in \(SpiralAppReturnTrace.milliseconds(moveStarted.duration(to: .now)))ms — row phase stays \(entries[eventID].map { "\($0.slot.phase)" } ?? "-")")
            #endif
            return
        }

        // A recycled cell can arrive still holding the previous occupant's container.
        surface.clear()
        if entries[eventID]?.slot.phase == .ready {
            entries[eventID]?.slot.phase = .away
        }
        SpiralAppReturnTrace.step(eventID, "show — cover on, phase=\(entries[eventID].map { "\($0.slot.phase)" } ?? "-") arming=\(entries[eventID]?.arming != nil) rule=\(returnRule)")
        // A row that bounced out and back keeps the return it had.
        guard entries[eventID]?.arming == nil else { return }
        if returnRule == .atOnce {
            returnNow(eventID)
        } else {
            arm(eventID)
        }
    }

    /// Put a kept app back in its row on the next turn of the main queue, out
    /// of the table's layout pass that added the row. Moving a web view that
    /// already runs costs no mount and no new process, unlike starting one.
    private func returnNow(_ eventID: String) {
        guard !isCovered else { return }
        #if DEBUG
        armings += 1
        #endif
        entries[eventID]?.arming = Task { [weak self] in
            await self?.returnToRow(eventID)
        }
    }

    /// Follow a post's actions, starting the read if nobody has yet.
    ///
    /// For an app about to start, and for a row whose reader hid media (§ 5.79):
    /// the post is somebody else's code and is not run, but what it last SAID
    /// is data, and it was written to be read where the code is not — a card
    /// that stays on its title for ever while «3 of 5 have voted» sits in the
    /// room was the only thing it could show. No web view, no place in the pool.
    @discardableResult
    private func read(_ eventID: String) -> SpiralAppPostSession? {
        guard var entry = entries[eventID] else { return nil }

        if let session = entry.session {
            session.wake()
            session.readIfStale()
            return session
        }

        let session = SpiralAppPostSession(postEventID: eventID,
                                           roomProxy: roomProxy,
                                           feed: feed,
                                           mediaProvider: mediaProvider,
                                           refusals: sendRefusals)
        entry.session = session
        entry.sessionCancellable = Self.follow(session.snapshotPublisher, into: entry.slot, names: memberName)
        entries[eventID] = entry
        Task { await session.start() }
        return session
    }

    /// Let go of the sessions nobody has wanted for longest. A post without
    /// one reads from the start next time, which is all it costs.
    private func trimSessions() {
        let keptCount = entries.values.count { $0.session != nil }
        guard keptCount > Self.maxKeptSessions else { return }

        let idle = entries
            .filter { $0.value.session != nil && $0.value.instance == nil && $0.value.arming == nil && $0.value.surface == nil }
            .sorted { $0.value.lastWantedAt < $1.value.lastWantedAt }

        for (id, entry) in idle.prefix(keptCount - Self.maxKeptSessions) {
            entry.session?.stop()
            entries[id]?.session = nil
            entries[id]?.sessionCancellable = nil
        }
    }

    /// What the card shows when no code runs: the newest summary's line, and
    /// the moment it counts down to. A summary with neither says nothing new;
    /// one with a line and no countdown clears the countdown, because the
    /// post has stopped counting.
    private static func follow(_ snapshots: AnyPublisher<SpiralAppStateReader.Snapshot, Never>,
                               into slot: SpiralAppSlot,
                               names: @escaping (String) -> String) -> AnyCancellable {
        snapshots
            .compactMap(\.summary)
            .filter { $0.line != nil || $0.countdownTo != nil }
            .removeDuplicates()
            .sink { [weak slot] summary in
                if let line = summary.line {
                    slot?.summaryLine = line
                    slot?.summaryWriter = summary.writer.map { ($0, names($0)) }
                }
                slot?.summaryCountdown = summary.countdownTo
            }
    }

    /// A member's name as the room shows it, or their id.
    private var memberName: (String) -> String {
        { [roomProxy] userID in
            let member = roomProxy.membersPublisher.value.first { $0.userID == userID }
            return member?.disambiguatedDisplayName ?? member?.displayName ?? userID
        }
    }

    /// A row is about to leave its window, with its web view still in it.
    func surfaceWillLeaveWindow(_ surface: SpiralAppSurface, eventID: String) {
        if entries[eventID]?.instance != nil, entries[eventID]?.surface !== surface {
            SpiralAppReturnTrace.step(eventID, "a \(surface.viewportMode) surface not holding the app will leave its window — presented=\(surface.presented != nil)")
        }
        guard entries[eventID]?.surface === surface else { return }
        if entries[eventID]?.instance != nil {
            SpiralAppReturnTrace.step(eventID, "\(surface.viewportMode) will leave its window — phase=\(entries[eventID].map { "\($0.slot.phase)" } ?? "-") presented=\(surface.presented != nil) visible=\(String(format: "%.2f", surface.visibleFraction))")
        }
        captureStandIn(eventID)
    }

    /// Take the picture a row shows while its app is away.
    ///
    /// Once per leaving, never on a state change: a snapshot after each change
    /// is what made the picture-based registries lag (§ 5.33). Only of an app
    /// that is on show in its row: there is nothing else to take.
    private func captureStandIn(_ eventID: String) {
        #if DEBUG || SPIRAL_STAGING
        if let entry = entries[eventID], let instance = entry.instance {
            let surface = entry.surface
            SpiralAppReturnTrace.step(eventID, "capture? phase=\(entry.slot.phase) surface=\(surface != nil) mode=\(surface.map { "\($0.viewportMode)" } ?? "-") "
                + "window=\(surface?.window != nil) presented=\(surface?.presented === instance.containerView) "
                + "visible=\(String(format: "%.2f", surface?.visibleFraction ?? 0)) had=\(SpiralAppReturnTrace.describe(entry.slot.standIn))")
        }
        let requested = ContinuousClock.now
        #endif
        guard let entry = entries[eventID],
              let instance = entry.instance,
              entry.slot.phase == .ready,
              let surface = entry.surface,
              surface.viewportMode == .row,
              surface.window != nil,
              surface.visibleFraction >= Self.standInVisibility,
              surface.presented === instance.containerView else { return }

        instance.takeSnapshot { [weak self, weak slot = entry.slot] image in
            #if DEBUG || SPIRAL_STAGING
            SpiralAppReturnTrace.step(eventID, "snapshot \(SpiralAppReturnTrace.describe(image)) in \(SpiralAppReturnTrace.milliseconds(requested.duration(to: .now)))ms "
                + "— row in window now: \(self?.entries[eventID]?.surface?.window != nil)")
            #endif
            // A blank picture is worse than the card, and never replaces a good one.
            guard let image, let slot, !SpiralAppStandInPicture.isBlank(image) else { return }
            slot.standIn = image
            self?.limitStandIns()
        }
    }

    /// The picture of an app just revealed. Taken at once it came back blank
    /// on Stage-A, as did one taken under a moving table; half a second
    /// later, on a still one, it is the page.
    private func captureSoon(_ eventID: String) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.pictureAfterReveal)
            guard let self, !scrollWatch.isMoving else { return }
            captureStandIn(eventID)
        }
    }

    /// Once per rest of the table, a picture of every live post in sight:
    /// what its row shows when it next comes back. Never on a state change
    /// (§ 5.33); the operator accepted one per scroll stop (2026-11-12).
    private func captureStandInsInSight() {
        for eventID in entries.keys {
            captureStandIn(eventID)
        }
    }

    /// Bounded like the entries: posts with a row keep theirs, and of the
    /// others the coldest let go.
    private func limitStandIns() {
        let idle = entries.values
            .filter { $0.slot.standIn != nil && $0.surface == nil }
            .sorted { $0.lastWantedAt < $1.lastWantedAt }

        for entry in idle.dropLast(Self.maxStandIns) {
            entry.slot.standIn = nil
        }
    }

    /// A row's surface left its window. Cancels an unfired arming — and
    /// nothing else.
    ///
    /// A running app is KEPT. It was not always, and that was the bug behind
    /// every blank post: a row leaving tore its `WKWebView` down that instant,
    /// and a timeline does not leave politely. Jumping to a pinned event makes
    /// rows leave and return several times a second — measured at ten web views
    /// built and destroyed in sixteen seconds for three posts — and what
    /// survived that churn went blank and stayed blank: alive, correctly sized,
    /// holding the right DOM, painting nothing.
    ///
    /// Keeping the app costs a web view that nobody is looking at, which is
    /// bounded by `maxLiveHosts` and is what eviction is for. Destroying it
    /// cost a fetch, a transpile, a fresh realm and a state re-read every time
    /// a row so much as flinched — and a reader watching a card turn back into
    /// an app for no reason they caused.
    ///
    /// Only THIS surface's departure counts. Cell recycling means a post can
    /// briefly have two surfaces; the old one leaving must not unregister the
    /// new one.
    func surfaceDidLeaveWindow(_ surface: SpiralAppSurface, eventID: String) {
        guard var entry = entries[eventID], entry.surface === surface else { return }
        if entry.instance != nil {
            SpiralAppReturnTrace.left(eventID, "\(surface.viewportMode) left its window — phase=\(entry.slot.phase) standIn=\(SpiralAppReturnTrace.describe(entry.slot.standIn))")
        }

        entry.surface = nil
        // A kept app's return is cancelled only if the row stays gone: a cell
        // re-hosted mid-scroll leaves and is back in a millisecond, and
        // restarting its wait each time put its app back later. A mount's
        // countdown goes at once, so the entry can be forgotten.
        if entry.instance == nil {
            entry.arming?.cancel()
            entry.arming = nil
        }
        entries[eventID] = entry
        if entry.instance != nil, let arming = entry.arming {
            Task { [weak self] in
                try? await Task.sleep(for: Self.rowBounce)
                guard let self, entries[eventID]?.surface == nil, entries[eventID]?.arming == arming else { return }
                arming.cancel()
                entries[eventID]?.arming = nil
            }
        }
        if entry.slot.phase == .ready {
            entry.slot.phase = .away
        }
        entry.session?.sleep()

        forgetColdestIfCrowded()
        trimSessions()
        limitStandIns()

        // A row leaving is the only event that can make room while the reader
        // stays put. A visible post that found the pool full when it arrived
        // is still waiting, and this is its cue.
        armMostVisibleWaitingPost()
    }

    /// Whether the reader can see a post's row right now. See
    /// `SpiralAppSurface.isOnScreen` for why this is geometry and not
    /// membership of a window.
    private func isVisible(_ eventID: String) -> Bool {
        visibility(eventID) > 0
    }

    /// How much of this post the reader can see, from 0 to 1. The registry
    /// ranks by this rather than by who asked first: a timeline has no fair
    /// order to be fair about, only a reader looking somewhere.
    private func visibility(_ eventID: String) -> CGFloat {
        entries[eventID]?.surface?.visibleFraction ?? 0
    }

    /// How much more visible a newcomer must be before it is worth taking a
    /// host from someone. Without a margin two rows of nearly equal share swap
    /// the same host back and forth for as long as the reader keeps scrolling:
    /// 184 evictions in one pass through twelve posts, none of which put an
    /// app anywhere it stayed.
    private static let visibilityWorthEvictingFor: CGFloat = 0.2

    /// The touch gate of the app running for `eventID`, if one is (M2): what decides whether the app may take the
    /// whole screen.
    func activation(for eventID: String) -> SpiralAppActivation? {
        entries[eventID]?.instance?.activation
    }

    /// What the row for this post should watch.
    ///
    /// Created on demand, and yes that means a read has an effect. The row is
    /// built before it appears, and it needs something observable at that
    /// moment or it can never be told an app has started — so the alternatives
    /// are this or a row that draws its card for ever.
    ///
    /// Bounded rather than left to grow: an entry made this way is stamped
    /// `.distantPast`, so it is the FIRST thing `forgetColdestIfCrowded` drops.
    /// The registry is not observable, so this cannot invalidate a view mid
    /// update either.
    func slot(for eventID: String, post: SpiralAppPost) -> SpiralAppSlot {
        // An empty id is not an id. A post still on its way to the server
        // cannot run — its state lives under the event id it does not have —
        // so it gets a slot of its own and the registry never hears of it.
        // Every such post once shared the key `""`, which made them watch each
        // other and left entries nothing could arm.
        guard !eventID.isEmpty else { return SpiralAppSlot() }

        if let existing = entries[eventID]?.slot {
            return existing
        }

        let slot = SpiralAppSlot()
        entries[eventID] = Entry(post: post,
                                 instance: nil,
                                 slot: slot,
                                 surface: nil,
                                 arming: nil,
                                 lastWantedAt: .distantPast)
        warmUp()
        return slot
    }

    /// A post row has arrived and will want a host: start one now, so that its
    /// process and shell come up during the settle instead of after it.
    ///
    /// Never in the frame the row arrives in, and never under a moving table.
    /// A row that was only flicked past, or that may not run, costs nothing.
    private func warmUp() {
        guard warming == nil else { return }
        warming = Task { [weak self] in
            try? await Task.sleep(for: Self.settleBeforeReturn)
            await self?.scrollWatch.untilStill()
            guard !Task.isCancelled, let self else { return }
            warming = nil
            guard mayMakeSpareHost, liveHostCount < maxLiveHosts, entries.values.contains(where: \.wantsHost) else { return }
            hasWarmed = true
            pool.prewarm()
        }
    }

    /// Everything goes. Called when the timeline itself goes away, by
    /// `SpiralAppTeardown` — see there for why the signal is an object's death
    /// rather than this registry's own.
    ///
    /// Logs the footprint on the way out, but that number is the least useful
    /// thing here: a `WKWebView`'s real cost is its WebContent process, which
    /// this process's footprint does not see at all. Count processes to judge
    /// it (`ps | grep WebKit.WebContent`), not megabytes.
    func releaseAll() {
        invariantWatch?.invalidate()
        invariantWatch = nil
        appObservers.removeAll()
        warming?.cancel()
        scrollWatch.stop()
        let liveBefore = liveHostCount
        var stopping: [SpiralAppInstance] = []
        for (id, entry) in entries {
            entry.arming?.cancel()
            entry.surface?.clear()
            returnToCard(id)
            if let instance = entry.instance {
                stopping.append(instance)
            }
            entry.session?.stop()
            entries[id] = nil
        }

        // The stops give hosts back to the pool as they finish; drain once
        // they all have, or a warm shell for a room nobody is in would
        // outlive the room. Awaited rather than yielded to: a stop takes as
        // long as its app takes to leave, up to the unmount deadline.
        Task { [pool] in
            for instance in stopping {
                await instance.stop()
            }
            pool.drain()
        }

        if liveBefore > 0 {
            MXLog.info("[SpiralApp] released \(liveBefore) — \(ExtensionLogger.formattedMemoryFootprint)")
        }
    }

    // MARK: - Private

    /// Drop the coldest idle entries once there are too many to be worth
    /// remembering. Never touches anything live or counting down.
    private func forgetColdestIfCrowded() {
        guard entries.count > Self.maxRememberedPosts else { return }

        // A post with a row is not idle, whatever else it is doing.
        let idle = entries
            .filter { $0.value.instance == nil && $0.value.arming == nil && $0.value.surface == nil }
            .sorted { $0.value.lastWantedAt < $1.value.lastWantedAt }

        for (id, entry) in idle.prefix(entries.count - Self.maxRememberedPosts) {
            entry.session?.stop()
            entries[id] = nil
        }
    }

    private func mountIfStillWanted(eventID: String) async {
        // The row may have left, or been mounted by an earlier arming, while
        // this one was sleeping.
        guard let entry = entries[eventID], entry.instance == nil else { return }
        guard !entry.isWedged, !entry.isBackingOff, !entry.slot.needsNewerApp else {
            entries[eventID]?.arming = nil
            return
        }

        // Say so before the fetch, not after: on a cold cache this is where
        // the time goes, and a row that looks idle while it works is the one
        // people tap twice.
        entry.slot.phase = .loading
        entry.slot.couldNotStart = false
        entries[eventID]?.loadingSince = .now

        // Three things that used to run one after the other: the download, the
        // read of the post's actions, and a web view's process and shell.
        guard let session = read(eventID) else { return }
        let fetching = Task { [artifacts, post = entry.post] in await artifacts.artifact(for: post) }
        if liveHostCount < maxLiveHosts {
            pool.prewarm()
        }

        switch await fetching.value {
        case .failure(let error):
            // A post that cannot be fetched keeps its quiet card, and asks
            // again after a while.
            MXLog.info("[SpiralApp] not mounting \(eventID): \(error)")
            entries[eventID]?.arming = nil
            returnToCard(eventID)
            noteFailure(eventID)
            return
        case .success(let artifact):
            // Awaiting the fetch means the world may have moved again — a
            // sheet may have come up over the room while it was on its way,
            // the row may have left, or the table may be moving.
            await scrollWatch.untilStill()
            guard let current = entries[eventID], current.instance == nil else { return }
            // A row in the window but out of sight has nobody to start for.
            guard !isCovered, current.surface?.isOnScreen == true else {
                entries[eventID]?.arming = nil
                returnToCard(eventID)
                return
            }

            // Everything live may be on screen, and a running app the reader
            // can see outranks one that has only just arrived. The newcomer
            // keeps its card and is armed again from `postDidDisappear`.
            guard await makeRoom(for: eventID) else {
                #if DEBUG
                let holders = entries
                    .filter { $0.value.instance != nil }
                    .map { "\($0.key.prefix(7))\(isVisible($0.key) ? "|seen" : "|unseen")" }
                    .joined(separator: " ")
                MXLog.info("[SpiralApp] no room for \(eventID.prefix(7)) — holders: \(holders)")
                // The geometry the answer above came from. Seven posts once
                // reported themselves on screen where three fit, and no amount
                // of reading the decision could show why — only the frames
                // could, and they did: rows tile the timeline, so five or six
                // always touch the window and two or three of those are
                // slivers. Cheap, DEBUG-only, and worth more than any log line
                // about what the registry decided.
                let seen = entries.compactMap { id, entry -> String? in
                    guard let surface = entry.surface, let window = surface.window else { return nil }
                    let frame = surface.convert(surface.bounds, to: window)
                    guard frame.intersects(window.bounds) else { return nil }
                    return "\(id.prefix(7))@\(Int(frame.minY))..\(Int(frame.maxY))h\(Int(frame.height))"
                }.sorted()
                MXLog.info("[SpiralApp] window \(Int(entries.values.compactMap { $0.surface?.window?.bounds.height }.first ?? 0))pt — on screen: \(seen.joined(separator: " "))")
                #endif
                entries[eventID]?.arming = nil
                returnToCard(eventID)
                return
            }

            let instance = SpiralAppInstance(session: session, pool: pool)
            entries[eventID]?.instance = instance
            entries[eventID]?.arming = nil

            // iOS kills the content processes of web views it thinks nobody is
            // looking at, and a timeline can hold several — so this is normal
            // operation, not an edge case. Without it the row keeps a correctly
            // sized, correctly placed, permanently blank rectangle.
            instance.onContentProcessDied = { [weak self] in
                self?.contentProcessDied(eventID: eventID)
            }

            // Into the surface BEFORE the app starts, not after. A `WKWebView`
            // that is not in a window has no viewport to render into, and an
            // app that booted into one stayed blank for good. The surface is
            // in a window — that is what being here means — so the container
            // is on screen from the first frame the shell paints. The card
            // covers it until the app says it has drawn.
            entries[eventID]?.surface?.present(instance.containerView)
            if let mode = entries[eventID]?.surface?.viewportMode { instance.setViewport(mode) }

            let outcome = await instance.start(artifact, instanceID: eventID)
            if outcome != .started {
                // Something else already took this instance down — an
                // eviction, a release — so the row is already a card and this
                // has nothing left to say.
                guard entries[eventID]?.instance === instance else { return }
                entries[eventID]?.instance = nil
                entries[eventID]?.surface?.clear()
                returnToCard(eventID)
                if await instance.stop() == .wedged {
                    noteWedged(eventID)
                    return
                }

                // The post can't be read, so it must not look read: the card
                // says so, and the read gets another try after a while.
                if outcome == .unreadable {
                    noteFailure(eventID)
                    return
                }

                if outcome == .needsNewerApp {
                    entries[eventID]?.slot.needsNewerApp = true
                    entries[eventID]?.slot.standIn = nil
                    return
                }

                // An INTERRUPTED start is not a broken app: its slot was taken
                // while it was starting, or the page churned under the call.
                // Leaving it as a card would be final, and it was — two posts
                // ended a session that way, sitting on screen while everything
                // around them ran. Give it another turn, but only while it is
                // still worth looking at and only so many times, because the
                // one thing worse than a card is a post that reloads for ever.
                if outcome == .interrupted, isVisible(eventID), entries[eventID]?.startsInterrupted ?? 0 < Self.mostInterruptionsWorthRetrying {
                    entries[eventID]?.startsInterrupted += 1
                    MXLog.info("[SpiralApp] \(eventID) was interrupted while starting — trying again")
                    arm(eventID)
                }
                return
            }

            // One last look: starting is a suspension point, and a fast reader
            // can leave during it.
            guard entries[eventID]?.instance === instance else {
                await instance.stop()
                return
            }

            // `start` waits for the app to have drawn, so this is the first
            // moment there is anything to reveal — if the row still has it.
            // `start` awaits, and a timeline does not hold still for that: the
            // row may have been recycled, and a new row takes the app back by
            // itself once the table has stopped. Revealing before that would
            // lift the cover off an empty rectangle.
            let isInItsRow = entries[eventID]?.surface.map { $0.viewportMode == .row && $0.presented === instance.containerView } ?? false
            entries[eventID]?.slot.phase = isInItsRow ? .ready : .away
            // A table rest came before the start, so this is the post's first
            // picture: without it, a reader who flicks away at once comes back to the card.
            if isInItsRow {
                captureSoon(eventID)
            }
            // The app may ask for the screen from here on; only the row knows
            // where that is, so the slot carries the request out.
            if let slot = entries[eventID]?.slot {
                instance.onExpandRequested = { [weak slot] in slot?.requestExpand() }
            }
            entries[eventID]?.loadingSince = nil
            entries[eventID]?.startsInterrupted = 0
            entries[eventID]?.retriedAfterDeath = false
            entries[eventID]?.failures = 0
            entries[eventID]?.notBefore = nil

            MXLog.info("[SpiralApp] mounted \(eventID) — \(liveHostCount) live, \(ExtensionLogger.formattedMemoryFootprint)")
        }
    }

    /// The row has been waiting for the table to stop: it takes its app back.
    ///
    /// The cover stays on until the page has drawn here: a web view back in a
    /// window shows nothing for a frame or several, and that gap was the white
    /// card of the phone recording (question 359).
    private func returnToRow(_ eventID: String) async {
        entries[eventID]?.arming = nil
        guard let entry = entries[eventID], let instance = entry.instance,
              let surface = entry.surface, surface.window != nil else { return }
        // A row just past the viewport under a moving table is about to be
        // seen; one past it under a still table is not, and the table's rest
        // asks every row again.
        guard surface.isOnScreen || (returnRule == .atOnce && scrollWatch.isMoving) else {
            SpiralAppReturnTrace.step(eventID, "not returning yet — on screen=false moving=\(scrollWatch.isMoving)")
            if returnRule != .atOnce, scrollWatch.isMoving {
                arm(eventID)
            }
            return
        }

        #if DEBUG || SPIRAL_STAGING
        let moveStarted = ContinuousClock.now
        let interval = SpiralAppReturnTrace.signposter.beginInterval("move")
        #endif
        surface.present(instance.containerView)
        #if DEBUG || SPIRAL_STAGING
        SpiralAppReturnTrace.signposter.endInterval("move", interval)
        let moveCost = moveStarted.duration(to: .now)
        SpiralAppReturnTrace.step(eventID, "presented in \(String(format: "%.2f", Double(moveCost.components.attoseconds) / 1e15 + Double(moveCost.components.seconds) * 1000))ms — "
            + "phase=\(entry.slot.phase) visible=\(String(format: "%.2f", surface.visibleFraction)) speed=\(Int(scrollWatch.speed))pt/s rule=\(returnRule)")
        #endif
        // Told before it is asked to draw: back from the viewer, the page lays
        // itself out again at the row's size, and the cover waits for that.
        await instance.applyViewport(surface.viewportMode)
        // A starting app keeps its cover until `start` says it has drawn.
        guard entry.slot.phase == .away else { return }

        #if DEBUG || SPIRAL_STAGING
        let asked = ContinuousClock.now
        #endif
        let hasDrawn = await instance.waitForLayout(surface.bounds.size)
        #if DEBUG || SPIRAL_STAGING
        SpiralAppReturnTrace.step(eventID, "page drew=\(hasDrawn) in \(SpiralAppReturnTrace.milliseconds(asked.duration(to: .now)))ms "
            + "— still ours=\(entries[eventID]?.instance === instance && surface.presented === instance.containerView)")
        #endif
        guard entries[eventID]?.instance === instance, surface.presented === instance.containerView else { return }

        if hasDrawn {
            SpiralAppReturnTrace.step(eventID, "cover off")
            entry.slot.phase = .ready
            captureSoon(eventID)
        } else {
            replaceSilentApp(eventID, instance)
        }
    }

    /// An app that has stopped drawing shows a still picture for ever while
    /// looking alive. It costs its host, and counts as a wedge.
    private func replaceSilentApp(_ eventID: String, _ instance: SpiralAppInstance) {
        MXLog.error("[SpiralApp] \(eventID) did not draw on coming back — replacing it")
        entries[eventID]?.instance = nil
        entries[eventID]?.surface?.clear()
        returnToCard(eventID)
        Task { await instance.discard() }
        noteWedged(eventID)
        if entries[eventID]?.isWedged == false {
            arm(eventID)
        }
    }

    /// The full-screen viewer has started to close: the app goes back to its
    /// row now, while the viewer slides away showing a picture of it.
    ///
    /// Waiting for the dismissal to end left the row an empty grey frame for
    /// the half second of the animation, then showed the page laid out at the
    /// viewer's size for a frame (Stage-A, 2026-11-12).
    ///
    /// The expand gate closes here too, not only at `onDismiss`: the row is
    /// ready again while the viewer still slides away, and a touch made inside
    /// the viewer must not reopen it in that gap (M2; Fable review, 412).
    func viewerWillClose(eventID: String) {
        guard entries[eventID] != nil else { return }
        entries[eventID]?.isViewerClosing = true
        entries[eventID]?.instance?.activation.viewerDismissed()
        guard let entry = entries[eventID],
              let instance = entry.instance,
              let viewer = entry.surface,
              viewer.viewportMode == .expanded,
              let row = entry.row,
              row.window != nil,
              // A row the table has hidden for reuse is in the window and sees nothing (question 411):
              // the viewer keeps the app, and the row in sight takes it at `onDismiss`.
              !row.isHiddenInWindow else {
            SpiralAppReturnTrace.step(eventID, "viewer closing — nothing to hand back (holder=\(entries[eventID]?.surface.map { "\($0.viewportMode)" } ?? "none") "
                + "row hidden=\(entries[eventID]?.row?.isHiddenInWindow ?? false))")
            return
        }

        final class Latch {
            var isClosed = false
        }
        let latch = Latch()
        let handBack: @MainActor () -> Void = { [weak self] in
            guard !latch.isClosed else { return }
            latch.isClosed = true
            self?.handBack(eventID, instance, from: viewer, to: row)
        }
        #if DEBUG || SPIRAL_STAGING
        let asked = ContinuousClock.now
        #endif
        instance.takeSnapshot { [weak viewer] image in
            #if DEBUG || SPIRAL_STAGING
            SpiralAppReturnTrace.step(eventID, "viewer picture \(SpiralAppReturnTrace.describe(image)) in \(SpiralAppReturnTrace.milliseconds(asked.duration(to: .now)))ms")
            #endif
            if !latch.isClosed, let image, !SpiralAppStandInPicture.isBlank(image) {
                viewer?.showStill(image)
            }
            handBack()
        }
        // A picture that doesn't come at once isn't worth the row's wait.
        Task {
            try? await Task.sleep(for: Self.viewerPictureDeadline)
            handBack()
        }
    }

    private func handBack(_ eventID: String, _ instance: SpiralAppInstance, from viewer: SpiralAppSurface, to row: SpiralAppSurface) {
        // A row recycled for another post while the viewer was up is not this post's row any more.
        // One hidden for reuse meanwhile can't show it.
        guard entries[eventID]?.instance === instance, entries[eventID]?.surface === viewer,
              row.window != nil, !row.isHiddenInWindow, row.eventID == eventID else { return }
        SpiralAppReturnTrace.step(eventID, "hand-back to the row — viewer still in window=\(viewer.window != nil)")
        entries[eventID]?.surface = row
        entries[eventID]?.row = nil
        if entries[eventID]?.slot.phase == .ready {
            entries[eventID]?.slot.phase = .away
        }
        entries[eventID]?.arming?.cancel()
        entries[eventID]?.arming = Task { [weak self] in
            await self?.returnToRow(eventID)
        }
    }

    /// The full-screen viewer for `eventID` closed: the app may not open it
    /// again on a touch made inside it (M2).
    func viewerDismissed(eventID: String) {
        entries[eventID]?.isViewerClosing = false
        entries[eventID]?.row = nil
        SpiralAppReturnTrace.step(eventID, "viewer onDismiss — phase=\(entries[eventID].map { "\($0.slot.phase)" } ?? "-") "
            + "holder=\(entries[eventID]?.surface.map { "\($0.viewportMode)" } ?? "none") standIn=\(SpiralAppReturnTrace.describe(entries[eventID]?.slot.standIn))")
        entries[eventID]?.instance?.activation.viewerDismissed()
    }

    /// The system killed an app's content process.
    ///
    /// Treated as an eviction, because that is what it is from here: the app is
    /// gone and the row must stop pretending otherwise. The card comes back
    /// with the last thing the app said, which is why that line is kept.
    ///
    /// Then ONE retry at once. A kill is usually the system reclaiming a web
    /// view nobody is looking at, and remounting is exactly right for that. But
    /// it is also what happens when memory has run out — and that is precisely
    /// when a retry loop would be worst, so a second death before the post has
    /// started again backs off. A start forgives a death, and no death is final.
    private func contentProcessDied(eventID: String) {
        guard let entry = entries[eventID], let instance = entry.instance else { return }

        entries[eventID]?.instance = nil
        entry.surface?.clear()
        returnToCard(eventID)
        // Discarded, not stopped: a host with a dead process has no warm shell
        // to give back, and parking it would poison the pool.
        Task { await instance.discard() }

        guard !entry.retriedAfterDeath else {
            MXLog.error("[SpiralApp] \(eventID) lost its content process twice — backing off")
            noteFailure(eventID)
            return
        }

        MXLog.info("[SpiralApp] \(eventID) lost its content process — remounting once")
        entries[eventID]?.retriedAfterDeath = true
        arm(eventID)
    }

    /// Evict the coldest live host that is OFF SCREEN, if the pool is full.
    ///
    /// Returns whether there is now room. There may not be: when every live app
    /// is on screen, the reader is looking at all of them, and taking one down
    /// to start another swaps a working app for a card in front of their eyes.
    /// The newcomer waits instead. It is armed again the moment any row leaves.
    ///
    /// The footprint is logged on both sides of this because `maxLiveHosts`
    /// was measured under the OLD rule, where a row leaving took its app down.
    /// Apps are kept now, so four of them can sit in memory for as long as the
    /// reader stays in the room — which is either fine or the reason to lower
    /// the number, and the log is how that gets decided from evidence.
    private func makeRoom(for eventID: String) async -> Bool {
        while liveHostCount >= maxLiveHosts {
            // The least-seen app gives way to a better-seen one. Ties, and
            // near-ties, go to whoever already has the host — see
            // `visibilityWorthEvictingFor`.
            let newcomer = visibility(eventID)
            // Least seen first; among the equally unseen — which is every
            // post that has scrolled away — the one wanted longest ago, so a
            // post the reader just left still finds its app on the way back.
            let coldest = entries
                .filter { $0.key != eventID && $0.value.instance != nil }
                .min {
                    let (left, right) = (visibility($0.key), visibility($1.key))
                    return left == right ? $0.value.lastWantedAt < $1.value.lastWantedAt : left < right
                }

            // The margin is for two rows the reader can BOTH see. Against a
            // holder that is off screen entirely it only blocks: a post 16 %
            // into view was refused while an app nobody could see kept its
            // host, because 0 + 0.2 is more than 0.16 (measured scrolling
            // Public 0067, 2026-09-21). Nothing is taken from the reader by
            // evicting what the reader cannot see.
            let coldestSeen = coldest.map { visibility($0.key) } ?? 0
            let worthIt = coldestSeen == 0 ? newcomer > 0 : coldestSeen + Self.visibilityWorthEvictingFor <= newcomer
            guard let coldest, let instance = coldest.value.instance, worthIt else { return false }

            MXLog.info("[SpiralApp] evicting \(coldest.key) to make room for \(eventID) — \(ExtensionLogger.formattedMemoryFootprint)")
            captureStandIn(coldest.key)
            entries[coldest.key]?.instance = nil
            coldest.value.surface?.clear()
            returnToCard(coldest.key)
            if coldest.value.surface == nil {
                coldest.value.session?.sleep()
            }
            // Awaited, not fired: the stop is what parks the host, and the
            // acquire that follows this call should find it there. A stop
            // left to run on its own made the next app build a fresh web
            // view a moment before the warm one came back. Bounded: an app
            // that will not leave costs its host, not the newcomer's turn.
            if await instance.stop() == .wedged {
                noteWedged(coldest.key)
            }
        }
        return true
    }

    /// A post failed to start for a reason a moment may cure: a download, or a
    /// read. The card says so, and the wait doubles, so the watchdog's
    /// half-second doesn't turn a dead network into a request a second.
    private func noteFailure(_ eventID: String) {
        guard var entry = entries[eventID] else { return }
        entry.failures += 1
        entry.notBefore = .now + min(Self.longestBackOff, .seconds(1 << min(entry.failures, 6)))
        entry.slot.couldNotStart = true
        // A picture says the post is there, and this one isn't.
        entry.slot.standIn = nil
        entries[eventID] = entry
    }

    /// An app that did not leave when told to. The second time it stays a
    /// card, until the app next comes back from the background.
    private func noteWedged(_ eventID: String) {
        guard entries[eventID] != nil else { return }
        if entries[eventID]?.hasWedged == true {
            MXLog.error("[SpiralApp] \(eventID) wedged its host twice — leaving it as a card")
            entries[eventID]?.isWedged = true
            entries[eventID]?.slot.standIn = nil
        } else {
            MXLog.error("[SpiralApp] \(eventID) wedged its host")
            entries[eventID]?.hasWedged = true
        }
    }

    /// Start the settle-then-mount countdown for a post. Never under a sheet
    /// of ours (`isCovered`): every path that asks for an app comes here.
    ///
    /// Every path that makes or mounts a web view for a row comes here too, so
    /// this is where the table is waited for: that is main-thread work, and the
    /// row's cover stands in meanwhile. A kept app that only moves waits here
    /// only under `whenCalm` and `whenStill`; `atOnce` goes by `returnNow`.
    private func arm(_ eventID: String) {
        guard !isCovered else { return }
        let settle = entries[eventID]?.instance == nil ? Self.settleBeforeMount : Self.settleBeforeReturn
        let isReturn = entries[eventID]?.instance != nil
        // Starting an app makes a web view and mounts it: only on a still table.
        // A kept app only moves, and may come back on a calm one.
        let mayGoOnCalm = isReturn && returnRule != .whenStill
        #if DEBUG
        armings += 1
        #endif
        entries[eventID]?.arming = Task { [weak self] in
            try? await Task.sleep(for: settle)
            if isReturn {
                SpiralAppReturnTrace.step(eventID, "settled \(SpiralAppReturnTrace.milliseconds(settle))ms — table moving=\(self?.scrollWatch.isMoving ?? false)")
            }
            if mayGoOnCalm {
                await self?.scrollWatch.untilCalm()
            } else {
                await self?.scrollWatch.untilStill()
            }
            if isReturn {
                SpiralAppReturnTrace.step(eventID, "table \(mayGoOnCalm ? "calm" : "still") — speed=\(Int(self?.scrollWatch.speed ?? 0))pt/s cancelled=\(Task.isCancelled)")
            }
            guard !Task.isCancelled, let self else { return }
            if entries[eventID]?.instance == nil {
                await mountIfStillWanted(eventID: eventID)
            } else {
                await returnToRow(eventID)
            }
        }
    }

    /// Give the pool's next slot to the visible post that has waited longest.
    ///
    /// Longest, not most recent: the reader has been looking at a card for
    /// that one the longest, and it is the one they are most likely to have
    /// noticed. Whether there is actually room is `makeRoom`'s question — this
    /// only asks.
    private func armMostVisibleWaitingPost() {
        let waiting = entries
            .compactMap { id, entry -> (String, CGFloat)? in
                guard let surface = entry.surface, surface.mayRunAutomatically,
                      entry.instance == nil, entry.arming == nil else { return nil }
                let seen = surface.visibleFraction
                guard seen > 0 else { return nil }
                return (id, seen)
            }
            .max { $0.1 < $1.1 }

        guard let (eventID, _) = waiting else { return }
        arm(eventID)
    }
}

/// Timings of a kept post coming back to its row, in DEBUG and Staging builds
/// only: what the reader sees between the row arriving and the live app
/// (the grey rectangle of 2026-11-12). One line per step, in milliseconds from
/// the row entering its window; grep `[SpiralApp][return]`.
@MainActor
enum SpiralAppReturnTrace {
    #if DEBUG || SPIRAL_STAGING
    private static var since: [String: ContinuousClock.Instant] = [:]
    private static var leftAt: [String: ContinuousClock.Instant] = [:]
    #endif

    /// A row with a running app entered its window: the clock starts.
    static func entered(_ eventID: String, _ details: @autoclosure () -> String) {
        #if DEBUG || SPIRAL_STAGING
        since[eventID] = .now
        let away = leftAt[eventID].map { " — away \(milliseconds($0.duration(to: .now)))ms" } ?? ""
        MXLog.info("[SpiralApp][return] \(eventID.prefix(8)) +0 entered — \(details())\(away)")
        #endif
    }

    /// The app left the reader's sight: a row left its window, or was cleared out of sight.
    static func left(_ eventID: String, _ details: @autoclosure () -> String) {
        #if DEBUG || SPIRAL_STAGING
        leftAt[eventID] = .now
        since[eventID] = nil
        MXLog.info("[SpiralApp][return] \(eventID.prefix(8)) left — \(details())")
        #endif
    }

    /// A step, timed from the row entering (or from leaving, before it has come back).
    static func step(_ eventID: String, _ details: @autoclosure () -> String) {
        #if DEBUG || SPIRAL_STAGING
        let clock: String
        if let start = since[eventID] {
            clock = "+\(milliseconds(start.duration(to: .now)))"
        } else if let left = leftAt[eventID] {
            clock = "left+\(milliseconds(left.duration(to: .now)))"
        } else {
            clock = "-"
        }
        MXLog.info("[SpiralApp][return] \(eventID.prefix(8)) \(clock) \(details())")
        #endif
    }

    /// Any line, with no post.
    static func note(_ details: @autoclosure () -> String) {
        #if DEBUG || SPIRAL_STAGING
        MXLog.info("[SpiralApp][return] \(details())")
        #endif
    }

    /// Size, and whether each half of the picture holds anything but one colour.
    static func describe(_ image: UIImage?) -> String {
        #if DEBUG || SPIRAL_STAGING
        guard let image else { return "none" }
        let size = "\(Int(image.size.width))x\(Int(image.size.height))@\(Int(image.scale))x"
        guard !SpiralAppStandInPicture.isBlank(image) else { return "\(size) BLANK" }
        let top = SpiralAppStandInPicture.isBlank(image, half: .top) ? "blank" : "drawn"
        let bottom = SpiralAppStandInPicture.isBlank(image, half: .bottom) ? "blank" : "drawn"
        return "\(size) drawn (top \(top), bottom \(bottom))"
        #else
        return ""
        #endif
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    #if DEBUG || SPIRAL_STAGING
    /// Instruments' view of the same moves: `move` intervals under `com.spiral.app`.
    static let signposter = OSSignposter(subsystem: "com.spiral.app", category: "SpiralAppReturn")
    #endif
}

/// Whether a picture of an app is worth standing in for it.
enum SpiralAppStandInPicture {
    enum Half {
        case top
        case bottom
    }

    /// One colour everywhere, to within a few levels, on a 16x16 reduction:
    /// what WebKit hands back for a web view it has stopped drawing. The card
    /// says more than that.
    static func isBlank(_ image: UIImage, half: Half? = nil) -> Bool {
        guard var cgImage = image.cgImage else { return true }
        if let half {
            let height = cgImage.height / 2
            let rect = CGRect(x: 0, y: half == .top ? 0 : height, width: cgImage.width, height: height)
            guard let cropped = cgImage.cropping(to: rect) else { return true }
            cgImage = cropped
        }

        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }

        for channel in 0..<4 {
            let values = stride(from: channel, to: pixels.count, by: 4).map { pixels[$0] }
            if let low = values.min(), let high = values.max(), Int(high) - Int(low) > 8 {
                return false
            }
        }
        return true
    }
}

#if DEBUG || SPIRAL_STAGING
/// Frame gaps while the table moves: how many frames came late, and by how much.
@MainActor
final class SpiralAppFrameProbe: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private var frames = 0
    private var late = 0
    private var hitch: CFTimeInterval = 0
    private var worst: CFTimeInterval = 0

    override init() {
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let expected = link.targetTimestamp - link.timestamp
        if let last {
            let gap = link.timestamp - last
            worst = max(worst, gap)
            if gap > expected * 1.5 {
                late += 1
                hitch += gap - expected
            }
        }
        last = link.timestamp
        frames += 1
    }

    func finish() -> String {
        link?.invalidate()
        link = nil
        return "\(frames) frames, \(late) late, \(Int(hitch * 1000))ms hitch, worst \(Int(worst * 1000))ms"
    }
}
#endif
