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
        /// The app has drawn something.
        case ready
    }

    @Published fileprivate(set) var phase: Phase = .waiting

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

    // A row leaving the screen does NOT take its app down. Only eviction and
    // the timeline going away do. See `postDidDisappear`.

    private struct Entry {
        /// `var`: an edit (`m.replace`) keeps the event id and changes the
        /// artifact, and the entry follows it (§ 5.55).
        var post: SpiralAppPost
        /// The running app: a session bound to a host. Lives and dies with
        /// visibility. The state itself is in Matrix, so a post that scrolls
        /// away and back re-reads rather than remembers — cheap, because the
        /// settle stops a flick from doing it at all.
        var instance: SpiralAppInstance?
        let slot: SpiralAppSlot
        /// The row's surface while that row is in a window, nil otherwise.
        /// THIS is what "visible" means here — a UIKit fact reported by the
        /// surface itself on `didMoveToWindow`, not a SwiftUI hint. When the
        /// app is running, its container is inside this surface.
        weak var surface: SpiralAppSurface?
        var summaryCancellable: AnyCancellable?
        var arming: Task<Void, Never>?
        /// Bumped whenever this post becomes visible, so the least recently
        /// wanted host is the one to take when the pool is full.
        var lastWantedAt: Date
        /// When this post started loading, so a mount that never answers can
        /// be seen. Nil once it is running or back to a card.
        var loadingSince: Date?
        /// Whether this post has already been given a second chance after the
        /// system killed its content process. See `contentProcessDied`.
        var retriedAfterDeath = false
        /// How many times a start was interrupted by something that was not
        /// this app's fault. Bounded so a post cannot reload for ever.
        var startsInterrupted = 0
        /// The post's actions, read with no app running — for a row that may
        /// not run one (media hidden) and still owes its card the newest line
        /// and countdown (§ 5.79). No web view, no place in the pool; only
        /// while the row is in a window.
        var reader: SpiralAppPostSession?
        var readerCancellable: AnyCancellable?
    }

    private var entries: [String: Entry] = [:]
    private var invariantWatch: Timer?
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
         makeHost: @escaping @MainActor () -> SpiralAppHostProtocol) {
        self.artifacts = artifacts
        self.roomProxy = roomProxy
        self.mediaProvider = mediaProvider
        self.maxLiveHosts = maxLiveHosts
        pool = SpiralAppHostPool(makeHost: makeHost)
        feed = SpiralAppActionFeed(roomProxy: roomProxy)
        startInvariantWatch()
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
    private func startInvariantWatch() {
        invariantWatch = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.repairSurfacesShowingNothing() }
        }
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
        entry.summaryCancellable = nil
        entry.surface?.clear()
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
            if entry.instance == nil, entry.arming == nil,
               let surface = entry.surface, surface.isOnScreen, surface.mayRunAutomatically,
               couldFindAHost {
                arm(eventID)
                continue
            }

            guard let instance = entry.instance,
                  let surface = entry.surface,
                  surface.isOnScreen,
                  surface.presented == nil else { continue }

            MXLog.error("[SpiralApp] \(eventID) was on screen with a running app and nothing to show — repaired")
            surface.present(instance.containerView)
            instance.setViewport(surface.viewportMode)
        }
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

    /// Whether one of our sheets covers the room (§ 5.80).
    ///
    /// Geometry cannot see a sheet: the rows under it are still in the window
    /// and still "on screen" by every measure this registry has, so the room
    /// kept all six of its apps running under the catalogue — six WebContent
    /// processes nobody could see, while the catalogue ran three more of its
    /// own. Covered, the room runs nothing; uncovered, the posts on screen ask
    /// again and `makeRoom` decides as always.
    private(set) var isCovered = false

    func setCovered(_ covered: Bool) {
        guard covered != isCovered else { return }
        isCovered = covered

        guard covered else {
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
            entries[eventID]?.instance = nil
            entries[eventID]?.summaryCancellable = nil
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
    /// If the app is already running, its container is shown here at once:
    /// a row that scrolled away and back finds its app rather than a card.
    func surfaceDidEnterWindow(_ surface: SpiralAppSurface, eventID: String, post: SpiralAppPost) {
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
            return
        }

        adoptEdit(eventID: eventID, post: post)

        if var existing = entries[eventID] {
            existing.surface = surface
            existing.lastWantedAt = .now
            entries[eventID] = existing
            if let instance = existing.instance {
                surface.present(instance.containerView)
                instance.setViewport(surface.viewportMode)
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
                                     summaryCancellable: nil,
                                     arming: nil,
                                     lastWantedAt: .now)
        }

        // A row that may not run its app is still READ: its card owes the
        // reader the newest line and the moment it counts down to.
        guard surface.mayRunAutomatically else {
            read(eventID)
            return
        }
        arm(eventID)
    }

    /// Follow a post's actions with no app running (§ 5.79).
    ///
    /// For a row whose reader hid media: the post is somebody else's code and
    /// is not run, but what it last SAID is data, and it was written to be
    /// read where the code is not — a card that stays on its title for ever
    /// while «3 of 5 have voted» sits in the room was the only thing it could
    /// show. A session without a host: the room's subscription and a read of
    /// the post's actions, no web view, no place in the pool.
    private func read(_ eventID: String) {
        guard var entry = entries[eventID], entry.instance == nil, entry.reader == nil else { return }
        let session = SpiralAppPostSession(postEventID: eventID, roomProxy: roomProxy, feed: feed)
        entry.reader = session
        entry.readerCancellable = Self.follow(session.snapshotPublisher, into: entry.slot)
        entries[eventID] = entry
        Task { await session.start() }
    }

    /// Stop following without an app: the row left, or an app took over.
    private func stopReading(_ eventID: String) {
        guard let reader = entries[eventID]?.reader else { return }
        entries[eventID]?.reader = nil
        entries[eventID]?.readerCancellable = nil
        reader.stop()
    }

    /// What the card shows when no code runs: the newest summary's line, and
    /// the moment it counts down to. A summary with neither says nothing new;
    /// one with a line and no countdown clears the countdown, because the
    /// post has stopped counting.
    private static func follow(_ snapshots: AnyPublisher<SpiralAppStateReader.Snapshot, Never>,
                               into slot: SpiralAppSlot) -> AnyCancellable {
        snapshots
            .compactMap(\.summary)
            .filter { $0.line != nil || $0.countdownTo != nil }
            .removeDuplicates()
            .sink { [weak slot] summary in
                if let line = summary.line {
                    slot?.summaryLine = line
                }
                slot?.summaryCountdown = summary.countdownTo
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

        entry.surface = nil
        entry.arming?.cancel()
        entry.arming = nil
        entries[eventID] = entry
        // Reading without an app is for a row the reader can see.
        stopReading(eventID)

        forgetColdestIfCrowded()

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
                                 summaryCancellable: nil,
                                 arming: nil,
                                 lastWantedAt: .distantPast)
        return slot
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
        let liveBefore = liveHostCount
        for (id, entry) in entries {
            entry.arming?.cancel()
            entry.surface?.clear()
            returnToCard(id)
            if let instance = entry.instance {
                Task { await instance.stop() }
            }
            entry.reader?.stop()
            entries[id] = nil
        }

        // The stops above are async and give hosts back to the pool as they
        // finish; drain once they have, or a warm shell for a room nobody is in
        // would outlive the room.
        Task { [pool] in
            await Task.yield()
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

        // A post being read is on screen by construction (`read` stops when
        // its row leaves), so it is not idle, and dropping it would orphan
        // its share of the room's subscription.
        let idle = entries
            .filter { $0.value.instance == nil && $0.value.arming == nil && $0.value.reader == nil }
            .sorted { $0.value.lastWantedAt < $1.value.lastWantedAt }

        for (id, _) in idle.prefix(entries.count - Self.maxRememberedPosts) {
            entries[id] = nil
        }
    }

    private func mountIfStillWanted(eventID: String) async {
        // The row may have left, or been mounted by an earlier arming, while
        // this one was sleeping.
        guard let entry = entries[eventID], entry.instance == nil else { return }

        // Say so before the fetch, not after: on a cold cache this is where
        // the time goes, and a row that looks idle while it works is the one
        // people tap twice.
        entry.slot.phase = .loading
        entries[eventID]?.loadingSince = .now

        switch await artifacts.artifact(for: entry.post) {
        case .failure(let error):
            // A post that cannot be fetched keeps its quiet card. Nothing is
            // retried here: the next time it becomes visible is the retry, and
            // that is the reader asking rather than a loop.
            MXLog.info("[SpiralApp] not mounting \(eventID): \(error)")
            entries[eventID]?.arming = nil
            returnToCard(eventID)
            return
        case .success(let artifact):
            // Awaiting the fetch means the world may have moved again — a
            // sheet may have come up over the room while it was on its way.
            guard let current = entries[eventID], current.instance == nil else { return }
            guard !isCovered else {
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

            // The app reads the post from here on; a reader following it
            // without one (media shown again) steps aside.
            stopReading(eventID)
            let instance = SpiralAppInstance(session: SpiralAppPostSession(postEventID: eventID,
                                                                           roomProxy: roomProxy,
                                                                           feed: feed,
                                                                           mediaProvider: mediaProvider,
                                                                           refusals: sendRefusals),
                                             pool: pool)
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

            // What is left for the registry to do with state: keep the last
            // line, and the moment it counts down to, for the card. Telling
            // the running app is the instance's job, and not something a
            // caller can forget.
            if let slot = entries[eventID]?.slot {
                entries[eventID]?.summaryCancellable = Self.follow(instance.snapshots, into: slot)
            }

            let outcome = await instance.start(artifact, instanceID: eventID)
            if outcome != .started {
                // Something else already took this instance down — an
                // eviction, a release — so the row is already a card and this
                // has nothing left to say.
                guard entries[eventID]?.instance === instance else { return }
                entries[eventID]?.instance = nil
                entries[eventID]?.summaryCancellable = nil
                entries[eventID]?.surface?.clear()
                returnToCard(eventID)
                await instance.stop()

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

            // Present AGAIN, into whatever surface is current now.
            //
            // The one before `start` is what gives the app a window to paint
            // into. But `start` awaits — a fetch, a shell, a paint — and a
            // timeline does not hold still for that: the row that was showing
            // this post may have been recycled, and the surface holding the
            // container may have gone. Reading the surface again here is the
            // difference between revealing an app and revealing an empty
            // rectangle, and it costs nothing when nothing moved because
            // `present` is idempotent.
            if let current = entries[eventID]?.surface {
                current.present(instance.containerView)
                instance.setViewport(current.viewportMode)
            }

            // `start` waits for the app to have drawn, so this is the first
            // moment there is anything to reveal.
            entries[eventID]?.slot.phase = .ready
            // The app may ask for the screen from here on; only the row knows
            // where that is, so the slot carries the request out.
            if let slot = entries[eventID]?.slot {
                instance.onExpandRequested = { [weak slot] in slot?.requestExpand() }
            }
            entries[eventID]?.loadingSince = nil
            entries[eventID]?.startsInterrupted = 0

            MXLog.info("[SpiralApp] mounted \(eventID) — \(liveHostCount) live, \(ExtensionLogger.formattedMemoryFootprint)")
        }
    }

    /// The system killed an app's content process.
    ///
    /// Treated as an eviction, because that is what it is from here: the app is
    /// gone and the row must stop pretending otherwise. The card comes back
    /// with the last thing the app said, which is why that line is kept.
    ///
    /// Then ONE retry. A kill is usually the system reclaiming a web view
    /// nobody is looking at, and remounting is exactly right for that. But it
    /// is also what happens when memory has run out — and that is precisely
    /// when a retry loop would be worst, so the second death is final and the
    /// post stays a card until the reader scrolls away and back.
    private func contentProcessDied(eventID: String) {
        guard let entry = entries[eventID], let instance = entry.instance else { return }

        entries[eventID]?.instance = nil
        entries[eventID]?.summaryCancellable = nil
        entry.surface?.clear()
        returnToCard(eventID)
        // Discarded, not stopped: a host with a dead process has no warm shell
        // to give back, and parking it would poison the pool.
        Task { await instance.discard() }

        guard !entry.retriedAfterDeath else {
            MXLog.error("[SpiralApp] \(eventID) lost its content process twice — leaving it as a card")
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
            entries[coldest.key]?.instance = nil
            entries[coldest.key]?.summaryCancellable = nil
            coldest.value.surface?.clear()
            returnToCard(coldest.key)
            // Awaited, not fired: the stop is what parks the host, and the
            // acquire that follows this call should find it there. A stop
            // left to run on its own made the next app build a fresh web
            // view a moment before the warm one came back.
            await instance.stop()
        }
        return true
    }

    /// Start the settle-then-mount countdown for a post. Never under a sheet
    /// of ours (`isCovered`): every path that asks for an app comes here.
    private func arm(_ eventID: String) {
        guard !isCovered else { return }
        entries[eventID]?.arming = Task { [weak self] in
            try? await Task.sleep(for: Self.settleBeforeMount)
            guard !Task.isCancelled else { return }
            await self?.mountIfStillWanted(eventID: eventID)
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
