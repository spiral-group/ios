//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): posts start fast, stay stable and
// never hold the table. The registry's policy under a moving table, a slow
// read, a row coming back, and the app's own comings and goings.
//

import Foundation
import MatrixRustSDKMocks
@testable import Spiral
import Synchronization
import Testing
import UIKit

@MainActor
struct SpiralAppPostLifecycleTests {
    #if DEBUG

    private typealias World = SpiralAppHostRegistryTests.World
    private typealias Counts = SpiralAppHostRegistryTests.Counts
    private typealias FakeHost = SpiralAppHostRegistryTests.FakeHost
    private typealias SpiralAppTestError = SpiralAppHostRegistryTests.SpiralAppTestError

    // MARK: - Never hold the table

    @Test
    func noWebViewIsMadeOrMountedWhileTheTableMoves() async throws {
        let world = try World()
        world.showInTable("$post")

        await world.scrollTable(for: .milliseconds(700))

        #expect(world.hostsMade == 0, "a web view was made under a moving table")
        #expect(world.mountAttempts == 0, "an app was mounted under a moving table")
        #expect(world.registry.scrollWatch.isMoving)

        try await world.settle()
        try await world.settle()
        #expect(world.registry.liveHostCount == 1, "the post never started once the table stopped")
        #expect(world.presented("$post") != nil)
    }

    /// Under the rule until 2026-11-12: a row with a running app takes it back
    /// in a frame of its own, once the table has stopped, and its cover stays
    /// on until it has.
    @Test
    func aRowArrivingUnderAMovingTableTakesItsAppBackOnceItStops() async throws {
        let world = try World()
        world.registry.returnRule = .whenStill
        world.showInTable("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)
        #expect(slot.phase == .ready)

        world.hide("$post")
        #expect(slot.phase == .away, "a row with no app kept saying it showed one")
        world.showInTable("$post")
        #expect(world.presented("$post") == nil, "the app moved in the frame the row arrived in")

        await world.scrollTable(for: .milliseconds(300))
        #expect(world.presented("$post") == nil, "the app moved while the table was moving")
        #expect(slot.phase == .away)

        try await world.settle()
        #expect(world.presented("$post") != nil, "the row never took its app back")
        #expect(slot.phase == .ready)
        #expect(world.hostsMade == 1)
    }

    @Test
    func aRowArrivingUnderAStillTableStillDoesNotTakeItsAppInTheSameFrame() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        world.hide("$post")

        world.show("$post")
        #expect(world.presented("$post") == nil)

        try await world.untilPresented("$post")
        #expect(world.presented("$post") != nil)
    }

    /// Under a finger the run loop is in its tracking mode, where a timer in
    /// `.default` never fires.
    @Test
    func theWatchdogTicksUnderAFinger() throws {
        let world = try World()
        let before = world.registry.watchdogTicks

        let end = Date().addingTimeInterval(1.2)
        while Date() < end {
            RunLoop.main.run(mode: .tracking, before: end)
        }

        #expect(world.registry.watchdogTicks > before)
    }

    /// A shell that never finishes used to hold its slot for ever. The host
    /// bounds the wait and counts as dead, so the post gets another host.
    @Test
    func aHostWhoseShellNeverComesFreesItsSlot() async throws {
        let world = try World()
        world.failNextShell()

        world.show("$post")
        try await world.settle()
        try await world.settle()

        #expect(world.destroyed == 1, "the host with no shell was kept")
        #expect(world.registry.liveHostCount == 1, "the post did not get another host")
        #expect(world.presented("$post") != nil)
    }

    // MARK: - Warm and overlap

    /// By the end of the settle the shell is already loading, instead of
    /// starting then.
    @Test
    func theFirstPostRowWarmsAHostBeforeItsSettleIsOver() async throws {
        let world = try World()
        _ = world.registry.slot(for: "$post", post: world.post)
        world.show("$post")

        try await Task.sleep(for: .milliseconds(150))

        #expect(world.hostsMade == 1, "nothing was warming when the settle ended")
        #expect(world.registry.pool.parkedCount == 1)
        #expect(world.mountAttempts == 0)

        try await world.settle()
        #expect(world.hostsMade == 1, "the post did not take the warm host")
        #expect(world.registry.pool.parkedCount == 0)
    }

