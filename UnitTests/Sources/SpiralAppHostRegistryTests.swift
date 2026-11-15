//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.15): does the registry hold to the
// policy the measurement asked for?
//
// The measurement said two things a naive registry gets wrong: visibility
// overshoots what is on screen, and a row can appear and disappear inside one
// flick. Both tests below fail against "visible means mounted", which is the
// implementation anyone would write first.
//

import Combine
import Foundation
import MatrixRustSDK
@testable import Spiral
import SpiralAppTestArtifacts
import Testing
import UIKit

@MainActor
struct SpiralAppHostRegistryTests {
    #if DEBUG

    // MARK: - Visibility arms a mount; it does not cause one

    @Test
    func aPostFlickedPastNeverCostsAWebView() async throws {
        let world = try World()

        world.show("$flicked")
        // Gone well before the settle, as happens on any fast scroll.
        world.hide("$flicked")
        try await Task.sleep(for: .milliseconds(450))

        #expect(world.registry.liveHostCount == 0)
        #expect(world.hostsMade == 0)
        // Not even fetched: the cheapest work is the work not started.
        #expect(world.loader.loadMediaContentForSourceCallsCount == 0)
    }

    /// A post still on its way to the server is nobody else's business.
    ///
    /// Rows ask for a slot before they appear, and a local echo has no event id
    /// to ask with. Those all arrived as `""` — so every unsent post in the room
    /// shared one slot and watched whatever the others were doing, and each left
    /// an entry that nothing could ever arm, since arming needs the event id
    /// too.
    @Test
    func aPostWithNoEventIDYetIsNobodyElsesBusiness() throws {
        let world = try World()

        let first = world.registry.slot(for: "", post: world.post)
        let second = world.registry.slot(for: "", post: world.post)

        #expect(first !== second, "two unsent posts were handed the same slot")
        #expect(world.registry.rememberedPostCount == 0, "an unsent post was remembered")

        // A real id still behaves as it must: one slot, kept, so a row that
        // scrolls back finds the app it left.
        #expect(world.registry.slot(for: "$sent", post: world.post)
            === world.registry.slot(for: "$sent", post: world.post))
    }

    @Test
    func aPostThatStaysIsMounted() async throws {
        let world = try World()

        world.show("$stays")
        try await world.settle()

        #expect(world.registry.liveHostCount == 1)
        #expect(world.presented("$stays") != nil)
    }

    /// § 5.55: an edit keeps the event id and replaces the artifact. The
    /// entry kept the post it first saw, so the row went on running the old
    /// version until the room was left; now the old app stops and the new
    /// one mounts in its place.
    @Test
    func anEditedPostIsRemountedWithItsNewArtifact() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        #expect(world.registry.liveHostCount == 1)
        let before = world.mountAttempts

        world.surface("$post")?.post = try world.editedPost()
        try await world.settle()

        #expect(world.mountAttempts == before + 1, "the edit was never mounted")
        #expect(world.registry.liveHostCount == 1, "the old version kept a host")
        #expect(world.presented("$post") != nil)
    }

    /// A row leaving is not a reason to take an app down.
    ///
    /// This is the bug that made posts go blank, as a test. A timeline jumping
    /// to a pinned event makes rows leave and return several times a second,
    /// and each of those flickers used to destroy a live `WKWebView` and build
    /// another — ten in sixteen seconds for three posts. What survived that
    /// churn painted nothing ever again.
    ///
    /// The property is not "it recovers". It is that the churn never happens:
    /// one web view, still the same one, still running.
    @Test
    func aRowThatLeavesKeepsItsApp() async throws {
        let world = try World()
        world.show("$stays")
        try await world.settle()

        let view = world.presented("$stays")

        for _ in 0..<5 {
            world.hide("$stays")
            try await Task.sleep(for: .milliseconds(120))
            world.show("$stays")
            try await Task.sleep(for: .milliseconds(120))
        }

        #expect(world.registry.liveHostCount == 1)
        #expect(world.hostsMade == 1, "leaving the screen must not cost a second web view")
        #expect(world.destroyed == 0)
        #expect(world.presented("$stays") === view,
                "the row must find the same app it left, not a new one")
    }

    @Test
    func appearingTwiceDoesNotMountTwice() async throws {
        // Balanced signals were measured, but a row re-arming while already
        // live must still not take a second web view.
        let world = try World()

        world.show("$twice")
        try await world.settle()
        world.show("$twice")
        try await world.settle()

        #expect(world.registry.liveHostCount == 1)
        #expect(world.hostsMade == 1)
    }

    // MARK: - The pool never exceeds what the gate proved

    @Test
    func theOvershootMeasuredOnDeviceDoesNotExceedTheCap() async throws {
        // More rows claiming to be visible at once than the pool allows is not
        // hypothetical: five at once was the peak measured while scrolling a
        // room with six posts (§5.15), against a gate that only ever proved
        // four live hosts. Written against the cap rather than against four,
        // because the cap now depends on the phone's memory (§5.48).
        let world = try World()

        for index in 0...SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$post\(index)")
        }
        try await world.settle()

        #expect(world.registry.liveHostCount == SpiralAppHostRegistry.defaultMaxLiveHosts)
    }

    /// The pool is full and every app in it is on screen. A fifth row arrives.
    ///
    /// Before this, the fifth evicted the "coldest" of the four — which was
    /// merely the one whose row appeared first, and was still on screen — and
    /// the reader watched a working app turn into a card that never came back,
    /// because nothing re-arms a row that is already visible. Twelve posts
    /// scrolled back and forth did this ninety times in five minutes.
    @Test
    func aNewcomerWaitsRatherThanEvictingAnAppTheReaderCanSee() async throws {
        let world = try World()
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$post\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await world.settle()

        world.show("$newcomer")
        try await world.settle()

        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            #expect(world.presented("$post\(index)") != nil,
                    "$post\(index) was evicted while on screen")
        }
        #expect(world.presented("$newcomer") == nil, "the newcomer jumped the queue")
        #expect(world.registry.slot(for: "$newcomer", post: world.post).phase == .waiting)
        #expect(world.registry.liveHostCount == SpiralAppHostRegistry.defaultMaxLiveHosts)
        #expect(world.destroyed == 0)
    }

    /// An app the reader CANNOT see gives way to one they can, however little
    /// of it shows.
    ///
    /// The eviction margin exists so two rows of nearly equal share do not
    /// swap a host back and forth. Applied to a holder that is off screen
    /// entirely it only blocked: scrolling Public 0067 produced `no room for
    /// $tPVzNW — holders: $Js6WhS|unseen …` for a post 16 % into view, because
    /// 0 + 0.2 is more than 0.16, and the reader watched a grey rectangle
    /// while an app nobody could see kept its web view (2026-09-21).
    @Test
    func anAppNobodyCanSeeGivesWayToOneTheReaderCanBarelySee() async throws {
        let world = try World()
        for index in 0..<(SpiralAppHostRegistry.defaultMaxLiveHosts - 1) {
            world.show("$seen\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        world.show("$unseen")
        try await world.settle()
        world.moveOffScreen("$unseen")
        #expect(world.registry.liveHostCount == SpiralAppHostRegistry.defaultMaxLiveHosts,
                "the pool should be full before the newcomer arrives")

        // 30 points of a 200-point row: 15 %, less than the 20 % margin.
        world.showPartly("$sliver", visible: 30)
        try await world.settle()

        #expect(world.presented("$sliver") != nil,
                "a post the reader can see was refused a host held by one they cannot")
        #expect(world.presented("$unseen") == nil, "the off-screen app kept its host")
    }

    /// A post that is on screen with no app and nothing on the way is asked
    /// for again, without waiting for a row to enter or leave.
    ///
    /// Every other cue is an event: `didMoveToWindow`, a row leaving, or the
    /// surface re-asserting after a scroll. The last of those is a DEBOUNCE —
    /// a slow continuous scroll cancels it on every frame — so a post refused
    /// for want of a host while it was a sliver had no cue at all until the
    /// reader stopped moving. Measured scrolling Public 0067: a post that lost
    /// its host waited a median of 3.4 s to get one back and the worst waited
    /// 129 s, while the mount itself takes 46 ms (2026-09-21).
    @Test
    func aVisiblePostWithNoAppIsAskedForAgainWithoutAnEvent() async throws {
        let world = try World()
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$post\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        world.showPartly("$late", visible: 20)
        try await world.settle()
        #expect(world.presented("$late") == nil, "the pool was not full to begin with")

        // The reader scrolls: the holders go off screen and the late post
        // comes fully into view. Frames change, so NO surface enters or leaves
        // a window and nothing in the event path fires.
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.surface("$post\(index)")?.frame = CGRect(x: 0, y: 2000, width: 300, height: 200)
        }
        world.surface("$late")?.frame = CGRect(x: 0, y: 0, width: 300, height: 200)

        // Longer than the watchdog's half second, and its arming settle.
        try await Task.sleep(for: .milliseconds(1200))

        #expect(world.presented("$late") != nil,
                "a post on screen with no app was left as a grey rectangle")
    }

    /// The same newcomer gets its turn the moment any row leaves — its own
    /// `onAppear` will never fire again, so a row leaving has to be the cue.
    @Test
    func aWaitingPostIsMountedWhenARowLeaves() async throws {
        let world = try World()
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$post\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await world.settle()
        world.show("$newcomer")
        try await world.settle()
        #expect(world.presented("$newcomer") == nil)

        world.hide("$post2")
        try await world.settle()

        #expect(world.presented("$newcomer") != nil, "the waiting post was not mounted")
        #expect(world.presented("$post2") == nil, "the post that left was not the one evicted")
        #expect(world.registry.liveHostCount == SpiralAppHostRegistry.defaultMaxLiveHosts)
        #expect(world.destroyed == 0, "an evicted host was destroyed rather than parked")
        #expect(world.hostsMade == SpiralAppHostRegistry.defaultMaxLiveHosts, "the newcomer did not take the parked host")
    }

    /// Cell recycling gives a post two rows for a moment: the new one enters
    /// the window BEFORE the old one leaves. With SwiftUI's hints this was
    /// invisible to the registry, and an aggressive scroll left the new row
    /// grey — the app's container was in the old row, which was gone. The
    /// newest surface must win, and the old one leaving must not count as
    /// the post leaving.
    @Test
    func aRecycledRowTakesTheAppFromTheRowItReplaces() async throws {
        let world = try World()
        world.show("$post0")
        try await world.settle()
        let container = try #require(world.presented("$post0"))

        // A second surface for the same post, while the first is still up.
        let replacement = SpiralAppSurface(frame: CGRect(x: 0, y: 300, width: 300, height: 200))
        replacement.registry = world.registry
        replacement.post = world.post
        replacement.eventID = "$post0"
        world.window.addSubview(replacement)
        try await world.settleOnReturn()

        #expect(replacement.presented === container, "the new row did not take the app")
        #expect(world.presented("$post0") == nil, "the old row still shows the app")

        // Now the old row goes. The post is still on screen.
        world.hide("$post0")
        #expect(replacement.presented === container, "the old row leaving took the app with it")
        #expect(world.registry.liveHostCount == 1, "the old row leaving was treated as the post leaving")

        // And it is still visible to eviction policy: fill the pool and the
        // recycled post must not be the one taken.
        for index in 1...SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$other\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await world.settle()
        #expect(replacement.presented === container, "a visible post was evicted because its surface was the replacement")
    }

    /// A VIEWER OUTRANKS A ROW. When the full-screen cover is up, the
    /// timeline is still in a window behind it, and the row re-asserts itself
    /// after every scroll settles. Before this, that first settle pulled the
    /// app out of the viewer and the reader was left looking at an empty
    /// screen — caught on two simulators, mid-drawing.
    @Test
    func aViewerKeepsTheAppWhenTheRowBehindItComesBack() async throws {
        let world = try World()
        world.show("$post0")
        try await world.settle()
        let container = try #require(world.presented("$post0"))

        // The cover goes up: a second surface, expanded, takes the app.
        let viewer = SpiralAppSurface(frame: CGRect(x: 0, y: 0, width: 402, height: 758))
        viewer.viewportMode = .expanded
        viewer.registry = world.registry
        viewer.post = world.post
        viewer.eventID = "$post0"
        world.window.addSubview(viewer)
        #expect(viewer.presented === container, "the viewer never got the app")

        // The row behind the cover re-asserts itself, as a scroll makes it do.
        let row = SpiralAppSurface(frame: CGRect(x: 0, y: 300, width: 322, height: 242))
        row.registry = world.registry
        row.post = world.post
        row.eventID = "$post0"
        world.window.addSubview(row)

        #expect(viewer.presented === container, "the row behind the cover took the app back")
        #expect(row.presented == nil, "the row took an app the viewer is showing")
    }

    /// SwiftUI recycles the UIKit view under a row: the same surface that
    /// showed post A is handed post B. Before this, A's container stayed
    /// inside it and B's row showed A's app — grey, since A had been told to
    /// stop painting when its row left. This was the "grey until it gets
    /// killed" the operator caught on an aggressive scroll.
    @Test
    func aSurfaceHandedANewPostDropsTheOldPostsApp() async throws {
        let world = try World()
        world.show("$a")
        try await world.settle()
        let surface = try #require(world.surface("$a"))
        let containerA = try #require(surface.presented)

        // The cell is recycled: same UIView, different post, still in window.
        surface.eventID = "$b"

        #expect(surface.presented == nil, "the recycled surface still shows the previous post's app")
        #expect(containerA.superview == nil, "A's container is inside a surface that now belongs to B")

        // B mounts into it; A is still live (it was not evicted, just unseen).
        try await world.settle()
        #expect(surface.presented != nil)
        #expect(surface.presented !== containerA, "B's row shows A's app")
        #expect(world.registry.liveHostCount == 2)
    }

    /// A timeline keeps rows in the hierarchy past the viewport, so "in a
    /// window" is not "on screen". With membership as the test, six posts
    /// reported themselves visible at once against a cap of four: none could
    /// be evicted, nothing on screen could get a turn, and every row that
    /// arrived kept its card. Measured in the room, not imagined.
    @Test
    func aRowPastTheViewportIsNotVisibleAndMayBeEvicted() async throws {
        let world = try World()
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$past\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await world.settle()
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.moveOffScreen("$past\(index)")
        }
        #expect(world.registry.liveHostCount == SpiralAppHostRegistry.defaultMaxLiveHosts,
                "the rows past the viewport were never started")

        world.show("$seen")
        try await world.settle()

        #expect(world.presented("$seen") != nil,
                "a row the reader can see was refused because rows past the viewport counted as visible")
    }

    /// A surface recycled to a new post while OFF screen used to keep the old
    /// post's registration. The registry reads "is this post visible" from the
    /// surface it was given, so when that view came back on screen showing the
    /// new post, the old one looked visible for ever: never evictable, the
    /// pool full of posts nobody could see, and every post actually on screen
    /// stuck with its card. This is the state the operator kept catching.
    @Test
    func aPostWhoseSurfaceWasRecycledOffScreenStopsLookingVisible() async throws {
        let world = try World()
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$old\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await world.settle()
        #expect(world.registry.liveHostCount == SpiralAppHostRegistry.defaultMaxLiveHosts)

        // Every row leaves the screen and its view is recycled onto a new post
        // while off screen — which is what a fast scroll does.
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            let surface = try #require(world.surface("$old\(index)"))
            surface.removeFromSuperview()
            surface.eventID = "$recycled\(index)"
        }

        // A post the reader can actually see arrives. Every live app is off
        // screen, so there is room for it.
        world.show("$visible")
        try await world.settle()

        #expect(world.presented("$visible") != nil, "a visible post could not get a turn: the pool is full of ghosts")
    }

    /// A start interrupted by something that is not the app's fault — its slot
    /// taken while it was starting, the page churning under the call — used to
    /// leave the post as a card for ever, because every failure looked alike.
    /// Measured 2026-09-16: two posts ended a session that way, sitting on
    /// screen while everything around them ran.
    @Test
    func aStartInterruptedByContentionIsTriedAgain() async throws {
        let world = try World()
        world.failNextMount(SpiralAppTestError.superseded)

        world.show("$post0")
        // Twice: the first settle covers the failed start, the second the
        // turn it is given afterwards.
        try await world.settle()
        try await world.settle()

        #expect(world.presented("$post0") != nil, "an interrupted start was left as a card")
        #expect(world.mountAttempts >= 2, "the post was never given another turn")
    }

    /// An app that will not run is not contention, and trying again would only
    /// refuse it again — so the card stays and the reader is told once.
    @Test
    func aStartTheAppItselfRefusedIsNotRetried() async throws {
        let world = try World()
        world.failNextMount(SpiralAppTestError.broken)

        world.show("$post0")
        try await world.settle()

        #expect(world.presented("$post0") == nil)
        #expect(world.mountAttempts == 1, "a broken artifact was retried")
    }

    /// A row with a corner showing is not a row being read.
    ///
    /// Measured 2026-09-16 in an 874pt window of 235pt posts: five or six rows
    /// intersect the window at once, of which three or four are really visible.
    /// While a sliver counted as fully on screen it could not be evicted, so
    /// the posts under the reader's eye kept their cards — with hosts to spare
    /// held by rows nobody could see.
    @Test
    func aSliverAtTheEdgeGivesItsHostToAPostBeingRead() async throws {
        let world = try World(maxLiveHosts: 1)

        world.showPartly("$sliver", visible: 20)
        try await world.settle()
        #expect(world.presented("$sliver") != nil, "the only post on screen never got the only host")

        world.show("$read")
        try await world.settle()

        #expect(world.presented("$read") != nil, "a post in full view could not take a host from a sliver")
        #expect(world.presented("$sliver") == nil)
    }

    /// The other half of the same rule: near-equal shares keep their hosts,
    /// or two rows swap one host for as long as the reader keeps scrolling.
    @Test
    func twoRowsSharingTheViewDoNotSwapTheHostBackAndForth() async throws {
        let world = try World(maxLiveHosts: 1)

        world.showPartly("$upper", visible: 110)
        try await world.settle()
        #expect(world.presented("$upper") != nil)

        world.showPartly("$lower", visible: 100)
        try await world.settle()

        #expect(world.presented("$upper") != nil, "a host moved for a share barely different from its own")
        #expect(world.presented("$lower") == nil)
    }

    /// One web view cannot serve two apps. Stopping an app twice used to give
    /// its host back to the pool twice, and the pool then handed that one host
    /// to two apps: both showed it, each stole it from the other, and whichever
    /// lost was a grey rectangle the reader was looking at. Reachable in
    /// ordinary use — an eviction stops an app WHILE it is starting, and the
    /// start's own cleanup stops it again. Measured in the room: two posts
    /// trading one container twice a second, 181 times.
    @Test
    func aHostGivenBackTwiceIsParkedOnce() async {
        let counts = Counts()
        let pool = SpiralAppHostPool {
            counts.made += 1
            return FakeHost(counts: counts)
        }

        let host = pool.acquire()
        await pool.release(host)
        await pool.release(host)

        #expect(pool.parkedCount == 1, "one host was parked twice")

        let first = pool.acquire()
        let second = pool.acquire()
        #expect(first !== second, "two apps were handed the same host")
        #expect(counts.made == 2, "the pool served a host it had already given away")
    }

    /// M3: an app spinning in `while (true) {}` blocks the shell's own
    /// JavaScript, so its unmount never answers. The host is destroyed at
    /// the deadline instead of waited on, and never parked.
    @Test
    func aHostWhoseUnmountNeverReturnsIsDestroyedAtTheDeadline() async {
        let counts = Counts()
        counts.unmountHangs = true
        let pool = SpiralAppHostPool(unmountDeadline: .milliseconds(100)) {
            counts.made += 1
            return FakeHost(counts: counts)
        }

        let started = ContinuousClock.now
        let outcome = await pool.release(pool.acquire())

        #expect(outcome == .wedged)
        #expect(ContinuousClock.now - started < .seconds(2), "the release waited on the hung unmount")
        #expect(counts.destroyed == 1)
        #expect(pool.parkedCount == 0, "a wedged host was parked for the next app")
    }

    /// M3, as the reader meets it: a wedged app must not keep the next post
    /// from mounting, and a post that wedges twice stays a card.
    @Test
    func aWedgedAppDoesNotHoldUpTheNextPost() async throws {
        let world = try World(maxLiveHosts: 1, unmountDeadline: .milliseconds(100))
        world.show("$wedged")
        try await world.settle()
        #expect(world.presented("$wedged") != nil)

        world.wedgeUnmounts()
        world.hide("$wedged")
        world.show("$next")
        try await world.settle()

        #expect(world.presented("$next") != nil, "the eviction waited on an app that never left")
        #expect(world.destroyed >= 1, "the wedged host was kept")

        // A first wedge is a death and the post may run again; a second is
        // final, as for a content process killed twice.
        world.hide("$next")
        world.show("$wedged")
        try await world.settle()
        #expect(world.presented("$wedged") != nil, "one wedge was final")

        world.hide("$wedged")
        world.show("$next")
        try await world.settle()
        world.hide("$next")
        world.show("$wedged")
        try await world.settle()
        #expect(world.presented("$wedged") == nil, "a post that wedged twice was mounted again")
    }

    /// The instance refuses the second stop, which is where the double-park
    /// came from: an eviction takes an app down WHILE it is starting, and the
    /// start's own cleanup then takes it down again.
    @Test
    func stoppingAnAppTwiceGivesItsHostBackOnce() async {
        let counts = Counts()
        let pool = SpiralAppHostPool {
            counts.made += 1
            return FakeHost(counts: counts)
        }
        let instance = SpiralAppInstance(session: SilentSession(), pool: pool)

        await instance.stop()
        #expect(pool.parkedCount == 1)

        await instance.stop()
        #expect(pool.parkedCount == 1, "the second stop parked the same host again")

        // And the proof that matters: two apps never get one web view.
        let first = pool.acquire()
        let second = pool.acquire()
        #expect(first !== second, "two apps were handed the same host")
    }

    /// Two surfaces for one post can be in a window at once while a cell is
    /// recycled. The container can only be in one of them. When both were
    /// allowed to claim it from `layoutSubviews`, they took it from each other
    /// on every pass — 379,309 times in one run, which froze the app, and the
    /// loser was the grey row the reader was looking at.
    ///
    /// Only the registry's current surface is answered. Laying out the other
    /// one must change nothing at all.
    @Test
    func twoSurfacesForOnePostDoNotFightOverIt() async throws {
        let world = try World()
        world.show("$post0")
        try await world.settle()
        let first = try #require(world.surface("$post0"))
        let container = try #require(first.presented)

        let second = SpiralAppSurface(frame: CGRect(x: 0, y: 300, width: 300, height: 200))
        second.registry = world.registry
        second.post = world.post
        second.eventID = "$post0"
        world.window.addSubview(second)
        try await world.settleOnReturn()
        #expect(second.presented === container, "the newest surface in a window did not become the current one")

        // Laying either one out must MOVE nothing. Layout that mutates the
        // hierarchy re-enters itself: an earlier version asked the registry
        // for the app from `layoutSubviews`, and `present` → `addSubview` →
        // `didMoveToWindow` → `layoutSubviews` spun the app at 115% CPU.
        for _ in 0..<5 {
            first.setNeedsLayout()
            first.layoutIfNeeded()
            second.setNeedsLayout()
            second.layoutIfNeeded()
        }
        #expect(second.presented === container, "layout moved the app")
        #expect(first.presented == nil, "layout gave the app to the surface that lost")
    }

    /// A table keeps the cells it may reuse as hidden subviews, in the window
    /// and at the frame they last had. One that last showed this post asked for
    /// its app at the table's rest like any row, and won: the page drew in a
    /// cell nobody could see, and the row in sight stayed an empty grey frame
    /// (Dev-B, a finished tug-of-war, question 411).
    @Test
    func aHiddenRowDoesNotTakeTheAppFromTheRowInSight() async throws {
        let world = try World()
        world.showInTable("$post0")
        try await world.settle()
        let container = try #require(world.presented("$post0"))

        // Lying right under the row in sight, as a cell hidden in place does.
        let hidden = world.showHiddenInTable("$post0")
        #expect(hidden.visibleFraction == 0, "a hidden row counted as seen")
        #expect(!hidden.isOnScreen)

        // The table's rest has every surface in its window ask again.
        hidden.reclaim()
        try await world.settleOnReturn()
        #expect(world.presented("$post0") === container, "the hidden row took the app from the row in sight")
        #expect(hidden.presented == nil, "the app went into a row nobody can see")
        #expect(world.registry.slot(for: "$post0", post: world.post).phase == .ready)
    }

    /// The other half: a table can show a reused cell again, and hide the one
    /// it replaces, with no row entering or leaving its window. The row now in
    /// sight gets the app without waiting for the table to move and rest.
    @Test
    func aRowShownAgainInItsWindowGetsItsApp() async throws {
        let world = try World()
        world.showInTable("$post0")
        try await world.settle()
        let container = try #require(world.presented("$post0"))

        // The replacement arrives hidden, so it doesn't ask…
        let replacement = world.showHiddenInTable("$post0")
        try await world.settleOnReturn()
        #expect(replacement.presented == nil)

        // …then the table swaps them in place.
        try #require(world.surface("$post0")).isHidden = true
        try #require(replacement.superview).isHidden = false
        let deadline = ContinuousClock.now + .seconds(3)
        while replacement.presented !== container, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(replacement.presented === container, "the row in sight never got its app")
        #expect(world.presented("$post0") == nil)
        #expect(world.registry.slot(for: "$post0", post: world.post).phase == .ready, "the row in sight kept its cover")
    }

    /// An animated reload keeps two shown cells for one post. The second one,
    /// past the viewport under a still table, covers the post for a return that
    /// never comes; the row in sight, which never lost the app, is then adopted
    /// and lifts that cover rather than keep it over a live app (411 L1).
    @Test
    func aRowAdoptedWhileItShowsTheAppLiftsItsCover() async throws {
        let world = try World()
        world.showInTable("$post0")
        try await world.settle()
        let row = try #require(world.surface("$post0"))
        let container = try #require(row.presented)
        let slot = world.registry.slot(for: "$post0", post: world.post)
        #expect(slot.phase == .ready)

        // Read at once: the registry's watch may adopt the row in sight on its next tick.
        world.showInTable("$post0", below: 2000)
        #expect(row.presented === container, "the cell out of sight took the app")
        #expect(slot.phase == .away)

        // That cell's return finds it out of sight; the watch adopts the row in sight.
        let deadline = ContinuousClock.now + .seconds(3)
        while slot.phase != .ready, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(slot.phase == .ready, "the row in sight kept its cover over its own app")
        #expect(row.presented === container)
    }

    /// A row in sight under the full-screen viewer is the one row the watch
    /// leaves alone: the viewer keeps the app, also while its cover slides and
    /// it is out of sight (411 L3).
    @Test
    func theWatchLeavesTheViewerItsApp() async throws {
        let world = try World()
        world.showInTable("$post0")
        try await world.settle()
        let container = try #require(world.presented("$post0"))

        world.showViewer("$post0")
        try await world.settleOnReturn()
        let viewer = try #require(world.viewer("$post0"))
        #expect(viewer.presented === container)

        let ticks = world.registry.watchdogTicks
        try await Task.sleep(for: .milliseconds(600))
        #expect(world.registry.watchdogTicks > ticks, "the watch never ran")
        #expect(viewer.presented === container, "the watch gave the viewer's app to the row behind it")

        // Mid-slide: in the window, out of sight.
        viewer.frame.origin.y = world.window.bounds.height
        try await Task.sleep(for: .milliseconds(600))
        #expect(viewer.presented === container, "the watch took the app from a sliding viewer")
        #expect(world.presented("$post0") == nil)
    }

    /// The timeline hides its whole table while the opening rows load, and
    /// shows it again without a scroll. A post whose row arrived meanwhile was
    /// refused (hidden), so the registry has never heard of it; it still gets
    /// its app once the table is shown, not on the reader's first scroll.
    @Test
    func aPostFirstSeenInAHiddenTableStartsOnceTheTableShows() async throws {
        let world = try World()
        let row = world.showHiddenInTable("$post0")
        try await world.settle()
        #expect(world.registry.rememberedPostCount == 0, "a hidden row registered its post")
        #expect(row.presented == nil)

        try #require(row.superview).isHidden = false
        let deadline = ContinuousClock.now + .seconds(3)
        while row.presented == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(row.presented != nil, "the row stayed on its card until a scroll")
        #expect(world.registry.liveHostCount == 1)
    }

    /// Among posts NOT on screen, the coldest goes first — recency still
    /// decides, it just no longer decides against the reader.
    @Test
    func evictionTakesTheColdestOffScreenPost() async throws {
        let world = try World()
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$post\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await world.settle()

        // All four scroll away; $post0 was wanted longest ago.
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.hide("$post\(index)")
        }

        world.show("$newcomer")
        try await world.settle()
        #expect(world.presented("$newcomer") != nil)
        #expect(world.registry.liveHostCount == SpiralAppHostRegistry.defaultMaxLiveHosts)

        // A warmer post scrolling back finds its app still running and is
        // shown it at once — no mount. The coldest one was the one evicted,
        // and scrolling back to it starts from the card.
        let mountsBefore = world.hostsMade
        world.show("$post1")
        try await world.untilPresented("$post1")
        #expect(world.presented("$post1") != nil, "a warmer post was evicted instead")
        #expect(world.hostsMade == mountsBefore, "a running app was mounted again on return")

        world.show("$post0")
        try await world.settleOnReturn()
        #expect(world.presented("$post0") == nil, "the coldest off-screen post survived")
    }

    /// iOS kills the content processes of web views nobody is looking at, so a
    /// timeline holding several will meet this in ordinary use. Before this,
    /// the host logged the death and the row kept a correctly sized,
    /// permanently blank rectangle — reproduced on a simulator by killing the
    /// process by hand.
    @Test
    func anAppWhoseContentProcessDiesComesBack() async throws {
        let world = try World()
        world.show("$post0")
        try await world.settle()
        #expect(world.registry.liveHostCount == 1)

        world.killContentProcess()
        try await world.settle()

        #expect(world.registry.liveHostCount == 1, "the app did not come back after a first death")
        #expect(world.destroyed == 1, "a host whose process died was parked as if warm")

        // It started again, so this is a new life and not a second death in
        // one: iOS kills what a backgrounded app leaves, and it mustn't add up.
        world.killContentProcess()
        try await world.settle()

        #expect(world.registry.liveHostCount == 1, "one death was final after a good start")
    }

    /// Dying again before it has started is memory running out, not a
    /// transient reclaim, and a retry loop is the worst answer to that.
    @Test
    func aPostThatDiesTwiceBeforeStartingBacksOff() async throws {
        let world = try World()
        world.blockStart()
        world.show("$post0")
        try await world.settle()

        world.killContentProcess()
        try await world.settle()
        let made = world.hostsMade
        world.killContentProcess()
        world.unblockStart()
        // Past the watchdog's beat, which used to start it again regardless.
        try await Task.sleep(for: .milliseconds(1100))

        #expect(world.registry.liveHostCount == 0, "a second death was retried at once")
        #expect(world.hostsMade == made)
        #expect(world.registry.slot(for: "$post0", post: world.post).couldNotStart)

        try await Task.sleep(for: .seconds(2))
        #expect(world.registry.liveHostCount == 1, "a second death was final")
    }

    /// An eviction used to cost a whole new web view. Now the evicted app's
    /// host is parked and the next app takes it — one host made, two apps
    /// served.
    @Test
    func anEvictedHostIsReusedByTheNextApp() async throws {
        let world = try World()
        world.show("$post0")
        try await world.settle()
        let first = try #require(world.lastHost)
        #expect(world.hostsMade == 1)

        world.hide("$post0")
        // The pool is full of on-screen apps only when the cap is reached;
        // here we force the eviction by filling to the cap and beyond.
        for index in 1...SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$post\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await world.settle()

        #expect(world.presented("$post0") == nil, "$post0 was not evicted")
        #expect(world.hostsMade == SpiralAppHostRegistry.defaultMaxLiveHosts, "the evicted host was not reused")
        #expect(world.destroyed == 0, "a host was destroyed instead of parked")
        #expect(first.unmounts == 1)
        #expect(world.registry.liveHostCount == SpiralAppHostRegistry.defaultMaxLiveHosts)
    }

    /// The invariant the pool must not weaken: an app sees only the state of
    /// the post it is mounted on. A host that has been given back answers
    /// nobody until the next app binds it — there is no window in which it
    /// could still reach the session it served a moment ago.
    @Test
    func aParkedHostCannotReachTheSessionItServed() async throws {
        let world = try World()
        world.show("$post0")
        try await world.settle()
        let host = try #require(world.lastHost)
        #expect(host.boundHandler != nil, "a mounted host must be bound")

        world.registry.releaseAll()
        try await Task.sleep(for: .milliseconds(80))

        #expect(host.boundHandler == nil, "a released host is still bound to its old session")
    }

    /// Warm hosts are still a process each, so the pool keeps a few and no more.
    ///
    /// Tested on the pool itself: through the registry, every eviction parks
    /// one host that the very next newcomer takes, so the cap is never
    /// reached that way. It is reached when several apps stop at once.
    @Test
    func thePoolKeepsAFewWarmHostsAndDestroysTheRest() async {
        let counts = Counts()
        let pool = SpiralAppHostPool {
            counts.made += 1
            return FakeHost(counts: counts)
        }

        let hosts = (0..<4).map { _ in pool.acquire() }
        #expect(counts.made == 4)

        for host in hosts {
            await pool.release(host)
        }

        #expect(pool.parkedCount == SpiralAppHostPool.maxParked)
        #expect(counts.destroyed == 4 - SpiralAppHostPool.maxParked, "hosts beyond the cap were parked, not destroyed")

        _ = pool.acquire()
        _ = pool.acquire()
        #expect(counts.made == 4, "a warm host was available and a new one was built instead")
        #expect(pool.parkedCount == 0)

        _ = pool.acquire()
        #expect(counts.made == 5, "the pool was empty and no host was built")
    }

    /// The moment nothing covered: `releaseAll` worked and nobody called it.
    ///
    /// Measured on a simulator before this existed — leaving a room with three
    /// posts running left three `WKWebView`s and their WebContent processes
    /// alive, and three visits to the one room left nine. The registry's own
    /// deallocation cannot be the signal, because it was still held; the
    /// timeline's is, through `SpiralAppTeardown`.
    @Test
    func theAppsGoWhenTheThingThatOwnsThemDoes() async throws {
        let world = try World()
        for index in 0..<3 {
            world.show("$post\(index)")
        }
        try await world.settle()
        #expect(world.registry.liveHostCount == 3)

        var teardown: SpiralAppTeardown? = SpiralAppTeardown(registry: world.registry)
        _ = teardown
        teardown = nil
        try await Task.sleep(for: .milliseconds(120))

        #expect(world.registry.liveHostCount == 0)
        #expect(world.destroyed == 3, "the hosts were dropped rather than destroyed")
    }

    /// A sheet of ours over the room (the catalogue, a generation thread):
    /// the rows under it are still "on screen" to every measure the registry
    /// has, and the room kept all its apps running under the catalogue —
    /// WebContent processes nobody could see (§ 5.80). Covered, nothing runs
    /// and nothing starts, the warm hosts included; uncovered, the posts on
    /// screen come back.
    @Test
    func aRoomUnderOurSheetRunsNothingAndComesBackAfter() async throws {
        let world = try World()
        for index in 0..<3 {
            world.show("$post\(index)")
        }
        try await world.settle()
        #expect(world.registry.liveHostCount == 3)

        world.registry.setCovered(true)
        try await Task.sleep(for: .milliseconds(120))
        #expect(world.registry.liveHostCount == 0)
        #expect(world.presented("$post0") == nil, "a row under the sheet still showed its app")
        #expect(world.registry.pool.parkedCount == 0, "the warm hosts outlived the room being covered")

        // A row arriving under the sheet, and the watchdog's half-second, ask
        // for nothing.
        world.show("$post3")
        try await Task.sleep(for: .milliseconds(700))
        #expect(world.registry.liveHostCount == 0, "a post started under the sheet")

        world.registry.setCovered(false)
        try await world.settle()
        #expect(world.registry.liveHostCount == 4)
        #expect(world.presented("$post3") != nil)
    }

    @Test
    func releasingEverythingLeavesNothingLive() async throws {
        let world = try World()
        for index in 0..<3 {
            world.show("$post\(index)")
        }
        try await world.settle()

        world.registry.releaseAll()
        try await Task.sleep(for: .milliseconds(80))

        #expect(world.registry.liveHostCount == 0)
        #expect(world.destroyed == 3)
    }

    @Test
    func scrollingPastManyPostsDoesNotAccumulateThemForEver() throws {
        // An entry outlives its host so eviction can pick the coldest. Nothing
        // bounded it, so a long room would leave one per post ever seen.
        let world = try World()

        for index in 0..<(SpiralAppHostRegistry.maxRememberedPosts * 2) {
            world.show("$scrolled\(index)")
            world.hide("$scrolled\(index)")
        }

        #expect(world.registry.rememberedPostCount <= SpiralAppHostRegistry.maxRememberedPosts)
    }

    // MARK: - A running app hears about someone else's action

    @Test
    func aStateChangeReachesTheRunningApp() async throws {
        // The gap this test exists for: an app only ever learns state by
        // asking, and it asks once at mount. Measured between two simulators
        // before the push existed — the feed delivered, the session folded, and
        // the app went on showing the old number until its row was rebuilt.
        let world = try World()
        world.show("$live")
        try await world.settle()

        let host = try #require(world.lastHost)
        let pushed = host.pushes.filter { $0["kind"] as? String == "state.changed" }

        #expect(pushed.isEmpty == false, "a mounted app was never told the state")
    }

    @Test
    func theAppIsToldTheSequenceAndNotJustTheState() async throws {
        // `seq` is what lets the SDK drop its optimistic copy; a push without
        // it would leave an app unable to tell its own write from anyone else's.
        let world = try World()
        world.show("$live")
        try await world.settle()

        let host = try #require(world.lastHost)
        let pushed = try #require(host.pushes.last { $0["kind"] as? String == "state.changed" })

        #expect(pushed["seq"] is Int)
        #expect(pushed["state"] != nil)
    }

    @Test
    func theRowIsGivenTheViewBeforeTheAppStarts() async throws {
        // A `WKWebView` that is not in a window has no viewport to render into.
        // Mounting first and showing after left an app running in a detached,
        // zero-sized frame: the row stayed grey until it was scrolled away and
        // rebuilt. Measured on a simulator before this order was swapped.
        let world = try World()
        world.blockStart()

        world.show("$early")
        try await world.settle()

        #expect(world.presented("$early") != nil,
                "the row had nothing to show while the app was starting")

        world.unblockStart()
    }

    // MARK: - What a post says when it is not running

    @Test
    func anEvictedPostKeepsTheLastThingItSaid() async throws {
        // The line exists to be read where the app is not running, so losing it
        // when the app is taken down would defeat the point of having it.
        let world = try World()
        world.show("$said")
        try await world.settle()

        let slot = world.registry.slot(for: "$said", post: world.post)
        let moment = Date(timeIntervalSince1970: 1_798_761_600)
        slot.reportForTesting(summaryLine: "3 of 5 have voted", countdown: moment)

        // Evicted rather than merely scrolled past: leaving the screen no
        // longer takes an app down, so filling the pool is the only way to
        // reach the state this test is about.
        world.hide("$said")
        for index in 0..<SpiralAppHostRegistry.defaultMaxLiveHosts {
            world.show("$other\(index)")
            try await Task.sleep(for: .milliseconds(20))
        }
        try await world.settle()

        #expect(slot.phase == .waiting, "the app is still mounted")
        #expect(slot.summaryLine == "3 of 5 have voted")
        #expect(slot.summaryCountdown == moment, "the card forgot what it counts down to")
    }

    // MARK: - A post that may not run is still read (§ 5.79)

    /// A reader who hid media gets no app — somebody else's code is not run
    /// for them — but what the post last SAID is data: the card shows the
    /// newest line and counts down to its moment, read from the room, with no
    /// web view and no place in the pool.
    @Test
    func aPostThatMayNotRunStillSaysItsLineAndCountsDown() async throws {
        let world = try World()
        world.room.loadSpiralAppRelationsForReturnValue = .success([Self.action(on: "$quiet",
                                                                                line: "3 are waiting",
                                                                                countdownTo: "2027-01-01T00:00:00.000Z")])

        world.show("$quiet", mayRun: false)
        try await world.settle()

        let slot = world.registry.slot(for: "$quiet", post: world.post)
        #expect(world.hostsMade == 0, "a post that may not run was given a web view")
        #expect(world.mountAttempts == 0)
        #expect(slot.phase == .waiting)
        #expect(slot.summaryLine == "3 are waiting")
        #expect(slot.summaryCountdown == Date(timeIntervalSince1970: 1_798_761_600))

        // Gone from the screen: the card keeps what it said.
        world.hide("$quiet")
        try await world.settle()
        #expect(slot.summaryLine == "3 are waiting")
    }

    // MARK: - A mount that never answers (§ 7 #19)

    /// A mount the frame never answers is bounded by the host
    /// (`mountDeadline`) and arrives here as `timedOut`: the row keeps
    /// its card, never uncovering a frame the app did not draw into.
    @Test
    func aMountThatNeverAnswersLeavesTheCard() async throws {
        let world = try World()
        world.failNextMount(SpiralAppHostError.timedOut)

        world.show("$silent")
        try await world.settle()

        let slot = world.registry.slot(for: "$silent", post: world.post)
        #expect(slot.phase == .waiting, "the card lifted off an app that never drew")
        #expect(world.presented("$silent") == nil, "a frame nobody drew into was left in the row")
        #expect(world.registry.liveHostCount == 0)
    }

    /// F6: an artifact whose manifest names a runtime this build does not
    /// carry keeps its card, says the app needs updating, and is not retried.
    @Test
    func aPostForANewerRuntimeAsksForAnUpdate() async throws {
        let world = try World()
        world.failNextMount(SpiralAppHostError.newerRuntime)

        world.show("$future")
        try await world.settle()

        let slot = world.registry.slot(for: "$future", post: world.post)
        #expect(slot.needsNewerApp)
        #expect(slot.phase == .waiting)
        #expect(world.registry.liveHostCount == 0)
    }

    /// One action on `post`, carrying a summary — the raw event a session reads.
    private static func action(on post: String, line: String, countdownTo: String) -> String {
        """
        {"type":"com.spiral.app.action","event_id":"$act-\(post)","sender":"@a:spiral.md",
         "origin_server_ts":1700000000000,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"\(post)"},
                    "op":{"set":{"path":"lastTouch","value":"@a:spiral.md"}},
                    "seq":1,
                    "summary":{"line":"\(line)","countdown_to":"\(countdownTo)"}}}
        """
    }

    // MARK: - A post that cannot be fetched keeps its quiet card

    @Test
    func anArtifactThatCannotBeFetchedMountsNothing() async throws {
        let world = try World()
        world.loader.loadMediaContentForSourceClosure = nil
        world.loader.loadMediaContentForSourceThrowableError = MediaLoaderError.unexpectedResponse

        world.show("$broken")
        try await world.settle()

        #expect(world.registry.liveHostCount == 0)
        #expect(world.presented("$broken") == nil)
        #expect(world.registry.slot(for: "$broken", post: world.post).couldNotStart)
    }

    /// The watchdog asks for a visible post with no app every half second,
    /// which for a failed download was a request every 0.75 s for as long as
    /// the row stayed.
    @Test
    func aFailedDownloadIsNotAskedForOnTheWatchdogsBeat() async throws {
        let world = try World()
        // Through the closure: the mock throws its own error before it counts.
        world.loader.loadMediaContentForSourceClosure = { _ in throw MediaLoaderError.unexpectedResponse }

        world.show("$broken")
        try await Task.sleep(for: .milliseconds(1800))

        #expect(world.loader.loadMediaContentForSourceCallsCount == 1)
    }

    #endif
}
