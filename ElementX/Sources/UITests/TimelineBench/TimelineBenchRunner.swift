//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 item 16): the timeline benchmark's scenarios. One scenario per launch, so one
// can't warm the caches of the next; the script runs each a few times and takes the medians.
// Compiled only with SPIRAL_TIMELINE_BENCH, which Tools/Scripts/run-timeline-bench.sh passes and no project file sets.
//

#if SPIRAL_TIMELINE_BENCH

import Kingfisher
import SwiftUI

@MainActor
final class TimelineBenchRunner {
    private enum Direction {
        case older
        case newer
    }
    
    private let stack: NavigationStackCoordinator
    private let analytics: AnalyticsServiceProtocol
    private let session = TimelineBenchSession()
    private let probe = TimelineBenchProbe.shared
    private let meter = TimelineBenchRunLoopMeter()
    private let frames: TimelineBenchFrameLog
    
    private let environment = ProcessInfo.processInfo.environment
    private var metrics: [String: Double] = [:]
    private var room: TimelineBenchRoom?
    /// The main thread's share while nothing happens, which is this harness's own frame log. Taken off what's measured.
    private var idleShare = 0.0
    
    private var scenario: String {
        environment["TIMELINE_BENCH_SCENARIO"] ?? "scroll"
    }
    
    /// Points per second. A firm flick, kept up all the way through the chat.
    private var scrollSpeed: CGFloat {
        CGFloat(Double(environment["TIMELINE_BENCH_SPEED"] ?? "") ?? 2000)
    }
    
    init(stack: NavigationStackCoordinator, analytics: AnalyticsServiceProtocol) {
        self.stack = stack
        self.analytics = analytics
        frames = TimelineBenchFrameLog(meter: meter)
    }
    
    func run() async {
        TimelineBenchCellHooks.install()
        await clearImageCache()
        meter.start()
        frames.start()
        await waitUntilIdle()
        await measureIdleShare()
        
        switch scenario {
        case "open": await runOpen()
        case "update": await runUpdates()
        case "scroll": await runScroll()
        case "pagination": await runPagination()
        case "messages": await runMessages()
        case "reaction": await runReaction()
        case "post": await runPost()
        case "postscroll": await runPostScroll()
        case "soak": await runSoak()
        case "calibrate": await runCalibrate()
        default: fatalError("Unknown scenario \(scenario)")
        }
        
        writeResults()
        exit(0)
    }
    
    private func clearImageCache() async {
        ImageCache.default.clearMemoryCache()
        await withCheckedContinuation { continuation in
            ImageCache.default.clearDiskCache { continuation.resume() }
        }
    }
    
    // MARK: - Opening the room
    
    /// A first open in a new process, then later opens of the same room, as a person going back to a chat.
    private func runOpen() async {
        let rows = rowCount(default: 300)
        await open(rows: rows, name: "open.cold")
        record("open.cold.memory_mb", TimelineBenchMemory.footprint / 1_048_576)
        
        var opens = [TimelineBenchOpen]()
        for _ in 0..<5 {
            await close()
            await opens.append(open(rows: rows, name: nil))
        }
        record("open.warm.first_frame_ms", opens.map(\.firstFrame).median)
        record("open.warm.first_rows_ms", opens.map(\.firstRows).median)
        record("open.warm.first_rows_cpu_ms", opens.map(\.firstRowsCPU).median)
        record("open.warm.settled_ms", opens.map(\.settled).median)
        record("open.warm.memory_mb", TimelineBenchMemory.footprint / 1_048_576)
        
        // Where a chat with unread opens: at the "New" divider, a few screens up from the end.
        await close()
        await open(rows: rows, hasUnread: true, name: "open.unread")
    }
    