    /// Each post that arrives, not only the room's first: its shell comes up
    /// during the settle, which is most of what a start costs.
    @Test
    func aLaterRowWarmsItsHostDuringItsSettle() async throws {
        // Two, so that the idle refill stays out of this.
        let world = try World(maxLiveHosts: 2)
        world.show("$first")
        try await world.settle()
        #expect(world.hostsMade == 1)

        world.show("$second")
        try await Task.sleep(for: .milliseconds(150))

        #expect(world.hostsMade == 2, "the second post's shell only starts when its settle ends")
        #expect(world.mountAttempts == 1, "the second post was already mounted, so this proves nothing")
    }

    @Test
    func aRowThatMayNotRunWarmsNothing() async throws {
        let world = try World()
        _ = world.registry.slot(for: "$post", post: world.post)
        world.show("$post", mayRun: false)

        try await world.settle()

        #expect(world.hostsMade == 0)
    }

    /// The download used to come first and the read last, with the web view
    /// between them.
    @Test
    func theHostAndTheReadStartWhileTheArtifactIsOnItsWay() async throws {
        let world = try World()
        world.holdArtifact()

        world.show("$post")
        try await world.settle()

        #expect(world.hostsMade == 1, "no web view was warming during the download")
        #expect(world.room.loadSpiralAppRelationsForCallsCount == 1, "nobody was reading during the download")
        #expect(world.mountAttempts == 0)
        #expect(world.registry.liveHostCount == 0)

        world.releaseArtifact()
        try await world.settle()
        #expect(world.registry.liveHostCount == 1)
        #expect(world.hostsMade == 1, "the app did not take the host that warmed for it")
    }

    /// Not only the room's first post: the first row's warm-up is long used
    /// by now, and this one's download is the only time left to overlap.
    @Test
    func aLaterPostWarmsItsHostAlongsideItsDownload() async throws {
        // Two, so that the idle refill stays out of this: it would make the
        // same host by another road.
        let world = try World(maxLiveHosts: 2)
        world.show("$first")
        try await world.settle()
        #expect(world.hostsMade == 1)

        let other = try world.editedPost()
        world.holdArtifact()
        world.show("$second", post: other)
        try await world.settle()

        #expect(world.hostsMade == 2, "no web view was warming during the download")
        #expect(world.mountAttempts == 1)
        world.releaseArtifact()
    }

    @Test
    func aWarmHostThatDiesIsNotHandedOut() async throws {
        var made: [FakeHost] = []
        let pool = SpiralAppHostPool {
            let host = FakeHost(counts: Counts())
            made.append(host)
            return host
        }

        pool.prewarm()
        pool.prewarm()
        #expect(made.count == 1, "warming twice made two hosts")

        made[0].onContentProcessDied?()

        #expect(pool.parkedCount == 0, "a dead host stayed parked")
        #expect(pool.acquire() !== made[0])
    }

    /// The second post's host is made while nothing is happening, not on the
    /// way to its first paint.
    @Test
    func aSpareHostIsMadeWhenIdleForAPostThatCouldUseIt() async throws {
        let world = try World()
        world.show("$first")
        _ = world.registry.slot(for: "$next", post: world.post)
        try await world.settle()
        #expect(world.hostsMade == 1)

        try await Task.sleep(for: .milliseconds(700))
        #expect(world.hostsMade == 2, "nothing was made ready for the next post")
        #expect(world.registry.pool.parkedCount == 1)

        try await Task.sleep(for: .milliseconds(1200))
        #expect(world.hostsMade == 2, "refilling did not stop at one")
    }

    @Test
    func aRoomWithOnePostKeepsNoSpareHost() async throws {
        let world = try World()
        world.show("$only")
        try await world.settle()

        try await Task.sleep(for: .milliseconds(1200))

        #expect(world.hostsMade == 1, "a spare process for a room with nothing to run on it")
    }

    @Test
    func noSpareHostIsMadeUnderAMovingTable() async throws {
        let world = try World()
        world.showInTable("$first")
        _ = world.registry.slot(for: "$next", post: world.post)
        try await world.settle()
        let made = world.hostsMade

        await world.scrollTable(for: .milliseconds(1200))

        #expect(world.hostsMade == made)
    }

    /// Live and parked together stay within the cap: the spare is a slot's
    /// worth of process, not one on top.
    @Test
    func spareHostsDoNotTakeTheWebViewsPastTheCap() async throws {
        let world = try World(maxLiveHosts: 2)
        world.show("$first")
        world.show("$second")
        _ = world.registry.slot(for: "$next", post: world.post)
        try await world.settle()

        try await Task.sleep(for: .milliseconds(1200))

        #expect(world.registry.liveHostCount == 2)
        #expect(world.registry.pool.parkedCount == 0)
    }