    @discardableResult
    private func open(rows: Int, olderRows: Int = 0, hasUnread: Bool = false, name: String?) async -> TimelineBenchOpen {
        // A "New" divider decides where a chat opens, so a chat without unread has none.
        let fixtureRows = session.fixture.rows(count: rows + olderRows).filter { hasUnread || $0.kind != "readMarker" }
        let items = fixtureRows.map(\.item)
        probe.kinds = Dictionary(fixtureRows.map { ($0.item.id.uniqueID.value, $0.kind) }) { first, _ in first }
        probe.resetCounts()
        
        let room = TimelineBenchRoom(items: Array(items.suffix(rows)), olderItems: Array(items.dropLast(rows)), hasUnread: hasUnread, session: session, analytics: analytics)
        self.room = room
        
        let startWall = TimelineBenchClock.wall
        let startCPU = TimelineBenchClock.cpu
        let mark = mainThreadMark()
        stack.push(room.makeCoordinator(), animated: false)
        
        let firstRows: (wall: UInt64, cpu: UInt64) = await withCheckedContinuation { continuation in
            meter.onSleep = { [unowned self] in
                guard probe.configurations > 0 else { return }
                meter.onSleep = nil
                continuation.resume(returning: (TimelineBenchClock.wall - startWall, TimelineBenchClock.cpu - startCPU))
            }
        }
        let configuredInFirstCommit = probe.configurations
        await nextFrame()
        let firstFrameMs = Double(TimelineBenchClock.wall - startWall) / 1_000_000
        
        await waitUntilIdle()
        let settled = Double(TimelineBenchClock.wall - startWall) / 1_000_000 - idleWindow * 1000
        let firstRowsMs = Double(firstRows.wall) / 1_000_000
        let firstRowsCPUMs = Double(firstRows.cpu) / 1_000_000
        
        if let name {
            record("\(name).first_rows_ms", firstRowsMs)
            record("\(name).first_frame_ms", firstFrameMs)
            record("\(name).first_rows_cpu_ms", firstRowsCPUMs)
            record("\(name).settled_ms", settled)
            record("\(name).settled_cpu_ms", mainThreadWork(since: mark).cpu.milliseconds)
            record("\(name).cells_in_first_commit", Double(configuredInFirstCommit))
        }
        return TimelineBenchOpen(firstFrame: firstFrameMs, firstRows: firstRowsMs, firstRowsCPU: firstRowsCPUMs, settled: settled)
    }
    
    private func close() async {
        stack.pop(animated: false)
        room = nil
        await waitUntilIdle()
        try? await Task.sleep(for: .milliseconds(300))
    }
    
    // MARK: - Updates
    
    /// One new row, one changed row, then a burst of 50, each at 100, 300 and 500 rows.
    private func runUpdates() async {
        for rows in [100, 300, 500] {
            await open(rows: rows, name: nil)
            await measureAppends(rows: rows)
            await measureChanges(rows: rows)
            await measureBurst(rows: rows, isPaced: false)
            await measureBurst(rows: rows, isPaced: true)
            await close()
        }
    }
    
    private func measureAppends(rows: Int) async {
        var costs = [TimelineBenchUpdateCost]()
        for number in 0..<20 {
            guard let room else { return }
            await costs.append(measuredUpdate(room.items + [TimelineBenchFixture.incomingMessage(number)]))
        }
        recordUpdates(costs, name: "update.\(rows).append")
    }
    
    private func measureChanges(rows: Int) async {
        var costs = [TimelineBenchUpdateCost]()
        for number in 0..<20 {
            guard let room, let (index, item) = newestPlainText(in: room.items) else { return }
            var changed = item
            changed.properties.reactions = number.isMultiple(of: 2) ? [TimelineBenchFixture.reaction("👍")] : []
            var items = room.items
            items[index] = changed
            await costs.append(measuredUpdate(items))
        }
        recordUpdates(costs, name: "update.\(rows).change")
    }
    
    private func measureBurst(rows: Int, isPaced: Bool) async {
        guard var items = room?.items else { return }
        let name = "update.\(rows).burst\(isPaced ? "_paced" : "")"
        let mark = mainThreadMark()
        frames.beginRecording()
        
        var builds = [TimelineBenchUpdateCost]()
        for number in 0..<50 {
            items.append(TimelineBenchFixture.incomingMessage((isPaced ? 2000 : 1000) + number))
            let build = await timedUpdate(items)
            builds.append(.init(buildWall: build.wall, buildCPU: build.cpu, busyWall: 0, busyCPU: 0))
            if isPaced {
                await nextFrame()
            }
        }
        await waitUntilIdle()
        
        let recorded = frames.endRecording()
        record("\(name).build_cpu_ms_p50", builds.map(\.buildCPU).milliseconds.median)
        record("\(name).build_cpu_ms_max", builds.map(\.buildCPU).milliseconds.max() ?? 0)
        let work = mainThreadWork(since: mark)
        record("\(name).main_cpu_ms", work.cpu.milliseconds)
        record("\(name).main_wall_ms", work.wall.milliseconds)
        recordFrames(recorded, name: name)
    }
    
    private func measuredUpdate(_ items: [RoomTimelineItemProtocol]) async -> TimelineBenchUpdateCost {
        let mark = mainThreadMark()
        let build = await timedUpdate(items)
        await waitUntilIdle()
        let work = mainThreadWork(since: mark)
        return .init(buildWall: build.wall, buildCPU: build.cpu, busyWall: work.wall, busyCPU: work.cpu)
    }
    
    /// The time the view model spends on an update: `buildTimelineViews` and what it starts in the same turn. The update
    /// reaches the view model through the main queue, so it runs between these two blocks and nothing else does.
    private func timedUpdate(_ items: [RoomTimelineItemProtocol]) async -> (wall: UInt64, cpu: UInt64) {
        let stamp = TimelineBenchStamp()
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                stamp.wall = TimelineBenchClock.wall
                stamp.cpu = TimelineBenchClock.cpu
            }
            room?.update(items)
            DispatchQueue.main.async {
                continuation.resume(returning: (TimelineBenchClock.wall - stamp.wall, TimelineBenchClock.cpu - stamp.cpu))
            }
        }
    }
    
    private func recordUpdates(_ costs: [TimelineBenchUpdateCost], name: String) {
        record("\(name).build_cpu_ms_p50", costs.map(\.buildCPU).milliseconds.median)
        record("\(name).build_cpu_ms_p95", costs.map(\.buildCPU).milliseconds.percentile(95))
        record("\(name).build_wall_ms_p50", costs.map(\.buildWall).milliseconds.median)
        record("\(name).total_cpu_ms_p50", costs.map(\.busyCPU).milliseconds.median)
        record("\(name).total_cpu_ms_p95", costs.map(\.busyCPU).milliseconds.percentile(95))
        record("\(name).total_wall_ms_p50", costs.map(\.busyWall).milliseconds.median)
    }
    
    private func newestPlainText(in items: [RoomTimelineItemProtocol]) -> (index: Int, item: TextRoomTimelineItem)? {
        for (index, item) in items.enumerated().reversed() {
            if let item = item as? TextRoomTimelineItem, item.properties.reactions.isEmpty || item.id.uniqueID.value.hasPrefix("incoming") {
                return (index, item)
            }
        }
        return nil
    }
    
    // MARK: - Scrolling
    
    /// Up to the oldest row and back, twice. The first way up builds every row kind for the first time; the rest is reuse.
    private func runScroll() async {
        await open(rows: rowCount(default: TimelineBenchFixture.maximumRowCount), hasUnread: true, name: nil)
        await goToEnd()
        let startMemory = TimelineBenchMemory.footprint
        record("memory.open_mb", startMemory / 1_048_576)
        probe.resetCosts()
        
        var memory = [Double]()
        await scroll(.older, name: "scroll.up1", memory: &memory)
        recordRowCosts(prefix: "rowcold")
        probe.resetCosts()
        await scroll(.newer, name: "scroll.down1", memory: &memory)
        await scroll(.older, name: "scroll.up2", memory: &memory)
        await scroll(.newer, name: "scroll.down2", memory: &memory)
        recordRowCosts(prefix: "rowwarm")
        
        record("memory.peak_mb", (memory.max() ?? 0) / 1_048_576)
        record("memory.end_of_scroll_mb", TimelineBenchMemory.footprint / 1_048_576)
        await waitUntilIdle()
        try? await Task.sleep(for: .seconds(3))
        record("memory.after_idle_mb", TimelineBenchMemory.footprint / 1_048_576)
        record("scroll.cells_made", Double(probe.cellIDs.count))
    }
    
    /// The way up through a chat that isn't all loaded: 100 rows, then a page at a time as the table asks, without slowing down.
    private func runPagination() async {
        await open(rows: 100, olderRows: TimelineBenchFixture.maximumRowCount - 100, name: nil)
        var memory = [Double]()
        await scroll(.older, name: "scroll.paginated", memory: &memory)
        record("scroll.paginated.pages", Double(room?.pagesLoaded ?? 0))
    }
    
    /// Up and down until the time set by the script is over, for a profiler to watch.
    private func runSoak() async {
        await open(rows: rowCount(default: TimelineBenchFixture.maximumRowCount), name: nil)
        let seconds = Double(environment["TIMELINE_BENCH_SECONDS"] ?? "") ?? 40
        let end = Date.now.addingTimeInterval(seconds)
        var memory = [Double]()
        var direction = Direction.older
        while Date.now < end {
            await scroll(direction, name: "soak", memory: &memory)
            direction = direction == .older ? .newer : .older
        }
    }
    
    /// Checks the frame log against stalls of a known length, and shows what it reports when nothing is happening.
    private func runCalibrate() async {
        await open(rows: 100, name: nil)
        
        frames.beginRecording()
        try? await Task.sleep(for: .seconds(5))
        recordFrames(frames.endRecording(), name: "calibrate.idle")
        
        var ticks = 0
        frames.onTick = { _ in
            ticks += 1
            if ticks.isMultiple(of: 60) {
                usleep(40000)
            }
            return 0
        }
        frames.beginRecording()
        try? await Task.sleep(for: .seconds(5))
        frames.onTick = nil
        recordFrames(frames.endRecording(), name: "calibrate.stalls_of_40ms")
    }
    
    private func scroll(_ direction: Direction, name: String, memory: inout [Double]) async {
        guard let table = findTable() else { fatalError("No timeline table") }
        
        probe.resetCounts()
        let webViewsBefore = probe.webViewsMade
        let mountsBefore = probe.mounts
        let tracker = TimelineBenchJumpTracker(table: table)
        let sign: CGFloat = direction == .older ? 1 : -1
        let speed = scrollSpeed
        var lastTarget = CACurrentMediaTime()
        var samples = [Double]()
        var tickCount = 0
        
        frames.beginRecording()
        await withCheckedContinuation { continuation in
            frames.onTick = { [unowned self] link in
                let jump = tracker.jumpSinceLastFrame()
                
                let limit = direction == .older ? table.contentSize.height + table.adjustedContentInset.bottom - table.bounds.height : -table.adjustedContentInset.top
                // By the time passed, so a late frame moves further, and from where the table is, as it shifts its offset
                // when rows come in at a different height from their estimate, and a real fling goes on from there.
                let wanted = table.contentOffset.y + sign * speed * CGFloat(link.targetTimestamp - lastTarget)
                lastTarget = link.targetTimestamp
                let isPastLimit = direction == .older ? wanted >= limit : wanted <= limit
                let offset = isPastLimit ? limit : wanted
                let isDone = isPastLimit && (direction == .newer || room?.hasOlderItems == false)
                
                tracker.willScroll(to: offset)
                table.contentOffset.y = offset
                
                tickCount += 1
                if tickCount.isMultiple(of: 6) {
                    samples.append(TimelineBenchMemory.footprint)
                }
                if isDone {
                    frames.onTick = nil
                    continuation.resume()
                }
                return jump
            }
        }
        recordFrames(frames.endRecording(), name: name)
        record("\(name).web_views_made", Double(probe.webViewsMade - webViewsBefore))
        record("\(name).mounts", Double(probe.mounts - mountsBefore))
        record("\(name).height_changes", Double(tracker.heightChanges))
        memory.append(contentsOf: samples)
        record("\(name).rows_configured", Double(probe.configurations))
        record("\(name).rows_sized", Double(probe.sizings))
        record("\(name).nested_sizings", Double(probe.nestedSizings))
        record("\(name).row_bodies", Double(probe.rowBodies))
        record("\(name).styler_bodies", Double(probe.stylerBodies))
    }
    
    /// The chat opens at "New" when it has one.
    private func goToEnd() async {
        findTable()?.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
        await waitUntilIdle()
    }
    
    private func findTable() -> UITableView? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.lazy.compactMap { Self.findTable(in: $0) }.first
    }
    
    /// The timeline's table is the flipped one.
    private static func findTable(in view: UIView) -> UITableView? {
        if let table = view as? UITableView, table.transform.d < 0 {
            return table
        }
        return view.subviews.lazy.compactMap { findTable(in: $0) }.first
    }
    
    // MARK: - Re-rendering
    
    /// New messages from other people at the end of the chat, ten a second.
    private func runMessages() async {
        await open(rows: rowCount(default: 300), name: nil)
        guard let table = findTable(), var items = room?.items else { fatalError("No timeline table") }
        
        probe.resetCounts()
        let mark = mainThreadMark()
        frames.beginRecording()
        
        var builds = [UInt64]()
        for number in 0..<20 {
            items.append(TimelineBenchFixture.incomingMessage(number))
            await builds.append(timedUpdate(items).cpu)
            try? await Task.sleep(for: .milliseconds(100))
        }
        await waitUntilIdle()
        
        recordFrames(frames.endRecording(), name: "messages")
        record("messages.visible_rows", Double(table.visibleCells.count))
        record("messages.build_cpu_ms_p50", builds.milliseconds.median)
        record("messages.main_cpu_ms", mainThreadWork(since: mark).cpu.milliseconds)
        recordRenders(name: "messages")
    }
    
    /// A reaction landing on a row in the middle of the screen, and the same reaction going away.
    private func runReaction() async {
        await open(rows: rowCount(default: 300), name: nil)
        guard let table = findTable(), let room else { fatalError("No timeline table") }
        
        let visibleIDs = table.visibleCells.compactMap { ($0 as? TimelineItemCell)?.item?.identifier.uniqueID.value }
        record("reaction.visible_rows", Double(visibleIDs.count))
        
        let candidates = room.items.enumerated().compactMap { index, item -> (index: Int, item: TextRoomTimelineItem)? in
            guard let item = item as? TextRoomTimelineItem, item.properties.reactions.isEmpty, visibleIDs.contains(item.id.uniqueID.value) else { return nil }
            return (index, item)
        }
        guard let target = candidates[safe: candidates.count / 2] else { fatalError("No text row on screen") }
        
        for (name, reactions) in [("reaction.add", [TimelineBenchFixture.reaction("🎉")]), ("reaction.remove", [])] {
            var changed = target.item
            changed.properties.reactions = reactions
            var items = room.items
            items[target.index] = changed
            
            probe.resetCounts()
            let cost = await measuredUpdate(items)
            record("\(name).build_cpu_ms", Double(cost.buildCPU) / 1_000_000)
            record("\(name).total_cpu_ms", Double(cost.busyCPU) / 1_000_000)
            recordRenders(name: name)
        }
    }
    
    // MARK: - Interactive posts
    
    /// Stops on each post in turn until its app has drawn, as someone reading the chat would.
    private func runPost() async {
        await open(rows: rowCount(default: TimelineBenchFixture.maximumRowCount), name: nil)
        guard let table = findTable(), let room else { fatalError("No timeline table") }
        
        let rowCount = table.numberOfRows(inSection: 0)
        let posts = room.items.enumerated().filter { $0.element is InteractivePostRoomTimelineItem }.map { (id: $0.element.id.uniqueID.value, row: rowCount - 1 - $0.offset) }
        record("post.posts", Double(posts.count))
        
        var drawn = [Double]()
        var longestFrames = [Double]()
        var jumpFrames = [Double]()
        var startFrames = [Double]()
        var mainCPU = [Double]()
        for post in posts.sorted(by: { $0.row < $1.row }) {
            table.scrollToRow(at: IndexPath(row: post.row, section: 0), at: .middle, animated: false)
            let mark = mainThreadMark()
            let start = TimelineBenchClock.wall
            frames.beginRecording()
            
            var isReady = false
            while !isReady, TimelineBenchClock.wall - start < 5_000_000_000 {
                try? await Task.sleep(for: .milliseconds(10))
                isReady = probe.postSlots[post.id]?.phase == .ready
            }
            if isReady {
                drawn.append(Double(TimelineBenchClock.wall - start) / 1_000_000)
            }
            await waitUntilIdle()
            
            let recorded = frames.endRecording()
            let deltas = zip(recorded, recorded.dropFirst()).map { $1.timestamp - $0.timestamp }
            longestFrames.append((deltas.max() ?? 0) * 1000)
            // The jump builds a screen of rows, which has nothing to do with the post: its settle puts the post's
            // own start at least 250 ms later, so the two can be told apart by when a frame ended.
            let settled = (recorded.first?.timestamp ?? 0) + 0.2
            let frames = zip(recorded, recorded.dropFirst()).map { (end: $1.timestamp, length: $1.timestamp - $0.timestamp) }
            jumpFrames.append((frames.filter { $0.end <= settled }.map(\.length).max() ?? 0) * 1000)
            startFrames.append((frames.filter { $0.end > settled }.map(\.length).max() ?? 0) * 1000)
            mainCPU.append(mainThreadWork(since: mark).cpu.milliseconds)
        }
        
        record("post.drawn", Double(drawn.count))
        record("post.drawn_ms_median", drawn.median)
        record("post.drawn_ms_max", drawn.max() ?? 0)
        record("post.longest_frame_ms_median", longestFrames.median)
        record("post.longest_frame_ms_max", longestFrames.max() ?? 0)
        record("post.jump_frame_ms_median", jumpFrames.median)
        record("post.start_frame_ms_median", startFrames.median)
        record("post.start_frame_ms_max", startFrames.max() ?? 0)
        record("post.main_cpu_ms_median", mainCPU.median)
        record("post.memory_mb", TimelineBenchMemory.footprint / 1_048_576)
    }
    
    /// Lets the newest posts draw, then scrolls through them and back: rows with a running app leave, come back, and
    /// others want a host, all with the table moving.
    private func runPostScroll() async {
        await open(rows: rowCount(default: TimelineBenchFixture.maximumRowCount), name: nil)
        guard let table = findTable(), let room else { fatalError("No timeline table") }
        
        let rowCount = table.numberOfRows(inSection: 0)
        let posts = room.items.enumerated().filter { $0.element is InteractivePostRoomTimelineItem }.map { (id: $0.element.id.uniqueID.value, row: rowCount - 1 - $0.offset) }
        for post in posts.sorted(by: { $0.row < $1.row }).prefix(3) {
            table.scrollToRow(at: IndexPath(row: post.row, section: 0), at: .middle, animated: false)
            let start = TimelineBenchClock.wall
            while probe.postSlots[post.id]?.phase != .ready, TimelineBenchClock.wall - start < 5_000_000_000 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            await waitUntilIdle()
        }
        await goToEnd()
        
        var memory = [Double]()
        await scroll(.older, name: "postscroll.up", memory: &memory)
        await scroll(.newer, name: "postscroll.down", memory: &memory)
        await waitUntilIdle()
        record("postscroll.memory_mb", TimelineBenchMemory.footprint / 1_048_576)
    }
    
    private func recordRenders(name: String) {
        record("\(name).row_bodies", Double(probe.rowBodies))
        record("\(name).rows_rerendered", Double(probe.rowBodyIDs.count))
        record("\(name).styler_bodies", Double(probe.stylerBodies))
        record("\(name).stylers_rerendered", Double(probe.stylerBodyIDs.count))
        record("\(name).cells_configured", Double(probe.configurations))
        record("\(name).cells_sized", Double(probe.sizings))
        record("\(name).configuration_updates", Double(probe.configurationUpdates))
    }
    
    // MARK: - Recording
    
    private func recordFrames(_ frames: [TimelineBenchFrame], name: String) {
        guard frames.count > 2 else { return }
        
        let period = frames.map(\.period).median
        var hitchTime = 0.0
        var hitches = 0
        var dropped = 0.0
        var longest = 0.0
        for (previous, frame) in zip(frames, frames.dropFirst()) {
            let delta = frame.timestamp - previous.timestamp
            longest = max(longest, delta)
            dropped += max(0, (delta / period).rounded() - 1)
            if delta > period * 1.5 {
                hitches += 1
                hitchTime += delta - period
            }
        }
        let duration = (frames.last?.timestamp ?? 0) - (frames.first?.timestamp ?? 0)
        
        let busyCPU = frames.map(\.busyCPU).milliseconds
        let busyWall = frames.map(\.busyWall).milliseconds
        record("\(name).frames", Double(frames.count))
        record("\(name).duration_s", duration)
        record("\(name).refresh_hz", 1 / period)
        record("\(name).hitch_ratio_ms_per_s", hitchTime * 1000 / duration)
        record("\(name).hitches", Double(hitches))
        record("\(name).longest_frame_ms", longest * 1000)
        record("\(name).dropped_frames", dropped)
        record("\(name).main_cpu_ms", busyCPU.reduce(0, +))
        record("\(name).frame_cpu_ms_p50", busyCPU.median)
        record("\(name).frame_cpu_ms_p95", busyCPU.percentile(95))
        record("\(name).frame_cpu_ms_p99", busyCPU.percentile(99))
        record("\(name).frame_cpu_ms_max", busyCPU.max() ?? 0)
        record("\(name).frame_wall_ms_p95", busyWall.percentile(95))
        record("\(name).frames_over_8ms_pct", Double(busyCPU.count { $0 > 1000 / 120 }) * 100 / Double(busyCPU.count))
        record("\(name).frames_over_16ms_pct", Double(busyCPU.count { $0 > 1000 / 60 }) * 100 / Double(busyCPU.count))
        record("\(name).jumps", Double(frames.count { abs($0.jump) > 1.5 })) // The table's own step off the newest edge is a point.
        record("\(name).largest_jump_pt", frames.map { abs($0.jump) }.map(Double.init).max() ?? 0)
    }
    
    private func recordRowCosts(prefix: String) {
        for (kind, cost) in probe.rowCosts {
            let name = "\(prefix).\(kind)"
            record("\(name).count", Double(cost.configureCPU.count))
            record("\(name).configure_us_mean", cost.configureCPU.microseconds.mean)
            record("\(name).size_count", Double(cost.sizeCPU.count))
            record("\(name).size_us_mean", cost.sizeCPU.microseconds.mean)
            record("\(name).first_size_us_mean", cost.firstSizeCPU.microseconds.mean)
            record("\(name).size_us_p95", cost.sizeCPU.microseconds.percentile(95))
            record("\(name).size_us_max", cost.sizeCPU.microseconds.max() ?? 0)
            record("\(name).layout_us_mean", cost.layoutCPU.microseconds.mean)
            record("\(name).total_us_per_row", (cost.configureCPU.sum + cost.sizeCPU.sum + cost.layoutCPU.sum) / 1000 / Double(max(cost.configureCPU.count, 1)))
        }
    }
    
    private func record(_ name: String, _ value: Double) {
        metrics[name] = value.isFinite ? value : 0
    }
    
    private func rowCount(default defaultCount: Int) -> Int {
        Int(environment["TIMELINE_BENCH_ROWS"] ?? "") ?? defaultCount
    }
    
    private func writeResults() {
        var isOptimised = true
        #if DEBUG
        isOptimised = false
        #endif
        let info: [String: Any] = ["scenario": scenario,
                                   "isOptimised": isOptimised,
                                   "model": environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "device",
                                   "os": UIDevice.current.systemVersion,
                                   "maximumFramesPerSecond": UIScreen.main.maximumFramesPerSecond,
                                   "rowKinds": Dictionary(grouping: session.fixture.rows(count: TimelineBenchFixture.maximumRowCount), by: \.kind).mapValues(\.count)]
        let results: [String: Any] = ["info": info, "metrics": metrics]
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) else {
            fatalError("Couldn't encode the results")
        }
        do {
            try data.write(to: directory.appending(path: "timeline-bench-\(scenario).json"))
        } catch {
            fatalError("Couldn't write the results: \(error)")
        }
    }
    
    // MARK: - Main thread
    
    private func measureIdleShare() async {
        let mark = mainThreadMark()
        try? await Task.sleep(for: .seconds(1))
        idleShare = Double(meter.busyCPU - mark.busyCPU) / Double(TimelineBenchClock.wall - mark.wall)
        record("harness.idle_cpu_ms_per_s", idleShare * 1000)
    }
    
    private func mainThreadMark() -> TimelineBenchMark {
        TimelineBenchMark(busyCPU: meter.busyCPU, busyWall: meter.busyWall, wall: TimelineBenchClock.wall)
    }
    
    /// The main thread's work since `mark`, in nanoseconds, without the harness's own.
    private func mainThreadWork(since mark: TimelineBenchMark) -> (cpu: UInt64, wall: UInt64) {
        let idle = UInt64(idleShare * Double(TimelineBenchClock.wall - mark.wall))
        let cpu = meter.busyCPU - mark.busyCPU
        let wall = meter.busyWall - mark.busyWall
        return (cpu > idle ? cpu - idle : 0, wall > idle ? wall - idle : 0)
    }
    
    // MARK: - Waiting
    
    /// How long the main thread must stay almost still to count as idle.
    private let idleWindow = 0.25
    
    private func waitUntilIdle() async {
        let step = Duration.milliseconds(50)
        var quietSteps = 0
        var lastBusy = meter.busyWall
        let deadline = TimelineBenchClock.wall + 8_000_000_000
        while quietSteps < Int(idleWindow / 0.05), TimelineBenchClock.wall < deadline {
            try? await Task.sleep(for: step)
            let busy = meter.busyWall
            quietSteps = busy - lastBusy < 3_000_000 ? quietSteps + 1 : 0
            lastBusy = busy
        }
    }
    
    private func nextFrame() async {
        await withCheckedContinuation { continuation in
            frames.onTick = { [unowned self] _ in
                frames.onTick = nil
                continuation.resume()
                return 0
            }
        }
    }
}