    @Test
    func aMemoryWarningPutsSpareHostsOff() async throws {
        let world = try World()
        world.show("$first")
        _ = world.registry.slot(for: "$next", post: world.post)
        try await world.settle()
        try await Task.sleep(for: .milliseconds(700))
        #expect(world.registry.pool.parkedCount == 1)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await Task.sleep(for: .milliseconds(1200))

        #expect(world.registry.pool.parkedCount == 0, "the warning's process came straight back")
    }

    // MARK: - Mount first, read alongside

    /// The app starts booting without waiting for the read, and the row's
    /// cover stays on until there is a state to show.
    @Test
    func aMountDoesNotWaitForTheReadAndTheCoverDoes() async throws {
        let world = try World()
        let isReleased = Mutex(false)
        world.room.loadSpiralAppRelationsForClosure = { _ in
            while !isReleased.withLock({ $0 }) {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return .success([])
        }

        world.show("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)

        #expect(world.mountAttempts == 1, "the mount waited for the read")
        #expect(slot.phase == .loading, "the cover lifted off a state nobody had read")

        isReleased.withLock { $0 = true }
        try await world.settleOnReturn()
        #expect(slot.phase == .ready)
    }

    /// The SDK takes any push as the state, so the empty fold of a read still
    /// running would draw an untouched post, cover or no cover.
    @Test
    func nothingUnvouchedForIsPushedToTheApp() async throws {
        let world = try World()
        let isReleased = Mutex(false)
        world.room.loadSpiralAppRelationsForClosure = { _ in
            while !isReleased.withLock({ $0 }) {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return .success([Self.action(on: "$post", seq: 1)])
        }

        world.show("$post")
        try await world.settle()
        let early = try #require(world.lastHost?.pushes.filter { $0["kind"] as? String == "state.changed" })
        #expect(early.isEmpty, "the app was pushed a state nobody had read: \(early)")

        isReleased.withLock { $0 = true }
        try await world.settleOnReturn()
        let pushes = try #require(world.lastHost?.pushes)
        #expect(pushes.contains { $0["seq"] as? Int == 1 }, "the read never reached the app")
    }

    /// A hole in the actions used to cost seconds of card, every mount.
    @Test
    func aHoleInThePostsActionsDoesNotHoldItsCard() async throws {
        let world = try World()
        world.room.loadSpiralAppRelationsForReturnValue = .success([Self.action(on: "$post", seq: 1), Self.action(on: "$post", seq: 3)])

        world.show("$post")
        try await world.settle()

        #expect(world.registry.slot(for: "$post", post: world.post).phase == .ready, "a hole kept the post on its card")
        let pushes = try #require(world.lastHost?.pushes)
        #expect(pushes.contains { $0["seq"] as? Int == 3 }, "the app was not told what could be read")
    }

    /// Never an empty post: the app comes down, the card says so, and the read
    /// is tried again after a while rather than twice a second.
    @Test
    func aPostWhoseStateCouldNotBeReadSaysSoAndTriesAgainLater() async throws {
        let world = try World()
        world.room.loadSpiralAppRelationsForReturnValue = .failure(.sdkError(SpiralAppTestError.noSubscription))

        world.show("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)

        #expect(slot.phase == .waiting, "the cover lifted off a post that could not be read")
        #expect(slot.couldNotStart)
        #expect(world.presented("$post") == nil)
        #expect(world.registry.liveHostCount == 0)
        let lostToTheFirstTry = world.room.loadSpiralAppRelationsForCallsCount

        try await Task.sleep(for: .milliseconds(1200))
        #expect(world.room.loadSpiralAppRelationsForCallsCount == lostToTheFirstTry, "the read was retried on the watchdog's beat")

        world.room.loadSpiralAppRelationsForReturnValue = .success([])
        try await Task.sleep(for: .seconds(2))
        #expect(slot.phase == .ready, "the post never tried again")
        #expect(!slot.couldNotStart)
    }

    /// An evicted post comes back from what it knows, with no second read.
    @Test
    func aRemountReadsNothingItAlreadyKnows() async throws {
        let world = try World(maxLiveHosts: 1)
        world.room.subscribeToSpiralEventsTypesListenerReturnValue = .success(TaskHandleSDKMock())
        world.show("$post")
        try await world.settle()
        let reads = world.room.loadSpiralAppRelationsForCallsCount
        #expect(reads == 1)

        world.hide("$post")
        world.show("$other")
        try await world.settle()
        world.hide("$other")
        world.show("$post")
        try await world.settle()

        #expect(world.registry.slot(for: "$post", post: world.post).phase == .ready)
        #expect(world.room.loadSpiralAppRelationsForCallsCount == reads + 1, "only $other had anything to read")
    }

    @Test
    func keptSessionsAreBounded() async throws {
        let world = try World()
        world.room.subscribeToSpiralEventsTypesListenerReturnValue = .success(TaskHandleSDKMock())
        let count = SpiralAppHostRegistry.maxKeptSessions + 8

        for index in 0..<count {
            world.show("$post\(index)", mayRun: false)
            try await Task.sleep(for: .milliseconds(5))
            world.hide("$post\(index)")
        }

        #expect(world.registry.keptSessionCount == SpiralAppHostRegistry.maxKeptSessions)
    }

    // MARK: - Background and foreground

    @Test
    func theBackgroundLeavesNoWebViewsAndComingBackStartsThePostsOnScreen() async throws {
        let world = try World()
        for index in 0..<3 {
            world.show("$post\(index)")
        }
        try await world.settle()
        #expect(world.registry.liveHostCount == 3)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await world.settleOnReturn()

        #expect(world.registry.liveHostCount == 0, "a web view stayed up for iOS to kill")
        #expect(world.registry.pool.parkedCount == 0)

        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await world.settle()

        #expect(world.registry.liveHostCount == 3, "the posts on screen did not come back")
    }

    @Test
    func goingToTheBackgroundLeavesPicturesBehind() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(world.registry.slot(for: "$post", post: world.post).standIn != nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @Test
    func comingBackDoesNotUncoverARoomUnderASheet() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()

        world.registry.setCovered(true)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await world.settle()

        #expect(world.registry.liveHostCount == 0, "a post started under the sheet")

        world.registry.setCovered(false)
        try await world.settle()
        #expect(world.registry.liveHostCount == 1)
    }

    @Test
    func goingBackgroundUnderASheetDoesNotUncoverItEither() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        world.registry.setCovered(true)
        world.registry.setCovered(false)
        try await world.settle()

        #expect(world.registry.liveHostCount == 0, "a post started in the background")
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @Test
    func comingBackGivesAPostWithAFailureAFreshStart() async throws {
        let world = try World()
        world.room.loadSpiralAppRelationsForReturnValue = .failure(.sdkError(SpiralAppTestError.noSubscription))
        world.show("$post")
        try await world.settle()
        #expect(world.registry.liveHostCount == 0)

        world.room.loadSpiralAppRelationsForReturnValue = .success([])
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await world.settle()

        #expect(world.registry.liveHostCount == 1, "the post sat out its wait after the app came back")
    }

    /// Actions can go by unheard while the app is away, so the kept session
    /// asks the authority once.
    @Test
    func comingBackReadsThePostAgain() async throws {
        let world = try World()
        world.room.subscribeToSpiralEventsTypesListenerReturnValue = .success(TaskHandleSDKMock())
        world.show("$post")
        try await world.settle()
        let reads = world.room.loadSpiralAppRelationsForCallsCount

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await world.settle()

        #expect(world.room.loadSpiralAppRelationsForCallsCount == reads + 1)
    }

    @Test
    func aMemoryWarningGivesBackWhatTheReaderCannotSee() async throws {
        let world = try World()
        world.show("$seen")
        world.show("$unseen")
        try await world.settle()
        world.hide("$unseen")
        let seen = world.registry.slot(for: "$seen", post: world.post)
        let unseen = world.registry.slot(for: "$unseen", post: world.post)
        #expect(unseen.standIn != nil)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await world.settleOnReturn()

        #expect(world.registry.liveHostCount == 1, "an app nobody can see outlived the warning")
        #expect(seen.phase == .ready, "the warning took the post being read")
        #expect(unseen.standIn == nil)
        #expect(world.registry.pool.parkedCount == 0)
        #expect(world.registry.keptSessionCount == 1)
    }

    // MARK: - No blank card

    /// The table rested before the start, so the start takes the first picture:
    /// a reader who flicks away at once must not come back to the card.
    @Test
    func aStartLeavesAPictureForTheRowsReturn() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)
        #expect(world.snapshotsTaken == 0, "the picture was taken before the page could have drawn")

        try await world.settle()
        #expect(slot.standIn != nil, "nothing was kept to stand in for the app")
        #expect(world.snapshotsTaken == 1)
    }

    @Test
    func aRowLeavingInSightLeavesAPictureForItsReturn() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        let taken = world.snapshotsTaken

        world.hide("$post")

        #expect(world.snapshotsTaken == taken + 1)
        #expect(world.registry.slot(for: "$post", post: world.post).standIn != nil)
    }

    /// WebKit hands back one colour for a web view scrolled out of the window;
    /// standing that in for the app was the grey rectangle (2026-11-12).
    @Test
    func aBlankPictureIsNeverKept() async throws {
        let world = try World()
        world.takeBlankSnapshots()
        world.show("$post")
        try await world.settle()

        world.hide("$post")

        #expect(world.snapshotsTaken > 0)
        #expect(world.registry.slot(for: "$post", post: world.post).standIn == nil, "a blank picture stood in for the app")
    }

    @Test
    func aBlankPictureNeverReplacesAGoodOne() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)
        let good = try #require(slot.standIn)