// MARK: - Support

private struct TimelineBenchMark {
    let busyCPU: UInt64
    let busyWall: UInt64
    let wall: UInt64
}

private final class TimelineBenchStamp {
    var wall: UInt64 = 0
    var cpu: UInt64 = 0
}

/// Milliseconds from asking for the room.
struct TimelineBenchOpen {
    let firstFrame: Double
    let firstRows: Double
    let firstRowsCPU: Double
    let settled: Double
}

struct TimelineBenchUpdateCost {
    let buildWall: UInt64
    let buildCPU: UInt64
    let busyWall: UInt64
    let busyCPU: UInt64
}

/// Whether the rows hold still: a row on screen should be exactly where the scroll put it. Follows the row nearest the middle.
@MainActor
private final class TimelineBenchJumpTracker {
    private let table: UITableView
    private var anchor: (id: String, visibleY: CGFloat)?
    private var contentHeight: CGFloat
    /// How often the table's content changed height: a row came out taller or shorter than its estimate.
    private(set) var heightChanges = 0
    
    init(table: UITableView) {
        self.table = table
        contentHeight = table.contentSize.height
    }
    
    /// How far the anchor is from where the last offset should have put it, in points.
    func jumpSinceLastFrame() -> CGFloat {
        if table.contentSize.height != contentHeight {
            contentHeight = table.contentSize.height
            heightChanges += 1
        }
        guard let anchor, let cell = cell(with: anchor.id) else { return 0 }
        return cell.frame.minY - table.contentOffset.y - anchor.visibleY
    }
    