        world.takeBlankSnapshots()
        world.hide("$post")

        #expect(slot.standIn === good, "a blank picture replaced a good one")
    }

    /// A row the reader can't see has nothing worth a picture.
    @Test
    func aRowOutOfSightTakesNoPicture() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        let taken = world.snapshotsTaken

        world.moveOffScreen("$post")
        try await Task.sleep(for: .milliseconds(700))
        world.hide("$post")

        #expect(world.presented("$post") == nil, "the app out of sight was not paused")
        #expect(world.snapshotsTaken == taken, "a picture was taken of a row out of sight")
    }

    /// One picture per rest of the table, of each live post in sight, and
    /// none of a post paused out of sight.
    @Test
    func aTableRestTakesOnePictureOfEachLivePostInSight() async throws {
        let world = try World()
        world.showInTable("$seen")
        world.showInTable("$gone", below: 300)
        try await world.settle()
        world.surface("$gone")?.frame.origin.y = 3000
        try await Task.sleep(for: .milliseconds(700))
        #expect(world.presented("$gone") == nil)
        let taken = world.snapshotsTaken

        await world.flingTable(for: .milliseconds(100))
        try await world.settle()

        #expect(world.snapshotsTaken == taken + 1)
    }

    /// § 5.33: a snapshot after every state change is what made the
    /// picture-based registries lag.
    @Test
    func aStateChangeTakesNoPicture() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        try await world.settle()

        let taken = world.snapshotsTaken
        world.room.loadSpiralAppRelationsForReturnValue = .success([Self.action(on: "$post", seq: 1)])
        try await world.settle()

        #expect(world.snapshotsTaken == taken)
    }

    /// Back in a window a page shows nothing until it has drawn, and that
    /// frame or two was the white card.
    @Test
    func aRowStaysCoveredUntilThePageHasDrawn() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)
        world.hide("$post")

        world.holdPaint()
        world.show("$post")
        try await world.settleOnReturn()

        #expect(world.presented("$post") != nil)
        #expect(slot.phase == .away, "the cover lifted off a page that had not drawn")

        world.releasePaint()
        try await world.settleOnReturn()
        #expect(slot.phase == .ready)
    }

    /// A still picture must not pass for an app that has stopped.
    @Test
    func anAppThatDoesNotDrawOnReturnIsReplaced() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        world.hide("$post")

        world.stopPainting()
        world.show("$post")
        try await world.settle()

        #expect(world.destroyed == 1, "the silent host was kept")
        #expect(world.hostsMade == 2, "the post was not given another host")
        #expect(world.mountAttempts == 2)
    }

    @Test
    func aFailedStartDropsThePicture() async throws {
        let world = try World(maxLiveHosts: 1)
        world.show("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)
        world.hide("$post")
        world.show("$other")
        try await world.settle()
        world.hide("$other")
        #expect(slot.standIn != nil)

        world.room.loadSpiralAppRelationsForReturnValue = .failure(.sdkError(SpiralAppTestError.noSubscription))
        world.show("$post")
        try await world.settle()

        #expect(slot.standIn == nil, "a picture stood in for a post that can't start")
        #expect(slot.couldNotStart)
    }

    @Test
    func anEditDropsThePictureOfTheOldVersion() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)
        world.hide("$post")
        #expect(slot.standIn != nil)

        world.show("$post")
        world.surface("$post")?.post = try world.editedPost()
        try await world.settleOnReturn()

        #expect(slot.standIn == nil)
    }

    @Test
    func picturesOfPostsWithNoRowAreBounded() async throws {
        let world = try World(maxLiveHosts: 1)
        var slots: [SpiralAppSlot] = []

        for index in 0..<(SpiralAppHostRegistry.maxStandIns + 3) {
            world.show("$post\(index)")
            try await world.settle()
            slots.append(world.registry.slot(for: "$post\(index)", post: world.post))
            world.hide("$post\(index)")
        }

        #expect(slots.count { $0.standIn != nil } == SpiralAppHostRegistry.maxStandIns)
        #expect(slots.last?.standIn != nil, "the newest picture went first")
    }

    // MARK: - Off-screen posts stop working

    /// WebKit counts this web view as visible, so only leaving the window
    /// pauses it. What runs is what is on screen, whatever is kept.
    @Test
    func anAppScrolledOutOfSightLeavesTheWindowAndStaysLive() async throws {
        let world = try World()
        world.show("$seen")
        world.show("$gone")
        try await world.settle()
        try await world.settle()
        let gone = world.registry.slot(for: "$gone", post: world.post)
        #expect(gone.phase == .ready)

        // Still in the window, as a timeline keeps rows past the viewport.
        world.surface("$gone")?.frame.origin.y = 2000
        try await Task.sleep(for: .milliseconds(700))

        #expect(world.presented("$gone") == nil, "an app nobody can see stayed in the window")
        #expect(gone.phase == .away)
        #expect(gone.standIn != nil, "nothing was kept for the row's return")
        #expect(world.registry.liveHostCount == 2, "pausing took the app down")
        #expect(world.presented("$seen") != nil, "the post being read was paused")
        #expect(world.mountAttempts == 2)

        world.surface("$gone")?.frame.origin.y = 0
        try await Task.sleep(for: .milliseconds(800))

        #expect(world.presented("$gone") != nil, "the row never took its app back")
        #expect(gone.phase == .ready)
        #expect(world.mountAttempts == 2, "coming back cost a mount")
    }

    @Test
    func nothingIsPausedWhileTheTableMoves() async throws {
        let world = try World()
        world.showInTable("$post")
        try await world.settle()
        world.surface("$post")?.frame.origin.y = 2000

        await world.scrollTable(for: .milliseconds(700))

        #expect(world.presented("$post") != nil, "a web view left its row under a moving table")
    }

    /// A row past the viewport used to take a host, and a mount, from a post
    /// somebody could see.
    @Test
    func aRowOutOfSightStartsNothing() async throws {
        let world = try World()

        world.showOffScreen("$post")
        try await world.settle()

        #expect(world.mountAttempts == 0)
        #expect(world.registry.liveHostCount == 0)
        #expect(world.registry.slot(for: "$post", post: world.post).phase == .waiting)

        world.surface("$post")?.frame.origin.y = 0
        try await Task.sleep(for: .milliseconds(900))
        #expect(world.registry.liveHostCount == 1, "it never started once it could be seen")
    }

    /// One live view per post on screen, whatever the table keeps.
    @Test
    func whatRunsNeverExceedsWhatIsOnScreen() async throws {
        let world = try World()
        for index in 0..<4 {
            world.show("$post\(index)")
        }
        try await world.settle()
        for index in 1..<4 {
            world.surface("$post\(index)")?.frame.origin.y = 2000
        }
        try await Task.sleep(for: .milliseconds(700))

        let running = (0..<4).count { world.presented("$post\($0)") != nil }
        #expect(running == 1)
        #expect(world.registry.liveHostCount <= world.registry.maxLiveHosts)
    }

    // MARK: - A kept app comes back

    /// A kept app only moves into its row: no web view is made, nothing is
    /// mounted, so it doesn't wait for the table (operator, 2026-11-12).
    @Test
    func aKeptAppComesBackAtOnceUnderAFling() async throws {
        let world = try World()
        world.registry.returnRule = .atOnce
        world.showInTable("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)
        world.hide("$post")

        world.showInTable("$post")
        await world.flingTable(for: .milliseconds(300))

        #expect(world.registry.scrollWatch.isMoving)
        #expect(world.presented("$post") != nil, "the kept app waited for the table")
        #expect(slot.phase == .ready)
        #expect(world.hostsMade == 1)
        #expect(world.mountAttempts == 1)
    }

    @Test
    func aKeptAppComesBackOnceTheTableDriftsSlowly() async throws {
        let world = try World()
        world.registry.returnRule = .whenCalm
        world.showInTable("$post")
        try await world.settle()
        world.hide("$post")

        world.showInTable("$post")
        await world.scrollTable(for: .milliseconds(500))

        #expect(world.registry.scrollWatch.isMoving)
        #expect(world.presented("$post") != nil, "the kept app waited for a drifting table to stop")
    }

    @Test
    func aKeptAppDoesNotComeBackUnderAFlingWhenItWaitsForCalm() async throws {
        let world = try World()
        world.registry.returnRule = .whenCalm
        world.showInTable("$post")
        try await world.settle()
        world.hide("$post")

        world.showInTable("$post")
        await world.flingTable(for: .milliseconds(400))
        #expect(world.presented("$post") == nil, "the app moved under a fling")

        try await world.settle()
        #expect(world.presented("$post") != nil, "the row never took its app back")
    }

    /// The table re-hosts a row mid-scroll in a millisecond. Its wait goes on.
    @Test
    func aRowThatBouncesKeepsItsReturn() async throws {
        let world = try World()
        world.registry.returnRule = .whenStill
        world.showInTable("$post")
        try await world.settle()
        world.hide("$post")
        world.showInTable("$post")
        await world.flingTable(for: .milliseconds(100))
        let armings = world.registry.armings

        world.bounce("$post")
        await world.flingTable(for: .milliseconds(100))

        #expect(world.registry.armings == armings, "a bounce restarted the row's wait")
        try await world.settle()
        #expect(world.presented("$post") != nil, "the row never took its app back")
    }

    @Test
    func aRowThatStaysGoneLosesItsReturn() async throws {
        let world = try World()
        world.registry.returnRule = .whenStill
        world.showInTable("$post")
        try await world.settle()
        world.hide("$post")
        world.showInTable("$post")
        await world.flingTable(for: .milliseconds(100))
        let surface = try #require(world.surface("$post"))

        world.hide("$post")
        try await world.settle()

        #expect(surface.presented == nil, "an app went into a row that had left")
    }

    // MARK: - The full-screen viewer

    /// The row has nothing in it while the viewer holds the app: it shows its
    /// picture, not an empty grey frame under the viewer's animation.
    @Test
    func openingTheViewerCoversTheRowWithItsPicture() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)

        world.showViewer("$post")

        #expect(world.viewer("$post")?.presented != nil, "the viewer didn't get the app")
        #expect(world.presented("$post") == nil)
        #expect(slot.phase == .away, "the row showed an empty frame under the viewer")
        #expect(slot.standIn != nil)
    }

    /// A touch made inside the viewer can't reopen it while it slides away (M2):
    /// the row is ready again before `onDismiss`, so the gate closes as the viewer
    /// starts to close, not only when it has gone.
    @Test
    func aClosingViewerCannotBeReopenedByATouchFromInsideIt() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        world.showViewer("$post")
        let activation = try #require(world.registry.activation(for: "$post"))
        activation.recordTouch()

        world.registry.viewerWillClose(eventID: "$post")

        #expect(!activation.consumeForExpand(), "the post reopened the viewer during its slide-out")
    }

    /// The app goes back to its row as the viewer starts to close, and the
    /// viewer slides away showing a picture of it.
    @Test
    func closingTheViewerHandsTheAppBackAtOnce() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        world.showViewer("$post")
        let slot = world.registry.slot(for: "$post", post: world.post)

        world.registry.viewerWillClose(eventID: "$post")
        try await world.settleOnReturn()

        #expect(world.presented("$post") != nil, "the row waited for the viewer to go")
        #expect(slot.phase == .ready)
        let viewer = try #require(world.viewer("$post"))
        #expect(viewer.presented == nil)
        #expect(viewer.subviews.contains { $0 is UIImageView }, "the closing viewer had nothing to show")

        world.hideViewer("$post")
        world.registry.viewerDismissed(eventID: "$post")
        try await world.settleOnReturn()
        #expect(world.presented("$post") != nil, "the viewer took the app with it")
    }

    /// Back from the viewer, the page lays itself out at the row's size a
    /// frame or more later; the cover waits for that, told the row's viewport first.
    @Test
    func theRowStaysCoveredUntilThePageHasLaidOutAtItsSize() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        world.showViewer("$post")
        let slot = world.registry.slot(for: "$post", post: world.post)

        world.holdLayout()
        world.registry.viewerWillClose(eventID: "$post")
        try await world.settleOnReturn()

        #expect(world.presented("$post") != nil)
        #expect(slot.phase == .away, "the cover lifted before the page had laid out at the row's size")
        let asked = try #require(world.layoutsAsked.last)
        #expect(asked.size == CGSize(width: 300, height: 200))
        #expect(asked.viewport == "row", "the page was asked to draw before it had been told it is in a row")

        world.releaseLayout()
        try await world.settleOnReturn()
        #expect(slot.phase == .ready)
    }

    /// A row recycled for another post while the viewer was up must not be
    /// handed this post's app when the viewer closes.
    @Test
    func aRowRecycledUnderTheViewerIsNotHandedItsOldApp() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        world.showViewer("$post")
        let container = try #require(world.viewer("$post")?.presented)
        let recycled = try #require(world.surface("$post"))

        recycled.eventID = "$other"
        world.registry.viewerWillClose(eventID: "$post")
        try await world.settleOnReturn()

        #expect(recycled.presented !== container, "another post's row was handed this post's app")
        world.hideViewer("$post")
        world.registry.viewerDismissed(eventID: "$post")
    }

    /// The table hid the row behind the viewer for reuse while the viewer was
    /// up: it is still in the window and still names this post, but nobody can
    /// see it. The closing viewer keeps the app rather than hand it to a row
    /// the reader won't see; the row in sight takes it at `onDismiss`.
    @Test
    func aRowHiddenUnderTheViewerIsNotHandedTheApp() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        world.showViewer("$post")
        let container = try #require(world.viewer("$post")?.presented)
        let hidden = try #require(world.surface("$post"))

        hidden.isHidden = true
        world.registry.viewerWillClose(eventID: "$post")
        try await world.settleOnReturn()

        #expect(hidden.presented !== container, "a hidden row was handed the app")
        let viewer = try #require(world.viewer("$post"))
        #expect(viewer.presented === container, "the app left the viewer for a row nobody can see")
        #expect(!viewer.subviews.contains { $0 is UIImageView }, "the viewer froze on a picture for a hand-back that went nowhere")

        // The table shows the row again; the viewer goes, and the row takes the app back.
        hidden.isHidden = false
        world.hideViewer("$post")
        world.registry.viewerDismissed(eventID: "$post")
        hidden.reclaim()
        try await world.settleOnReturn()
        #expect(hidden.presented === container, "the row in sight never got the app back")
    }

    /// Closed as fast as it opened: the viewer arrives already closing, and
    /// must not take the app away from the row the reader is going back to.
    @Test
    func aViewerClosedBeforeItArrivesNeverTakesTheApp() async throws {
        let world = try World()
        world.show("$post")
        try await world.settle()
        let slot = world.registry.slot(for: "$post", post: world.post)

        world.registry.viewerWillClose(eventID: "$post")
        world.showViewer("$post")

        #expect(world.presented("$post") != nil, "a closing viewer took the app")
        #expect(world.viewer("$post")?.presented == nil)
        #expect(slot.phase == .ready)
        world.hideViewer("$post")
        world.registry.viewerDismissed(eventID: "$post")
    }

    // MARK: - The table's pace

    @Test
    func aFlingIsNotCalm() {
        var pace = SpiralAppScrollPace()
        let start = ContinuousClock.now
        for frame in 0..<20 {
            pace.note(offset: CGFloat(frame) * 40, at: start + .milliseconds(16 * frame))
        }

        #expect(pace.speed > SpiralAppScrollPace.calmSpeed)
        #expect(!pace.isCalm(at: start + .milliseconds(16 * 20)))
    }

    /// The tail of a fling is calm once it has stayed slow, and a fast frame ends it.
    @Test
    func aDriftIsCalmOnlyOnceItHasLasted() {
        var pace = SpiralAppScrollPace()
        let start = ContinuousClock.now
        var offset: CGFloat = 0
        func frame(_ index: Int, step: CGFloat) {
            offset += step
            pace.note(offset: offset, at: start + .milliseconds(16 * index))
        }

        for index in 0..<10 {
            frame(index, step: 40)
        }
        for index in 10..<14 {
            frame(index, step: 2)
        }
        #expect(!pace.isCalm(at: start + .milliseconds(16 * 13)), "calm after a few slow frames")

        for index in 14..<18 {
            frame(index, step: 2)
        }
        #expect(pace.isCalm(at: start + .milliseconds(16 * 17)), "a drift of 125 pt/s for over 100 ms wasn't calm")

        frame(18, step: 40)
        #expect(!pace.isCalm(at: start + .milliseconds(16 * 18)), "a fast frame didn't end the calm")
    }

    /// Two offsets a rest apart say nothing about how fast the table goes now.
    @Test
    func aMovementAfterARestStartsWithNoPace() {
        var pace = SpiralAppScrollPace()
        let start = ContinuousClock.now
        pace.note(offset: 0, at: start)
        pace.note(offset: 10, at: start + .milliseconds(300))

        #expect(pace.speed == 0)
        #expect(!pace.isCalm(at: start + .milliseconds(450)))
    }

    /// One bare action on `post`, numbered.
    private static func action(on post: String, seq: Int) -> String {
        """
        {"type":"com.spiral.app.action","event_id":"$action\(seq)","sender":"@a:spiral.md","origin_server_ts":\(seq),
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"\(post)"},
                    "op":{"set":{"path":"n","value":\(seq)}},"seq":\(seq)}}
        """
    }

    #endif
}