    func willScroll(to offset: CGFloat) {
        let middle = table.contentOffset.y + table.bounds.height / 2
        let cell = table.visibleCells.lazy.compactMap { $0 as? TimelineItemCell }.min { abs($0.frame.midY - middle) < abs($1.frame.midY - middle) }
        guard let cell, let id = cell.item?.identifier.uniqueID.value else {
            anchor = nil
            return
        }
        anchor = (id, cell.frame.minY - offset)
    }
    
    private func cell(with id: String) -> TimelineItemCell? {
        table.visibleCells.lazy.compactMap { $0 as? TimelineItemCell }.first { $0.item?.identifier.uniqueID.value == id }
    }
}

private extension UInt64 {
    var milliseconds: Double {
        Double(self) / 1_000_000
    }
}

private extension Array where Element == UInt64 {
    var milliseconds: [Double] {
        map { Double($0) / 1_000_000 }
    }
    
    var microseconds: [Double] {
        map { Double($0) / 1000 }
    }
    
    var sum: Double {
        reduce(0) { $0 + Double($1) }
    }
}

private extension Array where Element == Double {
    var mean: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
    
    var median: Double {
        percentile(50)
    }
    
    func percentile(_ percent: Double) -> Double {
        guard !isEmpty else { return 0 }
        let sorted = sorted()
        return sorted[Swift.min(sorted.count - 1, Int((Double(sorted.count - 1) * percent / 100).rounded()))]
    }
}

#endif
